-- PIN login for the four HEIJO portal accounts. The initial PIN is set in the
-- deployed database only; change it immediately from Administrator > Kelola Akun.
create or replace function private.set_portal_pin(target_role text, new_pin text)
returns void language plpgsql security definer set search_path = '' as $$
declare target_email text; target_id uuid;
begin
  if auth.uid() is null or private.current_role() is distinct from 'administrator' then raise exception 'Akses ditolak' using errcode = '42501'; end if;
  if target_role not in ('administrator','therapist','customer','referral') or new_pin !~ '^[0-9]{6}$' then raise exception 'PIN harus tepat 6 angka' using errcode = '22023'; end if;
  target_email := case target_role when 'administrator' then 'admin.demo@kakang.test' when 'therapist' then 'terapis.demo@kakang.test' when 'customer' then 'customer.demo@kakang.test' when 'referral' then 'referral.demo@kakang.test' end;
  select id into target_id from auth.users where lower(email) = target_email for update;
  if target_id is null then raise exception 'Akun portal belum tersedia'; end if;
  update auth.users set encrypted_password = extensions.crypt(new_pin, extensions.gen_salt('bf', 10)), updated_at = now() where id = target_id;
end; $$;
revoke all on function private.set_portal_pin(text,text) from public, anon, authenticated;
grant execute on function private.set_portal_pin(text,text) to authenticated;
create or replace function public.set_portal_pin(target_role text, new_pin text)
returns void language sql security invoker set search_path = '' as $$ select private.set_portal_pin(target_role, new_pin); $$;
revoke all on function public.set_portal_pin(text,text) from public, anon;
grant execute on function public.set_portal_pin(text,text) to authenticated;
