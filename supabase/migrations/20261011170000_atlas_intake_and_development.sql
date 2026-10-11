-- Additive infrastructure. Imports never publish and all owner actions retain MFA.
create table private.atlas_batches(
 id text primary key,sha256 text not null check(sha256 ~ '^[a-f0-9]{64}$'),
 payload jsonb not null,created_at timestamptz not null default now(),reviewed_by uuid not null references auth.users(id)
);
alter table private.atlas_batches enable row level security;
grant all on private.atlas_batches to service_role;
create table private.development_drafts(
 id text primary key,document_id uuid not null references private.source_documents(id),
 payload jsonb not null,batch_id text not null references private.atlas_batches(id)
);
alter table private.development_drafts enable row level security;
grant all on private.development_drafts to service_role;
create trigger immutable_development_drafts before update or delete on private.development_drafts for each row execute function private.lock_budget_context();
create table private.development_publications(
 record_id text primary key references private.development_drafts(id),payload jsonb not null,
 active boolean not null default true,reviewed_by uuid not null references auth.users(id),reason text not null,
 decisions jsonb not null,published_at timestamptz not null default now()
);
alter table private.development_publications enable row level security;
grant all on private.development_publications to service_role;

create function public.stage_atlas_batch(p_payload jsonb,p_sha text) returns jsonb language plpgsql security definer set search_path='' as $$
declare previous private.atlas_batches; r jsonb; doc uuid;
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 if p_payload->>'version'<>'hisaab-intake/1' or p_sha !~ '^[a-f0-9]{64}$' or length(p_payload->>'batchId') not between 1 and 240 or octet_length(p_payload::text)>2097152 then raise exception 'Invalid bounded intake';end if;
 if pg_database_size(current_database())>445644800 then raise exception '425 MiB intake guard reached; preserve package outside database';end if;
 select * into previous from private.atlas_batches where id=p_payload->>'batchId';
 if found then if previous.sha256<>p_sha then raise exception 'Immutable batch identity conflict';end if;return jsonb_build_object('inserted',false,'id',previous.id);end if;
 for r in select value from jsonb_array_elements(p_payload->'sources') loop
  if not exists(select 1 from private.source_documents where sha256=r->>'hash' and original_url=r->>'url' and storage_path=r->>'storagePath') then raise exception 'Registered preserved original required';end if;
 end loop;
 insert into private.atlas_batches(id,sha256,payload,reviewed_by) values(p_payload->>'batchId',p_sha,p_payload,auth.uid());
 for r in select value from jsonb_array_elements(p_payload->'funding') loop
  select id into doc from private.source_documents where sha256=r->'source'->>'hash' and original_url=r->'source'->>'url' limit 1;
  if doc is null then raise exception 'Preserved funding original required';end if;
  if exists(select 1 from private.development_drafts where id=r->>'id' and payload is distinct from r) then raise exception 'Immutable funding edition conflict';end if;
  insert into private.development_drafts(id,document_id,payload,batch_id) values(r->>'id',doc,r,p_payload->>'batchId') on conflict(id) do nothing;
 end loop;
 insert into private.audit_events(actor,action,entity_type,entity_id,reason) values(auth.uid(),'stage','atlas_batch',p_payload->>'batchId','Validated agent package staged privately; no publication');
 return jsonb_build_object('inserted',true,'id',p_payload->>'batchId');
end $$;
revoke all on function public.stage_atlas_batch(jsonb,text) from public,anon;
grant execute on function public.stage_atlas_batch(jsonb,text) to authenticated;

create function public.admin_atlas_batches(p_id text default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 if p_id is not null then return (select jsonb_build_object('id',id,'hash',sha256,'payload',payload,'createdAt',created_at) from private.atlas_batches where id=p_id);end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',id,'hash',sha256,'jurisdiction',payload->>'jurisdiction','cutoff',payload->>'cutoff','createdAt',created_at,'projects',jsonb_array_length(payload->'projects'),'funding',jsonb_array_length(payload->'funding'),'payments',jsonb_array_length(payload->'payments'))) from(select * from private.atlas_batches order by created_at desc limit 100)b),'[]'::jsonb);
end $$;
revoke all on function public.admin_atlas_batches(text) from public,anon;
grant execute on function public.admin_atlas_batches(text) to authenticated;

create function public.development_records(p_year text,p_measure text) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(p.payload order by p.record_id),'[]'::jsonb)
 from private.development_publications p join private.development_drafts f on f.id=p.record_id
 join private.source_documents d on d.id=f.document_id join public.sources s on s.id=d.source_id
 where p.active and s.approved and p.payload->>'financialYear'=p_year and p.payload->>'measure'=p_measure
 and exists(select 1 from private.source_permission_reviews r where r.document_id=d.id);
$$;
revoke all on function public.development_records(text,text) from public;
grant execute on function public.development_records(text,text) to anon,authenticated;

