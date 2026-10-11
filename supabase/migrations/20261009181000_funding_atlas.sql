-- Funding is deliberately separate from project money and budget-context tables.
create table private.funding_records(
 id text primary key, document_id uuid not null references private.source_documents(id),
 payload jsonb not null, imported_at timestamptz not null default now()
);
alter table private.funding_records enable row level security;
grant all on private.funding_records to service_role;
create trigger immutable_funding_records before update or delete on private.funding_records for each row execute function private.lock_budget_context();
create index funding_year_measure on private.funding_records((payload->>'financialYear'),(payload->>'measure'));
create table private.funding_decisions(
 id bigint generated always as identity primary key,record_id text not null references private.funding_records(id),
 decision jsonb not null, reason text not null, reviewed_by uuid not null references auth.users(id),created_at timestamptz not null default now()
);
alter table private.funding_decisions enable row level security;
grant all on private.funding_decisions to service_role;
create table private.funding_publications(
 record_id text primary key references private.funding_records(id),decision_id bigint not null references private.funding_decisions(id),
 payload jsonb not null, active boolean not null default true, published_at timestamptz not null default now()
);
alter table private.funding_publications enable row level security;
grant all on private.funding_publications to service_role;

create function public.stage_funding(p_records jsonb) returns integer language plpgsql security definer set search_path='' as $$
declare r jsonb;doc uuid;old jsonb;inserted integer:=0;
begin
 if auth.role()<>'service_role' then raise exception 'Private ingestion only';end if;
 if jsonb_typeof(p_records)<>'array' or jsonb_array_length(p_records)>500 then raise exception 'Bounded records required';end if;
 for r in select value from jsonb_array_elements(p_records) loop
  if r->>'id' is null or length(r->>'id')>240 or r->>'financialYear' !~ '^20(1[6-9]|2[0-6])-20(1[7-9]|2[0-7])$'
   or split_part(r->>'financialYear','-',2)::integer<>split_part(r->>'financialYear','-',1)::integer+1
   or r->>'measure' not in ('allocated','released','reported_spent') or r->>'classification' not in ('included','excluded','mixed_unresolved','awaiting_review')
   or r->>'share' not in ('union','combined','unresolved') or r->>'aggregation' not in ('leaf','context')
   or r->>'instrument' not in ('grant','loan','direct_expenditure','unresolved')
   or r->>'accountingBasis' not in ('union_budget','union_release','union_booked_expenditure','recipient_utilisation')
   or r->>'jurisdiction' !~ '^(national|[0-9]{1,2}|historical:[a-z0-9_-]+)$'
   or (r->>'amountRupees' is not null and r->>'amountRupees' !~ '^-?[0-9]{1,18}\.[0-9]{2}$')
   or length(coalesce(r->'source'->>'locator',''))<1 or r->'source'->>'hash' !~ '^[a-f0-9]{64}$'
   or (r->>'periodStart')::date>(r->>'periodEnd')::date then raise exception 'Invalid funding evidence';end if;
  select id into doc from private.source_documents where sha256=r->'source'->>'hash' and original_url=r->'source'->>'url' limit 1;
  if doc is null then raise exception 'Preserved original required';end if;
  select payload into old from private.funding_records where id=r->>'id';
  if found then if old is distinct from r then raise exception 'Immutable edition conflict';end if;
  else insert into private.funding_records(id,document_id,payload) values(r->>'id',doc,r);inserted:=inserted+1;end if;
 end loop;return inserted;
end $$;
revoke all on function public.stage_funding(jsonb) from public,anon,authenticated;
grant execute on function public.stage_funding(jsonb) to service_role;

create function public.admin_funding(p_year text,p_offset integer default 0,p_query text default '') returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 return (with matching as(select f.* from private.funding_records f where payload->>'financialYear'=p_year and position(lower(left(p_query,200)) in lower(concat(payload->>'programme',' ',payload->>'ministry',' ',payload->>'jurisdictionLabel')))>0)
 select jsonb_build_object('total',(select count(*) from matching),'records',coalesce((select jsonb_agg(x.payload||jsonb_build_object('documentId',x.document_id,'permissionReviewed',exists(select 1 from private.source_permission_reviews pr where pr.document_id=x.document_id),'lastDecision',(select decision from private.funding_decisions d where d.record_id=x.id order by d.id desc limit 1),'published',exists(select 1 from private.funding_publications p where p.record_id=x.id and active))) from(select * from matching order by id limit 20 offset greatest(0,least(100000,p_offset))) x),'[]'::jsonb)));
