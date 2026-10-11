-- Additive protection for direct RPC calls and concurrent publication.
create or replace function public.review_development(p_id text,p_decisions jsonb,p_reason text,p_action text) returns boolean language plpgsql security definer set search_path='' as $$
declare fact private.development_drafts;
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 if length(trim(p_reason))<30 or p_action not in ('publish','withdraw') then raise exception 'Explicit review required';end if;
 select * into fact from private.development_drafts where id=p_id for update;if not found then raise exception 'Draft required';end if;
 select coalesce((select payload from private.development_decisions where record_id=p_id),fact.payload) into fact.payload;
 if p_action='publish' then
  perform pg_advisory_xact_lock(hashtextextended('hisaab:development:'||(fact.payload->>'reconciliationKey'),0));
  if fact.payload->>'origin'='joint' and (jsonb_array_length(fact.payload->'shares')=0 or (select sum((value->>'amountRupees')::numeric) from jsonb_array_elements(fact.payload->'shares'))<>(fact.payload->>'amountRupees')::numeric) then raise exception 'Joint shares must reconcile';end if;
  if (fact.payload->>'periodStart')::date>(fact.payload->>'periodEnd')::date or (fact.payload->>'amountRupees') !~ '^-?[0-9]+\.[0-9]{2}$' or (fact.payload->>'measure'='allocated' and fact.payload->>'accountingBasis'<>'budget') or (fact.payload->>'measure'='released' and fact.payload->>'accountingBasis'<>'release') or (fact.payload->>'measure'='reported_spent' and fact.payload->>'accountingBasis' not in ('booked_expenditure','recipient_utilisation')) then raise exception 'Invalid amount or accounting basis';end if;
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


create or replace function public.review_complaint_route(p_route jsonb,p_reason text) returns boolean language plpgsql security definer set search_path='' as $$ begin
 if not private.is_admin() or length(trim(p_reason))<30 then raise exception 'MFA and official channel evidence required';end if;
 if p_route->>'policyUrl' !~ '^https://' or length(p_route->>'policyNote')<30 or (p_route->>'expiresAt')::date<current_date or p_route->>'jurisdiction' not in ('national','01','02','03','04','05','06','07','08','09','10','11','12','13','14','15','16','17','18','19','20','21','22','23','24','26','27','28','29','30','31','32','33','34','35','36','37','38') or (p_route->>'channel'='email' and (lower(p_route->>'id')='cpgrams' or lower(p_route->>'destination') like '%@pgportal.gov.in' or p_route->>'destination' !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')) or (p_route->>'channel'='portal' and p_route->>'destination' !~ '^https://') then raise exception 'Official accepting route required';end if;
 insert into public.complaint_routes(id,name,jurisdiction,authority,channel,destination,policy_url,policy_note,checked_at,expires_at,approved) values(p_route->>'id',p_route->>'name',p_route->>'jurisdiction',p_route->>'authority',p_route->>'channel',p_route->>'destination',p_route->>'policyUrl',p_route->>'policyNote',current_date,(p_route->>'expiresAt')::date,true) on conflict(id) do update set name=excluded.name,jurisdiction=excluded.jurisdiction,authority=excluded.authority,channel=excluded.channel,destination=excluded.destination,policy_url=excluded.policy_url,policy_note=excluded.policy_note,checked_at=excluded.checked_at,expires_at=excluded.expires_at,approved=true;
 insert into private.audit_events(actor,action,entity_type,entity_id,reason) values(auth.uid(),'verify_route','complaint_route',p_route->>'id',p_reason);return true;end $$;
revoke all on function public.review_complaint_route(jsonb,text) from public,anon;grant execute on function public.review_complaint_route(jsonb,text) to authenticated;

create or replace function public.admin_complaint_evidence(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare hash text;
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 select p.case_hash into hash from private.complaint_packets p join private.private_cases c on c.token_hash=p.case_hash where p.id=p_id and c.revoked_at is null and c.expires_at>now();if not found then raise exception 'Live complaint required';end if;
 return jsonb_build_object('documents',(select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'path',a.original_path,'sha256',a.sha256,'metadata',a.encrypted_metadata)),'[]'::jsonb) from private.case_attachments a where a.case_hash=hash),'photos',(select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'path',m.derivative_path,'sha256',m.derivative_sha256)),'[]'::jsonb) from private.case_media m where m.case_hash=hash and m.derivative_path is not null),'videos',(select coalesce(jsonb_agg(jsonb_build_object('id',v.id,'path',v.path,'paths',v.paths,'payload',v.payload)),'[]'::jsonb) from private.case_videos v where v.case_hash=hash and v.status='complete'));
end $$;
revoke all on function public.admin_complaint_evidence(uuid) from public,anon;grant execute on function public.admin_complaint_evidence(uuid) to authenticated;
