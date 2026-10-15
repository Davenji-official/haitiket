-- HAITIKET lot 7 : catégories, géolocalisation boutiques, avis vérifiés, codes de remise (PIN), coupons,
-- parrainage, notifications in-app, statuts vendeur. Exécuter après 0001..0006.

create or replace function public._gen_pin() returns text language sql as $$ select lpad((floor(random() * 1000000))::int::text, 6, '0') $$;

-- ===== Catégories =====
insert into public.categories (name)
select n from (values ('Vêtements et chaussures'),('Nourriture et boissons'),('Électronique'),('Téléphones et accessoires'),('Maison et décoration'),('Beauté et soins'),('Livres et fournitures'),('Enfants et bébés'),('Sports et loisirs'),('Outils et matériel'),('Animaux'),('Autres')) v(n)
where not exists (select 1 from public.categories);
create index if not exists products_category_idx on public.products (category_id);

-- ===== Position des boutiques (arrondie à ~100 m) =====
alter table public.shops add column if not exists lat double precision, add column if not exists lng double precision;
create or replace function public.set_shop_location(p_shop uuid, p_lat double precision, p_lng double precision) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_lat not between -90 and 90 or p_lng not between -180 and 180 then raise exception 'Position invalide'; end if;
  update public.shops set lat = round(p_lat::numeric, 3), lng = round(p_lng::numeric, 3) where id = p_shop and owner_id = auth.uid();
  if not found then raise exception 'Boutique introuvable'; end if;
end $$;
grant execute on function public.set_shop_location(uuid, double precision, double precision) to authenticated;

-- ===== Avis vérifiés =====
create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  shop_id uuid not null references public.shops(id) on delete cascade,
  reviewer_id uuid not null references auth.users(id) on delete cascade,
  rating int not null check (rating between 1 and 5),
  comment text check (comment is null or char_length(comment) <= 1000),
  created_at timestamptz not null default now(),
  unique (order_id, reviewer_id)
);
alter table public.reviews enable row level security;
create policy reviews_public_read on public.reviews for select using (true);

create or replace function public.create_review(p_order uuid, p_rating int, p_comment text) returns void
language plpgsql security definer set search_path = public as $$
declare o public.orders;
begin
  select * into o from public.orders where id = p_order and customer_id = auth.uid();
  if o.id is null then raise exception 'Commande introuvable'; end if;
  if o.status not in ('DELIVERED','COMPLETED') then raise exception 'Avis possible uniquement après la remise'; end if;
  if exists (select 1 from public.reviews where order_id = p_order and reviewer_id = auth.uid()) then raise exception 'Avis déjà publié'; end if;
  insert into public.reviews(order_id, shop_id, reviewer_id, rating, comment) values (p_order, o.shop_id, auth.uid(), p_rating, nullif(trim(p_comment), ''));
end $$;
grant execute on function public.create_review(uuid, int, text) to authenticated;

create or replace function public.shop_rating(p_shop uuid) returns table (avg_rating numeric, n bigint)
language sql stable security definer set search_path = public as $$
  select round(avg(rating)::numeric, 1), count(*) from public.reviews where shop_id = p_shop $$;
grant execute on function public.shop_rating(uuid) to anon, authenticated;

-- ===== Statuts de commande, codes PIN, remise =====
create table public.order_pins (order_id uuid primary key references public.orders(id) on delete cascade, pin text not null, failed int not null default 0);
alter table public.order_pins enable row level security;   -- aucune politique : accessible uniquement via fonctions
create or replace function public._on_order_insert() returns trigger language plpgsql security definer set search_path = public as $$
begin insert into public.order_pins(order_id, pin) values (new.id, public._gen_pin()); return new; end $$;
create trigger orders_pin after insert on public.orders for each row execute function public._on_order_insert();
insert into public.order_pins(order_id, pin) select id, public._gen_pin() from public.orders on conflict do nothing;

