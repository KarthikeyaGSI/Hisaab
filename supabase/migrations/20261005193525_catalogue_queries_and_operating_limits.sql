create extension if not exists pg_trgm with schema extensions;
create index publication_payload_search on public.publication_snapshots using gin ((lower(coalesce(payload->>'title','')||' '||coalesce(payload->>'district','')||' '||coalesce(payload->>'state','')||' '||coalesce(payload->>'officialIds',''))) extensions.gin_trgm_ops) where approved and withdrawn_at is null;
create index publication_payload_purpose_year on public.publication_snapshots((payload->>'purpose'),(payload->>'financialYear')) where approved and withdrawn_at is null;
create function public.catalogue_page(p_query text default '',p_purpose text default null,p_year text default null,p_offset integer default 0,p_limit integer default 25) returns jsonb language sql stable security invoker set search_path='' as $$
 with matching as (
  select work_id,payload from public.published_work_receipts
  where position(lower(left(coalesce(p_query,''),200)) in lower(coalesce(payload->>'title','')||' '||coalesce(payload->>'district','')||' '||coalesce(payload->>'state','')||' '||coalesce(payload->>'officialIds','')))>0
  and (p_purpose is null or payload->>'purpose'=p_purpose) and (p_year is null or payload->>'financialYear'=p_year)
 ), page as (select * from matching order by work_id offset greatest(0,least(p_offset,10000000)) limit greatest(1,least(p_limit,100)))
 select jsonb_build_object('works',coalesce((select jsonb_agg(payload order by work_id) from page),'[]'::jsonb),'total',(select count(*) from matching));
$$;
create function public.catalogue_summary() returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('works',count(*),'districtsCovered',count(distinct payload->>'areaId'),'districtsExpected',null,'publishedAt',max(created_at)) from public.published_work_receipts;
$$;
create function public.catalogue_money(p_measure text,p_district text default null,p_year text default null,p_from text default null,p_to text default null) returns jsonb language sql stable security invoker set search_path='' as $$
 with events as (
 select e.value as event,(e.value->>'amount')::numeric as amount from public.published_work_receipts w cross join lateral jsonb_array_elements(w.payload->'money') e
 where (p_district is null or w.payload->>'district'=p_district) and (p_year is null or w.payload->>'financialYear'=p_year) and e.value->>'measure'=p_measure
 ), eligible as (select * from events where event->>'approved'='true' and coalesce(event->>'receiptId','')<>'' and event->>'kind'<>'cumulative'),
 grouped as (
 select event->>'canonicalId' as identity,min(amount) as amount,min(event->>'date') as event_date,count(distinct jsonb_build_array(amount,event->>'kind',event->>'date')) as variants from eligible group by event->>'canonicalId'
 ), accepted as (select * from grouped where variants=1 and (p_from is null or event_date>=p_from) and (p_to is null or event_date<=p_to))
 select jsonb_build_object('amount',case when count(*)>0 then round(sum(amount),2)::text else null end,'eventCount',count(*),'conflictingIdentities',(select count(*) from grouped where variants>1),'scope','Imported approved records only','demo',false) from accepted;
$$;
revoke all on function public.catalogue_page(text,text,text,integer,integer),public.catalogue_summary(),public.catalogue_money(text,text,text,text,text) from public;
grant execute on function public.catalogue_page(text,text,text,integer,integer),public.catalogue_summary(),public.catalogue_money(text,text,text,text,text) to anon,authenticated,service_role;
create table private.request_limits(key_hash text not null,window_start timestamptz not null,hits integer not null,primary key(key_hash,window_start));
alter table private.request_limits enable row level security;
grant all on private.request_limits to service_role;
create function public.consume_request_limit(p_key text,p_limit integer) returns boolean language plpgsql security definer set search_path='' as $$
declare used integer;
begin
 if p_key !~ '^[a-f0-9]{64}$' or p_limit<1 or p_limit>10000 then raise exception 'Valid operating limit required'; end if;
 insert into private.request_limits(key_hash,window_start,hits) values(p_key,date_trunc('minute',now()),1)
 on conflict(key_hash,window_start) do update set hits=private.request_limits.hits+1 returning hits into used;
 delete from private.request_limits where window_start<now()-interval '10 minutes';
 return used<=p_limit;
end $$;
revoke all on function public.consume_request_limit(text,integer) from public,anon,authenticated;
grant execute on function public.consume_request_limit(text,integer) to service_role;
