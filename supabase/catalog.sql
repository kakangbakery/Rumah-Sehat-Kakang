create table public.catalog_products (
 id uuid primary key default gen_random_uuid(), name text not null check(length(trim(name)) between 1 and 120),
 description text not null default '' check(length(description)<=3000), price integer not null check(price>=0),
 image text not null default '' check(length(image)<=400000), active boolean not null default true,
 is_demo boolean not null, revision uuid not null default gen_random_uuid(), created_at timestamptz not null default now()
);
alter table public.catalog_products enable row level security;
revoke all on public.catalog_products from public,anon,authenticated;
grant select,insert,update on public.catalog_products to authenticated;
create policy products_read on public.catalog_products for select to authenticated using(is_demo=(select private.current_demo()) and ((select private.current_role())='administrator' or ((select private.current_role())='customer' and active)));
create policy products_insert on public.catalog_products for insert to authenticated with check ((select private.current_role())='administrator' and is_demo=(select private.current_demo()));
create policy products_update on public.catalog_products for update to authenticated using ((select private.current_role())='administrator' and is_demo=(select private.current_demo())) with check ((select private.current_role())='administrator' and is_demo=(select private.current_demo()));
create table public.product_orders (
 id uuid primary key default gen_random_uuid(), customer_id uuid not null references public.profiles(id),
 customer_name text not null, phone text not null, address text not null, items jsonb not null,
 total integer not null check(total>=0), status text not null default 'pending', is_demo boolean not null,
 created_at timestamptz not null default now()
);
alter table public.product_orders enable row level security;
revoke all on public.product_orders from public,anon,authenticated;
grant select on public.product_orders to authenticated;
create policy orders_admin_read on public.product_orders for select to authenticated using ((select private.current_role())='administrator' and is_demo=(select private.current_demo()));
create function private.checkout_products(customer_name text,phone text,address text,cart jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare item jsonb; product public.catalog_products; line_count integer; total_sum bigint:=0; snapshot jsonb:='[]'::jsonb; order_id uuid; demo boolean;
begin
 if auth.uid() is null or private.current_role() is distinct from 'customer' then raise exception 'Akses ditolak' using errcode='42501'; end if;
 demo:=private.current_demo();
 if customer_name is null or phone is null or address is null or cart is null then raise exception 'Lengkapi data' using errcode='22023'; end if;
 if length(trim(customer_name)) not between 1 and 100 or phone !~ '^[+0-9 ()-]{7,25}$' or length(trim(address)) not between 1 and 500 or jsonb_typeof(cart) is distinct from 'array' then raise exception 'Periksa nama, nomor telepon, alamat, dan keranjang' using errcode='22023'; end if;
 if jsonb_array_length(cart) not between 1 and 50 then raise exception 'Keranjang tidak valid' using errcode='22023'; end if;
 for item in select value from jsonb_array_elements(cart) loop
  if item->>'quantity' is null or item->>'id' is null or item->>'price' is null or (item->>'quantity') !~ '^[0-9]{1,3}$' or (item->>'id') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then raise exception 'Keranjang tidak valid' using errcode='22023'; end if;
  line_count:=(item->>'quantity')::integer;
  if line_count<1 or line_count>100 then raise exception 'Jumlah tidak valid' using errcode='22023'; end if;
  select * into product from public.catalog_products where id=(item->>'id')::uuid and active and is_demo=demo;
  if not found then raise exception 'Produk tidak tersedia' using errcode='22023'; end if;
  if (item->>'price') !~ '^[0-9]{1,10}$' or (item->>'price')::bigint<>product.price then raise exception 'Harga produk berubah' using errcode='22023'; end if;
  total_sum:=total_sum+product.price::bigint*line_count;
  if total_sum>2147483647 then raise exception 'Total terlalu besar' using errcode='22023'; end if;
  snapshot:=snapshot||jsonb_build_array(jsonb_build_object('id',product.id,'name',product.name,'price',product.price,'quantity',line_count));
 end loop;
 insert into public.product_orders(customer_id,customer_name,phone,address,items,total,is_demo) values(auth.uid(),trim(customer_name),trim(phone),trim(address),snapshot,total_sum::integer,demo) returning id into order_id;
 return order_id;
end;$$;
revoke all on function private.checkout_products(text,text,text,jsonb) from public,anon;
grant execute on function private.checkout_products(text,text,text,jsonb) to authenticated;
create function public.checkout_products(customer_name text,phone text,address text,cart jsonb) returns uuid language sql security invoker set search_path='' as $$ select private.checkout_products(customer_name,phone,address,cart); $$;
revoke all on function public.checkout_products(text,text,text,jsonb) from public,anon;
grant execute on function public.checkout_products(text,text,text,jsonb) to authenticated;
