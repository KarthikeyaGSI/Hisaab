create function private.candidate_search_text(p_payload jsonb) returns text language sql immutable parallel safe set search_path='' as $$
 select lower(coalesce(p_payload->>'title','')||' '||coalesce(p_payload->>'state','')||' '||coalesce(p_payload->>'district',''));
$$;
create index ingestion_candidate_search on private.ingestion_candidates using gin (private.candidate_search_text(payload) extensions.gin_trgm_ops) where status='pending';
create index candidate_revision_search on private.candidate_revisions using gin (private.candidate_search_text(payload) extensions.gin_trgm_ops);
create or replace function public.admin_candidates_page(p_offset integer default 0,p_limit integer default 25,p_query text default '') returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
 query_text text:=lower(left(coalesce(p_query,''),200));
 search_pattern text;
 page_offset integer:=greatest(0,least(coalesce(p_offset,0),10000000));
 page_limit integer:=greatest(1,least(coalesce(p_limit,25),100));
 result jsonb;
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 if query_text='' then
  with page as materialized (
   select id from private.ingestion_candidates where status='pending' order by id offset page_offset limit page_limit
  )
  select jsonb_build_object('candidates',coalesce((
   select jsonb_agg(c.effective_payload||jsonb_build_object('review',c.payload->'review','sourceDocument',jsonb_build_object('id',d.id,'hash',d.sha256,'url',d.original_url,'licenseBasis',d.license_basis)) order by c.id)
   from page p join private.effective_candidates c on c.id=p.id join private.source_documents d on d.id=c.document_id
  ),'[]'::jsonb),'total',(select count(*) from private.ingestion_candidates where status='pending')) into result;
 else
  search_pattern:='%'||replace(replace(replace(query_text,chr(92),chr(92)||chr(92)),'%',chr(92)||'%'),'_',chr(92)||'_')||'%';
  -- Match indexed original or latest reviewed text, preserving literal substring semantics.
  with matching as materialized (
   select c.id from private.ingestion_candidates c where c.status='pending'
    and private.candidate_search_text(c.payload) like search_pattern escape E'\\'
    and not exists(select 1 from private.candidate_revisions r where r.candidate_id=c.id)
   union all
   select r.candidate_id from private.candidate_revisions r join private.ingestion_candidates c on c.id=r.candidate_id
    where c.status='pending' and private.candidate_search_text(r.payload) like search_pattern escape E'\\'
    and not exists(select 1 from private.candidate_revisions newer where newer.candidate_id=r.candidate_id and (newer.created_at,newer.id)>(r.created_at,r.id))
  ), page as (select id from matching order by id offset page_offset limit page_limit)
  select jsonb_build_object('candidates',coalesce((
   select jsonb_agg(c.effective_payload||jsonb_build_object('review',c.payload->'review','sourceDocument',jsonb_build_object('id',d.id,'hash',d.sha256,'url',d.original_url,'licenseBasis',d.license_basis)) order by c.id)
   from page p join private.effective_candidates c on c.id=p.id join private.source_documents d on d.id=c.document_id
  ),'[]'::jsonb),'total',(select count(*) from matching)) into result;
 end if;
 return result;
end $$;
revoke all on function public.admin_candidates_page(integer,integer,text) from public,anon;
grant execute on function public.admin_candidates_page(integer,integer,text) to authenticated;