create or replace function public._set_order_status(p_order uuid, p_to text, p_actor uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare old text;
begin
  select status into old from public.orders where id = p_order for update;
  update public.orders set status = p_to, reserved_until = null where id = p_order;
  insert into public.order_status_events(order_id, from_status, to_status, actor, reason) values (p_order, old, p_to, p_actor, p_reason);
end $$;
revoke all on function public._set_order_status(uuid, text, uuid, text) from public, anon, authenticated;

alter table public.delivery_jobs add column if not exists pickup_pin text, add column if not exists failed int not null default 0;
drop policy if exists jobs_own_read on public.delivery_jobs;   -- les PIN ne doivent jamais être lisibles : accès via my_jobs()

create or replace function public.create_delivery_job(p_order uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare o public.orders; city text; jid uuid;
begin
  select * into o from public.orders where id = p_order;
  if o.id is null or o.delivery_mode <> 'delivery' or o.status not in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP') then
    raise exception 'Commande non éligible à une mission';
  end if;
  select coalesce(city, 'Zone non précisée') into city from public.shops where id = o.shop_id;
  insert into public.delivery_jobs(order_id, pickup_area, dropoff_address, pay_minor, currency, pickup_pin)
  values (o.id, city, o.delivery_address, o.delivery_minor, o.currency, public._gen_pin()) returning id into jid;
  return jid;
end $$;
revoke all on function public.create_delivery_job(uuid) from public, anon, authenticated;

create or replace function public.my_jobs() returns table (id uuid, pickup_area text, dropoff_address text, pay_minor bigint, currency text, status text)
language sql stable security definer set search_path = public as $$
  select j.id, j.pickup_area, j.dropoff_address, j.pay_minor, j.currency, j.status from public.delivery_jobs j
  where j.courier_id = auth.uid() order by j.assigned_at desc nulls last limit 50 $$;
grant execute on function public.my_jobs() to authenticated;

create or replace function public.confirm_pickup(p_job uuid, p_pin text) returns boolean
language plpgsql security definer set search_path = public as $$
declare j public.delivery_jobs;
begin
  select * into j from public.delivery_jobs where id = p_job and courier_id = auth.uid() for update;
  if j.id is null then raise exception 'Mission introuvable'; end if;
  if j.status <> 'assigned' then raise exception 'Collecte non attendue'; end if;
  if j.failed >= 5 then raise exception 'Trop de tentatives : contactez le support'; end if;
  if j.pickup_pin = trim(p_pin) then
    update public.delivery_jobs set status = 'picked_up', failed = 0 where id = p_job;
    perform public._set_order_status(j.order_id, 'IN_TRANSIT', auth.uid(), 'pickup_confirmed');
    return true;
  end if;
  update public.delivery_jobs set failed = failed + 1 where id = p_job;
  return false;
end $$;
grant execute on function public.confirm_pickup(uuid, text) to authenticated;

create or replace function public.confirm_delivery(p_job uuid, p_pin text) returns boolean
language plpgsql security definer set search_path = public as $$
declare j public.delivery_jobs; pin text;
begin
  select * into j from public.delivery_jobs where id = p_job and courier_id = auth.uid() for update;
  if j.id is null then raise exception 'Mission introuvable'; end if;
  if j.status <> 'picked_up' then raise exception 'Remise non attendue'; end if;
  if j.failed >= 5 then raise exception 'Trop de tentatives : contactez le support'; end if;
  select op.pin into pin from public.order_pins op where op.order_id = j.order_id;
  if pin = trim(p_pin) then
    update public.delivery_jobs set status = 'delivered', failed = 0 where id = p_job;
    perform public._set_order_status(j.order_id, 'DELIVERED', auth.uid(), 'delivery_confirmed');
    return true;
  end if;
  update public.delivery_jobs set failed = failed + 1 where id = p_job;
  return false;
end $$;
grant execute on function public.confirm_delivery(uuid, text) to authenticated;

create or replace function public.get_order_pin(p_order uuid) returns text
language plpgsql security definer set search_path = public as $$
declare cust uuid; own uuid; r text; st text;
begin
  select o.customer_id, s.owner_id, o.status into cust, own, st from public.orders o join public.shops s on s.id = o.shop_id where o.id = p_order;
  if st is null or st in ('PENDING_PAYMENT','CANCELLED','REFUNDED') then return null; end if;
  if auth.uid() = cust then select pin into r from public.order_pins where order_id = p_order;
  elsif auth.uid() = own then select pickup_pin into r from public.delivery_jobs where order_id = p_order;
  end if;
  return r;
end $$;
grant execute on function public.get_order_pin(uuid) to authenticated;

create or replace function public.confirm_handover(p_order uuid, p_pin text) returns boolean
language plpgsql security definer set search_path = public as $$
declare o public.orders; op public.order_pins;
begin
  select o2.* into o from public.orders o2 join public.shops s on s.id = o2.shop_id where o2.id = p_order and s.owner_id = auth.uid();
  if o.id is null then raise exception 'Commande introuvable'; end if;
  if o.delivery_mode <> 'pickup' or o.status <> 'READY_FOR_PICKUP' then raise exception 'Remise non attendue'; end if;
  select * into op from public.order_pins where order_id = p_order for update;
  if op.failed >= 5 then raise exception 'Trop de tentatives : contactez le support'; end if;
  if op.pin = trim(p_pin) then
    perform public._set_order_status(p_order, 'COMPLETED', auth.uid(), 'handover_confirmed');
    return true;
  end if;
  update public.order_pins set failed = failed + 1 where order_id = p_order;
  return false;
end $$;
grant execute on function public.confirm_handover(uuid, text) to authenticated;

create or replace function public.seller_set_order_status(p_order uuid, p_to text) returns void
language plpgsql security definer set search_path = public as $$
declare o public.orders;
begin
  select o2.* into o from public.orders o2 join public.shops s on s.id = o2.shop_id where o2.id = p_order and s.owner_id = auth.uid();
  if o.id is null then raise exception 'Commande introuvable'; end if;
  if not ((o.status = 'PAID' and p_to = 'CONFIRMED') or (o.status = 'CONFIRMED' and p_to = 'PREPARING') or (o.status = 'PREPARING' and p_to = 'READY_FOR_PICKUP')) then
    raise exception 'Changement de statut non autorisé';
  end if;
  perform public._set_order_status(p_order, p_to, auth.uid(), 'seller_update');
  if p_to = 'CONFIRMED' and o.delivery_mode = 'delivery' then perform public.create_delivery_job(p_order); end if;
end $$;
grant execute on function public.seller_set_order_status(uuid, text) to authenticated;

-- ===== Coupons =====
create table public.coupons (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  kind text not null check (kind in ('percent','fixed')),
  value bigint not null check (value > 0),
  min_items_minor bigint not null default 0,
  max_discount_minor bigint,
  max_uses int, used_count int not null default 0,
  currency text not null default 'HTG',
  starts_at timestamptz not null default now(), expires_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create table public.coupon_redemptions (
  id uuid primary key default gen_random_uuid(),
  coupon_id uuid not null references public.coupons(id), user_id uuid not null references auth.users(id),
  order_id uuid references public.orders(id), amount_minor bigint not null,
  created_at timestamptz not null default now(), unique (coupon_id, user_id)
);
alter table public.coupons enable row level security;
alter table public.coupon_redemptions enable row level security;
create policy coupons_admin_read on public.coupons for select using (public.admin_unlocked());

create or replace function public.admin_create_coupon(p_code text, p_kind text, p_value bigint, p_min bigint, p_max_uses int, p_days int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if p_kind not in ('percent','fixed') or p_value <= 0 or (p_kind = 'percent' and p_value > 100) then raise exception 'Valeur invalide'; end if;
  if char_length(trim(p_code)) < 3 then raise exception 'Code trop court'; end if;
  insert into public.coupons(code, kind, value, min_items_minor, max_uses, expires_at)
  values (upper(trim(p_code)), p_kind, p_value, coalesce(p_min, 0), p_max_uses, case when coalesce(p_days, 0) > 0 then now() + make_interval(days => p_days) end);
  insert into public.admin_audit_logs(actor, action, resource) values (auth.uid(), 'create_coupon', 'coupon');
end $$;
grant execute on function public.admin_create_coupon(text, text, bigint, bigint, int, int) to authenticated;

create or replace function public.admin_set_coupon_active(p_id uuid, p_active boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  update public.coupons set active = p_active where id = p_id;
  insert into public.admin_audit_logs(actor, action, resource, resource_id) values (auth.uid(), 'coupon_active:' || p_active, 'coupon', p_id);
end $$;
grant execute on function public.admin_set_coupon_active(uuid, boolean) to authenticated;

-- create_orders avec coupon (remise financée par HAITIKET : la commission est calculée sur le prix catalogue)
alter table public.orders add column if not exists discount_minor bigint not null default 0;
drop function if exists public.create_orders(jsonb, text, text);
create or replace function public.create_orders(p_items jsonb, p_mode text, p_address text, p_coupon text default null) returns setof public.orders
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); bps int; mins int; fee bigint := 0;
  v_shop uuid; v_items bigint; v_ncur int; v_cur text; v_comm bigint; r record; o public.orders;
  cp public.coupons; has_cp boolean := false; v_fixed_left bigint := 0; v_disc bigint; v_total_disc bigint := 0; v_first uuid;
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

  if coalesce(trim(p_coupon), '') <> '' then
    select * into cp from public.coupons
      where code = upper(trim(p_coupon)) and active and starts_at <= now() and (expires_at is null or expires_at > now()) and (max_uses is null or used_count < max_uses) for update;
    if cp.id is null then raise exception 'Coupon invalide ou expiré'; end if;
    if exists (select 1 from public.coupon_redemptions where coupon_id = cp.id and user_id = uid) then raise exception 'Coupon déjà utilisé'; end if;
    has_cp := true;
    if cp.kind = 'fixed' then v_fixed_left := cp.value; end if;
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

    select count(distinct p.currency), min(p.currency), sum(p.price_minor * a.qty) into v_ncur, v_cur, v_items
    from (select x.product_id, sum(x.qty)::int as qty from jsonb_to_recordset(p_items) as x(product_id uuid, qty int) group by x.product_id) a
    join public.products p on p.id = a.product_id where p.shop_id = v_shop;
    if v_ncur <> 1 then raise exception 'Devises différentes dans une même boutique'; end if;

    v_disc := 0;
    if has_cp and cp.currency = v_cur and v_items >= cp.min_items_minor then
      if cp.kind = 'percent' then
        v_disc := least(v_items * least(cp.value, 100) / 100, coalesce(cp.max_discount_minor, v_items));
      else
        v_disc := least(v_items, v_fixed_left);
        v_fixed_left := v_fixed_left - v_disc;
      end if;
    end if;
    v_total_disc := v_total_disc + v_disc;

    v_comm := (v_items * bps + 5000) / 10000;
    insert into public.orders(customer_id, shop_id, delivery_mode, delivery_address, currency, items_minor, delivery_minor, discount_minor, total_minor, commission_bps, commission_minor, seller_net_minor, reserved_until)
    values (uid, v_shop, p_mode, case when p_mode = 'delivery' then trim(p_address) end, v_cur, v_items, fee, v_disc, v_items - v_disc + fee, bps, v_comm, v_items - v_comm, now() + make_interval(mins => mins))
    returning * into o;
    if v_first is null then v_first := o.id; end if;

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

  if has_cp then
    if v_total_disc = 0 then raise exception 'Coupon non applicable à ce panier'; end if;
    insert into public.coupon_redemptions(coupon_id, user_id, order_id, amount_minor) values (cp.id, uid, v_first, v_total_disc);
    update public.coupons set used_count = used_count + 1 where id = cp.id;
  end if;
  return;
end $$;
grant execute on function public.create_orders(jsonb, text, text, text) to authenticated;

-- ===== Parrainage =====
alter table public.profiles add column if not exists referral_code text unique, add column if not exists referred_by uuid references auth.users(id);
create table public.rewards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  source_user uuid references auth.users(id),
  amount_minor bigint not null check (amount_minor > 0), currency text not null default 'HTG',
  status text not null default 'pending' check (status in ('pending','validated','paid','cancelled')),
  created_at timestamptz not null default now()
);
alter table public.rewards enable row level security;
create policy rewards_self on public.rewards for select using (user_id = auth.uid());

create or replace function public.my_referral() returns json
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); c text;
begin
  if uid is null then raise exception 'Connexion requise'; end if;
  insert into public.profiles(id) values (uid) on conflict do nothing;
  select referral_code into c from public.profiles where id = uid;
  if c is null then
    c := upper(substr(md5(random()::text || uid::text), 1, 8));
    update public.profiles set referral_code = c where id = uid;
  end if;
  return json_build_object('code', c,
    'referred', (select count(*) from public.profiles where referred_by = uid),
    'pending', (select coalesce(sum(amount_minor), 0) from public.rewards where user_id = uid and status = 'pending'),
    'validated', (select coalesce(sum(amount_minor), 0) from public.rewards where user_id = uid and status in ('validated','paid')));
end $$;
grant execute on function public.my_referral() to authenticated;

create or replace function public.apply_referral(p_code text) returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); ref uuid;
begin
  if uid is null then raise exception 'Connexion requise'; end if;
  insert into public.profiles(id) values (uid) on conflict do nothing;
  if exists (select 1 from public.profiles where id = uid and referred_by is not null) then raise exception 'Code déjà appliqué'; end if;
  select id into ref from public.profiles where referral_code = upper(trim(p_code));
  if ref is null then raise exception 'Code introuvable'; end if;
  if ref = uid then raise exception 'Auto-parrainage impossible'; end if;
  update public.profiles set referred_by = ref where id = uid and referred_by is null;
end $$;
grant execute on function public.apply_referral(text) to authenticated;

-- Récompense : créée seulement à la première commande réellement remise, et seulement si le montant est configuré
-- (platform_settings.referral_reward_minor). Aucun montant n'est inventé.
create or replace function public._on_order_delivered() returns trigger language plpgsql security definer set search_path = public as $$
declare cust uuid; ref uuid; amt text;
begin
  select customer_id into cust from public.orders where id = new.order_id;
  select referred_by into ref from public.profiles where id = cust;
  select value into amt from public.platform_settings where key = 'referral_reward_minor';
  if ref is not null and amt is not null and not exists (select 1 from public.rewards where source_user = cust) then
    insert into public.rewards(user_id, source_user, amount_minor) values (ref, cust, amt::bigint);
  end if;
  return new;
end $$;
create trigger order_events_referral after insert on public.order_status_events
for each row when (new.to_status in ('DELIVERED','COMPLETED')) execute function public._on_order_delivered();

-- ===== Notifications in-app =====
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null, title text not null, body text, ref uuid,
  created_at timestamptz not null default now(), read_at timestamptz
);
create index on public.notifications (user_id, created_at desc);
alter table public.notifications enable row level security;
create policy notifs_self_read on public.notifications for select using (user_id = auth.uid());
do $$ begin alter publication supabase_realtime add table public.notifications;
exception when others then raise notice 'Activez le temps réel pour notifications (Database > Replication)'; end $$;

