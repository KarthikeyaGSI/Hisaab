create or replace function public.funding_records(p_year text,p_measure text) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(p.payload order by p.record_id),'[]'::jsonb) from private.funding_publications p join private.funding_records f on f.id=p.record_id
 join private.source_documents d on d.id=f.document_id join public.sources s on s.id=d.source_id
 where p.active and s.approved and p.payload->>'financialYear'=p_year and p.payload->>'measure'=p_measure
 and exists(select 1 from private.source_permission_reviews r where r.document_id=f.document_id);
$$;
create or replace function public.funding_history(p_state text,p_programme text) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(p.payload order by p.payload->>'financialYear',p.record_id),'[]'::jsonb) from private.funding_publications p join private.funding_records f on f.id=p.record_id
 join private.source_documents d on d.id=f.document_id join public.sources s on s.id=d.source_id
 where p.active and s.approved and p.payload->>'jurisdiction'=p_state and p.payload->>'programmeId'=p_programme and exists(select 1 from private.source_permission_reviews r where r.document_id=f.document_id);
$$;
-- Explicit source withdrawal revokes funding projections even if earlier permission reviews exist.
create function public.withdraw_funding_source(p_document uuid,p_reason text) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 if length(trim(p_reason))<30 then raise exception 'Documented withdrawal required';end if;
 update private.funding_publications set active=false where record_id in(select id from private.funding_records where document_id=p_document);
 insert into private.audit_events(actor,action,entity_type,entity_id,reason) values(auth.uid(),'withdraw_source','funding',p_document::text,p_reason);
 return true;
end $$;
revoke all on function public.withdraw_funding_source(uuid,text) from public,anon;
grant execute on function public.withdraw_funding_source(uuid,text) to authenticated;
