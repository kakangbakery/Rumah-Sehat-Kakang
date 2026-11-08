create table public.sop_entries (
 id uuid primary key default gen_random_uuid(),
 category text not null check(category in ('heijo','terapis','customer')),
 title text not null check(length(trim(title)) between 1 and 150),
 body text not null check(length(trim(body)) between 1 and 20000),
 is_demo boolean not null,
 revision uuid not null default gen_random_uuid(),
 created_at timestamptz not null default now()
);
alter table public.sop_entries enable row level security;
revoke all on public.sop_entries from public,anon,authenticated;
grant select,insert,update,delete on public.sop_entries to authenticated;
create policy sop_admin_select on public.sop_entries for select to authenticated using ((select private.current_role())='administrator' and is_demo=(select private.current_demo()));
create policy sop_admin_insert on public.sop_entries for insert to authenticated with check ((select private.current_role())='administrator' and is_demo=(select private.current_demo()));
create policy sop_admin_update on public.sop_entries for update to authenticated using ((select private.current_role())='administrator' and is_demo=(select private.current_demo())) with check ((select private.current_role())='administrator' and is_demo=(select private.current_demo()));
create policy sop_admin_delete on public.sop_entries for delete to authenticated using ((select private.current_role())='administrator' and is_demo=(select private.current_demo()));
