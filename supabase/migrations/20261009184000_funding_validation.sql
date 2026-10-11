create function private.validate_funding_payload(r jsonb) returns boolean language plpgsql immutable set search_path='' as $$
begin
 if jsonb_typeof(r)<>'object' or not (r ?& array['id','identity','edition','financialYear','programmeId','programme','budgetHead','ministry','jurisdiction','jurisdictionLabel','purpose','channel','instrument','measure','estimate','accountingBasis','share','amountRupees','periodStart','periodEnd','cutoff','publicationDate','coverageKey','aggregation','parentKey','classification','conflict','source','notes'])
 or exists(select 1 from jsonb_object_keys(r) k where k<>all(array['id','identity','edition','financialYear','programmeId','programme','budgetHead','ministry','jurisdiction','jurisdictionLabel','purpose','channel','instrument','measure','estimate','accountingBasis','share','amountRupees','periodStart','periodEnd','cutoff','publicationDate','coverageKey','aggregation','parentKey','classification','conflict','source','notes'])) then return false;end if;
 if not (r->'source' ?& array['hash','url','locator','retrievedAt','page']) or exists(select 1 from jsonb_object_keys(r->'source') k where k<>all(array['hash','url','locator','retrievedAt','page'])) then return false;end if;
 if length(r->>'identity')<1 or length(r->>'coverageKey')<1 or length(r->>'programmeId')<1 or length(r->>'programme')<1 or length(r->>'ministry')<1
 or r->>'purpose' not in ('infrastructure','health','education','housing','agriculture','rural','employment','social','energy','transport','environment','digital','disaster_response','disaster_mitigation','disaster_reconstruction','other')
 or r->>'channel' not in ('central_sector','centrally_sponsored','development_grant','capital_loan','finance_commission','disaster_grant','other')
 or r->>'estimate' not in ('original','revised','not_applicable') or jsonb_typeof(r->'conflict')<>'boolean'
 or (jsonb_typeof(r->'amountRupees') not in ('string','null')) or r->'source'->>'url' !~ '^https://' or length(r->'source'->>'locator')<1 then return false;end if;
 if (r->>'measure'='allocated' and (r->>'estimate'='not_applicable' or r->>'accountingBasis'<>'union_budget')) or (r->>'measure'='released' and (r->>'estimate'<>'not_applicable' or r->>'accountingBasis'<>'union_release')) or (r->>'measure'='reported_spent' and (r->>'estimate'<>'not_applicable' or r->>'accountingBasis' not in ('union_booked_expenditure','recipient_utilisation'))) then return false;end if;
 perform (r->>'cutoff')::date,(r->>'periodStart')::date,(r->>'periodEnd')::date,(r->'source'->>'retrievedAt')::timestamptz;
 if r->>'measure'<>'allocated' and (r->>'periodEnd')::date>(r->>'cutoff')::date then return false;end if;
 return true;
exception when others then return false;
end $$;
revoke all on function private.validate_funding_payload(jsonb) from public,anon,authenticated;
create function private.check_funding_insert() returns trigger language plpgsql set search_path='' as $$
begin if not private.validate_funding_payload(new.payload) then raise exception 'Invalid or unsafe funding payload';end if;return new;end $$;
create trigger validate_funding_insert before insert on private.funding_records for each row execute function private.check_funding_insert();
