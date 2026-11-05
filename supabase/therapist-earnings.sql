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
  if old.therapist_id is distinct from auth.uid() or not ((old.status='pending' and new.status='confirmed') or (old.status='confirmed' and new.status='in_progress') or (old.status='in_progress' and new.status='completed')) then
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
 update public.appointments set therapist_id=new_therapist_id where id=appointment_id and status in ('pending','confirmed');
 if not found then raise exception 'Reservasi tidak dapat ditugaskan'; end if;
end;
$$;

create function private.therapist_earnings(month_start date) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare rate numeric; demo boolean;
begin
 if auth.uid() is null or private.current_role() is distinct from 'therapist' then
  raise exception 'Akses ditolak' using errcode='42501';
 end if;
 if month_start is null or extract(day from month_start) <> 1
    or month_start < date '2000-01-01' or month_start >= date '2100-01-01' then
  raise exception 'Periode tidak valid' using errcode='22023';
 end if;
 demo:=private.current_demo();

 select (item->>'percent')::numeric into rate
 from (
  select items from public.finance_applied_allocations
  where is_demo=demo and period<=month_start order by period desc limit 1
 ) applied
 cross join lateral jsonb_array_elements(applied.items) with ordinality as positions(item,position)
 where lower(trim(item->>'name')) in ('terapis','fee terapis')
 order by (lower(trim(item->>'name'))='fee terapis') desc,position
 limit 1;

 return (
  select jsonb_build_object(
   'rate',rate,'total',coalesce(sum(fee),0),
   'sessions',coalesce(jsonb_agg(to_jsonb(sessions) order by finished_at desc,id),'[]'::jsonb)
  )
  from (
   select a.id, coalesce(a.booking_name,p.full_name,'Customer') as customer,
    s.name as service, coalesce(a.completed_at,a.starts_at) as finished_at,
    floor(a.price*rate/100) as fee
   from public.appointments a
   join public.services s on s.id=a.service_id
   left join public.profiles p on p.id=a.customer_id
   where a.therapist_id=auth.uid() and a.is_demo=demo and a.status='completed'
    and coalesce(a.completed_at,a.starts_at)>=month_start::timestamp at time zone 'Asia/Jakarta'
    and coalesce(a.completed_at,a.starts_at)<(month_start+interval '1 month') at time zone 'Asia/Jakarta'
  ) sessions
 );
end;
$$;

create function public.therapist_earnings(month_start date) returns jsonb
language sql stable security invoker set search_path='' as $$
 select private.therapist_earnings(month_start);
$$;

revoke all on function private.therapist_earnings(date), public.therapist_earnings(date) from public,anon;
grant execute on function private.therapist_earnings(date), public.therapist_earnings(date) to authenticated;
