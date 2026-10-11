create table private.budget_context(
 document_id uuid not null references private.source_documents(id),workbook_id uuid not null references private.source_documents(id),
 identity text not null,payload jsonb not null,imported_at timestamptz not null default now(),primary key(document_id,identity)
);
alter table private.budget_context enable row level security;
grant all on private.budget_context to service_role;
create index budget_context_demand on private.budget_context(((payload->>'demandNumber')::integer),identity);
create function private.lock_budget_context() returns trigger language plpgsql set search_path='' as $$
begin raise exception 'Budget originals are immutable; register a new source edition';end $$;
create trigger immutable_budget_context before update on private.budget_context for each row execute function private.lock_budget_context();

create function public.stage_budget_context(p_pdf_hash text,p_workbook_hash text,p_records jsonb) returns integer language plpgsql security definer set search_path='' as $$
declare pdf_doc uuid;workbook_doc uuid;item jsonb;existing jsonb;inserted integer:=0;part text;v text;
begin
 if jsonb_typeof(p_records) is distinct from 'array' or jsonb_array_length(p_records)>500 then raise exception 'At most 500 budget context rows';end if;
 select id into pdf_doc from private.source_documents where source_id='union-budget-2026' and sha256=p_pdf_hash and content_type='application/pdf';
 select id into workbook_doc from private.source_documents where source_id='union-budget-2026' and sha256=p_workbook_hash and content_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
 if pdf_doc is null or workbook_doc is null then raise exception 'Preserved official PDF and workbook required';end if;
 for item in select value from jsonb_array_elements(p_records) loop
  if coalesce(item->>'scope','')<>'union_demand_net' or coalesce(item->>'unit','')<>'crore'
   or item->'workPayment' is distinct from 'false'::jsonb or item->>'workId' is not null or item->>'location' is not null
   or coalesce(item->>'financialYear','') not in ('2024-2025','2025-2026','2026-2027')
   or coalesce(item->>'measure','') not in ('actual','budget_estimate','revised_estimate')
   or coalesce(item->>'demandNumber','')!~ '^[1-9][0-9]{0,2}$' or (item->>'demandNumber')::integer>102
   or coalesce(item->>'pdfPage','')!~ '^[1-9][0-9]{0,2}$' or length(coalesce(item->>'department',''))<3 or length(coalesce(item->>'locator',''))<10
   or item->>'identity' is distinct from 'union-budget-2026:demand:'||(item->>'demandNumber')||':'||(item->>'measure')||':'||(item->>'financialYear')
   then raise exception 'Valid non-payment budget identity and provenance required';end if;
  if not ((item->>'measure'='actual' and item->>'financialYear'='2024-2025') or (item->>'measure' in('budget_estimate','revised_estimate') and item->>'financialYear'='2025-2026') or (item->>'measure'='budget_estimate' and item->>'financialYear'='2026-2027')) then raise exception 'Unsupported edition period';end if;
  foreach part in array array['revenueCrore','capitalCrore','totalCrore'] loop
   if not item ? part then raise exception 'Missing classification amount';end if;
   v:=item->>part;
   if v is not null and (jsonb_typeof(item->part)<>'string' or v!~ '^-?[0-9]+\.[0-9]{2}$' or length(v)>24) then raise exception 'Exact decimal amount or explicit null required';end if;
  end loop;
  if item->>'revenueCrore' is not null and item->>'capitalCrore' is not null and (item->>'revenueCrore')::numeric+(item->>'capitalCrore')::numeric<>(item->>'totalCrore')::numeric then raise exception 'Net classifications do not reconcile';end if;
  select payload into existing from private.budget_context where document_id=pdf_doc and identity=item->>'identity';
  if found then
   if existing is distinct from item or not exists(select 1 from private.budget_context where document_id=pdf_doc and identity=item->>'identity' and workbook_id=workbook_doc) then raise exception 'Source edition conflict';end if;
  else
   insert into private.budget_context(document_id,workbook_id,identity,payload) values(pdf_doc,workbook_doc,item->>'identity',item);inserted:=inserted+1;
  end if;
 end loop;
 return inserted;
end $$;
revoke all on function public.stage_budget_context(text,text,jsonb) from public,anon,authenticated;
grant execute on function public.stage_budget_context(text,text,jsonb) to service_role;

create function public.admin_budget_context(p_offset integer default 0,p_query text default '') returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 return (with matching as materialized (
  select b.* from private.budget_context b where position(lower(left(coalesce(p_query,''),200)) in lower(b.payload->>'department'))>0
 ), demands as (select distinct (payload->>'demandNumber')::integer as demand from matching order by demand offset greatest(0,least(coalesce(p_offset,0),102)) limit 20)
 select jsonb_build_object('records',coalesce((select jsonb_agg(m.payload||jsonb_build_object('sourceDocument',jsonb_build_object('id',d.id,'url',d.original_url,'hash',d.sha256,'permissionReviewed',exists(select 1 from private.source_permission_reviews pr where pr.document_id=d.id)))) from matching m join demands p on p.demand=(m.payload->>'demandNumber')::integer join private.source_documents d on d.id=m.document_id),'[]'::jsonb),'totalDemands',(select count(distinct payload->>'demandNumber') from matching),'publication','private_pending_permission_and_review'));
end $$;
revoke all on function public.admin_budget_context(integer,text) from public,anon;
grant execute on function public.admin_budget_context(integer,text) to authenticated;
