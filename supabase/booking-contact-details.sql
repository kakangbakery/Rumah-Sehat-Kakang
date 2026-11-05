alter table public.appointments
 alter column customer_id drop not null,
 add column is_demo boolean,
 add column booking_name text check(length(booking_name)<=100),
 add column booking_address text check(length(booking_address)<=500),
 add column booking_phone text check(length(booking_phone)<=25),
 add column booking_notes text check(length(booking_notes)<=1000);
alter table public.appointments disable trigger validate_appointment;
update public.appointments a set is_demo=p.is_demo from public.profiles p where p.id=a.customer_id;
alter table public.appointments enable trigger validate_appointment;
alter table public.appointments alter column is_demo set not null;
grant insert(booking_name,booking_address,booking_phone,booking_notes) on public.appointments to authenticated;

drop policy appointments_read on public.appointments;
create policy appointments_read on public.appointments for select to authenticated using (
 is_demo=(select private.current_demo()) and (
 (select private.current_role())='administrator'
 or ((select private.current_role())='customer' and customer_id=(select auth.uid()))
 or ((select private.current_role())='therapist' and therapist_id=(select auth.uid()))
 ));
drop policy appointments_create on public.appointments;
create policy appointments_create on public.appointments for insert to authenticated with check (
 is_demo=(select private.current_demo()) and (
 (select private.current_role())='administrator'
 or ((select private.current_role())='customer' and customer_id=(select auth.uid()) and status='pending' and therapist_id is null)
 ));
drop policy appointments_status on public.appointments;
create policy appointments_status on public.appointments for update to authenticated
 using (is_demo=(select private.current_demo()) and ((select private.current_role())='administrator' or ((select private.current_role())='therapist' and therapist_id=(select auth.uid()))))
 with check (is_demo=(select private.current_demo()) and ((select private.current_role())='administrator' or ((select private.current_role())='therapist' and therapist_id=(select auth.uid()))));

create or replace function private.validate_appointment() returns trigger
language plpgsql security definer set search_path='' as $$
declare s public.services; cr text;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 cr:=private.current_role();
 if (new.customer_id is not null and not private.same_demo(new.customer_id)) or (new.therapist_id is not null and not private.same_demo(new.therapist_id)) then raise exception 'Data demo terpisah dari data asli' using errcode='42501';end if;
 if tg_op='INSERT' then
  new.is_demo:=private.current_demo();
  if cr='customer' then
   if new.customer_id is distinct from auth.uid() then
    raise exception 'Reservasi hanya untuk akun sendiri' using errcode='42501';
   end if;
   select coalesce(nullif(trim(full_name),''),email) into new.booking_name
   from public.profiles where id=auth.uid();
  elsif cr is distinct from 'administrator' then
   raise exception 'Akses ditolak' using errcode='42501';
  end if;
  if new.customer_id is null and (
   nullif(trim(new.booking_name),'') is null or nullif(trim(new.booking_address),'') is null
   or nullif(trim(new.booking_phone),'') is null
  ) then raise exception 'Lengkapi data pelanggan'; end if;
  select * into s from public.services where id=new.service_id and active and is_demo=private.current_demo();
  if s.id is null then raise exception 'Layanan tidak aktif'; end if;
  if new.customer_id is not null and not exists(select 1 from public.profiles where id=new.customer_id and role='customer' and active) then raise exception 'Customer tidak aktif'; end if;
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

create or replace function private.assign_therapist(appointment_id uuid,new_therapist_id uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or private.current_role() is distinct from 'administrator' then raise exception 'Akses ditolak' using errcode='42501'; end if;
 if not private.same_demo(new_therapist_id) or not exists(select 1 from public.appointments where id=appointment_id and is_demo=private.current_demo()) then raise exception 'Akses lintas demo ditolak' using errcode='42501';end if;
 if not exists(select 1 from public.profiles where id=new_therapist_id and role='therapist' and active) then raise exception 'Terapis tidak aktif'; end if;
 update public.appointments set therapist_id=new_therapist_id,status='confirmed' where id=appointment_id and status in ('pending','confirmed');
 if not found then raise exception 'Reservasi tidak dapat ditugaskan'; end if;
end;
$$;
