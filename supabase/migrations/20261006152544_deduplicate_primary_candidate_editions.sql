-- The first edition already has an immutable payload in ingestion_candidates.
-- Reference that copy instead of storing the same JSON twice. Later originals
-- retain their own complete payload, and every edition keeps a canonical hash.
create or replace function private.lock_candidate_original() returns trigger language plpgsql set search_path='' as $$
begin
 if new.id is distinct from old.id or new.source_id is distinct from old.source_id or new.document_id is distinct from old.document_id or new.payload is distinct from old.payload then raise exception 'Original candidate payload and identity are immutable; use a reviewed revision';end if;
 return new;
end $$;
drop trigger if exists candidate_original_immutable on private.ingestion_candidates;
create trigger candidate_original_immutable before update on private.ingestion_candidates for each row execute function private.lock_candidate_original();
do $$ begin
lock table private.candidate_import_editions in access exclusive mode;
create table if not exists private.compacted_candidate_editions(
 candidate_id text not null references private.ingestion_candidates(id),document_id uuid not null references private.source_documents(id),payload jsonb,
 imported_at timestamptz not null default now(),payload_hash text not null check(payload_hash ~ '^[a-f0-9]{64}$'),primary key(candidate_id,document_id)
);
insert into private.compacted_candidate_editions(candidate_id,document_id,payload,imported_at,payload_hash)
 select e.candidate_id,e.document_id,case when e.document_id=c.document_id and e.payload=c.payload then null else e.payload end,e.imported_at,encode(extensions.digest(e.payload::text,'sha256'),'hex')
 from private.candidate_import_editions e join private.ingestion_candidates c on c.id=e.candidate_id
 where not exists(select 1 from private.compacted_candidate_editions compact where compact.candidate_id=e.candidate_id and compact.document_id=e.document_id);
 if (select count(*) from private.compacted_candidate_editions)<>(select count(*) from private.candidate_import_editions) then raise exception 'Compaction must preserve every source edition';end if;
drop table private.candidate_import_editions;
alter table private.compacted_candidate_editions rename to candidate_import_editions;
alter table private.candidate_import_editions enable row level security;
grant all on private.candidate_import_editions to service_role;
end $$;
create function private.check_candidate_edition() returns trigger language plpgsql set search_path='' as $$
declare base private.ingestion_candidates;resolved jsonb;
begin
 select * into base from private.ingestion_candidates where id=new.candidate_id;
 if new.payload is null and new.document_id is distinct from base.document_id then raise exception 'Only the original edition may reference the candidate base payload';end if;
 resolved=coalesce(new.payload,base.payload);
 if new.payload_hash is distinct from encode(extensions.digest(resolved::text,'sha256'),'hex') then raise exception 'Edition payload checksum mismatch';end if;
 if tg_op='UPDATE' and new is distinct from old then raise exception 'Source edition is immutable';end if;
 return new;
end $$;
create trigger candidate_edition_immutable before insert or update on private.candidate_import_editions for each row execute function private.check_candidate_edition();
create or replace function public.stage_ingestion(p_source jsonb,p_document jsonb,p_candidates jsonb) returns integer language plpgsql security definer set search_path='' as $$
declare doc uuid;item jsonb;total integer:=0;inserted integer;base private.ingestion_candidates;item_hash text;
begin
 if p_source->>'official_url' !~ '^https://' or p_document->>'original_url' !~ '^https://' then raise exception 'HTTPS source required';end if;
 if jsonb_typeof(p_candidates)<>'array' or jsonb_array_length(p_candidates)>1000 then raise exception 'Batch must contain at most 1000 candidates';end if;
 if pg_database_size(current_database())>445644800 then raise exception 'Private database operating ceiling reached; assess capacity before importing more';end if;
 insert into public.sources(id,name,official_url,family,access_method,approved,reuse_permission) values(p_source->>'id',p_source->>'name',p_source->>'official_url',p_source->>'family','public_original_private_review',false,null) on conflict(id) do nothing;
 insert into private.source_documents(source_id,original_url,sha256,storage_path,content_type,query_manifest,parser_version) values(p_source->>'id',p_document->>'original_url',p_document->>'sha256',p_document->>'storage_path',p_document->>'content_type',p_document->'manifest',p_document->>'parser_version') on conflict(source_id,sha256) do update set sha256=excluded.sha256 returning id into doc;
 for item in select value from jsonb_array_elements(p_candidates) loop
  insert into private.ingestion_candidates(id,source_id,document_id,payload) values(item->>'id',p_source->>'id',doc,item) on conflict(id) do nothing;
  get diagnostics inserted=row_count;total:=total+inserted;
  select * into base from private.ingestion_candidates where id=item->>'id';
  if base.source_id<>p_source->>'id' then raise exception 'Candidate identity belongs to another source';end if;
  item_hash=encode(extensions.digest(item::text,'sha256'),'hex');
  if base.document_id=doc and base.payload<>item then raise exception 'Same original produced a changed candidate; version the parser and review explicitly';end if;
  insert into private.candidate_import_editions(candidate_id,document_id,payload,payload_hash) values(item->>'id',doc,case when base.document_id=doc then null else item end,item_hash) on conflict(candidate_id,document_id) do nothing;
  if exists(select 1 from private.candidate_import_editions where candidate_id=item->>'id' and document_id=doc and payload_hash<>item_hash) then raise exception 'Same original produced a changed candidate; version the parser and review explicitly';end if;
 end loop;
 return total;
end $$;
