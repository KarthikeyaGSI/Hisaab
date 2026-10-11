create or replace function private.is_admin() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and auth.jwt()->>'aal'='aal2'
 and exists(select 1 from private.admin_members where user_id=auth.uid() and enabled)
 and exists(select 1 from auth.sessions s join auth.mfa_factors f on f.id=s.factor_id and f.user_id=s.user_id
 where s.id::text=auth.jwt()->>'session_id' and s.user_id=auth.uid() and s.aal='aal2' and f.status='verified' and (s.not_after is null or s.not_after>now()));
$$;
create table private.candidate_revisions(
 id uuid primary key default gen_random_uuid(),candidate_id text not null references private.ingestion_candidates(id),
 payload jsonb not null,reviewed_by uuid not null references auth.users(id),reason text not null,created_at timestamptz not null default now()
);
alter table private.candidate_revisions enable row level security;
grant all on private.candidate_revisions to service_role;
create table private.source_permission_reviews(
 id uuid primary key default gen_random_uuid(),document_id uuid not null references private.source_documents(id),
 permission_basis text not null,evidence_reference text not null,reviewed_by uuid not null references auth.users(id),created_at timestamptz not null default now()
);
alter table private.source_permission_reviews enable row level security;
grant all on private.source_permission_reviews to service_role;
create view private.effective_candidates with (security_invoker=true) as
 select c.*,coalesce(r.payload,c.payload) as effective_payload from private.ingestion_candidates c
 left join lateral(select payload from private.candidate_revisions where candidate_id=c.id order by created_at desc,id desc limit 1) r on true;
grant select on private.effective_candidates to service_role;
create or replace function public.admin_candidates() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 return coalesce((select jsonb_agg(c.effective_payload||jsonb_build_object('review',c.payload->'review','sourceDocument',jsonb_build_object('id',d.id,'hash',d.sha256,'url',d.original_url,'licenseBasis',d.license_basis)) order by c.created_at) from private.effective_candidates c join private.source_documents d on d.id=c.document_id where c.status='pending'),'[]'::jsonb);
end $$;
create function public.reconcile_candidate(p_id text,p_payload jsonb,p_reason text) returns boolean language plpgsql security definer set search_path='' as $$
declare old_payload jsonb;
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 if length(trim(p_reason))<20 or p_payload->>'id'<>p_id or coalesce((p_payload->>'demo')::boolean,false) then raise exception 'Documented government work reconciliation required';end if;
 select effective_payload into old_payload from private.effective_candidates where id=p_id;
 if not found then raise exception 'Candidate required';end if;
 perform 1 from private.ingestion_candidates where id=p_id for update;
 insert into private.candidate_revisions(candidate_id,payload,reviewed_by,reason) values(p_id,p_payload,auth.uid(),p_reason);
 update private.ingestion_candidates set status='pending' where id=p_id;
 insert into private.audit_events(actor,action,entity_type,entity_id,before_hash,after_hash,reason) values(auth.uid(),'reconcile','candidate',p_id,encode(extensions.digest(old_payload::text,'sha256'),'hex'),encode(extensions.digest(p_payload::text,'sha256'),'hex'),p_reason);
 return true;
end $$;
create function public.verify_source_permission(p_document uuid,p_basis text,p_evidence text) returns boolean language plpgsql security definer set search_path='' as $$
declare source_id text;
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 if length(trim(p_basis))<30 or length(trim(p_evidence))<20 then raise exception 'Written permission or precise license evidence required';end if;
 select d.source_id into source_id from private.source_documents d where id=p_document for update;
 if not found then raise exception 'Preserved original required';end if;
 insert into private.source_permission_reviews(document_id,permission_basis,evidence_reference,reviewed_by) values(p_document,p_basis,p_evidence,auth.uid());
 update private.source_documents set license_basis=p_basis where id=p_document;
 update public.sources set approved=true,reuse_permission=p_basis,last_checked=now() where id=source_id;
 insert into private.audit_events(actor,action,entity_type,entity_id,reason) values(auth.uid(),'verify_permission','source_document',p_document::text,p_basis||' | Evidence: '||p_evidence);
 return true;
