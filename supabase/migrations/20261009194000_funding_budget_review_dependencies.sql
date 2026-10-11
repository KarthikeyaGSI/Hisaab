-- Exact original-row links, separate from source facts and publication snapshots.
create table private.funding_budget_drafts(record_id text primary key references private.funding_records(id),row_id text not null references private.funding_budget_lines(id),parser_version text not null,column_index integer not null check(column_index between 0 and 3));
alter table private.funding_budget_drafts enable row level security;
grant all on private.funding_budget_drafts to service_role;
create trigger immutable_funding_budget_link before update or delete on private.funding_budget_drafts for each row execute function private.lock_budget_context();

create or replace function public.draft_budget_funding(p_row_id text,p_parser_version text,p_column integer,p_metadata jsonb,p_reason text) returns text language plpgsql security definer set search_path='' as $$
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
 fact_id:='budget-row:'||p_row_id||':'||p_parser_version||':'||p_column||':'||pg_catalog.md5(p_metadata::text||original.purpose);
 fact_payload:=jsonb_build_object('id',fact_id,'identity',p_metadata->>'coverageKey','edition',original.financial_year||' expenditure budget / '||p_parser_version,'financialYear',fy,'programmeId',p_metadata->>'programmeId','programme',p_metadata->>'programme','budgetHead',p_metadata->>'budgetHead','ministry',p_metadata->>'ministry','jurisdiction','national','jurisdictionLabel','Nationwide / state breakdown unavailable','purpose',original.purpose,'channel',p_metadata->>'channel','instrument',p_metadata->>'instrument','measure',measure,'estimate',estimate,'accountingBasis',case when measure='allocated' then 'union_budget' else 'union_booked_expenditure' end,'share','union','amountRupees',column_data->>'totalRupees','periodStart',split_part(fy,'-',1)||'-04-01','periodEnd',split_part(fy,'-',2)||'-03-31','cutoff',p_metadata->>'cutoff','publicationDate',p_metadata->'publicationDate','coverageKey',p_metadata->>'coverageKey','parentKey',p_metadata->'parentKey','aggregation',p_metadata->>'aggregation','classification','awaiting_review','conflict',false,'source',jsonb_build_object('hash',original.payload->>'sourceHash','url',original.payload->>'sourceUrl','locator','PDF page '||(original.payload->>'page')||', line '||(original.payload->>'line')||'; '||(column_data->>'measure')||' '||fy||'; total column; source unit crore; programme/hierarchy interpretation: '||left(p_reason,700),'retrievedAt',(select d.query_manifest->>'retrievedAt' from private.source_documents d where d.id=original.document_id),'page',(original.payload->>'page')::integer),'notes','Privately drafted from an explicitly reviewed Union budget row. No state split, release, recipient utilisation or contractor settlement inferred. '||p_reason);
 if length(fact_id)>240 or not private.validate_funding_payload(fact_payload) then raise exception 'Invalid budget funding interpretation';end if;
 select payload into old_payload from private.funding_records where id=fact_id;
 if found then if old_payload is distinct from fact_payload then raise exception 'Immutable draft edition conflict';end if;return fact_id;end if;
 insert into private.funding_records(id,document_id,payload) values(fact_id,original.document_id,fact_payload);
 insert into private.funding_budget_drafts(record_id,row_id,parser_version,column_index) values(fact_id,p_row_id,p_parser_version,p_column);
 insert into private.audit_events(actor,action,entity_type,entity_id,reason) values(auth.uid(),'draft','funding',fact_id,p_reason);
 return fact_id;
end $$;

create or replace function public.review_funding_inventory(p_id text,p_classification text,p_purpose text,p_reason text) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 if p_classification not in ('included','excluded','mixed_unresolved','awaiting_review') or length(trim(p_reason))<30 then raise exception 'Documented classification required';end if;
 update private.funding_budget_lines set classification=p_classification,purpose=left(p_purpose,100),review_reason=p_reason,reviewed_by=auth.uid(),reviewed_at=now() where id=p_id;
 if not found then raise exception 'Original inventory row required';end if;
 update private.funding_publications set active=false where record_id in(select record_id from private.funding_budget_drafts where row_id=p_id);
 insert into private.audit_events(actor,action,entity_type,entity_id,reason) values(auth.uid(),'classify','funding_budget_line',p_id,p_reason);
 return true;
