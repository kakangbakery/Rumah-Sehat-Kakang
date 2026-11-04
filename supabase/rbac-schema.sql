-- RBAC schema. Applied to project tpdcetrvlpemqcibokmb through the migration API.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create table private.owner_bootstrap (
 singleton boolean primary key default true check(singleton),
 email text not null,
 claimed_user uuid references auth.users(id)
);
revoke all on private.owner_bootstrap from public, anon, authenticated;

create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 email text not null,
 full_name text not null default '' check(length(full_name)<=100),
 phone text not null default '' check(length(phone)<=25),
 role text not null default 'customer' check(role in ('administrator','therapist','customer')),
 active boolean not null default true,
 created_at timestamptz not null default now()
);
create index profiles_role_idx on public.profiles(role);
alter table public.profiles enable row level security;
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
grant update(full_name,phone) on public.profiles to authenticated;

create function private.current_role() returns text
language sql stable security definer set search_path='' as $$
 select p.role from public.profiles p join auth.users u on u.id=p.id where p.id=(select auth.uid()) and p.active and u.email_confirmed_at is not null and (select auth.uid()) is not null;
$$;
revoke all on function private.current_role() from public, anon;
grant execute on function private.current_role() to authenticated;

create function private.sync_auth_profile() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 insert into public.profiles(id,email,full_name) values(new.id,coalesce(new.email,''),left(coalesce(new.raw_user_meta_data->>'full_name',''),100))
 on conflict(id) do update set email=excluded.email;
 -- Only a verified owner email, configured outside the public API, can bootstrap once.
 perform pg_advisory_xact_lock(904341);
 if new.email_confirmed_at is not null then
  update private.owner_bootstrap set claimed_user=new.id
   where singleton and claimed_user is null and lower(email)=lower(new.email);
  if found then update public.profiles set role='administrator' where id=new.id; end if;
 end if;
 return new;
end;
$$;
revoke all on function private.sync_auth_profile() from public, anon, authenticated;
create trigger auth_profile_created after insert on auth.users for each row execute function private.sync_auth_profile();
create trigger auth_profile_confirmed after update of email,email_confirmed_at on auth.users for each row execute function private.sync_auth_profile();

create table public.appointments (
 id uuid primary key default gen_random_uuid(),
 customer_id uuid not null references public.profiles(id),
 therapist_id uuid references public.profiles(id),
 service_id uuid not null references public.services(id),
 starts_at timestamptz not null,
 duration_minutes integer not null,
 price integer not null,
 status text not null default 'pending' check(status in ('pending','confirmed','in_progress','completed','cancelled')),
 created_at timestamptz not null default now()
);
create index appointments_customer_idx on public.appointments(customer_id,starts_at);
create index appointments_therapist_idx on public.appointments(therapist_id,starts_at);
alter table public.appointments enable row level security;
revoke all on public.appointments from anon, authenticated;
grant select on public.appointments to authenticated;
grant insert(customer_id,service_id,starts_at) on public.appointments to authenticated;
grant update(status) on public.appointments to authenticated;

create policy profiles_read on public.profiles for select to authenticated using (
 (id=(select auth.uid()) and (select private.current_role()) is not null)
 or (select private.current_role())='administrator'
 or ((select private.current_role())='customer' and exists(select 1 from public.appointments a where a.therapist_id=profiles.id and a.customer_id=(select auth.uid())))
 or ((select private.current_role())='therapist' and exists(select 1 from public.appointments a where a.customer_id=profiles.id and a.therapist_id=(select auth.uid())))
);
create policy profiles_edit_self on public.profiles for update to authenticated
 using(id=(select auth.uid()) and (select private.current_role()) is not null)
 with check(id=(select auth.uid()) and (select private.current_role()) is not null);
create policy appointments_read on public.appointments for select to authenticated using (
 (select private.current_role())='administrator'
 or ((select private.current_role())='customer' and customer_id=(select auth.uid()))
 or ((select private.current_role())='therapist' and therapist_id=(select auth.uid()))
);
create policy appointments_create on public.appointments for insert to authenticated with check (
 (select private.current_role())='administrator'
 or ((select private.current_role())='customer' and customer_id=(select auth.uid()) and status='pending' and therapist_id is null)
);
create policy appointments_status on public.appointments for update to authenticated
 using ((select private.current_role())='administrator' or ((select private.current_role())='therapist' and therapist_id=(select auth.uid())))
 with check ((select private.current_role())='administrator' or ((select private.current_role())='therapist' and therapist_id=(select auth.uid())));

