-- HAITIKET V78 — commissions par produit/catégorie/boutique, revenus en direct, retrait livreur fiable,
-- propriétaire de la boutique officielle, pièces jointes et cartes produit dans la messagerie, AVIF.
-- À appliquer APRÈS 0068. Idempotent.

-- =====================================================================
-- 1. LIVREUR : arrêter proprement (et pouvoir redevenir livreur via une nouvelle candidature)
-- =====================================================================
alter table public.courier_applications drop constraint if exists courier_applications_status_check;
alter table public.courier_applications add constraint courier_applications_status_check
  check (status in ('submitted','verifying','approved','rejected','suspended','withdrawn'));

create or replace function public.courier_withdraw_self_v78() returns boolean
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if exists(select 1 from public.delivery_jobs where courier_id = auth.uid() and status in ('assigned','picked_up')) then
    raise exception 'Terminez d''abord vos missions en cours (collecte ou livraison).';
  end if;
  select id into v_id from public.courier_applications
   where user_id = auth.uid() and status in ('submitted','verifying','approved') order by created_at desc limit 1;
  if v_id is null then raise exception 'Aucune candidature livreur active à retirer'; end if;
  update public.courier_applications set status = 'withdrawn' where id = v_id;
  update public.courier_status set available = false where user_id = auth.uid();
  return true;
end $$;
revoke all on function public.courier_withdraw_self_v78() from public, anon;
grant execute on function public.courier_withdraw_self_v78() to authenticated;

-- =====================================================================
-- 2. BOUTIQUE OFFICIELLE : propriétaire visible et transférable entre administrateurs
-- =====================================================================
create or replace function public.admin_official_shop_owner() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  return (select jsonb_build_object('shop_id', s.id, 'owner_id', s.owner_id, 'owner_name', p.display_name, 'owner_email', u.email,
                                    'is_me', s.owner_id = auth.uid())
          from public.shops s join auth.users u on u.id = s.owner_id left join public.profiles p on p.id = s.owner_id
          where s.is_official limit 1);
end $$;
revoke all on function public.admin_official_shop_owner() from public, anon;
grant execute on function public.admin_official_shop_owner() to authenticated;

create or replace function public.admin_set_official_shop_owner(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if not exists(select 1 from public.user_roles where user_id = p_user and role = 'admin') then
    raise exception 'Le propriétaire de la boutique officielle doit être administrateur';
  end if;
  update public.shops set owner_id = p_user where is_official;
  if not found then raise exception 'Créez d''abord la boutique officielle'; end if;
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason) values (auth.uid(), 'transfer_official_shop', 'user', p_user, 'transfert de propriété de la boutique officielle');
end $$;
revoke all on function public.admin_set_official_shop_owner(uuid) from public, anon;
grant execute on function public.admin_set_official_shop_owner(uuid) to authenticated;

create or replace function public.admin_list_admins() returns table(user_id uuid, name text, email text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  return query select r.user_id, p.display_name, u.email::text from public.user_roles r join auth.users u on u.id = r.user_id left join public.profiles p on p.id = r.user_id where r.role = 'admin' order by p.display_name;
end $$;
revoke all on function public.admin_list_admins() from public, anon;
grant execute on function public.admin_list_admins() to authenticated;

-- =====================================================================
-- 3. MESSAGERIE : pièces jointes (photo, vidéo, fichier) et produits partagés
-- =====================================================================
alter table public.messages add column if not exists kind text not null default 'text';
alter table public.messages add column if not exists attachment_path text;
alter table public.messages add column if not exists attachment_name text;
alter table public.messages add column if not exists attachment_mime text;
alter table public.messages add column if not exists attachment_size bigint;
alter table public.messages add column if not exists product_id uuid references public.products(id) on delete set null;
alter table public.messages drop constraint if exists messages_kind_check;
alter table public.messages add constraint messages_kind_check check (kind in ('text','image','video','file','product'));
alter table public.messages drop constraint if exists messages_attachment_scope;
alter table public.messages add constraint messages_attachment_scope check (attachment_path is null or attachment_path like conversation_id::text || '/%');

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values (
  'chat-media', 'chat-media', false, 52428800,
  array['image/jpeg','image/png','image/webp','image/avif','image/gif','video/mp4','video/webm','video/quicktime',
        'application/pdf','text/plain','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','audio/mpeg','audio/mp4','audio/aac'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists chat_media_insert on storage.objects;
create policy chat_media_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'chat-media' and public.is_member(((storage.foldername(name))[1])::uuid));
drop policy if exists chat_media_select on storage.objects;
create policy chat_media_select on storage.objects for select to authenticated
  using (bucket_id = 'chat-media' and public.is_member(((storage.foldername(name))[1])::uuid));

-- AVIF accepté pour les photos de produits, logos et annonces
update storage.buckets set allowed_mime_types = (select array_agg(distinct x) from unnest(coalesce(allowed_mime_types, array[]::text[]) || array['image/avif','image/gif']) x)
where id = 'media';

-- =====================================================================
-- 4. COMMISSIONS PAR PRODUIT / CATÉGORIE / BOUTIQUE (priorité : produit > catégorie > boutique > défaut global)
-- =====================================================================
create table if not exists public.commission_rules (
  id uuid primary key default gen_random_uuid(),
  scope text not null check (scope in ('product','category','shop')),
  target_id uuid not null,
  bps integer not null check (bps between 0 and 10000),
  note text, active boolean not null default true,
  created_by uuid references auth.users(id), created_at timestamptz not null default now(),
  unique (scope, target_id)
);
alter table public.commission_rules enable row level security;
revoke all on public.commission_rules from anon, authenticated;

create or replace function public.commission_bps_for(p_product uuid) returns integer
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select r.bps from public.commission_rules r where r.active and r.scope = 'product' and r.target_id = p_product),
    (select r.bps from public.commission_rules r join public.products p on p.category_id = r.target_id where r.active and r.scope = 'category' and p.id = p_product),
    (select r.bps from public.commission_rules r join public.products p on p.shop_id = r.target_id where r.active and r.scope = 'shop' and p.id = p_product),
    (select nullif(value,'')::int from public.platform_settings where key = 'commission_bps'),
    200) $$;