create or replace function public.mark_notifications_read() returns void language sql security definer set search_path = public as $$
  update public.notifications set read_at = now() where user_id = auth.uid() and read_at is null $$;
grant execute on function public.mark_notifications_read() to authenticated;

create or replace function public._notify(p_user uuid, p_kind text, p_title text, p_body text, p_ref uuid) returns void
language sql security definer set search_path = public as $$
  insert into public.notifications(user_id, kind, title, body, ref) values (p_user, p_kind, p_title, p_body, p_ref) $$;
revoke all on function public._notify(uuid, text, text, text, uuid) from public, anon, authenticated;

create or replace function public._status_label(s text) returns text language sql immutable as $$
  select case s when 'PENDING_PAYMENT' then 'en attente de paiement' when 'PAID' then 'payée' when 'CONFIRMED' then 'confirmée'
    when 'PREPARING' then 'en préparation' when 'READY_FOR_PICKUP' then 'prête à récupérer' when 'IN_TRANSIT' then 'en livraison'
    when 'DELIVERED' then 'livrée' when 'COMPLETED' then 'terminée' when 'CANCELLED' then 'annulée' when 'REFUNDED' then 'remboursée' else lower(s) end $$;

create or replace function public._trg_order_event() returns trigger language plpgsql security definer set search_path = public as $$
declare cust uuid; own uuid;
begin
  select o.customer_id, s.owner_id into cust, own from public.orders o join public.shops s on s.id = o.shop_id where o.id = new.order_id;
  if cust is distinct from new.actor then perform public._notify(cust, 'order', 'Commande ' || public._status_label(new.to_status), null, new.order_id); end if;
  if own is distinct from new.actor and new.to_status <> 'PENDING_PAYMENT' then perform public._notify(own, 'order', 'Commande ' || public._status_label(new.to_status), null, new.order_id); end if;
  if new.from_status is null and own is distinct from new.actor then perform public._notify(own, 'order', 'Nouvelle commande', 'En attente de paiement', new.order_id); end if;
  return new;
