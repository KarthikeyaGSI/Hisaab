\set ON_ERROR_STOP on
begin;
insert into auth.users(id) values('00000000-0000-4000-8000-000000000001');
insert into private.works(id,title) values('00000000-0000-4000-8000-000000000002','Disposable publication policy test');
insert into public.publication_snapshots(work_id,publication_version,payload,reviewed_by,approved)
 values('00000000-0000-4000-8000-000000000002',1,'{"id":"policy-test-v1"}','00000000-0000-4000-8000-000000000001',true),
 ('00000000-0000-4000-8000-000000000002',2,'{"id":"policy-test-v2"}','00000000-0000-4000-8000-000000000001',true);
set local role anon;
do $$ begin
 if (select count(*) from public.published_work_receipts where work_id='00000000-0000-4000-8000-000000000002')<>1
 or not exists(select 1 from public.published_work_receipts where payload->>'id'='policy-test-v2') then
 raise exception 'Latest published version was not selected';end if;
 if exists(select 1 from public.publication_snapshots where payload->>'id'='policy-test-v1') then
 raise exception 'Superseded payload exposed';end if;
end $$;
reset role;
update public.publication_snapshots set withdrawn_at=now() where work_id='00000000-0000-4000-8000-000000000002' and publication_version=2;
set local role anon;
do $$ begin
 if exists(select 1 from public.published_work_receipts where work_id='00000000-0000-4000-8000-000000000002')
 or exists(select 1 from public.publication_snapshots where work_id='00000000-0000-4000-8000-000000000002') then
 raise exception 'Withdrawn or superseded payload exposed';end if;
end $$;
reset role;
rollback;