revoke all on function public.commission_bps_for(uuid) from public, anon;
grant execute on function public.commission_bps_for(uuid) to authenticated;

create or replace function public.admin_upsert_commission_rule(p_scope text, p_target uuid, p_bps integer, p_note text, p_active boolean) returns uuid
language plpgsql security definer set search_path = public as $$
declare v uuid;
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if p_scope not in ('product','category','shop') then raise exception 'Portée invalide'; end if;
  if p_bps is null or p_bps < 0 or p_bps > 10000 then raise exception 'Commission invalide (0 à 100 %%)'; end if;
  if (p_scope = 'product' and not exists(select 1 from public.products where id = p_target))
     or (p_scope = 'category' and not exists(select 1 from public.categories where id = p_target))
     or (p_scope = 'shop' and not exists(select 1 from public.shops where id = p_target)) then raise exception 'Cible introuvable'; end if;
  insert into public.commission_rules(scope, target_id, bps, note, active, created_by)
  values (p_scope, p_target, p_bps, nullif(trim(coalesce(p_note,'')),''), coalesce(p_active,true), auth.uid())
  on conflict (scope, target_id) do update set bps = excluded.bps, note = excluded.note, active = excluded.active
  returning id into v;
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason) values (auth.uid(), 'upsert_commission_rule', 'commission_rule', v, p_scope || ' = ' || p_bps || ' bps');
  return v;
end $$;
revoke all on function public.admin_upsert_commission_rule(text,uuid,integer,text,boolean) from public, anon;
grant execute on function public.admin_upsert_commission_rule(text,uuid,integer,text,boolean) to authenticated;

create or replace function public.admin_delete_commission_rule(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  delete from public.commission_rules where id = p_id;
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason) values (auth.uid(), 'delete_commission_rule', 'commission_rule', p_id, 'règle supprimée');
end $$;
revoke all on function public.admin_delete_commission_rule(uuid) from public, anon;
grant execute on function public.admin_delete_commission_rule(uuid) to authenticated;

