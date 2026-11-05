create function private.create_therapist(full_name text, email text, initial_password text)
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
  update public.profiles set role='therapist',is_demo=demo_account where id=new_id;
  insert into public.role_audit(actor_id,target_id,old_role,new_role,active)
  values(auth.uid(),new_id,'customer','therapist',true);
  return new_id;
end;
$$;
revoke all on function private.create_therapist(text,text,text) from public,anon;
grant execute on function private.create_therapist(text,text,text) to authenticated;

create function public.create_therapist(full_name text,email text,initial_password text)
returns uuid language sql security invoker set search_path='' as $$
  select private.create_therapist(full_name,email,initial_password);
$$;
revoke all on function public.create_therapist(text,text,text) from public,anon;
grant execute on function public.create_therapist(text,text,text) to authenticated;
