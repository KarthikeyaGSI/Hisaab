create table private.funding_budget_lines(
 id text primary key,document_id uuid not null references private.source_documents(id),financial_year text not null,payload jsonb not null,
 classification text not null default 'awaiting_review' check(classification in ('included','excluded','mixed_unresolved','awaiting_review')),
 purpose text,review_reason text,reviewed_by uuid references auth.users(id),reviewed_at timestamptz
);
alter table private.funding_budget_lines enable row level security;
grant all on private.funding_budget_lines to service_role;
create index funding_budget_lines_year on private.funding_budget_lines(financial_year,id);
create function public.stage_funding_inventory(p_hash text,p_year text,p_rows jsonb) returns integer language plpgsql security definer set search_path='' as $$
declare doc uuid;r jsonb;old jsonb;n integer:=0;
begin
 if auth.role()<>'service_role' then raise exception 'Private ingestion only';end if;
 if p_year !~ '^20(1[6-9]|2[0-6])-20(1[7-9]|2[0-7])$' or jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)>500 then raise exception 'Bounded annual rows required';end if;
 select id into doc from private.source_documents where sha256=p_hash limit 1;if doc is null then raise exception 'Preserved original required';end if;
 for r in select value from jsonb_array_elements(p_rows) loop
  if r->>'sourceHash' is distinct from p_hash or r->>'edition' is distinct from p_year or r->>'id' not like p_hash||':%' or length(coalesce(r->>'rawText',''))=0 or (r->>'page')::integer<1 then raise exception 'Original row identity required';end if;
  select payload into old from private.funding_budget_lines where id=r->>'id';
  if found then if old is distinct from r then raise exception 'Inventory edition conflict';end if;
  else insert into private.funding_budget_lines(id,document_id,financial_year,payload) values(r->>'id',doc,p_year,r);n:=n+1;end if;
 end loop;return n;
end $$;
revoke all on function public.stage_funding_inventory(text,text,jsonb) from public,anon,authenticated;
grant execute on function public.stage_funding_inventory(text,text,jsonb) to service_role;
create function public.admin_funding_inventory(p_year text,p_offset integer default 0,p_query text default '') returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 return (with m as(select * from private.funding_budget_lines where financial_year=p_year and position(lower(left(p_query,200)) in lower(payload->>'rawText'))>0)
 select jsonb_build_object('total',(select count(*) from m),'records',coalesce((select jsonb_agg(x.payload||jsonb_build_object('classification',x.classification,'purpose',x.purpose,'reviewReason',x.review_reason)) from(select * from m order by id limit 40 offset greatest(0,least(200000,p_offset))) x),'[]'::jsonb),'counts',(select jsonb_object_agg(classification,n) from(select classification,count(*) n from private.funding_budget_lines where financial_year=p_year group by classification) c)));
end $$;
revoke all on function public.admin_funding_inventory(text,integer,text) from public,anon;
grant execute on function public.admin_funding_inventory(text,integer,text) to authenticated;
create function public.review_funding_inventory(p_id text,p_classification text,p_purpose text,p_reason text) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 if p_classification not in ('included','excluded','mixed_unresolved','awaiting_review') or length(trim(p_reason))<30 then raise exception 'Documented classification required';end if;
 update private.funding_budget_lines set classification=p_classification,purpose=left(p_purpose,100),review_reason=p_reason,reviewed_by=auth.uid(),reviewed_at=now() where id=p_id;
 if not found then raise exception 'Original inventory row required';end if;
 insert into private.audit_events(actor,action,entity_type,entity_id,reason) values(auth.uid(),'classify','funding_budget_line',p_id,p_reason);
 return true;
end $$;
revoke all on function public.review_funding_inventory(text,text,text,text) from public,anon;
grant execute on function public.review_funding_inventory(text,text,text,text) to authenticated;
create function public.funding_history(p_state text,p_programme text) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(p.payload order by p.payload->>'financialYear',p.record_id),'[]'::jsonb) from private.funding_publications p join private.funding_records f on f.id=p.record_id
 where p.active and p.payload->>'jurisdiction'=p_state and p.payload->>'programmeId'=p_programme and exists(select 1 from private.source_permission_reviews r where r.document_id=f.document_id);
$$;
revoke all on function public.funding_history(text,text) from public;
grant execute on function public.funding_history(text,text) to anon,authenticated;
