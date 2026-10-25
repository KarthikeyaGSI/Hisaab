-- Narrow owner-only lookup for secondary originals retained in an intake batch.
-- Does not return storage paths, query manifests, original contents or credentials.
create function public.admin_source_document_by_identity(p_source_id text,p_hash text,p_url text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 if p_source_id is null or p_source_id !~ '^[a-zA-Z0-9_-]{1,100}$'
    or p_hash is null or p_hash !~ '^[a-f0-9]{64}$'
    or p_url is null or length(p_url)>2048 or p_url !~ '^https://' then
  raise exception 'Exact source identity required';
 end if;
 select jsonb_build_object('id',d.id,'sourceId',d.source_id,'hash',d.sha256,
   'url',d.original_url,'licenseBasis',d.license_basis,'sourceApproved',s.approved,
   'permissionReviewed',exists(select 1 from private.source_permission_reviews r where r.document_id=d.id))
 into result from private.source_documents d join public.sources s on s.id=d.source_id
 where d.source_id=p_source_id and d.sha256=p_hash and d.original_url=p_url;
 return result;
end $$;
revoke all on function public.admin_source_document_by_identity(text,text,text) from public,anon;
grant execute on function public.admin_source_document_by_identity(text,text,text) to authenticated;