end $$;

-- Qualify the reviewed fact independently of SQL payload columns.
create or replace function public.review_funding(p_id text,p_decision jsonb,p_reason text) returns boolean language plpgsql security definer set search_path='' as $$
declare fact private.funding_records;reviewed_payload jsonb;review_decision_id bigint;
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 if length(trim(p_reason))<30 or coalesce((p_decision->>'confirmed')::boolean,false) is not true or p_decision->>'classification' not in ('included','excluded','mixed_unresolved','awaiting_review') or p_decision->>'action' not in ('save','publish','withdraw') then raise exception 'Explicit documented decision required';end if;
 select * into fact from private.funding_records where id=p_id for update;if not found then raise exception 'Record required';end if;
 reviewed_payload:=fact.payload||jsonb_build_object('classification',p_decision->>'classification');
 if p_decision->>'action'='publish' then
  if exists(select 1 from private.funding_budget_drafts link join private.funding_budget_lines b on b.id=link.row_id where link.record_id=p_id and (b.classification<>'included' or b.purpose is distinct from reviewed_payload->>'purpose')) then raise exception 'Budget row must be reclassified and redrafted before publication';end if;
  if p_decision->>'classification'<>'included' or reviewed_payload->>'share'<>'union' or reviewed_payload->>'aggregation'<>'leaf' or reviewed_payload->>'amountRupees' is null or reviewed_payload->>'instrument'='unresolved' or (reviewed_payload->>'conflict')::boolean is distinct from false
   or not exists(select 1 from private.source_permission_reviews where document_id=fact.document_id)
   or not (coalesce((p_decision->>'sourceChecked')::boolean,false) and coalesce((p_decision->>'unitsChecked')::boolean,false) and coalesce((p_decision->>'jurisdictionChecked')::boolean,false) and coalesce((p_decision->>'scopeChecked')::boolean,false) and coalesce((p_decision->>'editionsChecked')::boolean,false)) then raise exception 'Evidence and rights gates incomplete';end if;
  -- A single published accounting scope cannot contain overlapping reporting periods,
  -- regardless of source, edition or cumulative cut-off. Withdraw superseded facts first.
  if exists(select 1 from private.funding_publications p where p.active and p.record_id<>p_id and
   p.payload->>'coverageKey'=reviewed_payload->>'coverageKey' and p.payload->>'jurisdiction'=reviewed_payload->>'jurisdiction' and
   p.payload->>'financialYear'=reviewed_payload->>'financialYear' and p.payload->>'measure'=reviewed_payload->>'measure' and
   p.payload->>'estimate'=reviewed_payload->>'estimate' and p.payload->>'accountingBasis'=reviewed_payload->>'accountingBasis' and
   (p.payload->>'periodStart')::date<=(reviewed_payload->>'periodEnd')::date and (reviewed_payload->>'periodStart')::date<=(p.payload->>'periodEnd')::date) then raise exception 'Overlapping edition: withdraw previous publication first';end if;
 end if;
 insert into private.funding_decisions(record_id,decision,reason,reviewed_by) values(p_id,p_decision,p_reason,auth.uid()) returning id into review_decision_id;
 -- Any re-review removes the prior public snapshot until an explicit publication.
 update private.funding_publications set active=false where record_id=p_id;
 if p_decision->>'action'='publish' then insert into private.funding_publications(record_id,decision_id,payload) values(p_id,review_decision_id,reviewed_payload) on conflict(record_id) do update set decision_id=excluded.decision_id,payload=excluded.payload,active=true,published_at=now();end if;
 insert into private.audit_events(actor,action,entity_type,entity_id,reason) values(auth.uid(),p_decision->>'action','funding',p_id,p_reason);
 return true;
end $$;
