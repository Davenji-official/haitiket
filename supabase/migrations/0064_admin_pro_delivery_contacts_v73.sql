-- HAITIKET V73 — livraison au tarif fixé par le livreur, contacts téléphone/WhatsApp,
-- présence en ligne, centre de contrôle admin complet, diffusion de messages.
-- À appliquer APRÈS 0063_late_delivery_refund_v72.sql. Idempotent (peut être rejoué).

-- =====================================================================
-- 1. LIVRAISON : plus d'erreur « aucun tarif configuré »
-- =====================================================================
-- Cahier des charges §13 : le livreur propose son prix/délai, le client choisit une offre valide.
-- Un tarif forfaitaire n'est donc plus obligatoire. Valeur 0 = « le livreur fixe son prix ».
insert into public.platform_settings(key, value) values ('delivery_flat_minor','0')
on conflict (key) do nothing;
insert into public.platform_settings(key, value) values ('delivery_offer_expiry_minutes','10')
on conflict (key) do nothing;

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
    -- V73 : le prix de livraison est fixé par le livreur (offres). Sans tarif forfaitaire, la commande démarre à 0
    -- et le client choisit ensuite une offre ; l'écart est réglé par select_delivery_price_offer.
    fee := coalesce(fee, 0);
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


-- =====================================================================
-- 2. CONTACTS : téléphone + WhatsApp entre client, vendeur et livreur
-- =====================================================================
alter table public.profiles add column if not exists whatsapp text;
alter table public.profiles add column if not exists last_seen_at timestamptz;
create index if not exists profiles_last_seen_idx on public.profiles(last_seen_at desc);

create or replace function public.update_my_contact(p_phone text, p_whatsapp text) returns void
language plpgsql security definer set search_path = public as $$
declare v_phone text := nullif(regexp_replace(coalesce(p_phone,''), '[^0-9+]', '', 'g'), '');
        v_wa text := nullif(regexp_replace(coalesce(p_whatsapp,''), '[^0-9+]', '', 'g'), '');
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if v_phone is not null and (length(v_phone) < 8 or length(v_phone) > 16) then raise exception 'Numéro de téléphone invalide'; end if;
  if v_wa is not null and (length(v_wa) < 8 or length(v_wa) > 16) then raise exception 'Numéro WhatsApp invalide'; end if;
  update public.profiles set phone = v_phone, whatsapp = v_wa where id = auth.uid();
  if not found then
    insert into public.profiles(id, phone, whatsapp) values (auth.uid(), v_phone, v_wa);
  end if;
end $$;
revoke all on function public.update_my_contact(text,text) from public, anon;
grant execute on function public.update_my_contact(text,text) to authenticated;

-- Contacts des autres participants d'une commande. Visibles uniquement par un participant
-- (client, propriétaire de la boutique, livreur affecté) et seulement une fois la commande payée.
create or replace function public.order_contacts(p_order uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); o public.orders; s public.shops; j public.delivery_jobs;
  res jsonb := '[]'::jsonb; is_cust boolean; is_seller boolean; is_courier boolean;
