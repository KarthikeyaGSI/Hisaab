\set ON_ERROR_STOP on
begin;
insert into auth.users(id) values('00000000-0000-4000-8000-000000000021');
insert into private.works(id,title) values('00000000-0000-4000-8000-000000000022','Disposable aggregate test');
insert into public.publication_snapshots(work_id,publication_version,payload,reviewed_by,approved) values('00000000-0000-4000-8000-000000000022',1,'{"id":"aggregate-test","district":"Test District","areaId":"test","title":"Exact road","financialYear":"2025-2026","money":[{"id":"1","canonicalId":"bill-1","measure":"payment","amount":"100.50","approved":true,"receiptId":"r","date":"2025-01-01","kind":"transaction"},{"id":"2","canonicalId":"bill-1","measure":"payment","amount":"100.50","approved":true,"receiptId":"r","date":"2025-01-01","kind":"transaction"},{"id":"3","canonicalId":"conflict","measure":"payment","amount":"20.00","approved":true,"receiptId":"r","date":"2025-01-01","kind":"transaction"},{"id":"4","canonicalId":"conflict","measure":"payment","amount":"30.00","approved":true,"receiptId":"r","date":"2025-02-01","kind":"transaction"},{"id":"5","canonicalId":"snapshot","measure":"payment","amount":"999999.00","approved":true,"receiptId":"r","date":"2025-01-01","kind":"cumulative"},{"id":"6","canonicalId":"reversal","measure":"payment","amount":"-10.00","approved":true,"receiptId":"r","date":"2025-01-01","kind":"reversal"}]}','00000000-0000-4000-8000-000000000021',true);
insert into private.works(id,title)
select ('00000000-0000-4000-8001-'||lpad(n::text,12,'0'))::uuid,'Disposable map test' from generate_series(1,102) n;
insert into public.publication_snapshots(work_id,publication_version,payload,reviewed_by,approved)
select ('00000000-0000-4000-8001-'||lpad(n::text,12,'0'))::uuid,1,
jsonb_build_object('id','map-test-'||n,'title','Map location test','location',case when n=101 then '[77.5,28.5]'::jsonb else '[10,10]'::jsonb end,'locationPrecision',case when n=102 then 'district' else 'source_point' end),
'00000000-0000-4000-8000-000000000021',true from generate_series(1,102) n;
set local role anon;
do $$ declare value jsonb; begin
 value:=public.catalogue_money('payment','Test District',null,'2025-01-01','2025-01-31');
 if value->>'amount'<>'90.50' or value->>'eventCount'<>'2' or value->>'conflictingIdentities'<>'1' then raise exception 'Financial semantics failed: %',value; end if;
 if (public.catalogue_page('Exact',null,null,0,1)->>'total')<>'1' then raise exception 'Catalogue filtering failed';end if;
 if (public.catalogue_page('Exact',null,null,1,1)->'works')<>'[]'::jsonb then raise exception 'Pagination offset failed';end if;
 value:=public.catalogue_map(77,28,78,29,100);
 if value->>'total'<>'1' or value->'features'->0->'properties'->>'id'<>'map-test-101' then raise exception 'Map must search beyond first catalogue page: %',value;end if;
 value:=public.catalogue_map(-180,-90,180,90,100);
 if value->>'total'<>'101' or value->>'truncated'<>'true' or jsonb_array_length(value->'features')<>100 then raise exception 'Map limit or imprecise location exclusion failed: %',value;end if;
 value:=public.catalogue_map_clusters(-180,-90,180,90);
 if value->>'total'<>'101' or value->>'truncated'<>'false' or jsonb_array_length(value->'features')<>2 then raise exception 'Full map grouping or precision exclusion failed: %',value;end if;
 value:=public.catalogue_map_members(-180,-90,180,90,'',null,null,100);
 if value->>'total'<>'101' or jsonb_array_length(value->'works')<>1 then raise exception 'Map group pagination must include works beyond first 100: %',value;end if;
 value:=public.catalogue_map_clusters(77,28,78,29,'Map location');
 if value->>'total'<>'1' or value->'features'->0->'properties'->>'id'<>'map-test-101' then raise exception 'Viewport map point retrieval failed: %',value;end if;
 if public.catalogue_map_clusters(-180,-90,180,90,'missing')->>'total'<>'0' then raise exception 'Map search failed';end if;
 if public.catalogue_map_members(-180,-90,180,90,'', 'Water')->>'total'<>'0' then raise exception 'Map purpose filtering failed';end if;
 if public.catalogue_map_clusters(-180,-90,180,90,'',null,'2020-2021')->>'total'<>'0' then raise exception 'Map year filtering failed';end if;
 if has_function_privilege('anon' ,'public.consume_request_limit(text,integer)','execute') then raise exception 'Limiter exposed';end if;
end $$;
reset role;
do $$ begin
 if not public.consume_request_limit(repeat('a',64),1) or public.consume_request_limit(repeat('a',64),1) then raise exception 'Distributed limit failed'; end if;
end $$;
rollback;
