-- Audited database: 401 MiB; remaining 768 candidates require roughly 5 MiB.
-- Retain a 425 MiB hard ceiling and headroom below the Free database allowance.
create or replace function public.stage_ingestion(p_source jsonb,p_document jsonb,p_candidates jsonb) returns integer language plpgsql security definer set search_path='' as $$
declare doc uuid;item jsonb;total integer:=0;inserted integer;
begin
 if p_source->>'official_url' !~ '^https://' or p_document->>'original_url' !~ '^https://' then raise exception 'HTTPS source required';end if;
 if jsonb_typeof(p_candidates)<>'array' or jsonb_array_length(p_candidates)>1000 then raise exception 'Batch must contain at most 1000 candidates';end if;
 if pg_database_size(current_database())>445644800 then raise exception 'Private database operating ceiling reached; assess capacity before importing more';end if;
 insert into public.sources(id,name,official_url,family,access_method,approved,reuse_permission) values(p_source->>'id',p_source->>'name',p_source->>'official_url',p_source->>'family','public_original_private_review',false,null) on conflict(id) do nothing;
 insert into private.source_documents(source_id,original_url,sha256,storage_path,content_type,query_manifest,parser_version) values(p_source->>'id',p_document->>'original_url',p_document->>'sha256',p_document->>'storage_path',p_document->>'content_type',p_document->'manifest',p_document->>'parser_version') on conflict(source_id,sha256) do update set sha256=excluded.sha256 returning id into doc;
 for item in select value from jsonb_array_elements(p_candidates) loop
  insert into private.ingestion_candidates(id,source_id,document_id,payload) values(item->>'id',p_source->>'id',doc,item) on conflict(id) do nothing;
  get diagnostics inserted=row_count;total:=total+inserted;
  insert into private.candidate_import_editions(candidate_id,document_id,payload) values(item->>'id',doc,item) on conflict(candidate_id,document_id) do nothing;
  if exists(select 1 from private.candidate_import_editions where candidate_id=item->>'id' and document_id=doc and payload<>item) then raise exception 'Same original produced a changed candidate; version the parser and review explicitly';end if;
 end loop;
 return total;
end $$;
