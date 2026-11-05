alter table public.services drop constraint services_partition_name_key;
create unique index services_active_partition_name_key
on public.services(is_demo,name) where active;

create policy services_read_booked on public.services for select to authenticated
using (exists (
  select 1 from public.appointments a where a.service_id=services.id
));

create function private.archive_service(service_id uuid) returns boolean
language plpgsql security definer set search_path='' as $$
begin
  if private.current_role() is distinct from 'administrator' then
    raise exception 'Akses ditolak' using errcode='42501';
  end if;

  update public.services set active=false
  where id=service_id and is_demo=private.current_demo();
  return found;
end;
$$;
revoke all on function private.archive_service(uuid) from public,anon;
grant execute on function private.archive_service(uuid) to authenticated;

create function public.archive_service(service_id uuid) returns boolean
language sql security invoker set search_path='' as $$
  select private.archive_service(service_id);
$$;
revoke all on function public.archive_service(uuid) from public,anon;
grant execute on function public.archive_service(uuid) to authenticated;
