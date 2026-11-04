create table public.services (
 id uuid primary key default gen_random_uuid(), name text not null unique,
 duration_minutes integer not null check(duration_minutes > 0),
 price integer not null check(price >= 0), description text not null,
 active boolean not null default true
);
alter table public.services enable row level security;
revoke all on public.services from anon, authenticated;
grant select on public.services to anon, authenticated;
create policy "Read active services" on public.services for select to anon, authenticated using (active = true);
insert into public.services(name,duration_minutes,price,description) values
 ('Refleksi Kaki',60,150000,'Waktu tenang untuk kaki yang aktif.'),
 ('Refleksi Seluruh Tubuh',90,200000,'Relaksasi menyeluruh setelah hari yang panjang.'),
 ('Refleksi & Relaksasi',120,250000,'Sesi lebih panjang, istirahat lebih nyaman.');