begin
  if uid is null then raise exception 'Connexion requise'; end if;
  select * into o from public.orders where id = p_order;
  if o.id is null then raise exception 'Commande introuvable'; end if;
  select * into s from public.shops where id = o.shop_id;
  select * into j from public.delivery_jobs where order_id = o.id and courier_id is not null;
  is_cust := o.customer_id = uid;
  is_seller := s.owner_id = uid;
  is_courier := j.courier_id is not null and j.courier_id = uid;
  if not (is_cust or is_seller or is_courier) then raise exception 'Accès refusé'; end if;
  if o.status in ('PENDING_PAYMENT','PAYMENT_PROCESSING','CANCELLED') then
    return res;
  end if;

  if not is_cust then
    res := res || coalesce((select jsonb_build_array(jsonb_build_object(
      'role','client',
      'name', coalesce(p.display_name,'Client'),
      'phone', p.phone,
      'whatsapp', coalesce(nullif(p.whatsapp,''), p.phone))) from public.profiles p where p.id = o.customer_id), '[]'::jsonb);
  end if;
  if not is_seller then
    res := res || coalesce((select jsonb_build_array(jsonb_build_object(
      'role','vendeur',
      'name', coalesce(s.name, p.display_name, 'Vendeur'),
      'phone', p.phone,
      'whatsapp', coalesce(nullif(p.whatsapp,''), p.phone))) from public.profiles p where p.id = s.owner_id), '[]'::jsonb);
  end if;
  if j.courier_id is not null and not is_courier then
    res := res || coalesce((select jsonb_build_array(jsonb_build_object(
      'role','livreur',
      'name', coalesce(p.display_name, ca.full_name, 'Livreur HAITIKET'),
      'phone', coalesce(nullif(p.phone,''), ca.phone),
      'whatsapp', coalesce(nullif(p.whatsapp,''), nullif(p.phone,''), ca.phone)))
      from (select 1) x
      left join public.profiles p on p.id = j.courier_id
      left join lateral (select c.full_name, c.phone from public.courier_applications c where c.user_id = j.courier_id order by c.created_at desc limit 1) ca on true), '[]'::jsonb);
  end if;
  return res;
end $$;
revoke all on function public.order_contacts(uuid) from public, anon;
grant execute on function public.order_contacts(uuid) to authenticated;

