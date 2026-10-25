-- Extract JSON fields before concatenation: chaining ->> with || otherwise
-- attempts to apply JSON extraction to an already-concatenated text value.
create or replace function public.register_atlas_original(p_source jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare
 doc private.source_documents;
 result uuid;
 source_id_value text:=p_source->>'id';
 source_hash_value text:=p_source->>'hash';
 source_url_value text:=p_source->>'url';
 storage_path_value text:=p_source->>'storagePath';
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 if source_id_value is null or source_id_value !~ '^[a-zA-Z0-9_-]{1,100}$'
 or source_hash_value is null or source_hash_value !~ '^[a-f0-9]{64}$'
 or source_url_value is null or source_url_value !~ '^https://'
 or storage_path_value is null or storage_path_value<>concat(source_id_value,'/',source_hash_value) then
  raise exception 'Invalid original identity';
 end if;
 select d.* into doc from private.source_documents d
 where d.source_id=source_id_value and d.sha256=source_hash_value;
 if found then
  if doc.original_url<>source_url_value or doc.storage_path<>storage_path_value then
   raise exception 'Immutable original conflict';
  end if;
  return doc.id;
 end if;
 if pg_database_size(current_database())>445644800 then raise exception '425 MiB intake guard reached';end if;
 insert into public.sources(id,name,official_url,family,access_method,approved,reuse_permission)
 values(source_id_value,p_source->>'name',source_url_value,p_source->>'family','owner_original_private_review',false,null)
 on conflict(id) do nothing;
 insert into private.source_documents(source_id,original_url,sha256,storage_path,content_type,query_manifest,parser_version)
 values(source_id_value,source_url_value,source_hash_value,storage_path_value,p_source->>'contentType',p_source,'hisaab-intake/1')
 returning id into result;
 return result;
end $$;
revoke all on function public.register_atlas_original(jsonb) from public,anon;
grant execute on function public.register_atlas_original(jsonb) to authenticated;
