alter table public.appointments add column completed_at timestamptz;

create function private.record_completion() returns trigger
language plpgsql set search_path='' as $$
begin
  if new.status='completed' then
    if tg_op='INSERT' then
      new.completed_at:=statement_timestamp();
    elsif old.status is distinct from 'completed' then
      new.completed_at:=statement_timestamp();
    end if;
  else
    new.completed_at:=null;
  end if;
  return new;
end;
$$;
revoke all on function private.record_completion() from public,anon,authenticated;
create trigger record_completion before insert or update of status on public.appointments
for each row execute function private.record_completion();

create index appointments_completed_income_idx
on public.appointments ((coalesce(completed_at,starts_at))) where status='completed';

create table public.finance_applied_allocations (
  is_demo boolean not null,
  period date not null,
  items jsonb not null check(private.valid_allocations(items)),
  revision uuid not null,
  primary key(is_demo,period)
);
insert into public.finance_applied_allocations(is_demo,period,items,revision)
select is_demo,date '0001-01-01',items,revision from public.finance_allocations;
alter table public.finance_applied_allocations enable row level security;
revoke all on public.finance_applied_allocations from public,anon,authenticated;
grant select on public.finance_applied_allocations to authenticated;
create policy applied_finance_read on public.finance_applied_allocations for select to authenticated
using ((select private.current_role())='administrator' and is_demo=(select private.current_demo()));

create function private.apply_finance_simulation(expected_revision uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare
  simulation public.finance_allocations;
  month_start date:=date_trunc('month',statement_timestamp() at time zone 'Asia/Jakarta')::date;
begin
  if private.current_role() is distinct from 'administrator' then
    raise exception 'Akses ditolak' using errcode='42501';
  end if;
  select * into simulation from public.finance_allocations
  where is_demo=private.current_demo() and revision=expected_revision for update;
  if not found then return false; end if;
  insert into public.finance_applied_allocations(is_demo,period,items,revision)
  values(simulation.is_demo,month_start,simulation.items,simulation.revision)
  on conflict(is_demo,period) do update set items=excluded.items,revision=excluded.revision;
  return true;
end;
$$;
revoke all on function private.apply_finance_simulation(uuid) from public,anon;
grant execute on function private.apply_finance_simulation(uuid) to authenticated;

create function public.apply_finance_simulation(expected_revision uuid) returns boolean
language sql security invoker set search_path='' as $$
  select private.apply_finance_simulation(expected_revision);
$$;
revoke all on function public.apply_finance_simulation(uuid) from public,anon;
grant execute on function public.apply_finance_simulation(uuid) to authenticated;

create function public.finance_income_report(month_start date) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare
  next_month date:=(month_start+interval '1 month')::date;
  breakdown jsonb;
  period_total bigint;
  applied public.finance_applied_allocations;
begin
  if private.current_role() is distinct from 'administrator' then
    raise exception 'Akses ditolak' using errcode='42501';
  end if;
  if month_start is null or extract(day from month_start)<>1 then
    raise exception 'Periode tidak valid' using errcode='22023';
  end if;
  select * into strict applied from public.finance_applied_allocations
  where period<=month_start order by period desc limit 1;
  select coalesce(jsonb_agg(to_jsonb(daily) order by day desc),'[]'::jsonb),coalesce(sum(total),0)
  into breakdown,period_total
  from (
    select (coalesce(completed_at,starts_at) at time zone 'Asia/Jakarta')::date as day,
      count(*) as bookings,sum(price) as total
    from public.appointments
    where status='completed'
      and coalesce(completed_at,starts_at)>=month_start::timestamp at time zone 'Asia/Jakarta'
      and coalesce(completed_at,starts_at)<next_month::timestamp at time zone 'Asia/Jakarta'
    group by 1
  ) daily;
  return jsonb_build_object('start',month_start,'end',next_month-1,'total',period_total,
    'days',breakdown,'items',applied.items,'revision',applied.revision);
end;
$$;
revoke all on function public.finance_income_report(date) from public,anon;
grant execute on function public.finance_income_report(date) to authenticated;
