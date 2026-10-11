create function public.catalogue_map(p_west numeric,p_south numeric,p_east numeric,p_north numeric,p_limit integer default 100) returns jsonb language plpgsql stable security invoker set search_path='' as $$
begin
 if p_west is null or p_south is null or p_east is null or p_north is null or p_west < -180 or p_east > 180 or p_south < -90 or p_north > 90 or p_west>=p_east or p_south>=p_north then raise exception 'Valid map bounds required';end if;
 return (
 with matching as (
  select work_id,payload from public.published_work_receipts
  where payload->>'locationPrecision' in ('source_point','address')
  and jsonb_typeof(payload->'location')='array'
  and (payload->'location'->>0)::numeric between p_west and p_east
  and (payload->'location'->>1)::numeric between p_south and p_north
 ), page as (select * from matching order by work_id limit greatest(1,least(p_limit,100)))
 select jsonb_build_object('type','FeatureCollection','features',coalesce((select jsonb_agg(jsonb_build_object('type','Feature','geometry',jsonb_build_object('type','Point','coordinates',payload->'location'),'properties',jsonb_build_object('id',payload->>'id','title',payload->>'title','purpose',payload->>'purpose','precision',payload->>'locationPrecision')) order by work_id) from page),'[]'::jsonb),'total',(select count(*) from matching),'truncated',(select count(*) from matching)>greatest(1,least(p_limit,100)))
 );
end $$;
revoke all on function public.catalogue_map(numeric,numeric,numeric,numeric,integer) from public;
grant execute on function public.catalogue_map(numeric,numeric,numeric,numeric,integer) to anon,authenticated,service_role;
