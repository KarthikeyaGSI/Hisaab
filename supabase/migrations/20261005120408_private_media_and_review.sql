update storage.buckets set allowed_mime_types=array['application/octet-stream'] where id='case-originals';
create function public.register_case_media(p_id uuid,p_hash text,p_original text,p_derivative text,p_original_hash text,p_derivative_hash text)
returns uuid language plpgsql security definer set search_path='' as $$ begin
 perform pg_advisory_xact_lock(hashtext(p_hash));
 if not exists(select 1 from private.private_cases where token_hash=p_hash and revoked_at is null and expires_at>now()) then raise exception 'case unavailable'; end if;
 if (select count(*) from private.case_media where case_hash=p_hash)>=5 then raise exception 'media limit';end if;
 if p_original not like p_hash||'/%' or p_derivative not like p_hash||'/%' then raise exception 'invalid media path';end if;
 insert into private.case_media(id,case_hash,original_path,original_sha256,derivative_path,derivative_sha256,state)
 values(p_id,p_hash,p_original,p_original_hash,p_derivative,p_derivative_hash,'private_validated');return p_id;end $$;
create function public.list_case_media(p_hash text) returns setof private.case_media
language sql security definer set search_path='' as $$
 select m.* from private.case_media m join private.private_cases c on c.token_hash=m.case_hash
 where c.token_hash=p_hash and c.revoked_at is null and c.expires_at>now();
$$;
revoke all on function public.register_case_media(uuid,text,text,text,text,text),public.list_case_media(text) from public,anon,authenticated;
grant execute on function public.register_case_media(uuid,text,text,text,text,text),public.list_case_media(text) to service_role;