end $$;
create trigger notify_order_event after insert on public.order_status_events for each row execute function public._trg_order_event();

create or replace function public._trg_message() returns trigger language plpgsql security definer set search_path = public as $$
declare m record; subj text;
begin
  select subject into subj from public.conversations where id = new.conversation_id;
  for m in select user_id from public.conversation_members where conversation_id = new.conversation_id and user_id <> new.sender_id loop
    perform public._notify(m.user_id, 'message', 'Nouveau message : ' || subj, left(new.body, 80), new.conversation_id);
  end loop;
  return new;
end $$;
create trigger notify_message after insert on public.messages for each row execute function public._trg_message();

create or replace function public._trg_ticket() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.admin_reply is distinct from old.admin_reply and new.admin_reply is not null then
    perform public._notify(new.user_id, 'support', 'Réponse du support', left(new.admin_reply, 80), new.id);
  end if;
  return new;
end $$;
create trigger notify_ticket after update on public.support_tickets for each row execute function public._trg_ticket();

create or replace function public._trg_shop_status() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status then
    perform public._notify(new.owner_id, 'shop', 'Boutique ' || new.name, case new.status when 'active' then 'Votre boutique est active.' when 'suspended' then 'Votre boutique est suspendue.' else 'Statut : ' || new.status end, new.id);
  end if;
  return new;
end $$;
create trigger notify_shop after update on public.shops for each row execute function public._trg_shop_status();

create or replace function public._trg_courier_status() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status then
    perform public._notify(new.user_id, 'courier', 'Candidature livreur', case new.status when 'approved' then 'Candidature approuvée : activez votre disponibilité.' when 'rejected' then 'Candidature rejetée.' else 'Statut : ' || new.status end, new.id);
  end if;
  return new;
end $$;
create trigger notify_courier after update on public.courier_applications for each row execute function public._trg_courier_status();

create or replace function public._trg_listing_status() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status and new.status in ('published','blocked') then
    perform public._notify(new.seller_id, 'listing', 'Annonce ' || new.title, case new.status when 'published' then 'Votre annonce est publiée.' else 'Votre annonce a été bloquée.' end, new.id);
  end if;
  return new;
end $$;
create trigger notify_listing after update on public.listings for each row execute function public._trg_listing_status();

create or replace function public._trg_new_job() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications(user_id, kind, title, body, ref)
  select cs.user_id, 'job', 'Nouvelle mission', 'Rémunération : ' || (new.pay_minor / 100.0)::numeric(12,2) || ' ' || new.currency, new.id
  from public.courier_status cs
  where cs.available and exists (select 1 from public.courier_applications a where a.user_id = cs.user_id and a.status = 'approved');
  return new;
end $$;
create trigger notify_new_job after insert on public.delivery_jobs for each row execute function public._trg_new_job();
-- HAITIKET lot 8 : paiements Bazik (MonCash), frais Bazar/boutique, Bazar = vente complète, personnalisation boutique,
-- abonnements aux boutiques, statistiques produit. Exécuter après 0001..0007.

-- ===== Réglages =====
insert into public.platform_settings(key, value) values ('bazar_fee_usd','2'), ('shop_fee_usd','20'), ('enforce_shop_plan','false')
on conflict (key) do nothing;
-- À RENSEIGNER par l'admin (sinon les frais Bazar/boutique restent "indisponibles") :
--   insert into public.platform_settings(key, value) values ('usd_htg_rate', '<taux du jour>');
drop policy if exists settings_public_read on public.platform_settings;
create policy settings_public_read on public.platform_settings for select using (key in ('commission_bps','reservation_minutes','bazar_fee_usd','shop_fee_usd'));

-- ===== Bazar = produits d'un vendeur particulier =====
alter table public.shops add column if not exists kind text not null default 'pro' check (kind in ('pro','personal'));
alter table public.shops add column if not exists logo_url text, add column if not exists banner_url text, add column if not exists slogan text,
  add column if not exists color_primary text, add column if not exists color_accent text;
