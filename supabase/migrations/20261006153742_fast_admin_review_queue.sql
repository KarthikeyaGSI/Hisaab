-- Limit payload/revision work to the visible page for an unfiltered queue.
create index candidate_revisions_latest on private.candidate_revisions(candidate_id,created_at desc,id desc);
create or replace function public.admin_candidates_page(p_offset integer default 0,p_limit integer default 25,p_query text default '') returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
 query_text text:=lower(left(coalesce(p_query,''),200));
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
  -- Materialize identities, not tens of thousands of full evidence payloads.
  with matching as materialized (
   select c.id from private.effective_candidates c where c.status='pending'
    and position(query_text in lower(coalesce(c.effective_payload->>'title','')||' '||coalesce(c.effective_payload->>'state','')||' '||coalesce(c.effective_payload->>'district','')))>0
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