create function private.validate_appointment() returns trigger
language plpgsql security definer set search_path='' as $$
declare s public.services; cr text;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 cr:=private.current_role();
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
revoke all on function private.validate_appointment() from public, anon, authenticated;
create trigger validate_appointment before insert or update on public.appointments for each row execute function private.validate_appointment();

create table public.role_audit (
 id bigint generated always as identity primary key,
 actor_id uuid not null references public.profiles(id),
 target_id uuid not null references public.profiles(id),
 old_role text not null,new_role text not null,active boolean not null,
 created_at timestamptz not null default now()
);
alter table public.role_audit enable row level security;
revoke all on public.role_audit from anon,authenticated;
grant select on public.role_audit to authenticated;
create policy role_audit_admin on public.role_audit for select to authenticated using((select private.current_role())='administrator');

create function private.manage_account(target_id uuid,new_role text,is_active boolean) returns void
language plpgsql security definer set search_path='' as $$
declare previous text;
begin
 if auth.uid() is null or private.current_role() is distinct from 'administrator' then raise exception 'Akses ditolak' using errcode='42501'; end if;
 if new_role not in ('administrator','therapist','customer') or is_active is null then raise exception 'Peran tidak valid'; end if;
 perform pg_advisory_xact_lock(904342);
 if target_id=auth.uid() then raise exception 'Anda tidak dapat mengubah akses akun sendiri'; end if;
 select role into previous from public.profiles where id=target_id for update;
 if previous is null then raise exception 'Akun tidak ditemukan'; end if;
 if previous='administrator' and (new_role<>'administrator' or not is_active) and (select count(*) from public.profiles where role='administrator' and active)<=1 then raise exception 'Administrator terakhir harus tetap aktif'; end if;
 if (previous<>new_role or not is_active) and exists(select 1 from public.appointments where (customer_id=target_id or therapist_id=target_id) and status not in ('completed','cancelled')) then raise exception 'Selesaikan atau batalkan reservasi aktif sebelum mengubah peran'; end if;
 update public.profiles set role=new_role,active=is_active where id=target_id;
 insert into public.role_audit(actor_id,target_id,old_role,new_role,active) values(auth.uid(),target_id,previous,new_role,is_active);
end;
$$;
revoke all on function private.manage_account(uuid,text,boolean) from public,anon;
grant execute on function private.manage_account(uuid,text,boolean) to authenticated;
create function public.manage_account(target_id uuid,new_role text,is_active boolean) returns void
language sql security invoker set search_path='' as $$ select private.manage_account(target_id,new_role,is_active); $$;
revoke all on function public.manage_account(uuid,text,boolean) from public,anon;
grant execute on function public.manage_account(uuid,text,boolean) to authenticated;

create function private.assign_therapist(appointment_id uuid,new_therapist_id uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or private.current_role() is distinct from 'administrator' then raise exception 'Akses ditolak' using errcode='42501'; end if;
 if not exists(select 1 from public.profiles where id=new_therapist_id and role='therapist' and active) then raise exception 'Terapis tidak aktif'; end if;
 update public.appointments set therapist_id=new_therapist_id,status='confirmed' where id=appointment_id and status in ('pending','confirmed');
 if not found then raise exception 'Reservasi tidak dapat ditugaskan'; end if;
end;
$$;
revoke all on function private.assign_therapist(uuid,uuid) from public,anon;
grant execute on function private.assign_therapist(uuid,uuid) to authenticated;
create function public.assign_therapist(appointment_id uuid,new_therapist_id uuid) returns void
language sql security invoker set search_path='' as $$ select private.assign_therapist(appointment_id,new_therapist_id); $$;
revoke all on function public.assign_therapist(uuid,uuid) from public,anon;
grant execute on function public.assign_therapist(uuid,uuid) to authenticated;
