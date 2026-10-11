create function public.register_atlas_original(p_source jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare doc private.source_documents;result uuid;
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 if p_source->>'id' !~ '^[a-zA-Z0-9_-]{1,100}$' or p_source->>'hash' !~ '^[a-f0-9]{64}$' or p_source->>'url' !~ '^https://' or p_source->>'storagePath'<>(p_source->>'id'||'/'||p_source->>'hash') then raise exception 'Invalid original identity';end if;
 select * into doc from private.source_documents where source_id=p_source->>'id' and sha256=p_source->>'hash';
 if found then if doc.original_url<>p_source->>'url' or doc.storage_path<>p_source->>'storagePath' then raise exception 'Immutable original conflict';end if;return doc.id;end if;
 if pg_database_size(current_database())>445644800 then raise exception '425 MiB intake guard reached';end if;
 insert into public.sources(id,name,official_url,family,access_method,approved,reuse_permission) values(p_source->>'id',p_source->>'name',p_source->>'url',p_source->>'family','owner_original_private_review',false,null) on conflict(id) do nothing;
 insert into private.source_documents(source_id,original_url,sha256,storage_path,content_type,query_manifest,parser_version) values(p_source->>'id',p_source->>'url',p_source->>'hash',p_source->>'storagePath',p_source->>'contentType',p_source,'hisaab-intake/1') returning id into result;
 return result;
end $$;
revoke all on function public.register_atlas_original(jsonb) from public,anon;
grant execute on function public.register_atlas_original(jsonb) to authenticated;

create function public.prepare_atlas_project_reviews(p_batch text) returns integer language plpgsql security definer set search_path='' as $$
declare batch private.atlas_batches;w jsonb;doc private.source_documents;candidate jsonb;counted integer:=0;
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 select * into batch from private.atlas_batches where id=p_batch;if not found then raise exception 'Batch required';end if;
 for w in select value from jsonb_array_elements(batch.payload->'projects') loop
  select d.* into doc from private.source_documents d where exists(select 1 from jsonb_array_elements(w->'stages') s cross join lateral jsonb_array_elements(s->'receipts') r where r->>'documentHash'=d.sha256 and r->>'url'=d.original_url) order by d.id limit 1;
  if not found then raise exception 'Project original required';end if;
  candidate:=w||jsonb_build_object('review',jsonb_build_object('documentHash',doc.sha256,'mappingVersion','hisaab-intake/1','batchId',p_batch,'matchedBy','unreviewed_source_identity'));
  if exists(select 1 from private.candidate_import_editions where candidate_id=w->>'id' and document_id=doc.id and payload<>candidate) then raise exception 'Changed project edition requires reconciliation';end if;
  insert into private.ingestion_candidates(id,source_id,document_id,payload) values(w->>'id',doc.source_id,doc.id,candidate) on conflict(id) do nothing;
  insert into private.candidate_import_editions(candidate_id,document_id,payload) values(w->>'id',doc.id,candidate) on conflict(candidate_id,document_id) do nothing;
  counted:=counted+1;
 end loop;return counted;
end $$;
revoke all on function public.prepare_atlas_project_reviews(text) from public,anon;
grant execute on function public.prepare_atlas_project_reviews(text) to authenticated;

create function public.admin_development_record(p_id text) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 return (select jsonb_build_object('payload',f.payload,'documentId',f.document_id,'permissionReviewed',exists(select 1 from private.source_permission_reviews where document_id=f.document_id),'published',exists(select 1 from private.development_publications where record_id=f.id and active)) from private.development_drafts f where id=p_id);
end $$;
revoke all on function public.admin_development_record(text) from public,anon;
grant execute on function public.admin_development_record(text) to authenticated;

create function public.catalogue_projects_page(p_query text default '',p_purpose text default null,p_year text default null,p_offset integer default 0,p_limit integer default 25,p_state text default null) returns jsonb language sql stable security invoker set search_path='' as $$
 with matching as(select work_id,payload from public.published_work_receipts where (p_state is null or payload->>'state'=p_state) and (p_purpose is null or payload->>'purpose'=p_purpose) and (p_year is null or payload->>'financialYear'=p_year) and position(lower(left(p_query,200)) in lower(concat(payload->>'title',' ',payload->>'district',' ',payload->>'state',' ',payload->>'officialIds')))>0),page as(select * from matching order by work_id limit greatest(1,least(100,p_limit)) offset greatest(0,p_offset))
 select jsonb_build_object('works',coalesce((select jsonb_agg(payload order by work_id) from page),'[]'::jsonb),'total',(select count(*) from matching));
$$;
revoke all on function public.catalogue_projects_page(text,text,text,integer,integer,text) from public;
grant execute on function public.catalogue_projects_page(text,text,text,integer,integer,text) to anon,authenticated;
