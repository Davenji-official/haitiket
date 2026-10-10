-- HAITIKET lot 2 : commandes, réservation de stock, commission 2 % calculée côté serveur.
-- Aucun paiement n'est simulé : les commandes restent PENDING_PAYMENT tant qu'un prestataire réel n'est pas branché.

create table public.platform_settings (key text primary key, value text not null, updated_at timestamptz not null default now());
insert into public.platform_settings(key, value) values ('commission_bps','200'), ('reservation_minutes','30')
on conflict (key) do nothing;
-- 'delivery_flat_minor' (frais de livraison forfaitaires en centimes) n'est PAS défini : livraison indisponible tant qu'il n'est pas configuré.
alter table public.platform_settings enable row level security;
create policy settings_public_read on public.platform_settings for select using (key in ('commission_bps','reservation_minutes'));

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references auth.users(id),
  shop_id uuid not null references public.shops(id),
  status text not null default 'PENDING_PAYMENT' check (status in ('PENDING_PAYMENT','PAYMENT_PROCESSING','PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED','COMPLETED','CANCELLED','DISPUTED','REFUNDED')),
  delivery_mode text not null check (delivery_mode in ('pickup','delivery')),
  delivery_address text,
  currency text not null,
  items_minor bigint not null check (items_minor >= 0),
  delivery_minor bigint not null default 0 check (delivery_minor >= 0),
  total_minor bigint not null,
  commission_bps int not null,
  commission_minor bigint not null,
  seller_net_minor bigint not null,
  reserved_until timestamptz,
  created_at timestamptz not null default now()
);
create index on public.orders (customer_id, created_at desc);
create index on public.orders (shop_id, created_at desc);
create index on public.orders (status, reserved_until);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid not null references public.products(id),
  name text not null, unit_minor bigint not null, qty int not null check (qty > 0)
);
create table public.order_status_events (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  from_status text, to_status text not null, actor uuid, reason text,
  created_at timestamptz not null default now()
);
create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id),
  order_id uuid references public.orders(id),
  delta int not null, reason text not null, actor uuid,
  created_at timestamptz not null default now()
);

alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.order_status_events enable row level security;
alter table public.inventory_movements enable row level security;

create policy orders_read on public.orders for select using (
  customer_id = auth.uid() or exists (select 1 from public.shops s where s.id = shop_id and s.owner_id = auth.uid()));
create policy order_items_read on public.order_items for select using (
  exists (select 1 from public.orders o where o.id = order_id and (o.customer_id = auth.uid() or exists (select 1 from public.shops s where s.id = o.shop_id and s.owner_id = auth.uid()))));
create policy order_events_read on public.order_status_events for select using (
  exists (select 1 from public.orders o where o.id = order_id and (o.customer_id = auth.uid() or exists (select 1 from public.shops s where s.id = o.shop_id and s.owner_id = auth.uid()))));
create policy inventory_read on public.inventory_movements for select using (
  exists (select 1 from public.products p join public.shops s on s.id = p.shop_id where p.id = product_id and s.owner_id = auth.uid()));
-- Aucune politique d'écriture : seules les fonctions ci-dessous modifient ces tables.

