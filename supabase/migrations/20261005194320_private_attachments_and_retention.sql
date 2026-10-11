create table private.case_attachments(
 id uuid primary key default gen_random_uuid(),case_hash text not null references private.private_cases(token_hash) on delete cascade,
 original_path text not null,sha256 text not null check(sha256 ~ '^[a-f0-9]{64}$'),encrypted_metadata jsonb not null,created_at timestamptz not null default now()
);
alter table private.case_attachments enable row level security;
grant all on private.case_attachments to service_role;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('case-documents','case-documents',false,11534336,array['application/octet-stream']) on conflict(id) do nothing;
create function public.register_case_attachment(p_id uuid,p_hash text,p_path text,p_sha text,p_metadata jsonb,p_event jsonb default null) returns uuid language plpgsql security definer set search_path='' as $$
begin
 perform 1 from private.private_cases where token_hash=p_hash and revoked_at is null and expires_at>now() for update;
 if not found then raise exception 'Active case required';end if;
 if p_path<>p_hash||'/'||p_id::text||'.enc' then raise exception 'Invalid private attachment path';end if;
 if (select count(*) from private.case_attachments where case_hash=p_hash)>=10 then raise exception 'Attachment limit';end if;
 insert into private.case_attachments(id,case_hash,original_path,sha256,encrypted_metadata) values(p_id,p_hash,p_path,p_sha,p_metadata);
 if p_event is not null then
  if (select count(*) from private.case_events where case_hash=p_hash)>=100 then raise exception 'Case event limit';end if;
  insert into private.case_events(case_hash,event_type,evidence_path,encrypted_payload) values(p_hash,'acknowledgement_uploaded',p_path,p_event);
 end if;return p_id;
end $$;
create function public.list_case_attachments(p_hash text) returns jsonb language sql security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'path',a.original_path,'sha256',a.sha256,'metadata',a.encrypted_metadata,'createdAt',a.created_at) order by a.created_at),'[]'::jsonb)
 from private.case_attachments a join private.private_cases c on c.token_hash=a.case_hash where c.token_hash=p_hash and c.revoked_at is null and c.expires_at>now();
$$;
create function public.expired_case_files(p_limit integer default 100) returns jsonb language sql security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('hash',c.token_hash,'photos',(select coalesce(jsonb_agg(jsonb_build_object('original',m.original_path,'derivative',m.derivative_path)),'[]'::jsonb) from private.case_media m where m.case_hash=c.token_hash),'documents',(select coalesce(jsonb_agg(a.original_path),'[]'::jsonb) from private.case_attachments a where a.case_hash=c.token_hash))),'[]'::jsonb)
 from (select token_hash from private.private_cases where expires_at<now() order by expires_at limit greatest(1,least(p_limit,100))) c;
$$;
create function public.delete_expired_case(p_hash text) returns boolean language plpgsql security definer set search_path='' as $$
begin
 delete from private.private_cases where token_hash=p_hash and expires_at<now();return found;
end $$;
revoke all on function public.register_case_attachment(uuid,text,text,text,jsonb,jsonb),public.list_case_attachments(text),public.expired_case_files(integer),public.delete_expired_case(text) from public,anon,authenticated;
grant execute on function public.register_case_attachment(uuid,text,text,text,jsonb,jsonb),public.list_case_attachments(text),public.expired_case_files(integer),public.delete_expired_case(text) to service_role;
