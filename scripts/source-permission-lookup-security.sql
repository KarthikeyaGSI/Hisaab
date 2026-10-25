\set ON_ERROR_STOP on
-- Run against a disposable/local database after installing the lookup migration.
-- This only asserts denial paths and always rolls back.
begin;
do $$ begin
 if has_function_privilege('anon','public.admin_source_document_by_identity(text,text,text)','execute') then
  raise exception 'Anonymous original metadata lookup must not be executable';
 end if;
 if not has_function_privilege('authenticated','public.admin_source_document_by_identity(text,text,text)','execute') then
  raise exception 'Authenticated owner RPC grant is missing';
 end if;
end $$;
set local role anon;
do $$ begin
 begin
  perform public.admin_source_document_by_identity('disposable-test',repeat('a',64),'https://example.invalid/test');
  raise exception 'Anonymous lookup unexpectedly succeeded';
 exception when insufficient_privilege then null;
 end;
end $$;
reset role;
set local role authenticated;
do $$ begin
 begin
  perform public.admin_source_document_by_identity('disposable-test',repeat('a',64),'https://example.invalid/test');
  raise exception 'A session without owner MFA unexpectedly succeeded';
 exception when raise_exception then
  if sqlerrm<>'MFA administrator required' then raise;end if;
 end;
end $$;
reset role;
rollback;
