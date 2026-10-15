-- HAITIKET lot 11 : variantes avec stock, tarifs par quantité (calculés côté serveur), coupons de boutique.
-- À exécuter après 0001..0010 (chaîne "full_features / payments_bazar / operations_admin").

-- ===== Colonnes complémentaires =====
alter table public.orders add column if not exists discount_funder text not null default 'platform' check (discount_funder in ('platform','shop'));
alter table public.orders add column if not exists platform_net_minor bigint;
alter table public.coupons add column if not exists shop_id uuid references public.shops(id) on delete cascade;
alter table public.coupons add column if not exists product_ids uuid[];
alter table public.coupons add column if not exists visible boolean not null default false;

-- ===== Variantes (taille / couleur) avec stock propre =====
create table public.product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  size text, color_name text, color_hex text check (color_hex is null or color_hex ~ '^#[0-9A-Fa-f]{6}$'),
  stock int not null default 0 check (stock >= 0),
  created_at timestamptz not null default now(),
  check (size is not null or color_name is not null)
);
create unique index product_variants_unique on public.product_variants (product_id, coalesce(size, ''), coalesce(color_name, ''));
alter table public.product_variants enable row level security;
create policy variants_read on public.product_variants for select using (exists (select 1 from public.products p where p.id = product_id));
create policy variants_owner_write on public.product_variants for all
  using (exists (select 1 from public.products p join public.shops s on s.id = p.shop_id where p.id = product_id and s.owner_id = auth.uid()))
  with check (exists (select 1 from public.products p join public.shops s on s.id = p.shop_id where p.id = product_id and s.owner_id = auth.uid()));

create or replace function public._sync_product_stock() returns trigger language plpgsql security definer set search_path = public as $$
declare pid uuid;
begin
  if tg_op = 'DELETE' then pid := old.product_id; else pid := new.product_id; end if;
  if exists (select 1 from public.product_variants where product_id = pid) then
    update public.products set stock = (select coalesce(sum(stock), 0) from public.product_variants where product_id = pid) where id = pid;
  end if;
  return null;
end $$;
drop trigger if exists variants_sync on public.product_variants;
create trigger variants_sync after insert or update of stock or delete on public.product_variants for each row execute function public._sync_product_stock();

alter table public.order_items add column if not exists variant_id uuid references public.product_variants(id);
alter table public.order_items add column if not exists variant_label text;

-- ===== Tarifs par quantité =====
create table public.product_tiers (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  min_qty int not null check (min_qty >= 2),
  unit_price_minor bigint not null check (unit_price_minor > 0),
  label text,
  unique (product_id, min_qty)
);
alter table public.product_tiers enable row level security;
create policy tiers_read on public.product_tiers for select using (exists (select 1 from public.products p where p.id = product_id));
create policy tiers_owner_write on public.product_tiers for all
  using (exists (select 1 from public.products p join public.shops s on s.id = p.shop_id where p.id = product_id and s.owner_id = auth.uid()))
  with check (exists (select 1 from public.products p join public.shops s on s.id = p.shop_id where p.id = product_id and s.owner_id = auth.uid()));

create or replace function public.unit_price(p_product uuid, p_qty int) returns bigint
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select t.unit_price_minor from public.product_tiers t where t.product_id = p_product and t.min_qty <= p_qty order by t.min_qty desc limit 1),
    (select price_minor from public.products where id = p_product)) $$;
grant execute on function public.unit_price(uuid, int) to anon, authenticated;

-- ===== Gestion du stock (produit ou variante) =====
create or replace function public._restore_stock(p_order uuid, p_reason text, p_actor uuid) returns void
language plpgsql security definer set search_path = public as $$
declare it record;
begin
  for it in select product_id, variant_id, qty from public.order_items where order_id = p_order loop
    if it.variant_id is not null then
      update public.product_variants set stock = stock + it.qty where id = it.variant_id;
    else
      update public.products set stock = stock + it.qty where id = it.product_id;
    end if;
    insert into public.inventory_movements(product_id, order_id, delta, reason, actor) values (it.product_id, p_order, it.qty, p_reason, p_actor);
  end loop;
