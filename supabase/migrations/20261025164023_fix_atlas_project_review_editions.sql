-- Respect compacted source editions and immutable candidate identities. This RPC
-- prepares new private candidates only; changed existing IDs require the separate
-- explicit reconciliation workflow and never create an implicit revision.
create or replace function public.prepare_atlas_project_reviews(p_batch text)
returns integer language plpgsql security definer set search_path='' as $$
declare
 batch private.atlas_batches;
 w jsonb;
 doc private.source_documents;
 candidate jsonb;
 base private.ingestion_candidates;
 item_hash text;
 inserted integer;
 counted integer:=0;
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 select * into batch from private.atlas_batches where id=p_batch for update;
 if not found then raise exception 'Batch required';end if;
 if jsonb_typeof(batch.payload->'projects') is distinct from 'array'
 or jsonb_typeof(batch.payload->'sources') is distinct from 'array'
 or jsonb_array_length(batch.payload->'projects')>100
 or octet_length(batch.payload::text)>2097152 then
  raise exception 'Invalid bounded project intake';
 end if;
 if pg_database_size(current_database())>445644800 then
  raise exception '425 MiB intake guard reached; preserve package outside database';
 end if;
 for w in select value from jsonb_array_elements(batch.payload->'projects') loop
  if jsonb_typeof(w) is distinct from 'object' or coalesce(length(w->>'id'),0) not between 1 and 240
  or jsonb_typeof(w->'stages') is distinct from 'array' then
   raise exception 'Project identity and stages required';
  end if;
  select d.* into doc from private.source_documents d
  where exists(
   select 1 from jsonb_array_elements(w->'stages') s
   cross join lateral jsonb_array_elements(s->'receipts') r
   where r->>'documentHash'=d.sha256 and r->>'url'=d.original_url)
  and exists(
   select 1 from jsonb_array_elements(batch.payload->'sources') original
   where original->>'id'=d.source_id and original->>'hash'=d.sha256
   and original->>'url'=d.original_url and original->>'storagePath'=d.storage_path)
  order by d.id limit 1;
  if not found then raise exception 'Project original required from registered batch sources';end if;
  candidate:=w||jsonb_build_object('review',jsonb_build_object(
   'documentHash',doc.sha256,'mappingVersion','hisaab-intake/1',
   'batchId',p_batch,'matchedBy','unreviewed_source_identity'));
  item_hash:=encode(extensions.digest(candidate::text,'sha256'),'hex');
  insert into private.ingestion_candidates(id,source_id,document_id,payload)
  values(w->>'id',doc.source_id,doc.id,candidate) on conflict(id) do nothing;
  get diagnostics inserted=row_count;
  select * into base from private.ingestion_candidates where id=w->>'id';
  if base.source_id is distinct from doc.source_id
  or base.document_id is distinct from doc.id or base.payload is distinct from candidate then
   raise exception 'Candidate % already exists with a different original or payload; explicit reconciliation required',w->>'id';
  end if;
  insert into private.candidate_import_editions(candidate_id,document_id,payload,payload_hash)
  values(w->>'id',doc.id,case when base.document_id=doc.id then null else candidate end,item_hash)
  on conflict(candidate_id,document_id) do nothing;
  if exists(select 1 from private.candidate_import_editions
   where candidate_id=w->>'id' and document_id=doc.id and payload_hash is distinct from item_hash) then
   raise exception 'Changed project edition requires explicit reconciliation';
  end if;
  counted:=counted+inserted;
 end loop;
 return counted;
end $$;
revoke all on function public.prepare_atlas_project_reviews(text) from public,anon,authenticated;
grant execute on function public.prepare_atlas_project_reviews(text) to authenticated;
