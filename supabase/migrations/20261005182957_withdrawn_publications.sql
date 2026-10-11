-- Public version pointers let invoker queries suppress old snapshots without
-- exposing withdrawn payloads through RLS or privileged callable functions.
create table public.publication_heads (
 work_id uuid primary key references private.works(id),
 publication_version bigint not null
);
alter table public.publication_heads enable row level security;
grant select on public.publication_heads to anon,authenticated;
grant all on public.publication_heads to service_role;
create policy version_pointer_read on public.publication_heads for select
 to anon,authenticated using (true);
insert into public.publication_heads(work_id,publication_version)
 select work_id,max(publication_version) from public.publication_snapshots
 where work_id is not null group by work_id;
create function private.advance_publication_head() returns trigger
language plpgsql security definer set search_path='' as $$ begin
 if NEW.work_id is not null then
 insert into public.publication_heads(work_id,publication_version)
 values(NEW.work_id,NEW.publication_version)
 on conflict(work_id) do update set publication_version=
 greatest(public.publication_heads.publication_version,excluded.publication_version);
 end if;
 return NEW; end $$;
revoke all on function private.advance_publication_head() from public,anon,authenticated;
create trigger advance_publication_head after insert on public.publication_snapshots
 for each row execute function private.advance_publication_head();
alter policy approved_read on public.publication_snapshots
 using (approved and withdrawn_at is null and exists (
 select 1 from public.publication_heads h where h.work_id=publication_snapshots.work_id
 and h.publication_version=publication_snapshots.publication_version));
-- Version identities are immutable. Corrections produce new snapshots.
create function private.immutable_publication_identity() returns trigger
language plpgsql set search_path='' as $$ begin
 if NEW.work_id is distinct from OLD.work_id or NEW.publication_version<>OLD.publication_version then
 raise exception 'Publication identity is immutable'; end if;return NEW;end $$;
revoke all on function private.immutable_publication_identity() from public,anon,authenticated;
create trigger immutable_publication_identity before update on public.publication_snapshots
 for each row execute function private.immutable_publication_identity();
create or replace view public.published_work_receipts with (security_invoker=true) as
 select s.work_id,s.publication_version,s.payload,s.created_at
 from public.publication_snapshots s join public.publication_heads h
 on h.work_id=s.work_id and h.publication_version=s.publication_version
 where s.approved and s.withdrawn_at is null;
