create table public.complaint_routes(id text primary key,name text not null,jurisdiction text not null,authority text not null,channel text not null check(channel in ('portal','email','postal')),destination text not null,policy_url text not null,policy_note text not null,checked_at date not null,expires_at date not null,approved boolean not null default false);
alter table public.complaint_routes enable row level security;
create policy reviewed_routes on public.complaint_routes for select to anon,authenticated using(approved and expires_at>=current_date);
grant select on public.complaint_routes to anon,authenticated;grant all on public.complaint_routes to service_role;
insert into public.complaint_routes values('cpgrams','CPGRAMS service-delivery grievance','national','Union ministries and participating state departments','portal','https://pgportal.gov.in/','https://pgportal.gov.in/','Citizen registers on the official portal. Emails are not accepted. RTI and court matters are excluded. Confirm the record-holding department before submission.',current_date,current_date+90,true);
create table private.complaint_packets(id uuid primary key default gen_random_uuid(),case_hash text not null references private.private_cases(token_hash) on delete cascade,route_id text not null references public.complaint_routes(id),payload jsonb not null,sha256 text not null check(sha256~'^[a-f0-9]{64}$'),status text not null default 'prepared' check(status in ('prepared','ready','dispatching','sent','ambiguous','failed','declined','acknowledged')),reason text,reviewed_by uuid references auth.users(id),created_at timestamptz not null default now(),provider_id text,unique(case_hash));
alter table private.complaint_packets enable row level security;grant all on private.complaint_packets to service_role;
create function public.prepare_complaint(p_hash text,p_route text,p_payload jsonb,p_sha text) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
 if not exists(select 1 from private.private_cases where token_hash=p_hash and revoked_at is null and expires_at>now()) then raise exception 'Live case required';end if;
 if p_sha !~ '^[a-f0-9]{64}$' or octet_length(p_payload::text)>50000 or not exists(select 1 from public.complaint_routes where id=p_route and approved and expires_at>=current_date) then raise exception 'Verified route and bounded packet required';end if;
 insert into private.complaint_packets(case_hash,route_id,payload,sha256) values(p_hash,p_route,p_payload,p_sha) returning id into result;return result;
end $$;
create function public.read_complaint(p_hash text) returns jsonb language sql stable security definer set search_path='' as $$ select jsonb_build_object('id',p.id,'status',p.status,'payload',p.payload,'createdAt',p.created_at,'providerId',p.provider_id) from private.complaint_packets p join private.private_cases c on c.token_hash=p.case_hash where c.token_hash=p_hash and c.revoked_at is null and c.expires_at>now(); $$;
revoke all on function public.prepare_complaint(text,text,jsonb,text),public.read_complaint(text) from public,anon,authenticated;grant execute on function public.prepare_complaint(text,text,jsonb,text),public.read_complaint(text) to service_role;
create function public.admin_complaints() returns jsonb language plpgsql stable security definer set search_path='' as $$ begin if not private.is_admin() then raise exception 'MFA administrator required';end if;return coalesce((select jsonb_agg(row_to_json(p)) from(select p.id,p.route_id,p.payload,p.sha256,p.status,p.created_at,c.reference from private.complaint_packets p join private.private_cases c on c.token_hash=p.case_hash where c.revoked_at is null and c.expires_at>now() order by p.created_at desc limit 100)p),'[]'::jsonb);end $$;
revoke all on function public.admin_complaints() from public,anon;grant execute on function public.admin_complaints() to authenticated;
create function public.review_complaint(p_id uuid,p_action text,p_reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare packet private.complaint_packets;
begin
 if not private.is_admin() or length(trim(p_reason))<30 then raise exception 'MFA and evidence review required';end if;
 select * into packet from private.complaint_packets where id=p_id for update;if not found then raise exception 'Packet required';end if;
 if not exists(select 1 from private.private_cases where token_hash=packet.case_hash and revoked_at is null and expires_at>now()) then raise exception 'Case expired';end if;
 if p_action='decline' and packet.status in ('prepared','ready') then update private.complaint_packets set status='declined',reason=p_reason,reviewed_by=auth.uid() where id=p_id;
 elsif p_action='ready' and packet.status='prepared' then update private.complaint_packets set status='ready',reason=p_reason,reviewed_by=auth.uid() where id=p_id;
 elsif p_action='send' and packet.status='ready' then
  if not exists(select 1 from public.complaint_routes where id=packet.route_id and approved and expires_at>=current_date and channel='email') then raise exception 'This route requires citizen portal or postal filing';end if;
  update private.complaint_packets set status='dispatching',reviewed_by=auth.uid(),reason=p_reason where id=p_id;
 else raise exception 'Invalid transition; delivery is never automatically retried';end if;
 insert into private.audit_events(actor,action,entity_type,entity_id,reason) values(auth.uid(),p_action,'complaint',p_id::text,p_reason);
 return jsonb_build_object('id',packet.id,'route',packet.route_id,'payload',packet.payload,'hash',packet.sha256);
end $$;
revoke all on function public.review_complaint(uuid,text,text) from public,anon;grant execute on function public.review_complaint(uuid,text,text) to authenticated;
create function public.finish_complaint(p_id uuid,p_status text,p_provider text) returns boolean language plpgsql security definer set search_path='' as $$ begin if p_status not in ('sent','ambiguous','failed') then raise exception 'Invalid transport state';end if;update private.complaint_packets set status=p_status,provider_id=p_provider where id=p_id and status='dispatching';return found;end $$;
revoke all on function public.finish_complaint(uuid,text,text) from public,anon,authenticated;grant execute on function public.finish_complaint(uuid,text,text) to service_role;
create function public.review_complaint_route(p_route jsonb,p_reason text) returns boolean language plpgsql security definer set search_path='' as $$ begin
 if not private.is_admin() or length(trim(p_reason))<30 then raise exception 'MFA and official channel evidence required';end if;
 insert into public.complaint_routes(id,name,jurisdiction,authority,channel,destination,policy_url,policy_note,checked_at,expires_at,approved) values(p_route->>'id',p_route->>'name',p_route->>'jurisdiction',p_route->>'authority',p_route->>'channel',p_route->>'destination',p_route->>'policyUrl',p_route->>'policyNote',current_date,(p_route->>'expiresAt')::date,true) on conflict(id) do update set name=excluded.name,jurisdiction=excluded.jurisdiction,authority=excluded.authority,channel=excluded.channel,destination=excluded.destination,policy_url=excluded.policy_url,policy_note=excluded.policy_note,checked_at=excluded.checked_at,expires_at=excluded.expires_at,approved=true;
 insert into private.audit_events(actor,action,entity_type,entity_id,reason) values(auth.uid(),'verify_route','complaint_route',p_route->>'id',p_reason);return true;end $$;
revoke all on function public.review_complaint_route(jsonb,text) from public,anon;grant execute on function public.review_complaint_route(jsonb,text) to authenticated;
