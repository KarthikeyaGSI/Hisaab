create function public.catalogue_party_projects(p_party text,p_first text,p_last text,p_offset integer default 0) returns jsonb language sql stable security invoker set search_path='' as $$
 with matching as(select work_id,payload from public.published_work_receipts where substring(payload->>'financialYear',1,4) between p_first and p_last and exists(select 1 from jsonb_array_elements(coalesce(payload->'roles','[]'::jsonb)) role where role->>'id'=p_party and role->>'identityBasis' in ('official_id','documented_crosswalk'))),page as(select * from matching order by payload->>'financialYear' desc,work_id limit 25 offset greatest(0,p_offset)) select jsonb_build_object('works',coalesce((select jsonb_agg(payload) from page),'[]'::jsonb),'total',(select count(*) from matching));
$$;
revoke all on function public.catalogue_party_projects(text,text,text,integer) from public;
grant execute on function public.catalogue_party_projects(text,text,text,integer) to anon,authenticated;
