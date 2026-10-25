create or replace function private.assert_publication_evidence(p jsonb) returns void language plpgsql set search_path='' as $$
declare s jsonb;e jsonb;receipt_ids jsonb;stage_id text;scaled numeric;raw_amount text;
begin
 if jsonb_array_length(p->'stages')<>4 or (select count(distinct value->>'id') from jsonb_array_elements(p->'stages'))<>4 then raise exception 'Four distinct stages required';end if;
 select coalesce(jsonb_agg(r.value->>'id'),'[]'::jsonb) into receipt_ids from jsonb_array_elements(p->'stages') st cross join lateral jsonb_array_elements(st.value->'receipts') r;
 for s in select value from jsonb_array_elements(p->'stages') loop
  if s->>'state'='found' and (coalesce(s->>'reviewStatus','')<>'verified' or jsonb_array_length(s->'receipts')=0) then raise exception 'Found stages require explicit verified evidence review';end if;
  if s->>'id'='completion' and s->>'state'='found' and coalesce(s->>'completionBasis','') not in ('reported','certificate') then raise exception 'Completion basis required';end if;
 end loop;
 for e in select value from jsonb_array_elements(p->'money') loop
  if coalesce(e->>'originalUnit','') not in ('rupees','lakh','crore') then raise exception 'Original financial unit required';end if;
  raw_amount:=e->>'originalAmount';
  if raw_amount !~ '^-?([0-9]+|[0-9]{1,2}(,[0-9]{2})*,[0-9]{3}|[0-9]{1,3}(,[0-9]{3})+)(\.[0-9]{1,9})?$' then raise exception 'Original financial amount is malformed';end if;
  scaled:=replace(raw_amount,',','')::numeric * case e->>'originalUnit' when 'lakh' then 100000 when 'crore' then 10000000 else 1 end;
  if scaled<>round(scaled,2) or scaled<>(e->>'amount')::numeric then raise exception 'Exact amount normalization required';end if;
  if coalesce((e->>'approved')::boolean,false) then
   if coalesce(e->>'reviewStatus','')<>'verified' or not receipt_ids ? (e->>'receiptId') then raise exception 'Explicit financial source review required';end if;
   stage_id:=case e->>'measure' when 'contract' then 'award' when 'sanction' then 'sanction' when 'payment' then 'payment' else '' end;
   if not exists(select 1 from jsonb_array_elements(p->'stages') st where st->>'id'=stage_id and st->>'state'='found' and st->>'reviewStatus'='verified') then raise exception 'Reviewed financial stage required';end if;
   if e->>'measure'='payment' and e->>'kind'<>'cumulative' then
    if coalesce(e->>'sourcePaymentId','')='' or coalesce(e->'allocation'->>'projectId','')<>p->>'id' or coalesce(e->'allocation'->>'amount','')<>e->>'amount' or not receipt_ids ? coalesce(e->'allocation'->>'receiptId','') or coalesce(e->>'flow','')<>'contractor_payment' or coalesce(e->>'amountBasis','') not in ('gross','net') or coalesce(e->>'payee','')='' then raise exception 'Individual payment allocation recipient and amount basis required';end if;
   end if;
  end if;
 end loop;
end $$;
