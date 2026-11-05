alter table public.finance_allocations
add column income integer not null default 0 check(income>=0);

grant update(income) on public.finance_allocations to authenticated;
