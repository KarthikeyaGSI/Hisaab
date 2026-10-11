create or replace function private.is_admin() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and auth.jwt()->>'aal'='aal2'
 and exists(select 1 from private.admin_members where user_id=auth.uid() and enabled)
 and exists(select 1 from auth.sessions where id::text=auth.jwt()->>'session_id' and user_id=auth.uid());
$$;
create function public.admin_context() returns uuid language sql stable security invoker set search_path='' as $$
 select case when private.is_admin() then auth.uid() else null end;
$$;
revoke all on function public.admin_context() from public,anon;
grant execute on function public.admin_context() to authenticated;
create function public.bootstrap_first_admin(p_user uuid) returns boolean language plpgsql security definer set search_path='' as $$
begin
 perform pg_advisory_xact_lock(82345612);
 if exists(select 1 from private.admin_members) then raise exception 'Administrator already configured'; end if;
 if not exists(select 1 from auth.users where id=p_user and email_confirmed_at is not null) then raise exception 'Confirmed user required'; end if;
 insert into private.admin_members(user_id) values(p_user);
 insert into private.audit_events(actor,action,entity_type,entity_id,reason) values(p_user,'bootstrap','administrator',p_user::text,'First owner created from local setup');
 return true;
end $$;
revoke all on function public.bootstrap_first_admin(uuid) from public,anon,authenticated;
grant execute on function public.bootstrap_first_admin(uuid) to service_role;
create table private.ingestion_candidates(
 id text primary key,source_id text not null references public.sources(id),document_id uuid not null references private.source_documents(id),
 payload jsonb not null, status text not null default 'pending' check(status in ('pending','published','rejected')),
 created_at timestamptz not null default now(),reviewed_by uuid references auth.users(id),reason text
);
alter table private.ingestion_candidates enable row level security;
grant all on private.ingestion_candidates to service_role;
create function public.admin_candidates() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not private.is_admin() then raise exception 'MFA administrator required'; end if;
 return coalesce((select jsonb_agg(payload order by created_at) from private.ingestion_candidates where status='pending'),'[]'::jsonb);
end $$;
revoke all on function public.admin_candidates() from public,anon;
grant execute on function public.admin_candidates() to authenticated;
create unique index works_hisaab_id on private.works((original_identifiers->>'hisaab_id'));
create function public.stage_ingestion(p_source jsonb,p_document jsonb,p_candidates jsonb) returns integer language plpgsql security definer set search_path='' as $$
declare doc uuid; item jsonb; total integer:=0;
begin
 if p_source->>'official_url' !~ '^https://' or p_document->>'original_url' !~ '^https://' then raise exception 'HTTPS source required'; end if;
 insert into public.sources(id,name,official_url,family,access_method,approved,reuse_permission)
 values(p_source->>'id',p_source->>'name',p_source->>'official_url',p_source->>'family','authorized_original',false,null)
 on conflict(id) do nothing;
 insert into private.source_documents(source_id,original_url,sha256,storage_path,content_type,query_manifest,parser_version)
 values(p_source->>'id',p_document->>'original_url',p_document->>'sha256',p_document->>'storage_path',p_document->>'content_type',p_document->'manifest',p_document->>'parser_version')
 on conflict(source_id,sha256) do update set sha256=excluded.sha256 returning id into doc;
 for item in select value from jsonb_array_elements(p_candidates) loop
  insert into private.ingestion_candidates(id,source_id,document_id,payload) values(item->>'id',p_source->>'id',doc,item) on conflict(id) do nothing;
  total:=total+1;
 end loop;
 return total;
end $$;
revoke all on function public.stage_ingestion(jsonb,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.stage_ingestion(jsonb,jsonb,jsonb) to service_role;
create function public.publish_reviewed_candidate(p_id text,p_payload jsonb,p_reason text) returns bigint language plpgsql security definer set search_path='' as $$
declare candidate private.ingestion_candidates; doc private.source_documents; work_uuid uuid; version bigint; receipt jsonb; expected jsonb;
begin
 if not private.is_admin() then raise exception 'MFA administrator required'; end if;
 if length(trim(p_reason))<20 then raise exception 'Documented review required'; end if;
 select * into candidate from private.ingestion_candidates where id=p_id for update;
 if not found or candidate.status<>'pending' then raise exception 'Pending candidate required'; end if;
 if p_payload->>'id'<>p_id or coalesce((p_payload->>'demo')::boolean,false) then raise exception 'Government work required'; end if;
 expected := (candidate.payload - 'review' - 'sourceId') || jsonb_build_object('stages',(select jsonb_agg(s || jsonb_build_object('state',case when s->>'state'='pending' then 'found' else s->>'state' end)) from jsonb_array_elements(candidate.payload->'stages') s),'money',coalesce((select jsonb_agg(e || jsonb_build_object('approved',true)) from jsonb_array_elements(candidate.payload->'money') e),'[]'::jsonb));
 if p_payload<>expected then raise exception 'Publication must match the preserved candidate; corrections need a new candidate'; end if;
 select * into doc from private.source_documents where id=candidate.document_id;
 if doc.license_basis is null or not exists(select 1 from public.sources where id=candidate.source_id and approved) then raise exception 'Source reuse permission must be independently verified'; end if;
 if not exists(select 1 from public.areas where id=p_payload->>'areaId' and kind='district' and approved) then raise exception 'Verified district identity required'; end if;
 for receipt in select r.value from jsonb_array_elements(p_payload->'stages') s cross join lateral jsonb_array_elements(s.value->'receipts') r loop
  if receipt->>'documentHash'<>doc.sha256 or receipt->>'url'<>doc.original_url or length(trim(receipt->>'locator'))=0 then raise exception 'Receipt must resolve to preserved original'; end if;
 end loop;
 if p_payload->'authorityReceipt'<>'null'::jsonb and (p_payload->'authorityReceipt'->>'documentHash'<>doc.sha256 or p_payload->'authorityReceipt'->>'url'<>doc.original_url) then raise exception 'Authority evidence mismatch'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id,0));
 select id into work_uuid from private.works where original_identifiers->>'hisaab_id'=p_id;
 if found then raise exception 'Existing work needs explicit revision reconciliation'; end if;
 insert into private.works(title,purpose,area_id,source_id,financial_year,original_identifiers,location_precision,physical_verification,publication_state)
 values(p_payload->>'title',p_payload->>'purpose',p_payload->>'areaId',candidate.source_id,p_payload->>'financialYear',jsonb_build_object('hisaab_id',p_id,'official',p_payload->'officialIds'),p_payload->>'locationPrecision',p_payload->>'physicalVerification','approved') returning id into work_uuid;
 version:=1;
 insert into public.publication_snapshots(work_id,publication_version,payload,reviewed_by,approved) values(work_uuid,version,p_payload,auth.uid(),true);
 update private.ingestion_candidates set status='published',reviewed_by=auth.uid(),reason=p_reason where id=p_id;
 insert into private.audit_events(actor,action,entity_type,entity_id,after_hash,reason) values(auth.uid(),'publish','work',work_uuid::text,encode(extensions.digest(p_payload::text,'sha256'),'hex'),p_reason);
 return version;
end $$;
revoke all on function public.publish_reviewed_candidate(text,jsonb,text) from public,anon;
grant execute on function public.publish_reviewed_candidate(text,jsonb,text) to authenticated;