create or replace function public._cancel_order(p_order uuid, p_actor uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare o public.orders; it record;
begin
  select * into o from public.orders where id = p_order for update;
  if o.id is null or o.status <> 'PENDING_PAYMENT' then return; end if;
  for it in select product_id, qty from public.order_items where order_id = p_order loop
    update public.products set stock = stock + it.qty where id = it.product_id;
    insert into public.inventory_movements(product_id, order_id, delta, reason, actor) values (it.product_id, p_order, it.qty, p_reason, p_actor);
  end loop;
  update public.orders set status = 'CANCELLED', reserved_until = null where id = p_order;
  insert into public.order_status_events(order_id, from_status, to_status, actor, reason) values (p_order, 'PENDING_PAYMENT', 'CANCELLED', p_actor, p_reason);
end $$;
revoke all on function public._cancel_order(uuid, uuid, text) from public, anon, authenticated;

create or replace function public.release_expired_reservations() returns int
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in select id from public.orders where status = 'PENDING_PAYMENT' and reserved_until < now() loop
    perform public._cancel_order(r.id, null, 'reservation_expired'); n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.release_expired_reservations() from public, anon, authenticated;

create or replace function public.cancel_order(p_order uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if not exists (select 1 from public.orders where id = p_order and customer_id = auth.uid() and status = 'PENDING_PAYMENT') then
    raise exception 'Commande introuvable ou non annulable';
  end if;
  perform public._cancel_order(p_order, auth.uid(), 'cancelled_by_customer');
end $$;

create or replace function public.create_orders(p_items jsonb, p_mode text, p_address text) returns setof public.orders
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); bps int; mins int; fee bigint := 0;
  v_shop uuid; v_items bigint; v_ncur int; v_cur text; v_comm bigint; r record; o public.orders;
begin
  if uid is null then raise exception 'Connexion requise'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'Panier vide'; end if;
  if p_mode not in ('pickup','delivery') then raise exception 'Mode de remise invalide'; end if;
  if p_mode = 'delivery' and coalesce(trim(p_address), '') = '' then raise exception 'Adresse de livraison requise'; end if;
  if exists (select 1 from jsonb_to_recordset(p_items) as x(product_id uuid, qty int) where x.product_id is null or x.qty is null or x.qty <= 0 or x.qty > 99) then
    raise exception 'Quantité invalide';
  end if;

  perform public.release_expired_reservations();
  select value::int into bps from public.platform_settings where key = 'commission_bps';
  select value::int into mins from public.platform_settings where key = 'reservation_minutes';
  if p_mode = 'delivery' then
    select value::bigint into fee from public.platform_settings where key = 'delivery_flat_minor';
    if fee is null then raise exception 'Livraison indisponible : aucun tarif configuré'; end if;
  end if;

  perform 1 from public.products where id in (select x.product_id from jsonb_to_recordset(p_items) as x(product_id uuid, qty int)) order by id for update;

  for v_shop in
    select distinct p.shop_id from public.products p where p.id in (select x.product_id from jsonb_to_recordset(p_items) as x(product_id uuid, qty int))
  loop
    if not exists (select 1 from public.shops s where s.id = v_shop and s.status = 'active') then raise exception 'Boutique indisponible'; end if;
    if exists (select 1 from public.shops s where s.id = v_shop and s.owner_id = uid) then raise exception 'Vous ne pouvez pas acheter dans votre propre boutique'; end if;

    for r in
      select p.id, p.name, p.price_minor, p.currency, p.status, p.stock, a.qty
      from (select x.product_id, sum(x.qty)::int as qty from jsonb_to_recordset(p_items) as x(product_id uuid, qty int) group by x.product_id) a
      join public.products p on p.id = a.product_id where p.shop_id = v_shop
    loop
      if r.status <> 'published' or r.stock < r.qty then raise exception 'Produit indisponible : %', r.name; end if;
    end loop;

    select count(distinct p.currency), min(p.currency), sum(p.price_minor * a.qty)
      into v_ncur, v_cur, v_items
    from (select x.product_id, sum(x.qty)::int as qty from jsonb_to_recordset(p_items) as x(product_id uuid, qty int) group by x.product_id) a
    join public.products p on p.id = a.product_id where p.shop_id = v_shop;
    if v_ncur <> 1 then raise exception 'Devises différentes dans une même boutique'; end if;

    v_comm := (v_items * bps + 5000) / 10000;
    insert into public.orders(customer_id, shop_id, delivery_mode, delivery_address, currency, items_minor, delivery_minor, total_minor, commission_bps, commission_minor, seller_net_minor, reserved_until)
    values (uid, v_shop, p_mode, case when p_mode = 'delivery' then trim(p_address) end, v_cur, v_items, fee, v_items + fee, bps, v_comm, v_items - v_comm, now() + make_interval(mins => mins))
    returning * into o;

    for r in
      select p.id, p.name, p.price_minor, a.qty
      from (select x.product_id, sum(x.qty)::int as qty from jsonb_to_recordset(p_items) as x(product_id uuid, qty int) group by x.product_id) a
      join public.products p on p.id = a.product_id where p.shop_id = v_shop
    loop
      insert into public.order_items(order_id, product_id, name, unit_minor, qty) values (o.id, r.id, r.name, r.price_minor, r.qty);
      update public.products set stock = stock - r.qty where id = r.id;
      insert into public.inventory_movements(product_id, order_id, delta, reason, actor) values (r.id, o.id, -r.qty, 'reservation', uid);
    end loop;
    insert into public.order_status_events(order_id, from_status, to_status, actor, reason) values (o.id, null, 'PENDING_PAYMENT', uid, 'order_created');
    return next o;
  end loop;
  return;
end $$;

grant execute on function public.create_orders(jsonb, text, text) to authenticated;
grant execute on function public.cancel_order(uuid) to authenticated;

-- Libération automatique des réservations expirées (toutes les 5 min) si pg_cron est activé dans Supabase.
do $$ begin
  create extension if not exists pg_cron;
  perform cron.schedule('release-expired-reservations', '*/5 * * * *', 'select public.release_expired_reservations()');
exception when others then raise notice 'pg_cron non disponible : activez-le dans Database > Extensions'; end $$;
