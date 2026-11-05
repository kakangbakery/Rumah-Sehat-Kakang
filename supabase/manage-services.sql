alter table public.services add column is_demo boolean not null default false;
alter table public.services alter column description set default '';
alter table public.services drop constraint services_name_key;
alter table public.services add constraint services_partition_name_key unique(is_demo,name);

insert into public.services(name,duration_minutes,price,description,is_demo)
select name,duration_minutes,price,description,true from public.services where active;

drop policy "Read active services" on public.services;
-- Legacy demo bookings still reference live catalog entries for their names.
create policy services_public_read on public.services for select to anon
using (active and not is_demo);
create policy services_read on public.services for select to authenticated
using (active and (not is_demo or (select private.current_demo()) is true));
create policy services_admin_insert on public.services for insert to authenticated
with check ((select private.current_role())='administrator' and is_demo=(select private.current_demo()));
create policy services_admin_update on public.services for update to authenticated
using ((select private.current_role())='administrator' and is_demo=(select private.current_demo()))
with check ((select private.current_role())='administrator' and is_demo=(select private.current_demo()));
grant insert(name,duration_minutes,price,is_demo),update(name,duration_minutes,price)
on public.services to authenticated;

create or replace function private.validate_appointment() returns trigger
language plpgsql security definer set search_path='' as $$
declare s public.services; cr text;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 cr:=private.current_role();
 if not private.same_demo(new.customer_id) or (new.therapist_id is not null and not private.same_demo(new.therapist_id)) then raise exception 'Data demo terpisah dari data asli' using errcode='42501';end if;
 if tg_op='INSERT' then
  select * into s from public.services where id=new.service_id and active and is_demo=private.current_demo();
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