end $$;
revoke all on function public._restore_stock(uuid, text, uuid) from public, anon, authenticated;

create or replace function public._take_stock(p_order uuid, p_reason text) returns boolean
language plpgsql security definer set search_path = public as $$
declare it record; ok boolean := true;
begin
  for it in select product_id, variant_id, qty from public.order_items where order_id = p_order loop
    if it.variant_id is not null then
      if not exists (select 1 from public.product_variants v join public.products p on p.id = v.product_id where v.id = it.variant_id and v.stock >= it.qty and p.status = 'published') then ok := false; end if;
    elsif not exists (select 1 from public.products p where p.id = it.product_id and p.status = 'published' and p.stock >= it.qty) then
      ok := false;
    end if;
  end loop;
  if not ok then return false; end if;
  for it in select product_id, variant_id, qty from public.order_items where order_id = p_order loop
    if it.variant_id is not null then
      update public.product_variants set stock = stock - it.qty where id = it.variant_id;
    else
      update public.products set stock = stock - it.qty where id = it.product_id;
    end if;
    insert into public.inventory_movements(product_id, order_id, delta, reason) values (it.product_id, p_order, -it.qty, p_reason);
  end loop;
  return true;
end $$;
revoke all on function public._take_stock(uuid, text) from public, anon, authenticated;

