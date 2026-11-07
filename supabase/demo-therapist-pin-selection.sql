-- Demo-only public directory: never publish real therapist email addresses here.
create or replace function public.list_demo_therapist_logins()
returns table(full_name text,email text) language sql stable security definer set search_path='' as $$
 select p.full_name,p.email from public.profiles p where p.role='therapist' and p.active and p.is_demo and lower(p.email) like '%@kakang.test' order by p.full_name,p.id;
$$;
revoke all on function public.list_demo_therapist_logins() from public;
grant execute on function public.list_demo_therapist_logins() to anon,authenticated;
create or replace function private.set_therapist_pin(target_id uuid,new_pin text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or private.current_role() is distinct from 'administrator' then raise exception 'Akses ditolak' using errcode='42501'; end if;
 if new_pin is null or new_pin !~ '^[0-9]{6}$' then raise exception 'PIN harus enam angka' using errcode='22023'; end if;
 if not exists(select 1 from public.profiles p where p.id=target_id and p.role='therapist' and p.is_demo=private.current_demo()) then raise exception 'Terapis tidak ditemukan' using errcode='42501'; end if;
 update auth.users set encrypted_password=extensions.crypt(new_pin,extensions.gen_salt('bf',10)),updated_at=now() where id=target_id;
end;$$;
revoke all on function private.set_therapist_pin(uuid,text) from public,anon;
grant execute on function private.set_therapist_pin(uuid,text) to authenticated;
create or replace function public.set_therapist_pin(target_id uuid,new_pin text)
returns void language sql security invoker set search_path='' as $$ select private.set_therapist_pin(target_id,new_pin); $$;
revoke all on function public.set_therapist_pin(uuid,text) from public,anon;
grant execute on function public.set_therapist_pin(uuid,text) to authenticated;
