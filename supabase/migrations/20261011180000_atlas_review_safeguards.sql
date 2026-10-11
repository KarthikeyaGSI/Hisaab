create or replace function private.assert_publication_evidence(p jsonb) returns void language plpgsql set search_path='' as $$
declare s jsonb;e jsonb;receipt_ids jsonb;stage_id text;scaled numeric;
begin
 if jsonb_array_length(p->'stages')<>4 or (select count(distinct value->>'id') from jsonb_array_elements(p->'stages'))<>4 then raise exception 'Four distinct stages required';end if;
 select coalesce(jsonb_agg(r.value->>'id'),'[]'::jsonb) into receipt_ids from jsonb_array_elements(p->'stages') st cross join lateral jsonb_array_elements(st.value->'receipts') r;
 for s in select value from jsonb_array_elements(p->'stages') loop
  if s->>'state'='found' and (coalesce(s->>'reviewStatus','')<>'verified' or jsonb_array_length(s->'receipts')=0) then raise exception 'Found stages require explicit verified evidence review';end if;
  if s->>'id'='completion' and s->>'state'='found' and coalesce(s->>'completionBasis','') not in ('reported','certificate') then raise exception 'Completion basis required';end if;
 end loop;
 for e in select value from jsonb_array_elements(p->'money') loop
  if coalesce(e->>'originalUnit','') not in ('rupees','lakh','crore') then raise exception 'Original financial unit required';end if;
  scaled:=(e->>'originalAmount')::numeric * case e->>'originalUnit' when 'lakh' then 100000 when 'crore' then 10000000 else 1 end;
  if scaled<>round(scaled,2) or scaled<>(e->>'amount')::numeric then raise exception 'Exact amount normalization required';end if;
  if coalesce((e->>'approved')::boolean,false) then
   if coalesce(e->>'reviewStatus','')<>'verified' or not receipt_ids ? (e->>'receiptId') then raise exception 'Explicit financial source review required';end if;
   stage_id:=case e->>'measure' when 'contract' then 'award' when 'sanction' then 'sanction' when 'payment' then 'payment' else '' end;
   if not exists(select 1 from jsonb_array_elements(p->'stages') st where st->>'id'=stage_id and st->>'state'='found' and st->>'reviewStatus'='verified') then raise exception 'Reviewed financial stage required';end if;
   if e->>'measure'='payment' and e->>'kind'<>'cumulative' then
    if coalesce(e->>'date','')='' or coalesce(e->>'sourcePaymentId','')='' or coalesce(e->'allocation'->>'projectId','')<>p->>'id' or coalesce(e->'allocation'->>'amount','')<>e->>'amount' or not receipt_ids ? coalesce(e->'allocation'->>'receiptId','') or coalesce(e->>'flow','')<>'contractor_payment' or coalesce(e->>'amountBasis','') not in ('gross','net') or coalesce(e->>'payee','')='' then raise exception 'Individual payment allocation recipient and amount basis required';end if;
   end if;
  end if;
 end loop;
 for s in select value->'receipt' from jsonb_array_elements(coalesce(p->'roles','[]'::jsonb)) union all select value->'receipt' from jsonb_array_elements(coalesce(p->'media','[]'::jsonb)) loop
  if s is null or coalesce(s->>'locator','')='' or not exists(select 1 from private.source_documents d join public.sources src on src.id=d.source_id where d.sha256=s->>'documentHash' and d.original_url=s->>'url' and d.license_basis is not null and src.approved) then raise exception 'Party and media sources require preserved permitted evidence';end if;
 end loop;
 for s in select value from jsonb_array_elements(coalesce(p->'roles','[]'::jsonb)) loop
  if s->>'photoUrl' is not null and coalesce(s->>'photoSource','')='' then raise exception 'Person photos require a documented source';end if;
 end loop;
end $$;
revoke all on function private.assert_publication_evidence(jsonb) from public,anon,authenticated;

create table private.development_decisions(record_id text primary key references private.development_drafts(id),payload jsonb not null,reason text not null,reviewed_by uuid not null references auth.users(id),reviewed_at timestamptz not null default now());
alter table private.development_decisions enable row level security;
grant all on private.development_decisions to service_role;
create function public.classify_development(p_id text,p_patch jsonb,p_reason text) returns boolean language plpgsql security definer set search_path='' as $$
declare draft jsonb;field text;
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 if length(trim(p_reason))<30 then raise exception 'Classification evidence required';end if;
 if exists(select 1 from private.development_publications where record_id=p_id and active) then raise exception 'Withdraw a published fact before changing classification';end if;
 for field in select jsonb_object_keys(p_patch) loop if field not in ('classification','purpose','scope','origin','reconciliationKey','disjointEvidence','shares','aggregation','parentKey','notes','instrument') then raise exception 'Immutable source field';end if;end loop;
 select coalesce(r.payload,d.payload) into draft from private.development_drafts d left join private.development_decisions r on r.record_id=d.id where d.id=p_id;if not found then raise exception 'Draft required';end if;
 draft:=draft||p_patch;
 if draft->>'classification' not in ('included','excluded','mixed_unresolved','awaiting_review') or draft->>'scope' not in ('within_area','received') or draft->>'origin' not in ('union','state','joint','local') then raise exception 'Invalid classification';end if;
 insert into private.development_decisions(record_id,payload,reason,reviewed_by) values(p_id,draft,p_reason,auth.uid()) on conflict(record_id) do update set payload=excluded.payload,reason=excluded.reason,reviewed_by=excluded.reviewed_by,reviewed_at=now();
 insert into private.audit_events(actor,action,entity_type,entity_id,reason) values(auth.uid(),'classify','development',p_id,p_reason);return true;