end $$;
revoke all on function public.admin_funding(text,integer,text) from public,anon;
grant execute on function public.admin_funding(text,integer,text) to authenticated;

create function public.review_funding(p_id text,p_decision jsonb,p_reason text) returns boolean language plpgsql security definer set search_path='' as $$
declare fact private.funding_records;payload jsonb;decision_id bigint;
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 if length(trim(p_reason))<30 or coalesce((p_decision->>'confirmed')::boolean,false) is not true or p_decision->>'classification' not in ('included','excluded','mixed_unresolved','awaiting_review') or p_decision->>'action' not in ('save','publish','withdraw') then raise exception 'Explicit documented decision required';end if;
 select * into fact from private.funding_records where id=p_id for update;if not found then raise exception 'Record required';end if;
 payload:=fact.payload||jsonb_build_object('classification',p_decision->>'classification');
 if p_decision->>'action'='publish' then
  if p_decision->>'classification'<>'included' or payload->>'share'<>'union' or payload->>'aggregation'<>'leaf' or payload->>'amountRupees' is null or payload->>'instrument'='unresolved' or (payload->>'conflict')::boolean is distinct from false
   or not exists(select 1 from private.source_permission_reviews where document_id=fact.document_id)
   or not (coalesce((p_decision->>'sourceChecked')::boolean,false) and coalesce((p_decision->>'unitsChecked')::boolean,false) and coalesce((p_decision->>'jurisdictionChecked')::boolean,false) and coalesce((p_decision->>'scopeChecked')::boolean,false) and coalesce((p_decision->>'editionsChecked')::boolean,false)) then raise exception 'Evidence and rights gates incomplete';end if;
  -- A single published accounting scope cannot contain overlapping reporting periods,
  -- regardless of source, edition or cumulative cut-off. Withdraw superseded facts first.
  if exists(select 1 from private.funding_publications p where p.active and p.record_id<>p_id and
   p.payload->>'coverageKey'=payload->>'coverageKey' and p.payload->>'jurisdiction'=payload->>'jurisdiction' and
   p.payload->>'financialYear'=payload->>'financialYear' and p.payload->>'measure'=payload->>'measure' and
   p.payload->>'estimate'=payload->>'estimate' and p.payload->>'accountingBasis'=payload->>'accountingBasis' and
   (p.payload->>'periodStart')::date<=(payload->>'periodEnd')::date and (payload->>'periodStart')::date<=(p.payload->>'periodEnd')::date) then raise exception 'Overlapping edition: withdraw previous publication first';end if;
 end if;
 insert into private.funding_decisions(record_id,decision,reason,reviewed_by) values(p_id,p_decision,p_reason,auth.uid()) returning id into decision_id;
 -- Any re-review removes the prior public snapshot until an explicit publication.
 update private.funding_publications set active=false where record_id=p_id;
 if p_decision->>'action'='publish' then insert into private.funding_publications(record_id,decision_id,payload) values(p_id,decision_id,payload) on conflict(record_id) do update set decision_id=excluded.decision_id,payload=excluded.payload,active=true,published_at=now();end if;
 insert into private.audit_events(actor,action,entity_type,entity_id,reason) values(auth.uid(),p_decision->>'action','funding',p_id,p_reason);
 return true;
end $$;
revoke all on function public.review_funding(text,jsonb,text) from public,anon;
grant execute on function public.review_funding(text,jsonb,text) to authenticated;

create function public.funding_records(p_year text,p_measure text) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(p.payload order by p.record_id),'[]'::jsonb) from private.funding_publications p join private.funding_records f on f.id=p.record_id
 where p.active and p.payload->>'financialYear'=p_year and p.payload->>'measure'=p_measure
 and exists(select 1 from private.source_permission_reviews r where r.document_id=f.document_id);
$$;
revoke all on function public.funding_records(text,text) from public;
grant execute on function public.funding_records(text,text) to anon,authenticated;
