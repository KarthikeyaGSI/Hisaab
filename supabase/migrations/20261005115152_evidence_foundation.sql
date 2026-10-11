create extension if not exists postgis with schema extensions;
create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to service_role;

create table private.admin_members (
 user_id uuid primary key references auth.users(id), enabled boolean not null default true,
 created_at timestamptz not null default now()
);
alter table private.admin_members enable row level security;
create function private.is_admin() returns boolean language sql stable security definer set search_path = '' as $$
 select auth.uid() is not null and auth.jwt()->>'aal' = 'aal2' and exists (
  select 1 from private.admin_members where user_id=auth.uid() and enabled
 );
$$;
revoke all on function private.is_admin() from public, anon;
grant usage on schema private to authenticated;
grant execute on function private.is_admin() to authenticated;

create table public.areas (
 id text primary key, code text not null, kind text not null check(kind in ('country','state','district','subdistrict','block','village','gp','ulb','ward')),
 name text not null, parent_id text references public.areas(id), aliases text[] not null default '{}',
 valid_from date, valid_to date, boundary_source text, boundary_edition text, boundary_license text,
 boundary extensions.geometry(MultiPolygon,4326), approved boolean not null default false,
 unique(code,kind,valid_from)
);
create index areas_parent on public.areas(parent_id);
create index areas_boundary on public.areas using gist(boundary);
create table private.area_crosswalks (
 id uuid primary key default gen_random_uuid(), historical_area text references public.areas(id),
 current_area text references public.areas(id), relation text not null, evidence_document uuid, reviewed boolean not null default false
);
create table public.sources (
 id text primary key, name text not null, official_url text not null check(official_url ~ '^https://'),
 family text not null, access_method text not null, terms_url text, reuse_permission text,
 acquisition_status text not null default 'unassessed', last_checked timestamptz, approved boolean not null default false
);
create table private.source_documents (
 id uuid primary key default gen_random_uuid(), source_id text not null references public.sources(id),
 original_url text not null, sha256 text not null check(sha256 ~ '^[a-f0-9]{64}$'), storage_path text not null,
 content_type text not null, retrieved_at timestamptz not null default now(), original_date date,
 query_manifest jsonb not null default '{}', license_basis text, parser_version text,
 supersedes uuid references private.source_documents(id), unique(source_id,sha256)
);
create table private.authorities (
 id uuid primary key default gen_random_uuid(), name text not null, jurisdiction text references public.areas(id),
 role text not null, evidence_document uuid references private.source_documents(id), locator text,
 verified_at timestamptz, routing_url text, filing_method text, filing_requirements jsonb, published_sla jsonb
);
create table private.works (
 id uuid primary key default gen_random_uuid(), title text not null, purpose text, area_id text references public.areas(id),
 original_identifiers jsonb not null default '{}', financial_year text, source_id text references public.sources(id),
 location extensions.geometry(Point,4326), location_precision text not null default 'unknown' check(location_precision in ('source_point','address','district','unknown')),
 authority_id uuid references private.authorities(id), physical_verification text not null default 'not_independently_verified',
 publication_state text not null default 'pending' check(publication_state in ('pending','approved','withdrawn')),
 created_at timestamptz not null default now()
);
create index works_area on private.works(area_id);
create index works_location on private.works using gist(location);
create table private.facts (
 id uuid primary key default gen_random_uuid(), work_id uuid not null references private.works(id),
 stage text not null, field text not null, original_text text not null, normalized_value jsonb,
 document_id uuid not null references private.source_documents(id), locator text not null,
 effective_date date, extraction_method text not null, extraction_version text not null,
 reviewed_by uuid references auth.users(id), reviewed_at timestamptz, supersedes uuid references private.facts(id)
);
create table private.financial_events (
 id uuid primary key default gen_random_uuid(), work_id uuid not null references private.works(id),
 canonical_event_id text not null, measure text not null check(measure in ('allocation','sanction','estimate','contract','variation','gross_bill','deduction','payment','transfer')),
 amount numeric(24,2) not null, original_amount text not null, original_unit text not null, currency text not null default 'INR',
 event_kind text not null check(event_kind in ('transaction','cumulative','reversal')),
 event_date date, financial_year text, fact_id uuid not null references private.facts(id),
 approved boolean not null default false, supersedes uuid references private.financial_events(id),
 check(event_kind <> 'reversal' or amount <= 0)
);
create index financial_events_work on private.financial_events(work_id,measure,event_date);
create table private.match_decisions (
 id uuid primary key default gen_random_uuid(), left_id text not null, right_id text not null,
 method text not null, evidence jsonb not null, status text not null default 'pending', reviewer uuid references auth.users(id), reviewed_at timestamptz
);
create table private.flags (
 id uuid primary key default gen_random_uuid(), work_id uuid references private.works(id), category text not null,
 rule_version text not null, explanation text not null, evidence jsonb not null, uncertainty text not null,
 source_search_success boolean not null default false, expected_record_basis text,
 status text not null default 'pending', reviewer uuid references auth.users(id),
 check(category <> 'missing_record' or (source_search_success and expected_record_basis is not null))
);
create table private.ingestion_runs (
 id uuid primary key default gen_random_uuid(), source_id text references public.sources(id),
 partition jsonb not null, state text not null default 'queued', checkpoint jsonb, attempts integer not null default 0,
 started_at timestamptz, finished_at timestamptz, failure_reason text, parser_version text
);
create table public.coverage_cells (
 id uuid primary key default gen_random_uuid(), source_id text not null references public.sources(id), area_id text references public.areas(id),
 financial_year text not null, record_type text not null, stage text not null,
 status text not null, record_count bigint, expected_count bigint, denominator_basis text,
 last_success_at timestamptz, failure_reason text, approved boolean not null default false,
 unique(source_id,area_id,financial_year,record_type,stage)
);
create table private.ai_runs (
 id uuid primary key default gen_random_uuid(), document_id uuid references private.source_documents(id),
 provider text not null, model text not null, prompt_version text not null, input_hash text not null,
 output jsonb, estimated_cost numeric(12,4), status text not null, review_decision text
);
create table private.private_cases (
 token_hash text primary key check(token_hash ~ '^[a-f0-9]{64}$'), reference text unique not null,
 encrypted_payload jsonb not null, created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(), expires_at timestamptz not null default now()+interval '12 months', revoked_at timestamptz
);
create table private.case_events (
 id uuid primary key default gen_random_uuid(), case_hash text references private.private_cases(token_hash) on delete cascade,
 event_type text not null check(event_type in ('observation','packet_ready','citizen_reported_submission','acknowledgement_uploaded','acknowledged','authority_response','authority_closed','citizen_accepted','independently_verified','reopened')),
 evidence_path text, encrypted_payload jsonb, happened_at timestamptz not null default now(), verified_by uuid references auth.users(id)
);
create table private.case_media (
 id uuid primary key default gen_random_uuid(), case_hash text references private.private_cases(token_hash) on delete cascade,
 original_path text not null, original_sha256 text not null, derivative_path text, derivative_sha256 text,
 state text not null default 'quarantined', consent_public boolean not null default false,
 created_at timestamptz not null default now()
);
create table private.corrections (
 id uuid primary key default gen_random_uuid(), work_id uuid references private.works(id),
 field text not null, reason text not null, supporting_evidence jsonb, status text not null default 'pending',
 reviewer uuid references auth.users(id), decision text, created_at timestamptz not null default now()
);
create table private.audit_events (
 id uuid primary key default gen_random_uuid(), actor uuid references auth.users(id),
 action text not null, entity_type text not null, entity_id text not null, before_hash text, after_hash text,
 reason text not null, created_at timestamptz not null default now()
);
create table public.publication_snapshots (
 id uuid primary key default gen_random_uuid(), work_id uuid references private.works(id),
 publication_version bigint not null, payload jsonb not null, reviewed_by uuid not null references auth.users(id),
 approved boolean not null default false, withdrawn_at timestamptz,
 created_at timestamptz not null default now(),
 check(coalesce((payload->>'demo')::boolean,false)=false), unique(work_id,publication_version)
);
create view public.published_work_receipts with (security_invoker=true) as
 select distinct on(work_id) work_id, publication_version, payload, created_at
 from public.publication_snapshots where approved and withdrawn_at is null order by work_id,publication_version desc;

