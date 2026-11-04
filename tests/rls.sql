begin;
-- Owner activation must require email verification and happen only once.
create temp table bootstrap_test(id uuid default gen_random_uuid());
insert into bootstrap_test default values;
insert into auth.users(id,email,raw_user_meta_data) select id,(select email from private.owner_bootstrap where singleton),'{}'::jsonb from bootstrap_test;
do $$begin
 if (select role from public.profiles where id=(select id from bootstrap_test))<>'customer' then raise exception 'Unverified owner elevated';end if;
end$$;
update auth.users set email_confirmed_at=now() where id=(select id from bootstrap_test);
do $$begin
 if (select role from public.profiles where id=(select id from bootstrap_test))<>'administrator' then raise exception 'Verified owner not activated';end if;
end$$;
create temp table rbac_people (label text,id uuid default gen_random_uuid());
insert into rbac_people(label) values('administrator'),('therapist'),('therapist2'),('customer'),('customer2');
create temp table rbac_booking_ids(label text,id uuid default gen_random_uuid());
insert into rbac_booking_ids(label) values('first'),('second');
grant select on rbac_people,rbac_booking_ids to authenticated;
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) select id,'rbac-test-'||id||'@example.invalid',now(),jsonb_build_object('full_name',label,'role','administrator') from rbac_people;
do $$begin
 if exists(select 1 from public.profiles p join rbac_people t on t.id=p.id where p.role<>'customer') then raise exception 'Metadata privilege escalation'; end if;
end$$;
update public.profiles p set role=case when t.label in ('therapist','therapist2') then 'therapist' when t.label='administrator' then 'administrator' else 'customer' end from rbac_people t where p.id=t.id;
set local role authenticated;
select set_config('request.jwt.claims',json_build_object('sub',(select id from rbac_people where label='customer'),'role','authenticated')::text,true);
do $$begin
 if private.current_role()<>'customer' then raise exception 'Wrong current role'; end if;
 if (select count(*) from public.profiles)<>1 then raise exception 'Customer profile isolation failed'; end if;
 begin update public.profiles set role='administrator' where id=auth.uid();raise exception 'Role update should fail'; exception when insufficient_privilege then null;end;
 begin perform public.manage_account(auth.uid(),'administrator',true);raise exception 'Self promotion should fail';exception when insufficient_privilege then null;end;
end$$;
-- Insert only permitted columns; the database fills price, duration and IDs.
insert into public.appointments(customer_id,service_id,starts_at) values(auth.uid(),(select id from public.services limit 1),now()+interval '2 days');
reset role;
update rbac_booking_ids set id=(select id from public.appointments where customer_id=(select id from rbac_people where label='customer')) where label='first';
set local role authenticated;
select set_config('request.jwt.claims',json_build_object('sub',(select id from rbac_people where label='customer2'),'role','authenticated')::text,true);
do $$begin
 if (select count(*) from public.appointments)<>0 then raise exception 'Customer cross-read'; end if;
 begin insert into public.appointments(customer_id,service_id,starts_at) values((select id from rbac_people where label='customer'),(select id from public.services limit 1),now()+interval '2 days');raise exception 'Cross-user insert should fail';exception when insufficient_privilege then null;end;
end$$;
insert into public.appointments(customer_id,service_id,starts_at) values(auth.uid(),(select id from public.services limit 1),now()+interval '2 days');
reset role;
update rbac_booking_ids set id=(select id from public.appointments where customer_id=(select id from rbac_people where label='customer2')) where label='second';
set local role authenticated;
select set_config('request.jwt.claims',json_build_object('sub',(select id from rbac_people where label='administrator'),'role','authenticated')::text,true);
select public.assign_therapist((select id from rbac_booking_ids where label='first'),(select id from rbac_people where label='therapist'));
select public.assign_therapist((select id from rbac_booking_ids where label='second'),(select id from rbac_people where label='therapist2'));
do $$begin
 if (select count(*) from public.appointments)<>2 then raise exception 'Admin missing appointments';end if;
 begin perform public.assign_therapist((select id from rbac_booking_ids where label='second'),(select id from rbac_people where label='therapist'));raise exception 'Overlap should fail';exception when raise_exception then if sqlerrm='Overlap should fail' then raise;end if;end;
end$$;
select set_config('request.jwt.claims',json_build_object('sub',(select id from rbac_people where label='therapist'),'role','authenticated')::text,true);
do $$begin
 if (select count(*) from public.appointments)<>1 then raise exception 'Therapist isolation failed';end if;
 if exists(select 1 from public.profiles where id=(select id from rbac_people where label='customer2')) then raise exception 'Unassigned customer exposed';end if;
 begin update public.appointments set price=1;raise exception 'Price tampering should fail';exception when insufficient_privilege then null;end;
 begin update public.appointments set status='completed';raise exception 'Skipped transition should fail';exception when insufficient_privilege then null;end;
 update public.appointments set status='in_progress' where id=(select id from rbac_booking_ids where label='first');
 update public.appointments set status='completed' where id=(select id from rbac_booking_ids where label='first');
 if (select status from public.appointments limit 1)<>'completed' then raise exception 'Status transition failed';end if;
end$$;
-- Deactivation must take effect immediately, even with an existing JWT.
reset role;
update public.profiles set active=false where id=(select id from rbac_people where label='therapist');
set local role authenticated;
do $$begin
 if private.current_role() is not null then raise exception 'Inactive role leaked';end if;
 if (select count(*) from public.appointments)<>0 then raise exception 'Inactive account sees data';end if;
 begin perform public.manage_account((select id from rbac_people where label='customer'),'administrator',true);raise exception 'Inactive promotion should fail';exception when insufficient_privilege then null;end;
end$$;
reset role;
set local role anon;
do $$begin
 begin perform 1 from public.profiles;raise exception 'Anon profiles should fail';exception when insufficient_privilege then null;end;
 begin perform 1 from public.appointments;raise exception 'Anon appointments should fail';exception when insufficient_privilege then null;end;
end$$;
reset role;
rollback;
select 'PASS: role escalation, row isolation, assignment, status transitions, inactive access, and anonymous denial' as rbac_test_result;
