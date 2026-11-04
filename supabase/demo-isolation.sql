alter table public.profiles add column is_demo boolean not null default false;
create function private.current_demo() returns boolean
language sql stable security definer set search_path='' as $$
 select is_demo from public.profiles where id=auth.uid() and active and private.current_role() is not null;
$$;
revoke all on function private.current_demo() from public,anon;
grant execute on function private.current_demo() to authenticated;
create function private.same_demo(target uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.current_role() is not null and exists(select 1 from public.profiles where id=target and is_demo=private.current_demo());
$$;
revoke all on function private.same_demo(uuid) from public,anon;
grant execute on function private.same_demo(uuid) to authenticated;

drop policy profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using (
 is_demo=(select private.current_demo()) and (
 (id=(select auth.uid()) and (select private.current_role()) is not null)
 or (select private.current_role())='administrator'
 or ((select private.current_role())='customer' and exists(select 1 from public.appointments a where a.therapist_id=profiles.id and a.customer_id=(select auth.uid())))
 or ((select private.current_role())='therapist' and exists(select 1 from public.appointments a where a.customer_id=profiles.id and a.therapist_id=(select auth.uid())))
 ));
drop policy appointments_read on public.appointments;
create policy appointments_read on public.appointments for select to authenticated using (
 private.same_demo(customer_id) and (
 (select private.current_role())='administrator'
 or ((select private.current_role())='customer' and customer_id=(select auth.uid()))
 or ((select private.current_role())='therapist' and therapist_id=(select auth.uid()))
 ));
drop policy appointments_create on public.appointments;
create policy appointments_create on public.appointments for insert to authenticated with check (
 private.same_demo(customer_id) and (
 (select private.current_role())='administrator'
 or ((select private.current_role())='customer' and customer_id=(select auth.uid()) and status='pending' and therapist_id is null)
 ));
drop policy appointments_status on public.appointments;
create policy appointments_status on public.appointments for update to authenticated
 using (private.same_demo(customer_id) and ((select private.current_role())='administrator' or ((select private.current_role())='therapist' and therapist_id=(select auth.uid()))))
 with check (private.same_demo(customer_id) and ((select private.current_role())='administrator' or ((select private.current_role())='therapist' and therapist_id=(select auth.uid()))));
drop policy role_audit_admin on public.role_audit;
create policy role_audit_admin on public.role_audit for select to authenticated using((select private.current_role())='administrator' and private.same_demo(actor_id));

create or replace function private.validate_appointment() returns trigger
language plpgsql security definer set search_path='' as $$
declare s public.services; cr text;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 cr:=private.current_role();
 if not private.same_demo(new.customer_id) or (new.therapist_id is not null and not private.same_demo(new.therapist_id)) then raise exception 'Data demo terpisah dari data asli' using errcode='42501';end if;
 if tg_op='INSERT' then
  select * into s from public.services where id=new.service_id and active;
  if s.id is null then raise exception 'Layanan tidak aktif'; end if;
  if not exists(select 1 from public.profiles where id=new.customer_id and role='customer' and active) then raise exception 'Customer tidak aktif'; end if;
  if new.starts_at < now() then raise exception 'Jadwal harus di masa depan'; end if;
  new.price:=s.price;new.duration_minutes:=s.duration_minutes;
 elsif cr='therapist' then
  if old.therapist_id<>auth.uid() or not ((old.status='confirmed' and new.status='in_progress') or (old.status='in_progress' and new.status='completed')) then
   raise exception 'Transisi status tidak diizinkan' using errcode='42501';
  end if;
 elsif cr<>'administrator' or cr is null then
  raise exception 'Akses ditolak' using errcode='42501';
 end if;
 if new.therapist_id is not null and not exists(select 1 from public.profiles where id=new.therapist_id and role='therapist' and active) then raise exception 'Terapis tidak aktif'; end if;
 if new.status in ('confirmed','in_progress','completed') and new.therapist_id is null then raise exception 'Pilih terapis sebelum konfirmasi'; end if;
 if new.therapist_id is not null and new.status not in ('cancelled','completed') then
  perform pg_advisory_xact_lock(hashtextextended(new.therapist_id::text,0));
  if exists(select 1 from public.appointments a where a.id<>new.id and a.therapist_id=new.therapist_id and a.status not in ('cancelled','completed') and a.starts_at < new.starts_at+make_interval(mins=>new.duration_minutes) and a.starts_at+make_interval(mins=>a.duration_minutes)>new.starts_at) then raise exception 'Jadwal terapis bertabrakan'; end if;
 end if;
 return new;
end;
$$;

create or replace function private.manage_account(target_id uuid,new_role text,is_active boolean) returns void
language plpgsql security definer set search_path='' as $$
declare previous text;
begin
 if auth.uid() is null or private.current_role() is distinct from 'administrator' then raise exception 'Akses ditolak' using errcode='42501'; end if;
 if new_role not in ('administrator','therapist','customer') or is_active is null then raise exception 'Peran tidak valid'; end if;
 if not private.same_demo(target_id) then raise exception 'Akses lintas demo ditolak' using errcode='42501';end if;
 perform pg_advisory_xact_lock(904342);
 if target_id=auth.uid() then raise exception 'Anda tidak dapat mengubah akses akun sendiri'; end if;
 select role into previous from public.profiles where id=target_id for update;
 if previous is null then raise exception 'Akun tidak ditemukan'; end if;
 if previous='administrator' and (new_role<>'administrator' or not is_active) and (select count(*) from public.profiles where role='administrator' and active and is_demo=private.current_demo())<=1 then raise exception 'Administrator terakhir harus tetap aktif'; end if;
 if (previous<>new_role or not is_active) and exists(select 1 from public.appointments where (customer_id=target_id or therapist_id=target_id) and status not in ('completed','cancelled')) then raise exception 'Selesaikan atau batalkan reservasi aktif sebelum mengubah peran'; end if;
 update public.profiles set role=new_role,active=is_active where id=target_id;
 insert into public.role_audit(actor_id,target_id,old_role,new_role,active) values(auth.uid(),target_id,previous,new_role,is_active);
end;
$$;

create or replace function private.assign_therapist(appointment_id uuid,new_therapist_id uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or private.current_role() is distinct from 'administrator' then raise exception 'Akses ditolak' using errcode='42501'; end if;
 if not private.same_demo(new_therapist_id) or not exists(select 1 from public.appointments where id=appointment_id and private.same_demo(customer_id)) then raise exception 'Akses lintas demo ditolak' using errcode='42501';end if;
 if not exists(select 1 from public.profiles where id=new_therapist_id and role='therapist' and active) then raise exception 'Terapis tidak aktif'; end if;
 update public.appointments set therapist_id=new_therapist_id,status='confirmed' where id=appointment_id and status in ('pending','confirmed');
 if not found then raise exception 'Reservasi tidak dapat ditugaskan'; end if;
end;
$$;