create or replace function public.job_contacts(p_job uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_order uuid;
begin
  select order_id into v_order from public.delivery_jobs where id = p_job and courier_id = auth.uid();
  if v_order is null then raise exception 'Mission introuvable'; end if;
  return public.order_contacts(v_order);
end $$;
revoke all on function public.job_contacts(uuid) from public, anon;
grant execute on function public.job_contacts(uuid) to authenticated;

-- =====================================================================
-- 3. PRÉSENCE (utilisateurs actifs / en ligne)
-- =====================================================================
create or replace function public.touch_presence() returns void
language sql security definer set search_path = public as $$
  update public.profiles set last_seen_at = now()
  where id = auth.uid() and (last_seen_at is null or last_seen_at < now() - interval '45 seconds') $$;
revoke all on function public.touch_presence() from public, anon;
grant execute on function public.touch_presence() to authenticated;

-- =====================================================================
-- 4. ADMIN PRO — statistiques, séries, recherche client, fiche 360°
-- =====================================================================
create or replace function public.admin_online_stats() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  select jsonb_build_object(
    'online_now',   count(*) filter (where last_seen_at > now() - interval '3 minutes'),
    'active_15m',   count(*) filter (where last_seen_at > now() - interval '15 minutes'),
    'active_24h',   count(*) filter (where last_seen_at > now() - interval '24 hours'),
    'active_7d',    count(*) filter (where last_seen_at > now() - interval '7 days'),
    'active_30d',   count(*) filter (where last_seen_at > now() - interval '30 days'),
    'inactive_30d', count(*) filter (where last_seen_at is null or last_seen_at <= now() - interval '30 days'),
    'total_users',  count(*),
    'new_today',    count(*) filter (where created_at >= date_trunc('day', now())),
    'new_7d',       count(*) filter (where created_at > now() - interval '7 days'),
    'banned',       count(*) filter (where coalesce(account_status,'active') <> 'active' or suspended)
  ) into r from public.profiles;
  r := r || jsonb_build_object(
    'couriers_available', (select count(*) from public.courier_status where available = true and location_updated_at > now() - interval '3 minutes'),
    'couriers_approved',  (select count(*) from public.courier_applications where status = 'approved'),
    'shops_active',       (select count(*) from public.shops where status = 'active'),
    'open_jobs',          (select count(*) from public.delivery_jobs where status = 'open'),
    'jobs_in_progress',   (select count(*) from public.delivery_jobs where status in ('assigned','picked_up')),
    'orders_in_progress', (select count(*) from public.orders where status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT')));
  return r;
end $$;
revoke all on function public.admin_online_stats() from public, anon;
grant execute on function public.admin_online_stats() to authenticated;

create or replace function public.admin_timeseries(p_days integer default 30)
returns table(day date, signups bigint, orders bigint, paid_orders bigint,
              gmv_htg bigint, gmv_usd bigint, commission_htg bigint, commission_usd bigint, active_users bigint)
language plpgsql stable security definer set search_path = public as $$
declare d integer := greatest(1, least(coalesce(p_days,30), 366));
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  return query
  with days as (select generate_series((current_date - (d-1))::timestamp, current_date::timestamp, interval '1 day')::date as day)
  select dd.day,
    (select count(*) from public.profiles p where p.created_at::date = dd.day),
    (select count(*) from public.orders o where o.created_at::date = dd.day),
    (select count(*) from public.orders o where o.created_at::date = dd.day and o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED','COMPLETED')),
    (select coalesce(sum(o.total_minor),0)::bigint from public.orders o where o.created_at::date = dd.day and o.currency='HTG' and o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED','COMPLETED')),
    (select coalesce(sum(o.total_minor),0)::bigint from public.orders o where o.created_at::date = dd.day and o.currency='USD' and o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED','COMPLETED')),
    (select coalesce(sum(o.commission_minor),0)::bigint from public.orders o where o.created_at::date = dd.day and o.currency='HTG' and o.status in ('DELIVERED','COMPLETED')),
    (select coalesce(sum(o.commission_minor),0)::bigint from public.orders o where o.created_at::date = dd.day and o.currency='USD' and o.status in ('DELIVERED','COMPLETED')),
    (select count(*) from public.profiles p where p.last_seen_at::date = dd.day)
  from days dd order by dd.day;
end $$;
revoke all on function public.admin_timeseries(integer) from public, anon;
grant execute on function public.admin_timeseries(integer) to authenticated;

create or replace function public.admin_order_status_breakdown() returns table(status text, n bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  return query select o.status::text, count(*) from public.orders o group by o.status order by count(*) desc;
end $$;
revoke all on function public.admin_order_status_breakdown() from public, anon;
grant execute on function public.admin_order_status_breakdown() to authenticated;

create or replace function public.admin_search_users_v73(p_q text default '', p_filter text default 'all', p_limit integer default 40, p_offset integer default 0)
returns table(id uuid, email text, display_name text, phone text, whatsapp text, city text, avatar_url text,
              account_status text, suspended boolean, created_at timestamptz, last_seen_at timestamptz, online boolean,
              is_courier boolean, shops_count bigint, orders_count bigint, is_admin boolean)
language plpgsql stable security definer set search_path = public as $$
declare q text := trim(coalesce(p_q,''));
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  return query
  select p.id, u.email::text, p.display_name, p.phone, p.whatsapp, p.city, p.avatar_url,
         coalesce(p.account_status,'active'), coalesce(p.suspended,false), p.created_at, p.last_seen_at,
         coalesce(p.last_seen_at > now() - interval '3 minutes', false),
         exists(select 1 from public.courier_applications c where c.user_id = p.id and c.status = 'approved'),
         (select count(*) from public.shops s where s.owner_id = p.id),
         (select count(*) from public.orders o where o.customer_id = p.id),
         exists(select 1 from public.user_roles r where r.user_id = p.id and r.role = 'admin')
  from public.profiles p join auth.users u on u.id = p.id
  where (q = '' or u.email ilike '%'||q||'%' or p.display_name ilike '%'||q||'%' or p.phone ilike '%'||q||'%'
         or p.whatsapp ilike '%'||q||'%' or p.id::text ilike q||'%' or p.city ilike '%'||q||'%')
    and (case coalesce(p_filter,'all')
      when 'online'  then p.last_seen_at > now() - interval '3 minutes'
      when 'active24' then p.last_seen_at > now() - interval '24 hours'
      when 'inactive' then (p.last_seen_at is null or p.last_seen_at <= now() - interval '30 days')
      when 'banned'  then (coalesce(p.account_status,'active') <> 'active' or coalesce(p.suspended,false))
      when 'couriers' then exists(select 1 from public.courier_applications c where c.user_id = p.id and c.status = 'approved')
      when 'sellers' then exists(select 1 from public.shops s where s.owner_id = p.id)
      when 'new' then p.created_at > now() - interval '7 days'
      else true end)
  order by (p.last_seen_at is null), p.last_seen_at desc, p.created_at desc
  limit greatest(1, least(coalesce(p_limit,40), 200)) offset greatest(0, coalesce(p_offset,0));
end $$;
revoke all on function public.admin_search_users_v73(text,text,integer,integer) from public, anon;
grant execute on function public.admin_search_users_v73(text,text,integer,integer) to authenticated;

create or replace function public.admin_user_360(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  select jsonb_build_object(
    'profile', to_jsonb(p) - 'referral_code',
    'email', u.email,
    'last_sign_in_at', u.last_sign_in_at,
    'email_confirmed', u.email_confirmed_at is not null,
    'roles', coalesce((select jsonb_agg(role) from public.user_roles where user_id = p.id), '[]'::jsonb),
    'shops', coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'status',s.status,'city',s.city,'created_at',s.created_at) order by s.created_at desc) from public.shops s where s.owner_id = p.id), '[]'::jsonb),
    'orders', coalesce((select jsonb_agg(x) from (select o.id,o.status,o.total_minor,o.currency,o.delivery_mode,o.created_at,o.shop_id from public.orders o where o.customer_id = p.id order by o.created_at desc limit 25) x), '[]'::jsonb),
    'sales', coalesce((select jsonb_agg(x) from (select o.id,o.status,o.total_minor,o.currency,o.created_at from public.orders o join public.shops s on s.id = o.shop_id where s.owner_id = p.id order by o.created_at desc limit 25) x), '[]'::jsonb),
    'wallets', coalesce((select jsonb_agg(jsonb_build_object('currency',w.currency,'balance_minor',public._wallet_balance_minor(w.id))) from public.wallet_accounts w where w.user_id = p.id), '[]'::jsonb),
    'transactions', coalesce((select jsonb_agg(x) from (select t.id,t.kind,t.status,t.amount_minor,t.currency,t.reference,t.created_at from public.wallet_transactions t where t.user_id = p.id order by t.created_at desc limit 25) x), '[]'::jsonb),
    'courier', (select to_jsonb(c) from public.courier_applications c where c.user_id = p.id order by c.created_at desc limit 1),
    'listings_count', (select count(*) from public.products pr join public.shops s on s.id = pr.shop_id where s.owner_id = p.id and pr.status <> 'removed'),
    'orders_count', (select count(*) from public.orders o where o.customer_id = p.id),
    'spent_htg', (select coalesce(sum(o.total_minor),0) from public.orders o where o.customer_id = p.id and o.currency='HTG' and o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED','COMPLETED')),
    'spent_usd', (select coalesce(sum(o.total_minor),0) from public.orders o where o.customer_id = p.id and o.currency='USD' and o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED','COMPLETED'))
  ) into r
  from public.profiles p join auth.users u on u.id = p.id where p.id = p_user;
  if r is null then raise exception 'Compte introuvable'; end if;
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason) values (auth.uid(), 'view_user_360', 'user', p_user, 'consultation fiche client');
  return r;
end $$;
revoke all on function public.admin_user_360(uuid) from public, anon;
grant execute on function public.admin_user_360(uuid) to authenticated;

create or replace function public.admin_update_user_profile(p_user uuid, p_display_name text, p_phone text, p_whatsapp text, p_city text, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if char_length(btrim(coalesce(p_reason,''))) < 3 then raise exception 'Motif requis'; end if;
  update public.profiles set
    display_name = nullif(left(trim(coalesce(p_display_name,'')),80),''),
    phone = nullif(regexp_replace(coalesce(p_phone,''),'[^0-9+]','','g'),''),
    whatsapp = nullif(regexp_replace(coalesce(p_whatsapp,''),'[^0-9+]','','g'),''),
    city = nullif(left(trim(coalesce(p_city,'')),80),'')
  where id = p_user;
  if not found then raise exception 'Compte introuvable'; end if;
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason) values (auth.uid(), 'edit_user_profile', 'user', p_user, left(p_reason,200));
end $$;
revoke all on function public.admin_update_user_profile(uuid,text,text,text,text,text) from public, anon;
grant execute on function public.admin_update_user_profile(uuid,text,text,text,text,text) to authenticated;

create or replace function public.admin_set_role(p_user uuid, p_role text, p_grant boolean, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if p_role not in ('admin','support') then raise exception 'Rôle invalide'; end if;
  if p_user = auth.uid() then raise exception 'Impossible de modifier vos propres rôles'; end if;
  if char_length(btrim(coalesce(p_reason,''))) < 3 then raise exception 'Motif requis'; end if;
  if p_grant then insert into public.user_roles(user_id, role) values (p_user, p_role) on conflict do nothing;
  else delete from public.user_roles where user_id = p_user and role = p_role; end if;
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason)
  values (auth.uid(), case when p_grant then 'grant_role_' else 'revoke_role_' end || p_role, 'user', p_user, left(p_reason,200));
end $$;
revoke all on function public.admin_set_role(uuid,text,boolean,text) from public, anon;
grant execute on function public.admin_set_role(uuid,text,boolean,text) to authenticated;

-- Journal d'une prise de contrôle (appelée par la fonction Edge admin-impersonate sous le JWT de l'admin).
create or replace function public.admin_log_impersonation(p_user uuid, p_reason text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if p_user = auth.uid() then raise exception 'Compte déjà connecté'; end if;
  if exists(select 1 from public.user_roles where user_id = p_user and role = 'admin') then raise exception 'Prise de contrôle interdite sur un administrateur'; end if;
  if char_length(btrim(coalesce(p_reason,''))) < 5 then raise exception 'Motif détaillé requis (5 caractères minimum)'; end if;
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason) values (auth.uid(), 'impersonate_user', 'user', p_user, left(p_reason,200));
  return true;
end $$;
revoke all on function public.admin_log_impersonation(uuid,text) from public, anon;
grant execute on function public.admin_log_impersonation(uuid,text) to authenticated;

-- =====================================================================
-- 5. ADMIN PRO — catalogue, réglages libres, commandes (sans passer par le code/la base)
-- =====================================================================
create or replace function public.admin_upsert_category(p_id uuid, p_name text, p_parent uuid, p_active boolean)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if char_length(btrim(coalesce(p_name,''))) < 2 then raise exception 'Nom de catégorie requis'; end if;
  if p_id is null then
    insert into public.categories(name, parent_id, active) values (trim(p_name), p_parent, coalesce(p_active,true)) returning id into v_id;
  else
    if p_parent = p_id then raise exception 'Une catégorie ne peut pas être son propre parent'; end if;
    update public.categories set name = trim(p_name), parent_id = p_parent, active = coalesce(p_active,true) where id = p_id returning id into v_id;
    if v_id is null then raise exception 'Catégorie introuvable'; end if;
  end if;
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason) values (auth.uid(), 'upsert_category', 'category', v_id, left(trim(p_name),200));
  return v_id;
end $$;
revoke all on function public.admin_upsert_category(uuid,text,uuid,boolean) from public, anon;
grant execute on function public.admin_upsert_category(uuid,text,uuid,boolean) to authenticated;

-- Suppression : supprime si inutilisée, sinon désactive (les produits existants gardent leur catégorie).
create or replace function public.admin_delete_category(p_id uuid) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if exists(select 1 from public.products where category_id = p_id) or exists(select 1 from public.categories where parent_id = p_id) then
    update public.categories set active = false where id = p_id;
    insert into public.admin_audit_logs(actor, action, resource, resource_id, reason) values (auth.uid(), 'deactivate_category', 'category', p_id, 'catégorie utilisée');
    return 'deactivated';
  end if;
  delete from public.categories where id = p_id;
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason) values (auth.uid(), 'delete_category', 'category', p_id, 'catégorie supprimée');
  return 'deleted';
end $$;
revoke all on function public.admin_delete_category(uuid) from public, anon;
grant execute on function public.admin_delete_category(uuid) to authenticated;

create or replace function public.admin_set_setting_any(p_key text, p_value text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if p_key !~ '^[a-z0-9_]{2,60}$' then raise exception 'Clé de réglage invalide (minuscules, chiffres, _)'; end if;
  if p_value is null or char_length(p_value) > 500 then raise exception 'Valeur invalide'; end if;
  insert into public.platform_settings(key, value, updated_at) values (p_key, p_value, now())
  on conflict (key) do update set value = excluded.value, updated_at = now();
  insert into public.admin_audit_logs(actor, action, resource, reason) values (auth.uid(), 'set_setting', 'platform_settings', left(p_key||'='||p_value,200));
end $$;
revoke all on function public.admin_set_setting_any(text,text) from public, anon;
grant execute on function public.admin_set_setting_any(text,text) to authenticated;

create or replace function public.admin_list_settings() returns table(key text, value text, updated_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  return query select s.key, s.value, s.updated_at from public.platform_settings s order by s.key;
end $$;
revoke all on function public.admin_list_settings() from public, anon;
grant execute on function public.admin_list_settings() to authenticated;

-- Modération produit : un produit supprimé ne peut jamais être republié par cette fonction (cahier §5).
create or replace function public.admin_set_product_status(p_product uuid, p_status text, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare cur text;
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if p_status not in ('draft','published','paused','removed') then raise exception 'Statut invalide'; end if;
  if char_length(btrim(coalesce(p_reason,''))) < 3 then raise exception 'Motif requis'; end if;
  select status into cur from public.products where id = p_product for update;
  if cur is null then raise exception 'Produit introuvable'; end if;
  if cur = 'removed' and p_status <> 'removed' then raise exception 'Un produit supprimé ne peut pas être republié'; end if;
  update public.products set status = p_status where id = p_product;
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason) values (auth.uid(), 'set_product_'||p_status, 'product', p_product, left(p_reason,200));
end $$;
revoke all on function public.admin_set_product_status(uuid,text,text) from public, anon;
grant execute on function public.admin_set_product_status(uuid,text,text) to authenticated;

create or replace function public.admin_search_products(p_q text default '', p_status text default 'all', p_limit integer default 40)
returns table(id uuid, name text, price_minor bigint, currency text, stock integer, status text, shop_name text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare q text := trim(coalesce(p_q,''));
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  return query
  select p.id, p.name, p.price_minor, p.currency, p.stock, p.status, s.name, p.created_at
  from public.products p join public.shops s on s.id = p.shop_id
  where (q = '' or p.name ilike '%'||q||'%' or s.name ilike '%'||q||'%' or p.id::text ilike q||'%')
    and (coalesce(p_status,'all') = 'all' or p.status = p_status)
  order by p.created_at desc limit greatest(1, least(coalesce(p_limit,40), 200));
end $$;
revoke all on function public.admin_search_products(text,text,integer) from public, anon;
grant execute on function public.admin_search_products(text,text,integer) to authenticated;

create or replace function public.admin_search_orders(p_q text default '', p_status text default 'all', p_limit integer default 40)
returns table(id uuid, status text, total_minor bigint, currency text, delivery_mode text, delivery_minor bigint,
              customer_name text, shop_name text, courier_name text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare q text := trim(coalesce(p_q,''));
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  return query
  select o.id, o.status::text, o.total_minor, o.currency, o.delivery_mode, o.delivery_minor,
         cp.display_name, s.name, cc.display_name, o.created_at
  from public.orders o
  join public.shops s on s.id = o.shop_id
  left join public.profiles cp on cp.id = o.customer_id
  left join public.delivery_jobs j on j.order_id = o.id
  left join public.profiles cc on cc.id = j.courier_id
  where (q = '' or o.id::text ilike q||'%' or cp.display_name ilike '%'||q||'%' or s.name ilike '%'||q||'%' or cc.display_name ilike '%'||q||'%')
    and (coalesce(p_status,'all') = 'all' or o.status = p_status)
  order by o.created_at desc limit greatest(1, least(coalesce(p_limit,40), 200));
end $$;
revoke all on function public.admin_search_orders(text,text,integer) from public, anon;
grant execute on function public.admin_search_orders(text,text,integer) to authenticated;

-- =====================================================================
-- 6. DIFFUSION : messages à tous les clients (image, lien, coupon, notification)
-- =====================================================================
alter table public.notifications add column if not exists image_url text;
alter table public.notifications add column if not exists link_url text;
alter table public.notifications add column if not exists coupon_code text;

create table if not exists public.admin_broadcasts (
  id uuid primary key default gen_random_uuid(),
  title text not null, body text not null,
  image_url text, link_url text, coupon_code text,
  audience text not null default 'all',
  recipients integer not null default 0,
  with_banner boolean not null default false,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
alter table public.admin_broadcasts enable row level security;
revoke all on public.admin_broadcasts from anon, authenticated;

create or replace function public.admin_send_broadcast(
  p_title text, p_body text, p_image text default null, p_link text default null,
  p_coupon text default null, p_audience text default 'all', p_banner boolean default false)
returns integer language plpgsql security definer set search_path = public as $$
declare n integer; v_coupon text := nullif(upper(trim(coalesce(p_coupon,''))),''); v_img text := nullif(trim(coalesce(p_image,'')),''); v_link text := nullif(trim(coalesce(p_link,'')),'');
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if char_length(btrim(coalesce(p_title,''))) < 2 or char_length(p_title) > 100 then raise exception 'Titre requis (2 à 100 caractères)'; end if;
  if char_length(btrim(coalesce(p_body,''))) < 2 or char_length(p_body) > 1200 then raise exception 'Message requis (2 à 1200 caractères)'; end if;
  if p_audience not in ('all','customers','sellers','couriers','active30','inactive30') then raise exception 'Audience invalide'; end if;
  if v_link is not null and v_link !~* '^https://' then raise exception 'Le lien doit commencer par https://'; end if;
  if v_img is not null and v_img !~* '^https://' then raise exception 'L''image doit être une adresse https://'; end if;
  if v_coupon is not null and not exists(select 1 from public.coupons where code = v_coupon and active and (expires_at is null or expires_at > now())) then
    raise exception 'Coupon introuvable, inactif ou expiré';
  end if;

  insert into public.notifications(user_id, kind, title, body, image_url, link_url, coupon_code)
  select p.id, 'broadcast', trim(p_title), trim(p_body), v_img, v_link, v_coupon
  from public.profiles p
  where coalesce(p.account_status,'active') = 'active' and not coalesce(p.suspended,false)
    and (case p_audience
      when 'all' then true
      when 'customers' then exists(select 1 from public.orders o where o.customer_id = p.id)
      when 'sellers' then exists(select 1 from public.shops s where s.owner_id = p.id)
      when 'couriers' then exists(select 1 from public.courier_applications c where c.user_id = p.id and c.status = 'approved')
      when 'active30' then p.last_seen_at > now() - interval '30 days'
      when 'inactive30' then (p.last_seen_at is null or p.last_seen_at <= now() - interval '30 days')
      else false end);
  get diagnostics n = row_count;

  if p_banner then
    insert into public.platform_announcements(title, body, severity, created_by)
    values (left(trim(p_title),100), left(trim(p_body),1200), 'info', auth.uid());
  end if;
  insert into public.admin_broadcasts(title, body, image_url, link_url, coupon_code, audience, recipients, with_banner, created_by)
  values (trim(p_title), trim(p_body), v_img, v_link, v_coupon, p_audience, n, coalesce(p_banner,false), auth.uid());
  insert into public.admin_audit_logs(actor, action, resource, reason) values (auth.uid(), 'send_broadcast', 'broadcast', left(trim(p_title)||' → '||n||' destinataires',200));
  return n;
end $$;
revoke all on function public.admin_send_broadcast(text,text,text,text,text,text,boolean) from public, anon;
grant execute on function public.admin_send_broadcast(text,text,text,text,text,text,boolean) to authenticated;

create or replace function public.admin_list_broadcasts(p_limit integer default 30)
returns table(id uuid, title text, body text, audience text, recipients integer, coupon_code text, link_url text, image_url text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  return query select b.id,b.title,b.body,b.audience,b.recipients,b.coupon_code,b.link_url,b.image_url,b.created_at
    from public.admin_broadcasts b order by b.created_at desc limit greatest(1, least(coalesce(p_limit,30),100));
end $$;
revoke all on function public.admin_list_broadcasts(integer) from public, anon;
grant execute on function public.admin_list_broadcasts(integer) to authenticated;
