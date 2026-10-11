-- Qualify the reviewed fact independently of SQL payload columns.
create or replace function public.review_funding(p_id text,p_decision jsonb,p_reason text) returns boolean language plpgsql security definer set search_path='' as $$
declare fact private.funding_records;reviewed_payload jsonb;review_decision_id bigint;
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 if length(trim(p_reason))<30 or coalesce((p_decision->>'confirmed')::boolean,false) is not true or p_decision->>'classification' not in ('included','excluded','mixed_unresolved','awaiting_review') or p_decision->>'action' not in ('save','publish','withdraw') then raise exception 'Explicit documented decision required';end if;
 select * into fact from private.funding_records where id=p_id for update;if not found then raise exception 'Record required';end if;
 reviewed_payload:=fact.payload||jsonb_build_object('classification',p_decision->>'classification');
 if p_decision->>'action'='publish' then
  if p_decision->>'classification'<>'included' or reviewed_payload->>'share'<>'union' or reviewed_payload->>'aggregation'<>'leaf' or reviewed_payload->>'amountRupees' is null or reviewed_payload->>'instrument'='unresolved' or (reviewed_payload->>'conflict')::boolean is distinct from false
   or not exists(select 1 from private.source_permission_reviews where document_id=fact.document_id)
   or not (coalesce((p_decision->>'sourceChecked')::boolean,false) and coalesce((p_decision->>'unitsChecked')::boolean,false) and coalesce((p_decision->>'jurisdictionChecked')::boolean,false) and coalesce((p_decision->>'scopeChecked')::boolean,false) and coalesce((p_decision->>'editionsChecked')::boolean,false)) then raise exception 'Evidence and rights gates incomplete';end if;
  -- A single published accounting scope cannot contain overlapping reporting periods,
  -- regardless of source, edition or cumulative cut-off. Withdraw superseded facts first.
  if exists(select 1 from private.funding_publications p where p.active and p.record_id<>p_id and
   p.payload->>'coverageKey'=reviewed_payload->>'coverageKey' and p.payload->>'jurisdiction'=reviewed_payload->>'jurisdiction' and
   p.payload->>'financialYear'=reviewed_payload->>'financialYear' and p.payload->>'measure'=reviewed_payload->>'measure' and
   p.payload->>'estimate'=reviewed_payload->>'estimate' and p.payload->>'accountingBasis'=reviewed_payload->>'accountingBasis' and
   (p.payload->>'periodStart')::date<=(reviewed_payload->>'periodEnd')::date and (reviewed_payload->>'periodStart')::date<=(p.payload->>'periodEnd')::date) then raise exception 'Overlapping edition: withdraw previous publication first';end if;
 end if;
 insert into private.funding_decisions(record_id,decision,reason,reviewed_by) values(p_id,p_decision,p_reason,auth.uid()) returning id into review_decision_id;
 -- Any re-review removes the prior public snapshot until an explicit publication.
 update private.funding_publications set active=false where record_id=p_id;
 if p_decision->>'action'='publish' then insert into private.funding_publications(record_id,decision_id,payload) values(p_id,review_decision_id,reviewed_payload) on conflict(record_id) do update set decision_id=excluded.decision_id,payload=excluded.payload,active=true,published_at=now();end if;
 insert into private.audit_events(actor,action,entity_type,entity_id,reason) values(auth.uid(),p_decision->>'action','funding',p_id,p_reason);
 return true;
end $$;
