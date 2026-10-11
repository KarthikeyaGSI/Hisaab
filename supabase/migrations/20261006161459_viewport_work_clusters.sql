create function public.catalogue_map_clusters(p_west numeric,p_south numeric,p_east numeric,p_north numeric,p_query text default '',p_purpose text default null,p_year text default null) returns jsonb language plpgsql stable security invoker set search_path='' as $$
begin
 if p_west is null or p_south is null or p_east is null or p_north is null or p_west < -180 or p_east > 180 or p_south < -90 or p_north > 90 or p_west>=p_east or p_south>=p_north then raise exception 'Valid map bounds required';end if;
 return (
 with matching as (
 select payload,(payload->'location'->>0)::numeric lng,(payload->'location'->>1)::numeric lat
 from public.published_work_receipts
 where payload->>'locationPrecision' in ('source_point','address') and jsonb_typeof(payload->'location')='array'
 and (payload->'location'->>0)::numeric between p_west and p_east and (payload->'location'->>1)::numeric between p_south and p_north
 and position(lower(left(coalesce(p_query,''),200)) in lower(coalesce(payload->>'title','')||' '||coalesce(payload->>'district','')||' '||coalesce(payload->>'state','')||' '||coalesce(payload->>'officialIds','')))>0
 and (p_purpose is null or payload->>'purpose'=p_purpose) and (p_year is null or payload->>'financialYear'=p_year)
 ), cells as (
 select least(15,floor((lng-p_west)/(p_east-p_west)*16)) x,least(15,floor((lat-p_south)/(p_north-p_south)*16)) y,count(*) n,avg(lng) lng,avg(lat) lat,min(lng) west,min(lat) south,max(lng) east,max(lat) north,min(payload->>'id') id,min(payload->>'title') title,min(payload->>'purpose') purpose
 from matching group by 1,2
 ) select jsonb_build_object('type','FeatureCollection','total',(select count(*) from matching),'truncated',false,'features',coalesce((select jsonb_agg(jsonb_build_object('type','Feature','geometry',jsonb_build_object('type','Point','coordinates',jsonb_build_array(lng,lat)),'properties',case when n=1 then jsonb_build_object('id',id,'title',title,'purpose',purpose,'count',1,'cluster',false) else jsonb_build_object('count',n,'cluster',true,'bounds',jsonb_build_array(west,south,east,north)) end) order by x,y) from cells),'[]'::jsonb))
 );
end $$;
revoke all on function public.catalogue_map_clusters(numeric,numeric,numeric,numeric,text,text,text) from public;
grant execute on function public.catalogue_map_clusters(numeric,numeric,numeric,numeric,text,text,text) to anon,authenticated,service_role;

create function public.catalogue_map_members(p_west numeric,p_south numeric,p_east numeric,p_north numeric,p_query text default '',p_purpose text default null,p_year text default null,p_offset integer default 0) returns jsonb language plpgsql stable security invoker set search_path='' as $$
begin
 if p_west is null or p_south is null or p_east is null or p_north is null or p_west < -180 or p_east > 180 or p_south < -90 or p_north > 90 or p_west>=p_east or p_south>=p_north then raise exception 'Valid map bounds required';end if;
 return (
 with matching as (
 select payload,(payload->'location'->>0)::numeric lng,(payload->'location'->>1)::numeric lat
 from public.published_work_receipts
 where payload->>'locationPrecision' in ('source_point','address') and jsonb_typeof(payload->'location')='array'
 and (payload->'location'->>0)::numeric between p_west and p_east and (payload->'location'->>1)::numeric between p_south and p_north
 and position(lower(left(coalesce(p_query,''),200)) in lower(coalesce(payload->>'title','')||' '||coalesce(payload->>'district','')||' '||coalesce(payload->>'state','')||' '||coalesce(payload->>'officialIds','')))>0
 and (p_purpose is null or payload->>'purpose'=p_purpose) and (p_year is null or payload->>'financialYear'=p_year)

 ), page as (select payload from matching order by payload->>'id' offset greatest(0,least(coalesce(p_offset,0),10000000)) limit 25)
 select jsonb_build_object('total',(select count(*) from matching),'works',coalesce((select jsonb_agg(jsonb_build_object('id',payload->>'id','title',payload->>'title','purpose',payload->>'purpose') order by payload->>'id') from page),'[]'::jsonb))
 );
end $$;
revoke all on function public.catalogue_map_members(numeric,numeric,numeric,numeric,text,text,text,integer) from public;
grant execute on function public.catalogue_map_members(numeric,numeric,numeric,numeric,text,text,text,integer) to anon,authenticated,service_role;