do $$ declare t text; begin
 for t in select tablename from pg_tables where schemaname='private' loop
  execute format('alter table private.%I enable row level security',t);
  execute format('grant all on private.%I to service_role',t);
 end loop;
 for t in select unnest(array['areas','sources','coverage_cells','publication_snapshots']) loop
  execute format('alter table public.%I enable row level security',t);
  execute format('grant select on public.%I to anon, authenticated',t);
  execute format('grant all on public.%I to service_role',t);
  execute format('create policy approved_read on public.%I for select to anon, authenticated using (approved)',t);
 end loop;
end $$;
grant select on public.published_work_receipts to anon,authenticated,service_role;

create function public.store_private_case(p_hash text,p_reference text,p_payload jsonb) returns boolean
language plpgsql security definer set search_path='' as $$ begin
 insert into private.private_cases(token_hash,reference,encrypted_payload) values(p_hash,p_reference,p_payload);
 return true; end $$;
create function public.read_private_case(p_hash text) returns jsonb
language sql security definer set search_path='' as $$
 select encrypted_payload from private.private_cases where token_hash=p_hash and revoked_at is null and expires_at>now();
$$;
create function public.delete_private_case(p_hash text) returns boolean
language plpgsql security definer set search_path='' as $$ begin
 delete from private.private_cases where token_hash=p_hash; return found; end $$;
revoke all on function public.store_private_case(text,text,jsonb),public.read_private_case(text),public.delete_private_case(text) from public,anon,authenticated;
grant execute on function public.store_private_case(text,text,jsonb),public.read_private_case(text),public.delete_private_case(text) to service_role;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('source-originals','source-originals',false,104857600,array['application/pdf','text/csv','application/json','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']),
 ('case-originals','case-originals',false,20971520,array['image/jpeg','image/png','image/webp','application/pdf']),
 ('case-derivatives','case-derivatives',false,10485760,array['image/png','image/webp'])
on conflict(id) do nothing;
-- No citizen storage policies: upload validation and case capabilities are server-controlled.