end $$;
create or replace function public.publish_reviewed_candidate(p_id text,p_payload jsonb,p_reason text) returns bigint language plpgsql security definer set search_path='' as $$
declare candidate private.ingestion_candidates;doc private.source_documents;work_uuid uuid;version bigint;receipt jsonb;stage_record jsonb;event jsonb;expected jsonb;before_hash text;document_uuid uuid;fact_uuid uuid;prior_event uuid;
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 if length(trim(p_reason))<20 then raise exception 'Documented review required';end if;
 select * into candidate from private.ingestion_candidates where id=p_id for update;
 if not found or candidate.status<>'pending' then raise exception 'Pending candidate required';end if;
 if p_payload->>'id'<>p_id or coalesce((p_payload->>'demo')::boolean,false) then raise exception 'Government work required';end if;
 select effective_payload into expected from private.effective_candidates where id=p_id;
 expected := (expected - 'review' - 'sourceId') || jsonb_build_object('stages',(select jsonb_agg(s || jsonb_build_object('state',case when s->>'state'='pending' then 'found' else s->>'state' end)) from jsonb_array_elements(expected->'stages') s),'money',coalesce((select jsonb_agg(e || jsonb_build_object('approved',true)) from jsonb_array_elements(expected->'money') e),'[]'::jsonb));
 if p_payload<>expected then raise exception 'Publication must match the preserved reconciliation';end if;
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
  values(work_uuid,event->>'canonicalId',event->>'measure',(event->>'amount')::numeric,event->>'originalAmount',event->>'originalUnit',event->>'kind',(event->>'date')::date,p_payload->>'financialYear',fact_uuid,true,prior_event);
 end loop;
 insert into public.publication_snapshots(work_id,publication_version,payload,reviewed_by,approved) values(work_uuid,version,p_payload,auth.uid(),true);
 update private.ingestion_candidates set status='published',reviewed_by=auth.uid(),reason=p_reason where id=p_id;
 insert into private.audit_events(actor,action,entity_type,entity_id,before_hash,after_hash,reason) values(auth.uid(),'publish','work',work_uuid::text,before_hash,encode(extensions.digest(p_payload::text,'sha256'),'hex'),p_reason);
 return version;
end $$;
revoke all on function public.reconcile_candidate(text,jsonb,text),public.verify_source_permission(uuid,text,text) from public,anon;
grant execute on function public.reconcile_candidate(text,jsonb,text),public.verify_source_permission(uuid,text,text) to authenticated;
create function public.withdraw_reviewed_work(p_id text,p_reason text) returns boolean language plpgsql security definer set search_path='' as $$
declare work_uuid uuid;version bigint;
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 if length(trim(p_reason))<20 then raise exception 'Documented withdrawal reason required';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id,0));
 select id into work_uuid from private.works where original_identifiers->>'hisaab_id'=p_id;
 if not found then raise exception 'Published work required';end if;
 select max(publication_version) into version from public.publication_snapshots where work_id=work_uuid;
 update public.publication_snapshots set withdrawn_at=now() where work_id=work_uuid and publication_version=version and withdrawn_at is null;
 if not found then raise exception 'Active publication required';end if;
 update private.works set publication_state='withdrawn' where id=work_uuid;
 insert into private.audit_events(actor,action,entity_type,entity_id,reason) values(auth.uid(),'withdraw','work',work_uuid::text,p_reason);
 return true;
end $$;
create function public.admin_publications() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('work',s.payload,'version',s.publication_version,'withdrawnAt',s.withdrawn_at) order by s.created_at desc) from public.publication_snapshots s join public.publication_heads h on h.work_id=s.work_id and h.publication_version=s.publication_version),'[]'::jsonb);
end $$;
revoke all on function public.withdraw_reviewed_work(text,text),public.admin_publications() from public,anon;
grant execute on function public.withdraw_reviewed_work(text,text),public.admin_publications() to authenticated;
