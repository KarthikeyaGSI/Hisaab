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
    if coalesce(e->>'sourcePaymentId','')='' or coalesce(e->'allocation'->>'projectId','')<>p->>'id' or coalesce(e->'allocation'->>'amount','')<>e->>'amount' or not receipt_ids ? coalesce(e->'allocation'->>'receiptId','') or coalesce(e->>'flow','')<>'contractor_payment' or coalesce(e->>'amountBasis','') not in ('gross','net') or coalesce(e->>'payee','')='' then raise exception 'Individual payment allocation recipient and amount basis required';end if;
   end if;
  end if;
 end loop;
end $$;
revoke all on function private.assert_publication_evidence(jsonb) from public,anon,authenticated;
create or replace function public.publish_reviewed_candidate(p_id text,p_payload jsonb,p_reason text) returns bigint language plpgsql security definer set search_path='' as $$
declare candidate private.ingestion_candidates;doc private.source_documents;work_uuid uuid;version bigint;receipt jsonb;stage_record jsonb;event jsonb;expected jsonb;before_hash text;document_uuid uuid;fact_uuid uuid;prior_event uuid;
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 if length(trim(p_reason))<20 then raise exception 'Documented review required';end if;
 select * into candidate from private.ingestion_candidates where id=p_id for update;
 if not found or candidate.status<>'pending' then raise exception 'Pending candidate required';end if;
 if p_payload->>'id'<>p_id or coalesce((p_payload->>'demo')::boolean,false) then raise exception 'Government work required';end if;
 select effective_payload into expected from private.effective_candidates where id=p_id;
 expected := expected - 'review' - 'sourceId' - 'sourceDocument';
 if p_payload<>expected then raise exception 'Publication must match the preserved reconciliation';end if;
 perform private.assert_publication_evidence(p_payload);
 select * into doc from private.source_documents where id=candidate.document_id;
 if doc.license_basis is null or not exists(select 1 from public.sources where id=candidate.source_id and approved) then raise exception 'Source reuse permission must be verified';end if;
 if not exists(select 1 from public.areas where id=p_payload->>'areaId' and kind='district' and approved) then raise exception 'Verified district identity required';end if;
 for receipt in select r.value from jsonb_array_elements(p_payload->'stages') s cross join lateral jsonb_array_elements(s.value->'receipts') r union all select p_payload->'authorityReceipt' where p_payload->'authorityReceipt'<>'null'::jsonb loop
  if length(trim(receipt->>'locator'))=0 or not exists(select 1 from private.source_documents d join public.sources s on s.id=d.source_id where d.sha256=receipt->>'documentHash' and d.original_url=receipt->>'url' and d.license_basis is not null and s.approved) then raise exception 'Every receipt needs its preserved, permitted original';end if;
 end loop;
 perform pg_advisory_xact_lock(hashtextextended(p_id,0));
 select id into work_uuid from private.works where original_identifiers->>'hisaab_id'=p_id;
 if not found then
  insert into private.works(title,purpose,area_id,source_id,financial_year,original_identifiers,location_precision,physical_verification,publication_state)
  values(p_payload->>'title',p_payload->>'purpose',p_payload->>'areaId',candidate.source_id,p_payload->>'financialYear',jsonb_build_object('hisaab_id',p_id,'official',p_payload->'officialIds'),p_payload->>'locationPrecision',p_payload->>'physicalVerification','approved') returning id into work_uuid;
 else
  select encode(extensions.digest(payload::text,'sha256'),'hex') into before_hash from public.publication_snapshots where work_id=work_uuid order by publication_version desc limit 1;
  update private.works set title=p_payload->>'title',purpose=p_payload->>'purpose',area_id=p_payload->>'areaId',financial_year=p_payload->>'financialYear',original_identifiers=jsonb_build_object('hisaab_id',p_id,'official',p_payload->'officialIds'),location_precision=p_payload->>'locationPrecision',physical_verification=p_payload->>'physicalVerification',publication_state='approved' where id=work_uuid;
 end if;
 version:=coalesce((select max(publication_version) from public.publication_snapshots where work_id=work_uuid),0)+1;
 for stage_record in select value from jsonb_array_elements(p_payload->'stages') loop
  for receipt in select value from jsonb_array_elements(stage_record->'receipts') loop
   select id into document_uuid from private.source_documents where sha256=receipt->>'documentHash' and original_url=receipt->>'url' and license_basis is not null limit 1;
   insert into private.facts(work_id,stage,field,original_text,normalized_value,document_id,locator,effective_date,extraction_method,extraction_version,reviewed_by,reviewed_at,supersedes)
   values(work_uuid,stage_record->>'id',receipt->>'id',receipt->>'rawText',stage_record,document_uuid,receipt->>'locator',(stage_record->>'date')::date,'human_review','publication-'||version,auth.uid(),now(),(select id from private.facts where work_id=work_uuid and stage=stage_record->>'id' and field=receipt->>'id' order by reviewed_at desc limit 1));
  end loop;
 end loop;
 for event in select value from jsonb_array_elements(p_payload->'money') loop
  select id into fact_uuid from private.facts where work_id=work_uuid and field=event->>'receiptId' and extraction_version='publication-'||version order by reviewed_at desc limit 1;
  if fact_uuid is null or event->>'originalAmount' is null or event->>'originalUnit' is null then raise exception 'Financial event needs its raw amount, unit and source fact';end if;
  select e.id into prior_event from private.financial_events e join private.facts f on f.id=e.fact_id where e.work_id=work_uuid and e.canonical_event_id=event->>'canonicalId' order by f.reviewed_at desc,e.id desc limit 1;
  insert into private.financial_events(work_id,canonical_event_id,measure,amount,original_amount,original_unit,event_kind,event_date,financial_year,fact_id,approved,supersedes)
  values(work_uuid,event->>'canonicalId',event->>'measure',(event->>'amount')::numeric,event->>'originalAmount',event->>'originalUnit',event->>'kind',(event->>'date')::date,p_payload->>'financialYear',fact_uuid,(event->>'approved')::boolean,prior_event);
 end loop;
 insert into public.publication_snapshots(work_id,publication_version,payload,reviewed_by,approved) values(work_uuid,version,p_payload,auth.uid(),true);
 update private.ingestion_candidates set status='published',reviewed_by=auth.uid(),reason=p_reason where id=p_id;
 insert into private.audit_events(actor,action,entity_type,entity_id,before_hash,after_hash,reason) values(auth.uid(),'publish','work',work_uuid::text,before_hash,encode(extensions.digest(p_payload::text,'sha256'),'hex'),p_reason);
 return version;
end $$;

revoke all on function public.publish_reviewed_candidate(text,jsonb,text) from public,anon;
grant execute on function public.publish_reviewed_candidate(text,jsonb,text) to authenticated;
