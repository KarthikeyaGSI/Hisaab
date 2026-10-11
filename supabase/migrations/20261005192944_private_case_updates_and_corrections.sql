create function public.append_private_case_event(p_hash text,p_type text,p_payload jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare event_id uuid;
begin
 perform 1 from private.private_cases where token_hash=p_hash and revoked_at is null and expires_at>now() for update;
 if not found then raise exception 'Active private case required'; end if;
 if p_type not in ('citizen_reported_submission','authority_response','citizen_accepted','reopened') then raise exception 'Citizen event type required'; end if;
 if (select count(*) from private.case_events where case_hash=p_hash)>=100 then raise exception 'Case event limit reached'; end if;
 insert into private.case_events(case_hash,event_type,encrypted_payload) values(p_hash,p_type,p_payload) returning id into event_id;
 return event_id;
end $$;
create function public.list_private_case_events(p_hash text) returns jsonb language sql security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'type',e.event_type,'payload',e.encrypted_payload,'createdAt',e.happened_at) order by e.happened_at,e.id),'[]'::jsonb)
 from private.case_events e join private.private_cases c on c.token_hash=e.case_hash where c.token_hash=p_hash and c.revoked_at is null and c.expires_at>now();
$$;
create function public.submit_private_correction(p_hisaab_id text,p_field text,p_payload jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare work_uuid uuid; correction_id uuid;
begin
 select id into work_uuid from private.works where original_identifiers->>'hisaab_id'=p_hisaab_id and publication_state='approved';
 if not found then raise exception 'Published government work required'; end if;
 if length(p_field)<1 or length(p_field)>100 then raise exception 'Correction field required'; end if;
 insert into private.corrections(work_id,field,reason,supporting_evidence) values(work_uuid,p_field,'Encrypted citizen correction',p_payload) returning id into correction_id;
 return correction_id;
end $$;
create function public.admin_corrections() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not private.is_admin() then raise exception 'MFA administrator required'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',id,'workId',work_id,'field',field,'payload',supporting_evidence,'createdAt',created_at)) from private.corrections where status='pending'),'[]'::jsonb);
end $$;
create function public.review_correction(p_id uuid,p_decision text,p_reason text) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if not private.is_admin() then raise exception 'MFA administrator required'; end if;
 if p_decision not in ('accepted_for_reconciliation','rejected') or length(trim(p_reason))<20 then raise exception 'Documented decision required'; end if;
 update private.corrections set status=p_decision,reviewer=auth.uid(),decision=p_reason where id=p_id and status='pending';
 if not found then raise exception 'Pending correction required'; end if;
 insert into private.audit_events(actor,action,entity_type,entity_id,reason) values(auth.uid(),p_decision,'correction',p_id::text,p_reason);
 return true;
end $$;
revoke all on function public.append_private_case_event(text,text,jsonb),public.list_private_case_events(text),public.submit_private_correction(text,text,jsonb) from public,anon,authenticated;
grant execute on function public.append_private_case_event(text,text,jsonb),public.list_private_case_events(text),public.submit_private_correction(text,text,jsonb) to service_role;
revoke all on function public.admin_corrections(),public.review_correction(uuid,text,text) from public,anon;
grant execute on function public.admin_corrections(),public.review_correction(uuid,text,text) to authenticated;
