\set ON_ERROR_STOP on
-- Disposable/local PostgreSQL only. Every fixture and assertion rolls back.
begin;
do $$ begin
 if has_function_privilege('anon','public.prepare_atlas_project_reviews(text)','execute') then
  raise exception 'Anonymous project preparation must not be executable';
 end if;
 if not has_function_privilege('authenticated','public.prepare_atlas_project_reviews(text)','execute') then
  raise exception 'Authenticated owner RPC grant is missing';
 end if;
end $$;
select set_config('request.jwt.claims','{}',true);
set local role authenticated;
do $$ begin
 begin
  perform public.prepare_atlas_project_reviews('disposable-review-editions');
  raise exception 'Owner MFA must be required';
 exception when raise_exception then
  if sqlerrm<>'MFA administrator required' then raise;end if;
 end;
end $$;
reset role;

insert into auth.users(id) values('4d06596d-8a61-403a-9594-2c73a9834fe0');
insert into private.admin_members(user_id) values('4d06596d-8a61-403a-9594-2c73a9834fe0');
insert into auth.mfa_factors(id,user_id,factor_type,status,created_at,updated_at,secret)
 values('4d06596d-8a61-403a-9594-2c73a9834fe1','4d06596d-8a61-403a-9594-2c73a9834fe0','totp','verified',now(),now(),'disposable-local-test');
insert into auth.sessions(id,user_id,aal,factor_id,created_at,updated_at,not_after)
 values('4d06596d-8a61-403a-9594-2c73a9834fe2','4d06596d-8a61-403a-9594-2c73a9834fe0','aal2','4d06596d-8a61-403a-9594-2c73a9834fe1',now(),now(),now()+interval '1 hour');
select set_config('request.jwt.claims','{"sub":"4d06596d-8a61-403a-9594-2c73a9834fe0","aal":"aal2","session_id":"4d06596d-8a61-403a-9594-2c73a9834fe2"}',true);
insert into public.sources(id,name,official_url,family,access_method,approved)
 values('disposable-edition-source','Disposable source','https://example.invalid/source','test','private test',false),
 ('disposable-edition-other','Other disposable source','https://example.invalid/other','test','private test',false);
insert into private.source_documents(id,source_id,original_url,sha256,storage_path,content_type,query_manifest,parser_version)
 values('4d06596d-8a61-403a-9594-2c73a9834fe3','disposable-edition-source','https://example.invalid/original',repeat('a',64),'disposable-edition-source/'||repeat('a',64),'application/json','{}','test'),
 ('4d06596d-8a61-403a-9594-2c73a9834fe4','disposable-edition-source','https://example.invalid/later',repeat('b',64),'disposable-edition-source/'||repeat('b',64),'application/json','{}','test'),
 ('4d06596d-8a61-403a-9594-2c73a9834fe5','disposable-edition-other','https://example.invalid/other',repeat('c',64),'disposable-edition-other/'||repeat('c',64),'application/json','{}','test');
insert into private.atlas_batches(id,sha256,payload,reviewed_by)
select 'disposable-review-editions',repeat('d',64),jsonb_build_object(
 'sources',jsonb_build_array(jsonb_build_object('id','disposable-edition-source','hash',repeat('a',64),'url','https://example.invalid/original','storagePath','disposable-edition-source/'||repeat('a',64))),
 'projects',jsonb_build_array(jsonb_build_object('id','disposable-review-project','title','Original project','stages',jsonb_build_array(jsonb_build_object('id','sanction','receipts',jsonb_build_array(jsonb_build_object('documentHash',repeat('a',64),'url','https://example.invalid/original')))))))
 ,'4d06596d-8a61-403a-9594-2c73a9834fe0';

set local role authenticated;
do $$ begin
 if public.prepare_atlas_project_reviews('disposable-review-editions')<>1 then raise exception 'First preparation must count the new candidate';end if;
 if public.prepare_atlas_project_reviews('disposable-review-editions')<>0 then raise exception 'Idempotent retry must not count an existing candidate';end if;
end $$;
reset role;
do $$ declare e private.candidate_import_editions;c private.ingestion_candidates;begin
 select * into c from private.ingestion_candidates where id='disposable-review-project';
 select * into e from private.candidate_import_editions where candidate_id=c.id;
 if e.payload is not null or e.payload_hash is distinct from encode(extensions.digest(c.payload::text,'sha256'),'hex') then
  raise exception 'Primary edition must compact its exact payload with a valid checksum';
 end if;
 if c.status<>'pending' or exists(select 1 from private.candidate_revisions where candidate_id=c.id)
 or exists(select 1 from private.source_permission_reviews where document_id=c.document_id)
 or exists(select 1 from public.sources where id=c.source_id and approved) then
  raise exception 'Preparation must not create revisions, approvals or publication state';
 end if;
end $$;

-- A changed batch cannot overwrite the base or silently create a revision/edition.
insert into private.atlas_batches(id,sha256,payload,reviewed_by)
select 'disposable-review-changed',repeat('e',64),jsonb_set(payload,'{projects,0,title}','"Changed project"'),reviewed_by
 from private.atlas_batches where id='disposable-review-editions';
set local role authenticated;
do $$ begin
 begin
  perform public.prepare_atlas_project_reviews('disposable-review-changed');
  raise exception 'Changed existing identity must be rejected';
 exception when raise_exception then
  if sqlerrm not like 'Candidate %explicit reconciliation required' then raise;end if;
 end;
end $$;
reset role;

-- A later original must not attach an implicit revision to an existing ID.
insert into private.atlas_batches(id,sha256,payload,reviewed_by)
select 'disposable-review-later',repeat('f',64),replace(replace(payload::text,repeat('a',64),repeat('b',64)),'https://example.invalid/original','https://example.invalid/later')::jsonb,reviewed_by
 from private.atlas_batches where id='disposable-review-editions';
set local role authenticated;
do $$ begin
 begin
  perform public.prepare_atlas_project_reviews('disposable-review-later');
  raise exception 'Existing ID with later original must be rejected';
 exception when raise_exception then
  if sqlerrm not like 'Candidate %explicit reconciliation required' then raise;end if;
 end;
end $$;
reset role;

-- A batch's source metadata must match the registered original, not just hash/URL.
insert into private.atlas_batches(id,sha256,payload,reviewed_by)
select 'disposable-review-wrong-source',repeat('1',64),jsonb_set(payload,'{sources,0,id}','"disposable-edition-other"'),reviewed_by
 from private.atlas_batches where id='disposable-review-editions';
set local role authenticated;
do $$ begin
 begin
  perform public.prepare_atlas_project_reviews('disposable-review-wrong-source');
  raise exception 'Wrong source metadata must be rejected';
 exception when raise_exception then
  if sqlerrm<>'Project original required from registered batch sources' then raise;end if;
 end;
end $$;
reset role;
do $$ begin
 if (select count(*) from private.candidate_import_editions where candidate_id='disposable-review-project')<>1
 or exists(select 1 from private.candidate_revisions where candidate_id='disposable-review-project')
 or (select payload->>'title' from private.ingestion_candidates where id='disposable-review-project')<>'Original project' then
  raise exception 'Collision handling changed immutable originals or created revisions';
 end if;
end $$;
rollback;
