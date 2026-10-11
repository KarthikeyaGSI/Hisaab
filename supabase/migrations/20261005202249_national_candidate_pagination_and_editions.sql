create table private.candidate_import_editions(
 candidate_id text not null references private.ingestion_candidates(id),document_id uuid not null references private.source_documents(id),payload jsonb not null,
 imported_at timestamptz not null default now(),primary key(candidate_id,document_id)
);
alter table private.candidate_import_editions enable row level security;
grant all on private.candidate_import_editions to service_role;
insert into private.candidate_import_editions(candidate_id,document_id,payload) select id,document_id,payload from private.ingestion_candidates;
create index ingestion_pending_order on private.ingestion_candidates(status,id);
create function public.admin_candidates_page(p_offset integer default 0,p_limit integer default 25,p_query text default '') returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 return(with matching as (select * from private.effective_candidates c where c.status='pending' and position(lower(left(coalesce(p_query,''),200)) in lower(coalesce(c.effective_payload->>'title','')||' '||coalesce(c.effective_payload->>'state','')||' '||coalesce(c.effective_payload->>'district','')))>0), page as(select * from matching order by id offset greatest(0,least(p_offset,10000000)) limit greatest(1,least(p_limit,100)))
 select jsonb_build_object('candidates',coalesce((select jsonb_agg(c.effective_payload||jsonb_build_object('review',c.payload->'review','sourceDocument',jsonb_build_object('id',d.id,'hash',d.sha256,'url',d.original_url,'licenseBasis',d.license_basis)) order by c.id) from page c join private.source_documents d on d.id=c.document_id),'[]'::jsonb),'total',(select count(*) from matching)));
end $$;
create function public.admin_candidate(p_id text) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 return(select c.effective_payload||jsonb_build_object('review',c.payload->'review','sourceDocument',jsonb_build_object('id',d.id,'hash',d.sha256,'url',d.original_url,'licenseBasis',d.license_basis)) from private.effective_candidates c join private.source_documents d on d.id=c.document_id where c.id=p_id and c.status='pending');
end $$;
create or replace function public.admin_candidates() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin return public.admin_candidates_page(0,100,'')->'candidates';end $$;
revoke all on function public.admin_candidates_page(integer,integer,text),public.admin_candidate(text) from public,anon;
grant execute on function public.admin_candidates_page(integer,integer,text),public.admin_candidate(text) to authenticated;
create or replace function public.stage_ingestion(p_source jsonb,p_document jsonb,p_candidates jsonb) returns integer language plpgsql security definer set search_path='' as $$
declare doc uuid;item jsonb;total integer:=0;inserted integer;
begin
 if p_source->>'official_url' !~ '^https://' or p_document->>'original_url' !~ '^https://' then raise exception 'HTTPS source required';end if;
 if jsonb_typeof(p_candidates)<>'array' or jsonb_array_length(p_candidates)>1000 then raise exception 'Batch must contain at most 1000 candidates';end if;
 if pg_database_size(current_database())>419430400 then raise exception 'Private database operating ceiling reached; assess capacity before importing more';end if;
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
