begin;
create temp table isolation_fixture(id uuid default gen_random_uuid());
insert into isolation_fixture default values;
grant select on isolation_fixture to authenticated;
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) select id,'isolation-'||id||'@example.invalid',now(),'{}'::jsonb from isolation_fixture;
select set_config('request.jwt.claims',json_build_object('sub',(select id from public.profiles where email='admin.demo@kakang.test'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin
 if exists(select 1 from public.profiles where id=(select id from isolation_fixture)) then raise exception 'Demo sees a real profile';end if;
 if exists(select 1 from public.profiles where not is_demo) then raise exception 'Non-demo profile exposed';end if;
 begin perform public.manage_account((select id from isolation_fixture),'administrator',true);raise exception 'Demo changed real account';exception when insufficient_privilege then null;end;
 begin insert into public.appointments(customer_id,service_id,starts_at) values((select id from isolation_fixture),(select id from public.services limit 1),now()+interval '3 days');raise exception 'Demo created real booking';exception when insufficient_privilege then null;end;
 begin update public.profiles set is_demo=false where id=auth.uid();raise exception 'Demo escaped partition';exception when insufficient_privilege then null;end;
end$$;
reset role;
select set_config('request.jwt.claims',json_build_object('sub',(select id from isolation_fixture),'role','authenticated')::text,true);
set local role authenticated;
do $$begin
 if exists(select 1 from public.profiles where is_demo) then raise exception 'Real account sees demo profiles';end if;
 if exists(select 1 from public.appointments) then raise exception 'Real account sees demo bookings';end if;
end$$;
reset role;
rollback;
select 'PASS: demo accounts cannot read or mutate real profiles/bookings or escape isolation' as demo_isolation_test;