create or replace function public.admin_list_commission_rules() returns table(id uuid, scope text, target_id uuid, target_name text, bps integer, note text, active boolean, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  return query select r.id, r.scope, r.target_id,
    case r.scope when 'product' then (select p.name from public.products p where p.id = r.target_id)
                 when 'category' then (select c.name from public.categories c where c.id = r.target_id)
                 else (select s.name from public.shops s where s.id = r.target_id) end,
    r.bps, r.note, r.active, r.created_at
  from public.commission_rules r order by r.scope, r.created_at desc;
end $$;
revoke all on function public.admin_list_commission_rules() from public, anon;
grant execute on function public.admin_list_commission_rules() to authenticated;

create or replace function public.admin_search_shops(p_q text default '') returns table(id uuid, name text, kind text, is_official boolean, status text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  return query select s.id, s.name, s.kind, s.is_official, s.status from public.shops s
    where coalesce(p_q,'') = '' or s.name ilike '%' || p_q || '%' order by s.is_official desc, s.name limit 50;
end $$;
revoke all on function public.admin_search_shops(text) from public, anon;
grant execute on function public.admin_search_shops(text) to authenticated;

-- Commande : commission calculée ligne par ligne (reprend create_orders V73 + règles)
create or replace function public.create_orders(p_items jsonb, p_mode text, p_address text, p_coupon text default null) returns setof public.orders
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); bps int; mins int; fee bigint := 0; v_comm_raw numeric := 0; v_eff_bps int := 0;
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

    v_items := 0; v_elig := 0; v_cur := null; v_comm_raw := 0;
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
      -- V78 : commission par produit (règle produit > catégorie > boutique > défaut global)
      v_comm_raw := v_comm_raw + (v_unit * r.qty)::numeric * public.commission_bps_for(r.id);
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

    if v_items > 0 then
      v_comm := round(v_comm_raw / 10000.0 * (case when v_shop_funded then (v_items - v_disc)::numeric / v_items else 1 end))::bigint;
      v_eff_bps := round(v_comm_raw / v_items)::int;
    else
      v_comm := 0; v_eff_bps := 0;
    end if;
    insert into public.orders(customer_id, shop_id, delivery_mode, delivery_address, currency, items_minor, delivery_minor, discount_minor, discount_funder,
                              total_minor, commission_bps, commission_minor, seller_net_minor, platform_net_minor, reserved_until)
    values (uid, v_shop, p_mode, case when p_mode = 'delivery' then trim(p_address) end, v_cur, v_items, fee, v_disc, case when v_shop_funded then 'shop' else 'platform' end,
            v_items - v_disc + fee, v_eff_bps, v_comm,
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
-- 5. REVENUS DE HAITIKET EN DIRECT (commissions, abonnements boutiques, annonces Bazar, boutique officielle)
-- =====================================================================
create or replace function public.admin_revenue_live(p_days integer default 30) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d integer := greatest(1, least(coalesce(p_days,30), 366)); r jsonb;
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  select jsonb_build_object(
    'orders', coalesce((select jsonb_object_agg(t.cur, t.x) from (
        select o.currency as cur, jsonb_build_object(
          'gmv_minor', coalesce(sum(o.items_minor) filter (where o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED','COMPLETED')),0),
          'commission_earned', coalesce(sum(o.commission_minor) filter (where o.status in ('DELIVERED','COMPLETED')),0),
          'platform_net_earned', coalesce(sum(o.platform_net_minor) filter (where o.status in ('DELIVERED','COMPLETED')),0),
          'commission_pending', coalesce(sum(o.commission_minor) filter (where o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT')),0),
          'orders_paid', count(*) filter (where o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED','COMPLETED'))) as x
        from public.orders o where o.created_at >= now() - make_interval(days => d) group by o.currency) t), '{}'::jsonb),
    'official', coalesce((select jsonb_object_agg(t.cur, t.x) from (
        select o.currency as cur, jsonb_build_object(
          'sales_minor', coalesce(sum(o.items_minor - o.discount_minor) filter (where o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED','COMPLETED')),0),
          'orders', count(*) filter (where o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED','COMPLETED'))) as x
        from public.orders o join public.shops s on s.id = o.shop_id and s.is_official
        where o.created_at >= now() - make_interval(days => d) group by o.currency) t), '{}'::jsonb),
    'subscriptions_usd_minor', (select coalesce(sum(w.amount_minor),0) from public.wallet_transactions w where w.kind = 'subscription_fee' and w.status = 'successful' and w.created_at >= now() - make_interval(days => d)),
    'subscriptions_count', (select count(*) from public.wallet_transactions w where w.kind = 'subscription_fee' and w.status = 'successful' and w.created_at >= now() - make_interval(days => d)),
    'bazar_usd_minor', (select coalesce(sum(w.amount_minor),0) from public.wallet_transactions w where w.kind = 'purchase' and w.status = 'successful' and w.metadata->>'purpose' = 'bazar_listing' and w.created_at >= now() - make_interval(days => d)),
    'bazar_count', (select count(*) from public.wallet_transactions w where w.kind = 'purchase' and w.status = 'successful' and w.metadata->>'purpose' = 'bazar_listing' and w.created_at >= now() - make_interval(days => d)),
    'by_day', coalesce((select jsonb_agg(x order by x.day) from (
        select g.day::date as day,
          (select coalesce(sum(o.commission_minor),0) from public.orders o where o.created_at::date = g.day::date and o.currency = 'HTG' and o.status in ('DELIVERED','COMPLETED')) as commission_htg,
          (select coalesce(sum(o.commission_minor),0) from public.orders o where o.created_at::date = g.day::date and o.currency = 'USD' and o.status in ('DELIVERED','COMPLETED')) as commission_usd,
          (select coalesce(sum(w.amount_minor),0) from public.wallet_transactions w where w.created_at::date = g.day::date and w.kind = 'subscription_fee' and w.status = 'successful') as subscriptions_usd,
          (select coalesce(sum(w.amount_minor),0) from public.wallet_transactions w where w.created_at::date = g.day::date and w.kind = 'purchase' and w.status = 'successful' and w.metadata->>'purpose' = 'bazar_listing') as bazar_usd,
          (select coalesce(sum(o.items_minor - o.discount_minor),0) from public.orders o join public.shops s on s.id = o.shop_id and s.is_official where o.created_at::date = g.day::date and o.currency = 'HTG' and o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED','COMPLETED')) as official_htg,
          (select coalesce(sum(o.items_minor - o.discount_minor),0) from public.orders o join public.shops s on s.id = o.shop_id and s.is_official where o.created_at::date = g.day::date and o.currency = 'USD' and o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED','COMPLETED')) as official_usd
        from generate_series((current_date - (d - 1))::timestamp, current_date::timestamp, interval '1 day') as g(day)) x), '[]'::jsonb),
    'generated_at', now()) into r;
  return r;
end $$;
revoke all on function public.admin_revenue_live(integer) from public, anon;
grant execute on function public.admin_revenue_live(integer) to authenticated;
