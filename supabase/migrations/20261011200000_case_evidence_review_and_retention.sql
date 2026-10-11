create or replace function public.expired_case_files(p_limit integer default 100) returns jsonb language sql security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('hash',c.token_hash,'photos',(select coalesce(jsonb_agg(jsonb_build_object('original',m.original_path,'derivative',m.derivative_path)),'[]'::jsonb) from private.case_media m where m.case_hash=c.token_hash),'documents',(select coalesce(jsonb_agg(a.original_path),'[]'::jsonb) from private.case_attachments a where a.case_hash=c.token_hash),'videos',(select coalesce(jsonb_agg(v.path),'[]'::jsonb) from private.case_videos v where v.case_hash=c.token_hash))),'[]'::jsonb) from(select token_hash from private.private_cases where expires_at<now() order by expires_at limit greatest(1,least(p_limit,100)))c;
$$;
create function public.delete_case_video(p_hash text,p_id uuid) returns boolean language plpgsql security definer set search_path='' as $$ begin delete from private.case_videos where case_hash=p_hash and id=p_id and exists(select 1 from private.private_cases where token_hash=p_hash and revoked_at is null and expires_at>now());return found;end $$;
revoke all on function public.delete_case_video(text,uuid) from public,anon,authenticated;grant execute on function public.delete_case_video(text,uuid) to service_role;
create function public.admin_complaint_evidence(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare hash text;
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 select p.case_hash into hash from private.complaint_packets p join private.private_cases c on c.token_hash=p.case_hash where p.id=p_id and c.revoked_at is null and c.expires_at>now();if not found then raise exception 'Live complaint required';end if;
 return jsonb_build_object('documents',(select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'path',a.original_path,'sha256',a.sha256,'metadata',a.encrypted_metadata)),'[]'::jsonb) from private.case_attachments a where a.case_hash=hash),'photos',(select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'path',m.derivative_path,'sha256',m.derivative_sha256)),'[]'::jsonb) from private.case_media m where m.case_hash=hash and m.derivative_path is not null),'videos',(select coalesce(jsonb_agg(jsonb_build_object('id',v.id,'path',v.path,'payload',v.payload)),'[]'::jsonb) from private.case_videos v where v.case_hash=hash and v.status='complete'));
end $$;
revoke all on function public.admin_complaint_evidence(uuid) from public,anon;grant execute on function public.admin_complaint_evidence(uuid) to authenticated;
create function public.acknowledge_complaint(p_id uuid,p_attachment uuid,p_payload jsonb,p_reason text) returns boolean language plpgsql security definer set search_path='' as $$
declare hash text;
begin
 if not private.is_admin() or length(trim(p_reason))<30 then raise exception 'MFA and documentary acknowledgement review required';end if;
 select case_hash into hash from private.complaint_packets where id=p_id for update;if not found then raise exception 'Packet required';end if;
 if not exists(select 1 from private.private_cases where token_hash=hash and revoked_at is null and expires_at>now()) or not exists(select 1 from private.case_attachments where id=p_attachment and case_hash=hash) then raise exception 'Preserved acknowledgement in this live case required';end if;
 if (select count(*) from private.case_events where case_hash=hash)>=100 then raise exception 'Case event limit';end if;
 update private.complaint_packets set status='acknowledged',reason=p_reason,reviewed_by=auth.uid() where id=p_id;
 insert into private.case_events(case_hash,event_type,evidence_path,encrypted_payload,verified_by) values(hash,'acknowledged',(select original_path from private.case_attachments where id=p_attachment),p_payload,auth.uid());
 insert into private.audit_events(actor,action,entity_type,entity_id,reason) values(auth.uid(),'acknowledge','complaint',p_id::text,p_reason);return true;
end $$;
revoke all on function public.acknowledge_complaint(uuid,uuid,jsonb,text) from public,anon;grant execute on function public.acknowledge_complaint(uuid,uuid,jsonb,text) to authenticated;