alter table public.products add column if not exists source text not null default 'marketplace' check (source in ('marketplace','bazar'));
alter table public.products add column if not exists paid_until timestamptz;
alter table public.products drop constraint if exists products_status_check;
alter table public.products add constraint products_status_check check (status in ('draft','published','paused','removed','blocked'));
create index if not exists products_source_idx on public.products (source, status, created_at desc);

create or replace function public.shop_plan_ok(p_shop uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select value from public.platform_settings where key = 'enforce_shop_plan'), 'false') <> 'true'
      or exists (select 1 from public.shops where id = p_shop and (kind = 'personal' or plan_paid_until > now())) $$;
grant execute on function public.shop_plan_ok(uuid) to anon, authenticated;

drop policy if exists products_read on public.products;
create policy products_read on public.products for select using (
  (status = 'published'
    and exists (select 1 from public.shops s where s.id = shop_id and s.status = 'active' and public.shop_plan_ok(s.id))
    and (source = 'marketplace' or paid_until > now()))
  or exists (select 1 from public.shops s where s.id = shop_id and s.owner_id = auth.uid()));

-- Garde-fou : un vendeur ne peut ni se publier gratuitement au Bazar, ni modifier sa date de paiement, ni débloquer un produit bloqué.
create or replace function public._guard_product() returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('haitiket.system', true), '') = '1' then return new; end if;
  if tg_op = 'INSERT' then
    if new.source = 'bazar' then new.status := 'draft'; new.paid_until := null; end if;
  else
    new.source := old.source;
    if old.source = 'bazar' then
      new.paid_until := old.paid_until;
      if new.status = 'published' and old.status <> 'published' and (old.paid_until is null or old.paid_until < now()) then
        raise exception 'Paiement de l''annonce requis';
      end if;
    end if;
    if old.status in ('blocked','removed') and new.status <> old.status then raise exception 'Produit bloqué : contactez le support'; end if;
  end if;
  return new;
end $$;
drop trigger if exists products_guard on public.products;
create trigger products_guard before insert or update on public.products for each row execute function public._guard_product();

create or replace function public.ensure_personal_shop(p_city text) returns uuid
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); sid uuid; nm text;
begin
  if uid is null then raise exception 'Connexion requise'; end if;
  select id into sid from public.shops where owner_id = uid and kind = 'personal' limit 1;
  if sid is not null then return sid; end if;
  select coalesce(nullif(trim(display_name), ''), 'Vendeur') into nm from public.profiles where id = uid;
  insert into public.shops(owner_id, name, city, status, kind) values (uid, 'Bazar · ' || coalesce(nm, 'Vendeur'), nullif(trim(p_city), ''), 'active', 'personal') returning id into sid;
  return sid;
end $$;
grant execute on function public.ensure_personal_shop(text) to authenticated;

-- Frais : bloque (statut 'removed') les annonces non renouvelées depuis plus de 30 jours.
create or replace function public.purge_expired_bazar() returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  perform set_config('haitiket.system', '1', true);
  update public.products set status = 'removed' where source = 'bazar' and status in ('published','draft','paused') and paid_until is not null and paid_until < now() - interval '30 days';
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.purge_expired_bazar() from public, anon, authenticated;
do $$ begin
  create extension if not exists pg_cron;
  perform cron.schedule('purge-expired-bazar', '15 3 * * *', 'select public.purge_expired_bazar()');
exception when others then raise notice 'pg_cron non disponible'; end $$;

