\set ON_ERROR_STOP on
begin;
insert into auth.users(id) values('00000000-0000-4000-8000-000000000011');
insert into public.sources(id,name,official_url,family,access_method,approved)
values('disposable-rights-test','Disposable source','https://example.invalid/original','test','fixture',true);
insert into private.source_documents(id,source_id,original_url,sha256,storage_path,content_type,license_basis)
values('00000000-0000-4000-8000-000000000012','disposable-rights-test','https://example.invalid/original',repeat('a',64),'disposable','application/pdf','Synthetic test');
insert into private.works(id,title) values('00000000-0000-4000-8000-000000000013','Disposable source rights regression');
insert into public.publication_snapshots(work_id,publication_version,payload,reviewed_by,approved)
values('00000000-0000-4000-8000-000000000013',1,jsonb_build_object('roles',jsonb_build_array(jsonb_build_object('receipt',jsonb_build_object('documentHash',repeat('a',64))))),'00000000-0000-4000-8000-000000000011',true);
update public.sources set approved=false where id='disposable-rights-test';
set local role anon;
do $$ begin
 if exists(select 1 from public.published_work_receipts where work_id='00000000-0000-4000-8000-000000000013') then raise exception 'Revoked role evidence remains public';end if;
end $$;
reset role;
update public.sources set approved=true where id='disposable-rights-test';
do $$ begin
 if exists(select 1 from public.published_work_receipts where work_id='00000000-0000-4000-8000-000000000013') then raise exception 'Restoring rights silently republished a snapshot';end if;
end $$;
insert into public.publication_snapshots(work_id,publication_version,payload,reviewed_by,approved)
values('00000000-0000-4000-8000-000000000013',2,jsonb_build_object('media',jsonb_build_array(jsonb_build_object('receipt',jsonb_build_object('documentHash',repeat('a',64))))),'00000000-0000-4000-8000-000000000011',true);
update private.source_documents set license_basis=null where id='00000000-0000-4000-8000-000000000012';
set local role anon;
do $$ begin
 if exists(select 1 from public.published_work_receipts where work_id='00000000-0000-4000-8000-000000000013') then raise exception 'Revoked media evidence remains public';end if;
end $$;
reset role;
rollback;