create or replace function public._cancel_order(p_order uuid, p_actor uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare o public.orders;
begin
  select * into o from public.orders where id = p_order for update;
  if o.id is null or o.status <> 'PENDING_PAYMENT' then return; end if;
  perform public._restore_stock(p_order, p_reason, p_actor);
  update public.orders set status = 'CANCELLED', reserved_until = null where id = p_order;
  insert into public.order_status_events(order_id, from_status, to_status, actor, reason) values (p_order, 'PENDING_PAYMENT', 'CANCELLED', p_actor, p_reason);
end $$;
revoke all on function public._cancel_order(uuid, uuid, text) from public, anon, authenticated;

create or replace function public.request_cancellation(p_order uuid) returns void
language plpgsql security definer set search_path = public as $$
declare o public.orders; own uuid; uid uuid := auth.uid();
begin
  if uid is null then raise exception 'Connexion requise'; end if;
  select * into o from public.orders where id = p_order and customer_id = uid for update;
  if o.id is null then raise exception 'Commande introuvable'; end if;
  if o.status <> 'PAID' then raise exception 'Annulation directe impossible : utilisez « Signaler un problème »'; end if;
  perform public._restore_stock(o.id, 'cancelled_after_payment', uid);
  update public.delivery_jobs set status = 'cancelled' where order_id = o.id and status = 'open';
  perform public._set_order_status(o.id, 'CANCELLED', uid, 'customer_cancellation');
  insert into public.refund_requests(order_id, user_id, amount_minor, reason) values (o.id, uid, o.total_minor, 'Annulation avant confirmation du vendeur') on conflict (order_id) do nothing;
  select owner_id into own from public.shops where id = o.shop_id;
  perform public._notify(own, 'order', 'Commande annulée par le client', null, o.id);
  perform public._notify_admins('Remboursement à exécuter', 'Annulation client', o.id);
end $$;
grant execute on function public.request_cancellation(uuid) to authenticated;

create or replace function public.apply_payment_success(p_attempt uuid) returns text
language plpgsql security definer set search_path = public as $$
declare a public.payment_attempts; o public.orders;
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
      if not public._take_stock(o.id, 'reservation_after_late_payment') then
        update public.payment_attempts set status = 'refund_required', updated_at = now() where id = a.id;
        return 'refund_required';
      end if;
    else
      update public.payment_attempts set status = 'refund_required', updated_at = now() where id = a.id;
      return 'refund_required';
    end if;
    update public.payment_attempts set status = 'successful', updated_at = now() where id = a.id;
    perform public._set_order_status(o.id, 'PAID', null, 'payment_confirmed');
    insert into public.ledger_entries(attempt_id, order_id, kind, amount_minor, currency) values
      (a.id, o.id, 'payment_received', o.total_minor, o.currency),
      (a.id, o.id, 'seller_payable', o.seller_net_minor, o.currency),
      (a.id, o.id, 'platform_net', coalesce(o.platform_net_minor, o.commission_minor - o.discount_minor), o.currency),
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

create or replace function public.admin_mark_refund(p_id uuid, p_executed boolean, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.refund_requests; o public.orders; att uuid;
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  select * into r from public.refund_requests where id = p_id and status = 'to_execute' for update;
  if r.id is null then raise exception 'Remboursement introuvable ou déjà traité'; end if;
  if not p_executed then
    update public.refund_requests set status = 'failed', note = left(coalesce(p_note, ''), 300) where id = p_id;
  else
    select * into o from public.orders where id = r.order_id for update;
    update public.refund_requests set status = 'executed', executed_at = now(), note = left(coalesce(p_note, ''), 300) where id = p_id;
    perform public._set_order_status(o.id, 'REFUNDED', auth.uid(), 'refund_executed');
    select id into att from public.payment_attempts where order_id = o.id and status in ('successful','refund_required') order by created_at desc limit 1;
    if att is not null then
      insert into public.ledger_entries(attempt_id, order_id, kind, amount_minor, currency) values
        (att, o.id, 'refund_executed', -o.total_minor, o.currency),
        (att, o.id, 'seller_payable_reversal', -o.seller_net_minor, o.currency),
        (att, o.id, 'platform_net_reversal', -coalesce(o.platform_net_minor, o.commission_minor - o.discount_minor), o.currency),
        (att, o.id, 'courier_payable_reversal', -o.delivery_minor, o.currency)
      on conflict do nothing;
      update public.payment_attempts set status = 'cancelled', updated_at = now() where id = att and status = 'refund_required';
    end if;
    perform public._notify(r.user_id, 'order', 'Remboursement effectué', null, o.id);
  end if;
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason) values (auth.uid(), case when p_executed then 'refund_executed' else 'refund_failed' end, 'refund', p_id, left(coalesce(p_note, ''), 200));
end $$;
grant execute on function public.admin_mark_refund(uuid, boolean, text) to authenticated;

-- ===== Coupons de boutique =====
drop policy if exists coupons_owner_read on public.coupons;
create policy coupons_owner_read on public.coupons for select using (shop_id is not null and exists (select 1 from public.shops s where s.id = coupons.shop_id and s.owner_id = auth.uid()));

create or replace function public.shop_create_coupon(p_shop uuid, p_code text, p_kind text, p_value bigint, p_min bigint, p_max_uses int, p_days int, p_products uuid[], p_visible boolean) returns void
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not exists (select 1 from public.shops where id = p_shop and owner_id = auth.uid() and status = 'active') then raise exception 'Boutique introuvable ou inactive'; end if;
  if p_kind not in ('percent','fixed') or p_value <= 0 or (p_kind = 'percent' and p_value > 100) then raise exception 'Valeur invalide'; end if;
  if char_length(trim(p_code)) < 3 then raise exception 'Code trop court (3 caractères minimum)'; end if;
  if p_products is not null and array_length(p_products, 1) > 0 then
    select count(*) into n from public.products where shop_id = p_shop and id = any(p_products);
    if n <> array_length(p_products, 1) then raise exception 'Produit hors de votre boutique'; end if;
  else
    p_products := null;
  end if;
  insert into public.coupons(code, kind, value, min_items_minor, max_uses, expires_at, shop_id, product_ids, visible)
  values (upper(trim(p_code)), p_kind, p_value, coalesce(p_min, 0), p_max_uses, case when coalesce(p_days, 0) > 0 then now() + make_interval(days => p_days) end, p_shop, p_products, coalesce(p_visible, false));
exception when unique_violation then raise exception 'Ce code existe déjà';
end $$;
grant execute on function public.shop_create_coupon(uuid, text, text, bigint, bigint, int, int, uuid[], boolean) to authenticated;

create or replace function public.shop_set_coupon_active(p_id uuid, p_active boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.coupons set active = p_active where id = p_id and shop_id in (select id from public.shops where owner_id = auth.uid());
  if not found then raise exception 'Coupon introuvable'; end if;
end $$;
grant execute on function public.shop_set_coupon_active(uuid, boolean) to authenticated;

create or replace function public.product_promos(p_product uuid) returns table (code text, kind text, value bigint, expires_at timestamptz, min_items_minor bigint)
language sql stable security definer set search_path = public as $$
  select c.code, c.kind, c.value, c.expires_at, c.min_items_minor
  from public.coupons c join public.products p on p.id = p_product
  where c.shop_id = p.shop_id and c.active and c.visible and c.starts_at <= now()
    and (c.expires_at is null or c.expires_at > now()) and (c.max_uses is null or c.used_count < c.max_uses)
    and (c.product_ids is null or p_product = any(c.product_ids)) $$;
grant execute on function public.product_promos(uuid) to anon, authenticated;

-- ===== create_orders : variantes, paliers de prix, coupons de boutique =====
create or replace function public.create_orders(p_items jsonb, p_mode text, p_address text, p_coupon text default null) returns setof public.orders
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); bps int; mins int; fee bigint := 0;
  v_shop uuid; v_items bigint; v_elig bigint; v_cur text; v_comm bigint; r record; o public.orders;
  cp public.coupons; has_cp boolean := false; v_fixed_left bigint := 0; v_disc bigint; v_total_disc bigint := 0; v_first uuid;
  v_shop_funded boolean; v_unit bigint; v_hasvar boolean; v_vstock int; v_vlabel text;
begin
  if uid is null then raise exception 'Connexion requise'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'Panier vide'; end if;
  if p_mode not in ('pickup','delivery') then raise exception 'Mode de remise invalide'; end if;
  if p_mode = 'delivery' and coalesce(trim(p_address), '') = '' then raise exception 'Adresse de livraison requise'; end if;
  if exists (select 1 from jsonb_to_recordset(p_items) as x(product_id uuid, variant_id uuid, qty int) where x.product_id is null or x.qty is null or x.qty <= 0 or x.qty > 99) then
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

  perform 1 from public.products where id in (select x.product_id from jsonb_to_recordset(p_items) as x(product_id uuid, variant_id uuid, qty int)) order by id for update;
  perform 1 from public.product_variants where product_id in (select x.product_id from jsonb_to_recordset(p_items) as x(product_id uuid, variant_id uuid, qty int)) order by id for update;

  for v_shop in
    select distinct p.shop_id from public.products p where p.id in (select x.product_id from jsonb_to_recordset(p_items) as x(product_id uuid, variant_id uuid, qty int))
  loop
    if not exists (select 1 from public.shops s where s.id = v_shop and s.status = 'active') or not public.shop_plan_ok(v_shop) then raise exception 'Boutique indisponible'; end if;
    if exists (select 1 from public.shops s where s.id = v_shop and s.owner_id = uid) then raise exception 'Vous ne pouvez pas acheter dans votre propre boutique'; end if;

    v_items := 0; v_elig := 0; v_cur := null;
    for r in
      with agg as (
        select x.product_id, x.variant_id, sum(x.qty)::int as qty from jsonb_to_recordset(p_items) as x(product_id uuid, variant_id uuid, qty int) group by x.product_id, x.variant_id),
      tot as (select product_id, sum(qty)::int as tq from agg group by product_id)
      select p.id, p.name, p.currency, p.status, p.stock, p.source, p.paid_until, a.variant_id, a.qty, t.tq
      from agg a join tot t on t.product_id = a.product_id join public.products p on p.id = a.product_id where p.shop_id = v_shop
    loop
      if r.status <> 'published' or (r.source = 'bazar' and (r.paid_until is null or r.paid_until < now())) then raise exception 'Produit indisponible : %', r.name; end if;
      select exists (select 1 from public.product_variants where product_id = r.id) into v_hasvar;
      if v_hasvar then
        if r.variant_id is null then raise exception 'Choisissez une variante pour : %', r.name; end if;
        v_vstock := null;
        select stock into v_vstock from public.product_variants where id = r.variant_id and product_id = r.id;
        if v_vstock is null then raise exception 'Variante introuvable pour : %', r.name; end if;
        if v_vstock < r.qty then raise exception 'Produit indisponible : %', r.name; end if;
      else
        if r.variant_id is not null then raise exception 'Variante invalide pour : %', r.name; end if;
        if r.stock < r.qty then raise exception 'Produit indisponible : %', r.name; end if;
      end if;
      if v_cur is null then v_cur := r.currency; elsif v_cur <> r.currency then raise exception 'Devises différentes dans une même boutique'; end if;
      v_unit := public.unit_price(r.id, r.tq);
      v_items := v_items + v_unit * r.qty;
      if has_cp and (cp.shop_id is null or cp.shop_id = v_shop) and (cp.product_ids is null or r.id = any(cp.product_ids)) then v_elig := v_elig + v_unit * r.qty; end if;
    end loop;

    v_disc := 0;
    v_shop_funded := has_cp and cp.shop_id is not null;
    if has_cp and cp.currency = v_cur and v_elig > 0 and v_items >= cp.min_items_minor then
      if cp.kind = 'percent' then
        v_disc := least(v_elig * least(cp.value, 100) / 100, coalesce(cp.max_discount_minor, v_elig));
      else
        v_disc := least(v_elig, v_fixed_left);
        v_fixed_left := v_fixed_left - v_disc;
      end if;
    end if;
    v_total_disc := v_total_disc + v_disc;

    if v_shop_funded then v_comm := ((v_items - v_disc) * bps + 5000) / 10000; else v_comm := (v_items * bps + 5000) / 10000; end if;
    insert into public.orders(customer_id, shop_id, delivery_mode, delivery_address, currency, items_minor, delivery_minor, discount_minor, discount_funder,
                              total_minor, commission_bps, commission_minor, seller_net_minor, platform_net_minor, reserved_until)
    values (uid, v_shop, p_mode, case when p_mode = 'delivery' then trim(p_address) end, v_cur, v_items, fee, v_disc, case when v_shop_funded then 'shop' else 'platform' end,
            v_items - v_disc + fee, bps, v_comm,
            (v_items - case when v_shop_funded then v_disc else 0 end) - v_comm,
            v_comm - case when v_shop_funded then 0 else v_disc end,
            now() + make_interval(mins => mins))
    returning * into o;
    if v_first is null then v_first := o.id; end if;

    for r in
      with agg as (
        select x.product_id, x.variant_id, sum(x.qty)::int as qty from jsonb_to_recordset(p_items) as x(product_id uuid, variant_id uuid, qty int) group by x.product_id, x.variant_id),
      tot as (select product_id, sum(qty)::int as tq from agg group by product_id)
      select p.id, p.name, a.variant_id, a.qty, t.tq
      from agg a join tot t on t.product_id = a.product_id join public.products p on p.id = a.product_id where p.shop_id = v_shop
    loop
      v_unit := public.unit_price(r.id, r.tq);
      v_vlabel := null;
      if r.variant_id is not null then
        select concat_ws(' · ', size, color_name) into v_vlabel from public.product_variants where id = r.variant_id;
        update public.product_variants set stock = stock - r.qty where id = r.variant_id;
      else
        update public.products set stock = stock - r.qty where id = r.id;
      end if;
      insert into public.order_items(order_id, product_id, name, unit_minor, qty, variant_id, variant_label) values (o.id, r.id, r.name, v_unit, r.qty, r.variant_id, v_vlabel);
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
