-- The original row remains immutable while its review metadata can change.
create function private.lock_funding_inventory_original() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='DELETE' then raise exception 'Original budget row is immutable';end if;
 if new.id is distinct from old.id or new.document_id is distinct from old.document_id or new.financial_year is distinct from old.financial_year or new.payload is distinct from old.payload then raise exception 'Original budget row is immutable';end if;
 return new;
end $$;
create trigger immutable_funding_inventory_original before update or delete on private.funding_budget_lines for each row execute function private.lock_funding_inventory_original();
create trigger immutable_funding_interpretation before update or delete on private.funding_budget_interpretations for each row execute function private.lock_budget_context();

create function public.draft_budget_funding(p_row_id text,p_parser_version text,p_column integer,p_metadata jsonb,p_reason text) returns text language plpgsql security definer set search_path='' as $$
declare original private.funding_budget_lines;interpretation jsonb;column_data jsonb;fact_payload jsonb;fact_id text;old_payload jsonb;fy text;measure text;estimate text;required text[]:=array['programmeId','programme','budgetHead','ministry','channel','instrument','coverageKey','parentKey','aggregation','cutoff','publicationDate','confirmed'];
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 if jsonb_typeof(p_metadata)<>'object' or not (p_metadata ?& required) or exists(select 1 from jsonb_object_keys(p_metadata) k where k<>all(required)) or coalesce((p_metadata->>'confirmed')::boolean,false) is not true or length(trim(p_reason))<30 or length(p_reason)>2000 then raise exception 'Explicit documented source interpretation required';end if;
 if exists(select 1 from unnest(array['programmeId','programme','budgetHead','ministry','channel','instrument','coverageKey','aggregation','cutoff']) k where jsonb_typeof(p_metadata->k) is distinct from 'string') or jsonb_typeof(p_metadata->'parentKey') not in ('string','null') or jsonb_typeof(p_metadata->'publicationDate') not in ('string','null') or jsonb_typeof(p_metadata->'confirmed') is distinct from 'boolean' then raise exception 'Typed original interpretation required';end if;
 select * into original from private.funding_budget_lines where id=p_row_id for update;
 if not found or original.classification<>'included' then raise exception 'Classify the original development row first';end if;
 if original.payload->>'sourceUrl' not like 'https://www.indiabudget.gov.in/%' or not exists(select 1 from private.source_documents d where d.id=original.document_id and d.original_url=original.payload->>'sourceUrl' and d.sha256=original.payload->>'sourceHash') then raise exception 'Union budget original required';end if;
 select i.payload->'interpretation' into interpretation from private.funding_budget_interpretations i where i.row_id=p_row_id and i.parser_version=p_parser_version;
 if not found or interpretation->>'sourceUnit'<>'crore' or p_column not between 0 and 3 then raise exception 'Verified original fiscal column required';end if;
 column_data:=interpretation->'columns'->p_column;fy:=column_data->>'financialYear';
 if fy !~ '^20(1[6-9]|2[0-6])-20(1[7-9]|2[0-7])$' or split_part(fy,'-',2)::integer<>split_part(fy,'-',1)::integer+1 or column_data->>'totalRupees' is null then raise exception 'Known amount in agreed fiscal scope required';end if;
 if column_data->>'measure'='actual' then measure:='reported_spent';estimate:='not_applicable';
 elsif column_data->>'measure' in ('budget_estimate','revised_estimate') then measure:='allocated';estimate:=case when column_data->>'measure'='budget_estimate' then 'original' else 'revised' end;
 else raise exception 'Original fiscal-column meaning unresolved';end if;
 if length(trim(p_metadata->>'programmeId')) not between 1 and 200 or length(trim(p_metadata->>'programme')) not between 1 and 400 or length(trim(p_metadata->>'budgetHead')) not between 1 and 240 or length(trim(p_metadata->>'ministry')) not between 1 and 240 or length(trim(p_metadata->>'coverageKey')) not between 1 and 240 or length(coalesce(p_metadata->>'parentKey',''))>240 or p_metadata->>'aggregation' not in ('leaf','context') or p_metadata->>'instrument' not in ('grant','loan','direct_expenditure','unresolved') then raise exception 'Documented programme and hierarchy required';end if;
 fact_id:='budget-row:'||p_row_id||':'||p_parser_version||':'||p_column||':'||pg_catalog.md5(p_metadata::text);
 fact_payload:=jsonb_build_object('id',fact_id,'identity',p_metadata->>'coverageKey','edition',original.financial_year||' expenditure budget / '||p_parser_version,'financialYear',fy,'programmeId',p_metadata->>'programmeId','programme',p_metadata->>'programme','budgetHead',p_metadata->>'budgetHead','ministry',p_metadata->>'ministry','jurisdiction','national','jurisdictionLabel','Nationwide / state breakdown unavailable','purpose',original.purpose,'channel',p_metadata->>'channel','instrument',p_metadata->>'instrument','measure',measure,'estimate',estimate,'accountingBasis',case when measure='allocated' then 'union_budget' else 'union_booked_expenditure' end,'share','union','amountRupees',column_data->>'totalRupees','periodStart',split_part(fy,'-',1)||'-04-01','periodEnd',split_part(fy,'-',2)||'-03-31','cutoff',p_metadata->>'cutoff','publicationDate',p_metadata->'publicationDate','coverageKey',p_metadata->>'coverageKey','parentKey',p_metadata->'parentKey','aggregation',p_metadata->>'aggregation','classification','awaiting_review','conflict',false,'source',jsonb_build_object('hash',original.payload->>'sourceHash','url',original.payload->>'sourceUrl','locator','PDF page '||(original.payload->>'page')||', line '||(original.payload->>'line')||'; '||(column_data->>'measure')||' '||fy||'; total column; source unit crore; programme/hierarchy interpretation: '||left(p_reason,700),'retrievedAt',(select d.query_manifest->>'retrievedAt' from private.source_documents d where d.id=original.document_id),'page',(original.payload->>'page')::integer),'notes','Privately drafted from an explicitly reviewed Union budget row. No state split, release, recipient utilisation or contractor settlement inferred. '||p_reason);
 if length(fact_id)>240 or not private.validate_funding_payload(fact_payload) then raise exception 'Invalid budget funding interpretation';end if;
 select payload into old_payload from private.funding_records where id=fact_id;
 if found then if old_payload is distinct from fact_payload then raise exception 'Immutable draft edition conflict';end if;return fact_id;end if;
 insert into private.funding_records(id,document_id,payload) values(fact_id,original.document_id,fact_payload);
 insert into private.audit_events(actor,action,entity_type,entity_id,reason) values(auth.uid(),'draft','funding',fact_id,p_reason);
 return fact_id;
end $$;
revoke all on function public.draft_budget_funding(text,text,integer,jsonb,text) from public,anon,service_role;
grant execute on function public.draft_budget_funding(text,text,integer,jsonb,text) to authenticated;

create or replace function public.admin_funding_inventory(p_year text,p_offset integer default 0,p_query text default '') returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 return (with m as(select * from private.funding_budget_lines where financial_year=p_year and position(lower(left(p_query,200)) in lower(payload->>'rawText'))>0)
 select jsonb_build_object('total',(select count(*) from m),'records',coalesce((select jsonb_agg(x.payload||jsonb_build_object('classification',x.classification,'purpose',x.purpose,'reviewReason',x.review_reason,'interpretation',(select i.payload->'interpretation'||jsonb_build_object('parserVersion',i.parser_version) from private.funding_budget_interpretations i where i.row_id=x.id order by created_at desc,parser_version desc limit 1))) from(select * from m order by id limit 40 offset greatest(0,least(200000,p_offset))) x),'[]'::jsonb),'counts',(select jsonb_object_agg(classification,n) from(select classification,count(*) n from private.funding_budget_lines where financial_year=p_year group by classification) c)));
end $$;

