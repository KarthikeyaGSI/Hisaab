-- Source rights are a continuing condition, including auxiliary role/media evidence.
-- Revocation withdraws snapshots; restoring permission never silently republishes them.
create function private.invalidate_atlas_document(p_document uuid) returns void
language plpgsql security definer set search_path='' as $$
declare checksum text;
begin
 select sha256 into checksum from private.source_documents where id=p_document;
 if checksum is null then return;end if;
 update public.publication_snapshots set withdrawn_at=now()
 where withdrawn_at is null and jsonb_path_exists(payload,'$.**.documentHash ? (@ == $hash)',jsonb_build_object('hash',checksum));
 update private.funding_publications set active=false
 where active and record_id in(select id from private.funding_records where document_id=p_document);
 update private.development_publications set active=false
 where active and record_id in(select id from private.development_drafts where document_id=p_document);
end $$;
revoke all on function private.invalidate_atlas_document(uuid) from public,anon,authenticated;

create function private.invalidate_source_rights() returns trigger
language plpgsql security definer set search_path='' as $$
declare document uuid;
begin
 if tg_table_name='sources' then
  if old.approved and not new.approved then
   for document in select id from private.source_documents where source_id=new.id loop
    perform private.invalidate_atlas_document(document);
   end loop;
  end if;
 elsif tg_table_name='source_documents' then
  if old.license_basis is not null and new.license_basis is null then perform private.invalidate_atlas_document(new.id);end if;
 else perform private.invalidate_atlas_document(old.document_id);
 end if;
 return coalesce(new,old);
end $$;
revoke all on function private.invalidate_source_rights() from public,anon,authenticated;
create trigger invalidate_atlas_source_rights after update of approved on public.sources
for each row execute function private.invalidate_source_rights();
create trigger invalidate_atlas_document_rights after update of license_basis on private.source_documents
for each row execute function private.invalidate_source_rights();
create trigger invalidate_atlas_permission_delete after delete on private.source_permission_reviews
for each row execute function private.invalidate_source_rights();
