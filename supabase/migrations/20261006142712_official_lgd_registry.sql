create table public.lgd_registry_editions(
 source_hash text primary key check(source_hash ~ '^[a-f0-9]{64}$'), source_url text not null check(source_url ~ '^https://'),
 assessed_at date not null, district_count integer not null,state_count integer not null,active boolean not null default false
);
create unique index one_active_lgd_registry on public.lgd_registry_editions(active) where active;
create table public.lgd_registry_members(
 source_hash text not null references public.lgd_registry_editions(source_hash),area_id text not null references public.areas(id),
 primary key(source_hash,area_id)
);
alter table public.lgd_registry_editions enable row level security;
alter table public.lgd_registry_members enable row level security;
create policy registry_metadata_read on public.lgd_registry_editions for select to anon,authenticated using(true);
create policy registry_members_read on public.lgd_registry_members for select to anon,authenticated using(true);
grant select on public.lgd_registry_editions,public.lgd_registry_members to anon,authenticated;
grant all on public.lgd_registry_editions,public.lgd_registry_members to service_role;

create function public.import_lgd_registry(p_hash text,p_date date,p_areas jsonb) returns integer language plpgsql security definer set search_path='' as $$
declare item jsonb;districts integer;states integer;imported integer;
begin
 if not exists(select 1 from private.source_documents where source_id='lgd' and sha256=p_hash) then raise exception 'Preserved LGD original required';end if;
 if jsonb_typeof(p_areas)<>'array' or jsonb_array_length(p_areas)>10000 then raise exception 'Bounded LGD registry required';end if;
 if exists(select 1 from public.lgd_registry_editions where active and source_hash<>p_hash) then raise exception 'New registry edition requires explicit adoption and historical reconciliation';end if;
 if exists(select 1 from jsonb_array_elements(p_areas) a where a->>'kind' not in ('state','district') or coalesce(a->>'code','') !~ '^[1-9][0-9]*$' or a->>'id'<>a->>'kind'||':'||(a->>'code') or coalesce(a->>'name','')='') then raise exception 'Valid LGD identities required';end if;
 if (select count(distinct a->>'id') from jsonb_array_elements(p_areas) a)<>jsonb_array_length(p_areas) then raise exception 'Duplicate LGD identities';end if;
 select count(*) filter(where a->>'kind'='district'),count(*) filter(where a->>'kind'='state') into districts,states from jsonb_array_elements(p_areas) a;
 if districts=0 or states=0 then raise exception 'States and districts required';end if;
 if exists(select 1 from jsonb_array_elements(p_areas) a where (a->>'kind'='state' and a->>'parent_id' is not null) or (a->>'kind'='district' and not exists(select 1 from jsonb_array_elements(p_areas) s where s->>'kind'='state' and s->>'id'=a->>'parent_id'))) then raise exception 'LGD parent state must be in the same registry';end if;
 if exists(select 1 from public.lgd_registry_editions where source_hash=p_hash and (district_count<>districts or state_count<>states or assessed_at<>p_date)) then raise exception 'Original registry metadata changed';end if;
 if exists(select 1 from jsonb_array_elements(p_areas) a join public.areas r on r.id=a->>'id' where r.code<>a->>'code' or r.name<>a->>'name' or r.kind<>a->>'kind' or r.parent_id is distinct from a->>'parent_id') then raise exception 'Conflicting LGD area identity requires review';end if;
 insert into public.lgd_registry_editions(source_hash,source_url,assessed_at,district_count,state_count,active) values(p_hash,'https://lgdirectory.gov.in/',p_date,districts,states,true) on conflict(source_hash) do nothing;
 for item in select a from jsonb_array_elements(p_areas) a order by case when a->>'kind'='state' then 0 else 1 end loop
  insert into public.areas(id,code,kind,name,parent_id,approved) values(item->>'id',item->>'code',item->>'kind',item->>'name',item->>'parent_id',true) on conflict(id) do nothing;
  insert into public.lgd_registry_members(source_hash,area_id) values(p_hash,item->>'id') on conflict do nothing;
 end loop;
 select count(*) into imported from public.lgd_registry_members where source_hash=p_hash;
 if imported<>jsonb_array_length(p_areas) then raise exception 'Registry membership mismatch';end if;
 return districts;
end $$;
revoke all on function public.import_lgd_registry(text,date,jsonb) from public,anon,authenticated;
grant execute on function public.import_lgd_registry(text,date,jsonb) to service_role;

create or replace function public.catalogue_summary() returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('works',count(*),'districtsCovered',count(distinct payload->>'areaId') filter(where exists(select 1 from public.lgd_registry_members m join public.lgd_registry_editions e using(source_hash) join public.areas a on a.id=m.area_id where e.active and a.kind='district' and a.approved and m.area_id=payload->>'areaId')),'districtsExpected',(select district_count from public.lgd_registry_editions where active),'publishedAt',max(created_at)) from public.published_work_receipts;
$$;