end $$;
revoke all on function public.classify_development(text,jsonb,text) from public,anon;
grant execute on function public.classify_development(text,jsonb,text) to authenticated;
create or replace function public.admin_development_record(p_id text) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 return (select jsonb_build_object('payload',coalesce(r.payload,f.payload),'original',f.payload,'documentId',f.document_id,'permissionReviewed',exists(select 1 from private.source_permission_reviews where document_id=f.document_id),'published',exists(select 1 from private.development_publications where record_id=f.id and active)) from private.development_drafts f left join private.development_decisions r on r.record_id=f.id where f.id=p_id);
end $$;
create function public.development_history(p_scope text,p_programme text) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(p.payload order by p.payload->>'financialYear',p.payload->>'measure'),'[]'::jsonb) from private.development_publications p join private.development_drafts f on f.id=p.record_id join private.source_documents d on d.id=f.document_id join public.sources s on s.id=d.source_id where p.active and s.approved and p.payload->>'jurisdiction'=p_scope and p.payload->>'programmeId'=p_programme and exists(select 1 from private.source_permission_reviews r where r.document_id=d.id);
$$;
revoke all on function public.development_history(text,text) from public;
grant execute on function public.development_history(text,text) to anon,authenticated;
create or replace function public.review_development(p_id text,p_decisions jsonb,p_reason text,p_action text) returns boolean language plpgsql security definer set search_path='' as $$
declare fact private.development_drafts;
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 if length(trim(p_reason))<30 or p_action not in ('publish','withdraw') then raise exception 'Explicit review required';end if;
 select * into fact from private.development_drafts where id=p_id for update;if not found then raise exception 'Draft required';end if;
 select coalesce((select payload from private.development_decisions where record_id=p_id),fact.payload) into fact.payload;
 if p_action='publish' then
  if fact.payload->>'origin'='joint' and (jsonb_array_length(fact.payload->'shares')=0 or (select sum((value->>'amountRupees')::numeric) from jsonb_array_elements(fact.payload->'shares'))<>(fact.payload->>'amountRupees')::numeric) then raise exception 'Joint shares must reconcile';end if;
  if (fact.payload->>'periodStart')::date>(fact.payload->>'periodEnd')::date or (fact.payload->>'amountRupees') !~ '^-?[0-9]+\.[0-9]{2}$' or (fact.payload->>'measure'='allocated' and fact.payload->>'accountingBasis'<>'budget') or (fact.payload->>'measure'='released' and fact.payload->>'accountingBasis'<>'release') or (fact.payload->>'measure'='reported_spent' and fact.payload->>'accountingBasis' not in ('booked_expenditure','recipient_utilisation')) then raise exception 'Invalid amount or accounting basis';end if;
  if not (coalesce((p_decisions->>'sourceChecked')::boolean,false) and coalesce((p_decisions->>'unitsChecked')::boolean,false) and coalesce((p_decisions->>'jurisdictionChecked')::boolean,false) and coalesce((p_decisions->>'scopeChecked')::boolean,false) and coalesce((p_decisions->>'editionsChecked')::boolean,false) and coalesce((p_decisions->>'nonOverlapChecked')::boolean,false) and coalesce((p_decisions->>'confirmed')::boolean,false)) then raise exception 'Evidence review gates incomplete';end if;
  if fact.payload->>'classification'<>'included' or fact.payload->>'aggregation'<>'leaf' or fact.payload->>'amountRupees' is null or fact.payload->>'instrument'='unresolved' or (fact.payload->>'conflict')::boolean is distinct from false then raise exception 'Unresolved records cannot be published';end if;
  if not exists(select 1 from private.source_permission_reviews r join private.source_documents d on d.id=r.document_id join public.sources s on s.id=d.source_id where r.document_id=fact.document_id and s.approved) then raise exception 'Source rights review required';end if;
  if exists(select 1 from private.development_publications p where p.active and p.record_id<>p_id and p.payload->>'reconciliationKey'=fact.payload->>'reconciliationKey' and p.payload->>'jurisdiction'=fact.payload->>'jurisdiction' and p.payload->>'scope'=fact.payload->>'scope' and p.payload->>'measure'=fact.payload->>'measure' and p.payload->>'estimate'=fact.payload->>'estimate' and p.payload->>'accountingBasis'=fact.payload->>'accountingBasis' and (p.payload->>'periodStart')::date<=(fact.payload->>'periodEnd')::date and (fact.payload->>'periodStart')::date<=(p.payload->>'periodEnd')::date) then raise exception 'Overlapping edition must be withdrawn first';end if;
  insert into private.development_publications(record_id,payload,reviewed_by,reason,decisions) values(p_id,fact.payload,auth.uid(),p_reason,p_decisions) on conflict(record_id) do update set active=true,payload=excluded.payload,reviewed_by=excluded.reviewed_by,reason=excluded.reason,decisions=excluded.decisions,published_at=now();
 else update private.development_publications set active=false where record_id=p_id;end if;
 insert into private.audit_events(actor,action,entity_type,entity_id,reason) values(auth.uid(),p_action,'development',p_id,p_reason);return true;
end $$;
revoke all on function public.review_development(text,jsonb,text,text) from public,anon;
grant execute on function public.review_development(text,jsonb,text,text) to authenticated;

