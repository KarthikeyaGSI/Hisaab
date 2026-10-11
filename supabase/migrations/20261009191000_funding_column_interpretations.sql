create table private.funding_budget_interpretations(
 row_id text not null references private.funding_budget_lines(id),parser_version text not null,payload jsonb not null,
 created_at timestamptz not null default now(),primary key(row_id,parser_version)
);
alter table private.funding_budget_interpretations enable row level security;
grant all on private.funding_budget_interpretations to service_role;
create function public.stage_funding_interpretations(p_rows jsonb) returns integer language plpgsql security definer set search_path='' as $$
declare r jsonb;old jsonb;n integer:=0;
begin
 if auth.role()<>'service_role' then raise exception 'Private ingestion only';end if;
 if pg_database_size(current_database())>445644800 then raise exception 'Private ingestion paused at capacity guard';end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)>200 then raise exception 'Bounded interpretations required';end if;
 for r in select value from jsonb_array_elements(p_rows) loop
  if length(coalesce(r->>'parserVersion',''))<1 or not exists(select 1 from private.funding_budget_lines where id=r->>'rowId' and financial_year=r->>'edition') or r->'interpretation'->>'sourceUnit'<>'crore' or jsonb_array_length(r->'interpretation'->'columns')<>4 then raise exception 'Original row and explicit columns required';end if;
  select payload into old from private.funding_budget_interpretations where row_id=r->>'rowId' and parser_version=r->>'parserVersion';
  if found then if old is distinct from r then raise exception 'Interpretation version conflict';end if;
  else insert into private.funding_budget_interpretations(row_id,parser_version,payload) values(r->>'rowId',r->>'parserVersion',r);n:=n+1;end if;
 end loop;return n;
end $$;
revoke all on function public.stage_funding_interpretations(jsonb) from public,anon,authenticated;
grant execute on function public.stage_funding_interpretations(jsonb) to service_role;
create or replace function public.admin_funding_inventory(p_year text,p_offset integer default 0,p_query text default '') returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_admin() then raise exception 'MFA administrator required';end if;
 return (with m as(select * from private.funding_budget_lines where financial_year=p_year and position(lower(left(p_query,200)) in lower(payload->>'rawText'))>0)
 select jsonb_build_object('total',(select count(*) from m),'records',coalesce((select jsonb_agg(x.payload||jsonb_build_object('classification',x.classification,'purpose',x.purpose,'reviewReason',x.review_reason,'interpretation',(select i.payload->'interpretation' from private.funding_budget_interpretations i where i.row_id=x.id order by created_at desc,parser_version desc limit 1))) from(select * from m order by id limit 40 offset greatest(0,least(200000,p_offset))) x),'[]'::jsonb),'counts',(select jsonb_object_agg(classification,n) from(select classification,count(*) n from private.funding_budget_lines where financial_year=p_year group by classification) c)));
end $$;

create function public.funding_ingestion_capacity() returns bigint language plpgsql stable security definer set search_path='' as $$
begin if auth.role()<>'service_role' then raise exception 'Private ingestion only';end if;return pg_database_size(current_database());end $$;
revoke all on function public.funding_ingestion_capacity() from public,anon,authenticated;
grant execute on function public.funding_ingestion_capacity() to service_role;
