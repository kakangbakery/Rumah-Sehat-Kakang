create function private.valid_allocations(items jsonb) returns boolean
language plpgsql immutable set search_path='' as $$
declare item jsonb; total numeric:=0; rate numeric;
begin
  if jsonb_typeof(items) is distinct from 'array' then return false; end if;
  if jsonb_array_length(items)>30 then return false; end if;
  for item in select value from jsonb_array_elements(items) loop
    if jsonb_typeof(item->'name') is distinct from 'string'
      or length(trim(item->>'name')) not between 1 and 100
      or jsonb_typeof(item->'percent') is distinct from 'number' then return false; end if;
    rate:=(item->>'percent')::numeric;
    if rate<0 or rate>100 or rate<>round(rate,2) then return false; end if;
    total:=total+rate;
  end loop;
  return total<=100;
end;
$$;
revoke all on function private.valid_allocations(jsonb) from public,anon;
grant execute on function private.valid_allocations(jsonb) to authenticated;

create table public.finance_allocations (
  is_demo boolean primary key,
  items jsonb not null check(private.valid_allocations(items)),
  revision uuid not null default gen_random_uuid()
);
insert into public.finance_allocations(is_demo,items)
select demo, '[{"name":"Sedekah","percent":5},{"name":"Pendidikan terapis","percent":5},{"name":"Kas perusahaan","percent":15},{"name":"Pemilik","percent":15},{"name":"Referral","percent":5},{"name":"Terapis","percent":35},{"name":"Operasional","percent":20}]'::jsonb
from (values(false),(true)) as partitions(demo);
alter table public.finance_allocations enable row level security;
revoke all on public.finance_allocations from anon,authenticated;
grant select,update(items,revision) on public.finance_allocations to authenticated;
create policy finance_admin_read on public.finance_allocations for select to authenticated
using ((select private.current_role())='administrator' and is_demo=(select private.current_demo()));
create policy finance_admin_write on public.finance_allocations for update to authenticated
using ((select private.current_role())='administrator' and is_demo=(select private.current_demo()))
with check ((select private.current_role())='administrator' and is_demo=(select private.current_demo()));

alter table public.profiles drop constraint profiles_role_check;
alter table public.profiles add constraint profiles_role_check
check(role in ('administrator','therapist','customer','referral'));

create function private.create_staff_account(full_name text, email text, initial_password text, account_role text)
returns uuid
language plpgsql security definer set search_path='' as $$
declare
  new_id uuid := gen_random_uuid();
  account_email text := lower(trim(email));
  account_name text := trim(full_name);
  demo_account boolean;
begin
  if auth.uid() is null or private.current_role() is distinct from 'administrator' then
    raise exception 'Akses ditolak' using errcode='42501';
  end if;
  if account_role is null or account_role not in ('therapist','referral') then
    raise exception 'Peran tidak valid' using errcode='22023';
  end if;
  demo_account := private.current_demo();
  if demo_account is null then
    raise exception 'Akses ditolak' using errcode='42501';
  end if;
  if account_name is null or length(account_name) not between 1 and 100
    or account_email is null or length(account_email)>254
    or account_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
    or initial_password is null or length(initial_password)<8
    or octet_length(initial_password)>72 then
    raise exception 'Nama, email, atau password tidak valid' using errcode='22023';
  end if;
  if demo_account and split_part(account_email,'@',2) <> 'kakang.test' then
    raise exception 'Akun demo memakai email @kakang.test' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(904341);
  if exists(select 1 from private.owner_bootstrap b where lower(b.email)=account_email) then
    raise exception 'Email tidak tersedia' using errcode='23505';
  end if;

  insert into auth.users (
    instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
    confirmation_token,recovery_token,email_change_token_new,email_change,
    raw_app_meta_data,raw_user_meta_data,is_super_admin,created_at,updated_at
  ) values (
    '00000000-0000-0000-0000-000000000000',new_id,'authenticated','authenticated',
    account_email,extensions.crypt(initial_password,extensions.gen_salt('bf',10)),now(),
    '','','','',
    '{"provider":"email","providers":["email"]}',jsonb_build_object('full_name',account_name),
    false,now(),now()
  );
  insert into auth.identities(provider_id,user_id,identity_data,provider,created_at,updated_at)
  values(new_id::text,new_id,jsonb_build_object(
    'sub',new_id::text,'email',account_email,'email_verified',true,'phone_verified',false
  ),'email',now(),now());
  update public.profiles set role=account_role,is_demo=demo_account where id=new_id;
  insert into public.role_audit(actor_id,target_id,old_role,new_role,active)
  values(auth.uid(),new_id,'customer',account_role,true);
  return new_id;
end;
$$;
revoke all on function private.create_staff_account(text,text,text,text) from public,anon;
grant execute on function private.create_staff_account(text,text,text,text) to authenticated;

create or replace function private.create_therapist(full_name text,email text,initial_password text)
returns uuid language sql security invoker set search_path='' as $$
  select private.create_staff_account(full_name,email,initial_password,'therapist');
$$;

create function public.create_referral(full_name text,email text,initial_password text)
returns uuid language sql security invoker set search_path='' as $$
  select private.create_staff_account(full_name,email,initial_password,'referral');
$$;
revoke all on function public.create_referral(text,text,text) from public,anon;
grant execute on function public.create_referral(text,text,text) to authenticated;

create or replace function private.manage_account(target_id uuid,new_role text,is_active boolean) returns void
language plpgsql security definer set search_path='' as $$
declare previous text;
begin
 if auth.uid() is null or private.current_role() is distinct from 'administrator' then raise exception 'Akses ditolak' using errcode='42501'; end if;
 if new_role not in ('administrator','therapist','customer','referral') or is_active is null then raise exception 'Peran tidak valid'; end if;
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