-- ===== Personnalisation des boutiques professionnelles =====
create or replace function public.update_shop_branding(p_shop uuid, p_logo text, p_banner text, p_slogan text, p_primary text, p_accent text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_primary is not null and p_primary !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'Couleur principale invalide'; end if;
  if p_accent is not null and p_accent !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'Couleur secondaire invalide'; end if;
  if char_length(coalesce(p_slogan, '')) > 80 then raise exception 'Slogan trop long (80 caractères)'; end if;
  if coalesce(p_logo, 'https://x') !~ '^https://' or coalesce(p_banner, 'https://x') !~ '^https://' then raise exception 'Lien d''image invalide'; end if;
  update public.shops set logo_url = p_logo, banner_url = p_banner, slogan = nullif(trim(p_slogan), ''), color_primary = p_primary, color_accent = p_accent
  where id = p_shop and owner_id = auth.uid() and kind = 'pro';
  if not found then raise exception 'Boutique professionnelle introuvable'; end if;
end $$;
grant execute on function public.update_shop_branding(uuid, text, text, text, text, text) to authenticated;

-- ===== Abonnement aux boutiques =====
create table public.shop_follows (
  user_id uuid not null references auth.users(id) on delete cascade,
  shop_id uuid not null references public.shops(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, shop_id)
);
alter table public.shop_follows enable row level security;
create policy follows_self on public.shop_follows for select using (user_id = auth.uid());
create or replace function public.toggle_follow(p_shop uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'Connexion requise'; end if;
  if exists (select 1 from public.shop_follows where user_id = uid and shop_id = p_shop) then
    delete from public.shop_follows where user_id = uid and shop_id = p_shop; return false;
  end if;
  if not exists (select 1 from public.shops where id = p_shop and status = 'active') then raise exception 'Boutique introuvable'; end if;
  insert into public.shop_follows(user_id, shop_id) values (uid, p_shop); return true;
end $$;
grant execute on function public.toggle_follow(uuid) to authenticated;

create or replace function public._trg_new_product() returns trigger language plpgsql security definer set search_path = public as $$
declare sname text; sowner uuid;
begin
  if new.status = 'published' and (tg_op = 'INSERT' or old.status <> 'published') then
    select name, owner_id into sname, sowner from public.shops where id = new.shop_id;
    insert into public.notifications(user_id, kind, title, body, ref)
    select f.user_id, 'shop', 'Nouveau chez ' || sname, new.name, new.id from public.shop_follows f where f.shop_id = new.shop_id and f.user_id <> sowner;
  end if;
  return new;
end $$;
drop trigger if exists notify_new_product on public.products;
create trigger notify_new_product after insert or update of status on public.products for each row execute function public._trg_new_product();

-- ===== Statistiques publiques =====
create table public.product_events (
  product_id uuid not null references public.products(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('cart')),
  created_at timestamptz not null default now(),
  primary key (product_id, user_id, kind)
);
alter table public.product_events enable row level security;
create or replace function public.track_product_event(p_product uuid, p_kind text) returns void
language sql security definer set search_path = public as $$
  insert into public.product_events(product_id, user_id, kind) select p_product, auth.uid(), p_kind where auth.uid() is not null and p_kind = 'cart' on conflict do nothing $$;
grant execute on function public.track_product_event(uuid, text) to authenticated;

create or replace function public.product_stats(p_product uuid) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'purchases', coalesce((select sum(oi.qty) from public.order_items oi join public.orders o on o.id = oi.order_id
       where oi.product_id = p_product and o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED','COMPLETED')), 0),
    'favorites', (select count(*) from public.favorites where product_id = p_product),
    'cart_adds', (select count(*) from public.product_events where product_id = p_product and kind = 'cart')) $$;
grant execute on function public.product_stats(uuid) to anon, authenticated;

create or replace function public.shop_stats(p_shop uuid) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'followers', (select count(*) from public.shop_follows where shop_id = p_shop),
    'products', (select count(*) from public.products where shop_id = p_shop and status = 'published'),
    'sold', coalesce((select sum(oi.qty) from public.order_items oi join public.orders o on o.id = oi.order_id
       where o.shop_id = p_shop and o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED','COMPLETED')), 0)) $$;
grant execute on function public.shop_stats(uuid) to anon, authenticated;

-- ===== Paiements Bazik =====
create table public.payment_attempts (
  id uuid primary key default gen_random_uuid(),
  purpose text not null default 'order' check (purpose in ('order','bazar_listing','shop_plan')),
  target_id uuid not null,
  order_id uuid references public.orders(id),
  user_id uuid not null references auth.users(id),
  provider text not null default 'bazik',
  amount_minor bigint not null check (amount_minor > 0),
  currency text not null default 'HTG',
  status text not null default 'created' check (status in ('created','pending','successful','failed','cancelled','refund_required')),
  provider_order_id text unique,
  redirect_url text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index on public.payment_attempts (user_id, created_at desc);
create index on public.payment_attempts (target_id, status);
create table public.payment_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null default 'bazik', provider_order_id text, payload jsonb,
  signature text, signature_ok boolean, note text,
  created_at timestamptz not null default now()
);
create table public.ledger_entries (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.payment_attempts(id),
  order_id uuid references public.orders(id),
  kind text not null check (kind in ('payment_received','seller_payable','platform_net','courier_payable','bazar_fee','shop_plan_fee')),
  amount_minor bigint not null, currency text not null default 'HTG',
  created_at timestamptz not null default now(),
  unique (attempt_id, kind)
);
alter table public.payment_attempts enable row level security;
alter table public.payment_events enable row level security;
alter table public.ledger_entries enable row level security;
create policy pa_self_read on public.payment_attempts for select using (user_id = auth.uid());
create policy pa_admin_read on public.payment_attempts for select using (public.admin_unlocked());
create policy pe_admin_read on public.payment_events for select using (public.admin_unlocked());
create policy le_admin_read on public.ledger_entries for select using (public.admin_unlocked());

create or replace function public._fee_minor(p_key text) returns bigint
language plpgsql stable security definer set search_path = public as $$
declare usd numeric; rate numeric;
begin
  select value::numeric into usd from public.platform_settings where key = p_key;
  select value::numeric into rate from public.platform_settings where key = 'usd_htg_rate';
  if usd is null then raise exception 'Tarif non configuré'; end if;
  if rate is null or rate <= 0 then raise exception 'Taux USD/HTG non configuré'; end if;
  return ceil(usd * rate)::bigint * 100;
end $$;
revoke all on function public._fee_minor(text) from public, anon, authenticated;

create or replace function public.quote_fee(p_kind text) returns bigint
language plpgsql stable security definer set search_path = public as $$
begin
  return public._fee_minor(case p_kind when 'bazar_listing' then 'bazar_fee_usd' else 'shop_fee_usd' end);
exception when others then return null;
end $$;
grant execute on function public.quote_fee(text) to anon, authenticated;

create or replace function public.start_payment(p_purpose text, p_target uuid, p_user uuid) returns public.payment_attempts
language plpgsql security definer set search_path = public as $$
declare a public.payment_attempts; amt bigint; o public.orders; pr public.products; sh public.shops;
begin
  if p_purpose = 'order' then
    select * into o from public.orders where id = p_target and customer_id = p_user for update;
    if o.id is null then raise exception 'Commande introuvable'; end if;
    if o.status not in ('PENDING_PAYMENT','PAYMENT_PROCESSING') then raise exception 'Commande non payable (statut %)', o.status; end if;
    if o.reserved_until is not null and o.reserved_until < now() then raise exception 'Réservation expirée : veuillez recommander'; end if;
    if o.currency <> 'HTG' then raise exception 'Seul le HTG est pris en charge'; end if;
    amt := o.total_minor;
    update public.orders set reserved_until = greatest(coalesce(reserved_until, now()), now() + interval '25 minutes') where id = o.id;
  elsif p_purpose = 'bazar_listing' then
    select p.* into pr from public.products p join public.shops s on s.id = p.shop_id where p.id = p_target and p.source = 'bazar' and s.owner_id = p_user;
    if pr.id is null then raise exception 'Annonce introuvable'; end if;
    if pr.status in ('blocked','removed') then raise exception 'Annonce bloquée'; end if;
    amt := public._fee_minor('bazar_fee_usd');
  elsif p_purpose = 'shop_plan' then
    select * into sh from public.shops where id = p_target and owner_id = p_user and kind = 'pro';
    if sh.id is null then raise exception 'Boutique introuvable'; end if;
    amt := public._fee_minor('shop_fee_usd');
  else
    raise exception 'Type de paiement invalide';
  end if;
  if amt <= 0 then raise exception 'Montant invalide'; end if;
  if amt > 7500000 then raise exception 'Montant supérieur à 75 000 HTG : paiement impossible'; end if;
  update public.payment_attempts set status = 'cancelled', updated_at = now() where purpose = p_purpose and target_id = p_target and user_id = p_user and status = 'created';
  insert into public.payment_attempts(purpose, target_id, order_id, user_id, amount_minor)
  values (p_purpose, p_target, case when p_purpose = 'order' then p_target end, p_user, amt) returning * into a;
  return a;
end $$;
revoke all on function public.start_payment(text, uuid, uuid) from public, anon, authenticated;

create or replace function public.attach_provider_order(p_attempt uuid, p_provider_order text, p_url text) returns void
language sql security definer set search_path = public as $$
  update public.payment_attempts set provider_order_id = p_provider_order, redirect_url = p_url, status = 'pending', updated_at = now() where id = p_attempt $$;
revoke all on function public.attach_provider_order(uuid, text, text) from public, anon, authenticated;

create or replace function public.mark_payment_failed(p_attempt uuid, p_status text) returns void
language sql security definer set search_path = public as $$
  update public.payment_attempts set status = case when p_status = 'cancelled' then 'cancelled' else 'failed' end, updated_at = now()
  where id = p_attempt and status in ('created','pending') $$;
revoke all on function public.mark_payment_failed(uuid, text) from public, anon, authenticated;

create or replace function public.apply_payment_success(p_attempt uuid) returns text
language plpgsql security definer set search_path = public as $$
declare a public.payment_attempts; o public.orders; it record; ok boolean := true;
begin
  select * into a from public.payment_attempts where id = p_attempt for update;
  if a.id is null then raise exception 'Tentative introuvable'; end if;
  if a.status = 'successful' then return 'already'; end if;
  perform set_config('haitiket.system', '1', true);

  if a.purpose = 'order' then
    select * into o from public.orders where id = a.order_id for update;
    if o.status in ('PENDING_PAYMENT','PAYMENT_PROCESSING') then
      null;
    elsif o.status = 'CANCELLED' then
      -- paiement tardif : on ne crée une vente que si le stock peut être réservé à nouveau
      for it in select product_id, qty from public.order_items where order_id = o.id loop
        if not exists (select 1 from public.products p where p.id = it.product_id and p.status = 'published' and p.stock >= it.qty) then ok := false; end if;
      end loop;
      if not ok then
        update public.payment_attempts set status = 'refund_required', updated_at = now() where id = a.id;
        return 'refund_required';
      end if;
      for it in select product_id, qty from public.order_items where order_id = o.id loop
        update public.products set stock = stock - it.qty where id = it.product_id;
        insert into public.inventory_movements(product_id, order_id, delta, reason) values (it.product_id, o.id, -it.qty, 'reservation_after_late_payment');
      end loop;
    else
      update public.payment_attempts set status = 'refund_required', updated_at = now() where id = a.id;
      return 'refund_required';
    end if;
    update public.payment_attempts set status = 'successful', updated_at = now() where id = a.id;
    perform public._set_order_status(o.id, 'PAID', null, 'payment_confirmed');
    insert into public.ledger_entries(attempt_id, order_id, kind, amount_minor, currency) values
      (a.id, o.id, 'payment_received', o.total_minor, o.currency),
      (a.id, o.id, 'seller_payable', o.seller_net_minor, o.currency),
      (a.id, o.id, 'platform_net', o.commission_minor - o.discount_minor, o.currency),
      (a.id, o.id, 'courier_payable', o.delivery_minor, o.currency)
    on conflict do nothing;
    return 'paid';

  elsif a.purpose = 'bazar_listing' then
    update public.products set status = 'published', paid_until = greatest(coalesce(paid_until, now()), now()) + interval '14 days'
      where id = a.target_id and status in ('draft','paused','published');
    update public.payment_attempts set status = 'successful', updated_at = now() where id = a.id;
    insert into public.ledger_entries(attempt_id, kind, amount_minor, currency) values (a.id, 'bazar_fee', a.amount_minor, a.currency) on conflict do nothing;
    return 'paid';

  else
    update public.shops set plan_paid_until = greatest(coalesce(plan_paid_until, now()), now()) + interval '30 days' where id = a.target_id;
    update public.payment_attempts set status = 'successful', updated_at = now() where id = a.id;
    insert into public.ledger_entries(attempt_id, kind, amount_minor, currency) values (a.id, 'shop_plan_fee', a.amount_minor, a.currency) on conflict do nothing;
    return 'paid';
  end if;
end $$;
revoke all on function public.apply_payment_success(uuid) from public, anon, authenticated;

-- ===== Portefeuille (soldes calculés ; aucun versement automatique à ce stade) =====
create or replace function public.my_wallet() returns json
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); sp bigint; sa bigint; cp bigint; ca bigint;
begin
  if uid is null then raise exception 'Connexion requise'; end if;
  select coalesce(sum(o.seller_net_minor) filter (where o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT')), 0),
         coalesce(sum(o.seller_net_minor) filter (where o.status in ('DELIVERED','COMPLETED')), 0)
    into sp, sa from public.orders o join public.shops s on s.id = o.shop_id where s.owner_id = uid;
  select coalesce(sum(pay_minor) filter (where status in ('assigned','picked_up')), 0), coalesce(sum(pay_minor) filter (where status = 'delivered'), 0)
    into cp, ca from public.delivery_jobs where courier_id = uid;
  return json_build_object('seller_pending', sp, 'seller_available', sa, 'courier_pending', cp, 'courier_available', ca);
end $$;
grant execute on function public.my_wallet() to authenticated;

-- ===== create_orders : règles Bazar (annonce payée) et abonnement boutique =====
create or replace function public.create_orders(p_items jsonb, p_mode text, p_address text, p_coupon text default null) returns setof public.orders
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); bps int; mins int; fee bigint := 0;
  v_shop uuid; v_items bigint; v_ncur int; v_cur text; v_comm bigint; r record; o public.orders;
  cp public.coupons; has_cp boolean := false; v_fixed_left bigint := 0; v_disc bigint; v_total_disc bigint := 0; v_first uuid;
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

  if coalesce(trim(p_coupon), '') <> '' then
    select * into cp from public.coupons
      where code = upper(trim(p_coupon)) and active and starts_at <= now() and (expires_at is null or expires_at > now()) and (max_uses is null or used_count < max_uses) for update;
    if cp.id is null then raise exception 'Coupon invalide ou expiré'; end if;
    if exists (select 1 from public.coupon_redemptions where coupon_id = cp.id and user_id = uid) then raise exception 'Coupon déjà utilisé'; end if;
    has_cp := true;
    if cp.kind = 'fixed' then v_fixed_left := cp.value; end if;
  end if;

  perform 1 from public.products where id in (select x.product_id from jsonb_to_recordset(p_items) as x(product_id uuid, qty int)) order by id for update;

  for v_shop in
    select distinct p.shop_id from public.products p where p.id in (select x.product_id from jsonb_to_recordset(p_items) as x(product_id uuid, qty int))
  loop
    if not exists (select 1 from public.shops s where s.id = v_shop and s.status = 'active') or not public.shop_plan_ok(v_shop) then raise exception 'Boutique indisponible'; end if;
    if exists (select 1 from public.shops s where s.id = v_shop and s.owner_id = uid) then raise exception 'Vous ne pouvez pas acheter dans votre propre boutique'; end if;

    for r in
      select p.id, p.name, p.price_minor, p.currency, p.status, p.stock, p.source, p.paid_until, a.qty
      from (select x.product_id, sum(x.qty)::int as qty from jsonb_to_recordset(p_items) as x(product_id uuid, qty int) group by x.product_id) a
      join public.products p on p.id = a.product_id where p.shop_id = v_shop
    loop
      if r.status <> 'published' or r.stock < r.qty or (r.source = 'bazar' and (r.paid_until is null or r.paid_until < now())) then
        raise exception 'Produit indisponible : %', r.name;
      end if;
    end loop;

    select count(distinct p.currency), min(p.currency), sum(p.price_minor * a.qty) into v_ncur, v_cur, v_items
    from (select x.product_id, sum(x.qty)::int as qty from jsonb_to_recordset(p_items) as x(product_id uuid, qty int) group by x.product_id) a
    join public.products p on p.id = a.product_id where p.shop_id = v_shop;
    if v_ncur <> 1 then raise exception 'Devises différentes dans une même boutique'; end if;

    v_disc := 0;
    if has_cp and cp.currency = v_cur and v_items >= cp.min_items_minor then
      if cp.kind = 'percent' then
        v_disc := least(v_items * least(cp.value, 100) / 100, coalesce(cp.max_discount_minor, v_items));
      else
        v_disc := least(v_items, v_fixed_left);
        v_fixed_left := v_fixed_left - v_disc;
      end if;
    end if;
    v_total_disc := v_total_disc + v_disc;

    v_comm := (v_items * bps + 5000) / 10000;
    insert into public.orders(customer_id, shop_id, delivery_mode, delivery_address, currency, items_minor, delivery_minor, discount_minor, total_minor, commission_bps, commission_minor, seller_net_minor, reserved_until)
    values (uid, v_shop, p_mode, case when p_mode = 'delivery' then trim(p_address) end, v_cur, v_items, fee, v_disc, v_items - v_disc + fee, bps, v_comm, v_items - v_comm, now() + make_interval(mins => mins))
    returning * into o;
    if v_first is null then v_first := o.id; end if;

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

  if has_cp then
    if v_total_disc = 0 then raise exception 'Coupon non applicable à ce panier'; end if;
    insert into public.coupon_redemptions(coupon_id, user_id, order_id, amount_minor) values (cp.id, uid, v_first, v_total_disc);
    update public.coupons set used_count = used_count + 1 where id = cp.id;
  end if;
  return;
end $$;
grant execute on function public.create_orders(jsonb, text, text, text) to authenticated;

-- ===== Modération admin : annonces Bazar = produits =====
create or replace function public.admin_set_status(p_kind text, p_id uuid, p_status text, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if p_status in ('suspended','rejected','blocked','closed') and coalesce(trim(p_reason), '') = '' then raise exception 'Motif requis'; end if;
  perform set_config('haitiket.system', '1', true);
  if p_kind = 'shop' and p_status in ('pending','active','suspended','closed') then
    update public.shops set status = p_status where id = p_id;
  elsif p_kind = 'courier' and p_status in ('verifying','approved','rejected','suspended') then
    update public.courier_applications set status = p_status where id = p_id;
  elsif p_kind = 'listing' and p_status in ('blocked','paused') then
    update public.products set status = p_status where id = p_id and source = 'bazar';
  else
    raise exception 'Action invalide';
  end if;
  get diagnostics n = row_count;
  if n = 0 then raise exception 'Élément introuvable'; end if;
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason) values (auth.uid(), 'set_status:' || p_status, p_kind, p_id, p_reason);
end $$;
-- HAITIKET lot 9 : galerie photos/vidéos, caractéristiques par catégorie, unité de vente.
-- Purement additif : ne modifie aucune fonction existante. Exécuter après 0001..0008.

alter table public.products add column if not exists attributes jsonb not null default '{}'::jsonb;
alter table public.products add column if not exists unit_label text not null default 'unité';

insert into public.categories (name)
select v.n from (values ('Pièces détachées'),('Femmes enceintes'),('Services autorisés'),('Électroménager et ménager')) v(n)
where not exists (select 1 from public.categories c where c.name = v.n);

create table public.product_media (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  url text not null check (url ~ '^https://'),
  kind text not null default 'image' check (kind in ('image','video')),
  position int not null default 0,
  created_at timestamptz not null default now()
);
create index on public.product_media (product_id, position);
alter table public.product_media enable row level security;
create policy media_read on public.product_media for select using (exists (select 1 from public.products p where p.id = product_id));
create policy media_owner_write on public.product_media for all
  using (exists (select 1 from public.products p join public.shops s on s.id = p.shop_id where p.id = product_id and s.owner_id = auth.uid()))
  with check (exists (select 1 from public.products p join public.shops s on s.id = p.shop_id where p.id = product_id and s.owner_id = auth.uid()));

create or replace function public._limit_media() returns trigger language plpgsql as $$
begin
  if (select count(*) from public.product_media where product_id = new.product_id) >= 10 then raise exception 'Maximum 10 photos/vidéos par produit'; end if;
  return new;
end $$;
drop trigger if exists product_media_limit on public.product_media;
create trigger product_media_limit before insert on public.product_media for each row execute function public._limit_media();

-- Le stockage accepte désormais de courtes vidéos (20 Mo max).
update storage.buckets set file_size_limit = 20971520,
  allowed_mime_types = array['image/jpeg','image/png','image/webp','video/mp4','video/webm','video/quicktime']
where id = 'media';