create function public.review_development(p_id text,p_decisions jsonb,p_reason text,p_action text) returns boolean language plpgsql security definer set search_path='' as $$
declare fact private.development_drafts;
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 if length(trim(p_reason))<30 or p_action not in ('publish','withdraw') then raise exception 'Explicit review required';end if;
 select * into fact from private.development_drafts where id=p_id for update;if not found then raise exception 'Draft required';end if;
 if p_action='publish' then
  if not (coalesce((p_decisions->>'sourceChecked')::boolean,false) and coalesce((p_decisions->>'unitsChecked')::boolean,false) and coalesce((p_decisions->>'jurisdictionChecked')::boolean,false) and coalesce((p_decisions->>'scopeChecked')::boolean,false) and coalesce((p_decisions->>'editionsChecked')::boolean,false) and coalesce((p_decisions->>'nonOverlapChecked')::boolean,false) and coalesce((p_decisions->>'confirmed')::boolean,false)) then raise exception 'Evidence review gates incomplete';end if;
  if fact.payload->>'classification'<>'included' or fact.payload->>'aggregation'<>'leaf' or fact.payload->>'amountRupees' is null or fact.payload->>'instrument'='unresolved' or (fact.payload->>'conflict')::boolean is distinct from false then raise exception 'Unresolved records cannot be published';end if;
  if not exists(select 1 from private.source_permission_reviews r join private.source_documents d on d.id=r.document_id join public.sources s on s.id=d.source_id where r.document_id=fact.document_id and s.approved) then raise exception 'Source rights review required';end if;
  if exists(select 1 from private.development_publications p where p.active and p.record_id<>p_id and p.payload->>'reconciliationKey'=fact.payload->>'reconciliationKey' and p.payload->>'jurisdiction'=fact.payload->>'jurisdiction' and p.payload->>'scope'=fact.payload->>'scope' and p.payload->>'measure'=fact.payload->>'measure' and p.payload->>'estimate'=fact.payload->>'estimate' and p.payload->>'accountingBasis'=fact.payload->>'accountingBasis' and (p.payload->>'periodStart')::date<=(fact.payload->>'periodEnd')::date and (fact.payload->>'periodStart')::date<=(p.payload->>'periodEnd')::date) then raise exception 'Overlapping edition must be withdrawn first';end if;
  insert into private.development_publications(record_id,payload,reviewed_by,reason,decisions) values(p_id,fact.payload,auth.uid(),p_reason,p_decisions) on conflict(record_id) do update set active=true,payload=excluded.payload,reviewed_by=excluded.reviewed_by,reason=excluded.reason,decisions=excluded.decisions,published_at=now();
 else update private.development_publications set active=false where record_id=p_id;end if;
 insert into private.audit_events(actor,action,entity_type,entity_id,reason) values(auth.uid(),p_action,'development',p_id,p_reason);return true;
end $$;
revoke all on function public.review_development(text,jsonb,text,text) from public,anon;
grant execute on function public.review_development(text,jsonb,text,text) to authenticated;

-- Pages retain every project identity; the browser draws GPU points rather than DOM clusters.
create function public.catalogue_map_points(p_west numeric,p_south numeric,p_east numeric,p_north numeric,p_query text default '',p_purpose text default null,p_year text default null,p_state text default null,p_offset integer default 0) returns jsonb language sql stable security invoker set search_path='' as $$
 with matching as(select work_id,payload from public.published_work_receipts where payload->>'locationPrecision' in ('source_point','address') and jsonb_typeof(payload->'location')='array' and (payload->'location'->>0)::numeric between p_west and p_east and (payload->'location'->>1)::numeric between p_south and p_north and (p_purpose is null or payload->>'purpose'=p_purpose) and (p_year is null or payload->>'financialYear'=p_year) and (p_state is null or payload->>'state'=p_state) and position(lower(left(p_query,200)) in lower(concat(payload->>'title',' ',payload->>'state',' ',payload->>'district',' ',payload->>'officialIds')))>0),page as(select * from matching order by work_id limit 5000 offset greatest(0,p_offset))
 select jsonb_build_object('type','FeatureCollection','features',coalesce((select jsonb_agg(jsonb_build_object('type','Feature','geometry',jsonb_build_object('type','Point','coordinates',payload->'location'),'properties',jsonb_build_object('id',payload->>'id','title',payload->>'title','purpose',payload->>'purpose'))) from page),'[]'::jsonb),'total',(select count(*) from matching),'nextOffset',case when (select count(*) from matching)>p_offset+5000 then p_offset+5000 else null end);
$$;
revoke all on function public.catalogue_map_points(numeric,numeric,numeric,numeric,text,text,text,text,integer) from public;
grant execute on function public.catalogue_map_points(numeric,numeric,numeric,numeric,text,text,text,text,integer) to anon,authenticated;
