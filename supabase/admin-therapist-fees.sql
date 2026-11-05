create function private.therapist_fee_report(month_start date, therapist uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare rate numeric; demo boolean;
begin
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
   where a.therapist_id=therapist and a.is_demo=demo and a.status='completed'
    and coalesce(a.completed_at,a.starts_at)>=month_start::timestamp at time zone 'Asia/Jakarta'
    and coalesce(a.completed_at,a.starts_at)<(month_start+interval '1 month') at time zone 'Asia/Jakarta'
  ) sessions
 );
end;
$$;

revoke all on function private.therapist_fee_report(date,uuid) from public,anon,authenticated;

create or replace function private.therapist_earnings(month_start date) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or private.current_role() is distinct from 'therapist' then
  raise exception 'Akses ditolak' using errcode='42501';
 end if;
 return private.therapist_fee_report(month_start,auth.uid());
end;
$$;

create function private.admin_therapist_fees(month_start date,target uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or private.current_role() is distinct from 'administrator' then
  raise exception 'Akses ditolak' using errcode='42501';
 end if;
 if month_start is null or extract(day from month_start) <> 1
    or month_start < date '2000-01-01' or month_start >= date '2100-01-01' then
  raise exception 'Periode tidak valid' using errcode='22023';
 end if;
 if target is not null then
  if not private.same_demo(target) then
   raise exception 'Akses ditolak' using errcode='42501';
  end if;
  return private.therapist_fee_report(month_start,target);
 end if;
 return (
  select coalesce(jsonb_agg(to_jsonb(staff) order by staff.name,staff.id),'[]'::jsonb)
  from (
   select p.id,coalesce(nullif(trim(p.full_name),''),p.email) as name
   from public.profiles p
   where p.is_demo=private.current_demo()
     and exists (
      select 1 from public.appointments a
      where a.therapist_id=p.id and a.is_demo=p.is_demo and a.status='completed'
        and coalesce(a.completed_at,a.starts_at)>=month_start::timestamp at time zone 'Asia/Jakarta'
        and coalesce(a.completed_at,a.starts_at)<(month_start+interval '1 month') at time zone 'Asia/Jakarta'
     )
  ) staff
 );
end;
$$;

create function public.admin_therapist_fees(month_start date,target uuid) returns jsonb
language sql stable security invoker set search_path='' as $$
 select private.admin_therapist_fees(month_start,target);
$$;

revoke all on function private.admin_therapist_fees(date,uuid),public.admin_therapist_fees(date,uuid) from public,anon;
grant execute on function private.admin_therapist_fees(date,uuid),public.admin_therapist_fees(date,uuid) to authenticated;
