-- HAITIKET lot 7 : paiements manuels vérifiés, registre financier, portefeuille/retraits, cycle de commande complet
-- (PIN de remise, suivi), avis vérifiés, coupons, parrainage, notifications, signalements, catégories, réglages admin.
-- Aucun paiement n'est simulé : un paiement n'est « confirmé » que lorsqu'un administrateur vérifie la transaction réelle.

-- ===== Réglages =====
insert into public.platform_settings(key, value) values
  ('listing_fee_minor','200'), ('shop_plan_fee_minor','2000'), ('payment_review_hours','24'),
  ('manual_payment_instructions','Envoyez le montant exact par MonCash ou NatCash au numéro communiqué par HAITIKET, puis saisissez la référence de la transaction. Un administrateur vérifie le paiement.'),
  ('referral_reward_minor','0')
on conflict (key) do nothing;
drop policy if exists settings_public_read on public.platform_settings;
create policy settings_public_read on public.platform_settings for select
  using (key in ('commission_bps','reservation_minutes','delivery_flat_minor','listing_fee_minor','shop_plan_fee_minor','manual_payment_instructions'));
create policy settings_admin_read on public.platform_settings for select using (public.admin_unlocked());

create or replace function public.admin_set_setting(p_key text, p_value text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if p_key not in ('commission_bps','reservation_minutes','delivery_flat_minor','listing_fee_minor','shop_plan_fee_minor','manual_payment_instructions','referral_reward_minor','payment_review_hours') then
    raise exception 'Réglage inconnu';
  end if;
  if p_key <> 'manual_payment_instructions' and p_value !~ '^[0-9]{1,9}$' then raise exception 'Valeur numérique requise'; end if;
  insert into public.platform_settings(key, value) values (p_key, trim(p_value))
  on conflict (key) do update set value = excluded.value, updated_at = now();
  insert into public.admin_audit_logs(actor, action, resource, reason) values (auth.uid(), 'set_setting', p_key, left(p_value, 200));
end $$;
grant execute on function public.admin_set_setting(text, text) to authenticated;

-- ===== Catégories =====
create unique index if not exists categories_name_uq on public.categories(name);
insert into public.categories(name) values
  ('Vêtements et chaussures'),('Nourriture et boissons'),('Électronique'),('Téléphones et accessoires'),('Maison et décoration'),
  ('Beauté et soins'),('Livres et fournitures'),('Enfants et bébés'),('Animaux'),('Sports et loisirs'),('Outils et matériel'),('Autres')
on conflict (name) do nothing;

-- ===== Notifications =====
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null, title text not null, body text, ref_id uuid,
  read boolean not null default false, created_at timestamptz not null default now()
);
create index on public.notifications (user_id, created_at desc);
alter table public.notifications enable row level security;
create policy notif_self_read on public.notifications for select using (user_id = auth.uid());
do $$ begin alter publication supabase_realtime add table public.notifications;
exception when others then raise notice 'Activez le temps réel pour notifications (Database > Replication)'; end $$;

create or replace function public._notify(u uuid, k text, t text, b text, r uuid) returns void
language sql security definer set search_path = public as $$
  insert into public.notifications(user_id, kind, title, body, ref_id) values (u, k, t, b, r) $$;
revoke all on function public._notify(uuid, text, text, text, uuid) from public, anon, authenticated;

create or replace function public._notify_admins(t text, b text, r uuid) returns void
language sql security definer set search_path = public as $$
  insert into public.notifications(user_id, kind, title, body, ref_id) select user_id, 'admin', t, b, r from public.user_roles where role = 'admin' $$;
revoke all on function public._notify_admins(text, text, uuid) from public, anon, authenticated;

create or replace function public.mark_notifications_read() returns void
language sql security definer set search_path = public as $$
  update public.notifications set read = true where user_id = auth.uid() and not read $$;
grant execute on function public.mark_notifications_read() to authenticated;

create or replace function public._notify_message() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications(user_id, kind, title, body, ref_id)
  select m.user_id, 'message', 'Nouveau message', left(new.body, 120), new.conversation_id
  from public.conversation_members m where m.conversation_id = new.conversation_id and m.user_id <> new.sender_id;
  return new;
end $$;
create trigger trg_notify_message after insert on public.messages for each row execute function public._notify_message();

-- ===== Commandes : colonnes, PIN, suivi, registre =====
alter table public.orders add column if not exists discount_minor bigint not null default 0;
alter table public.orders add column if not exists coupon_code text;

create table public.order_pins (
  order_id uuid primary key references public.orders(id) on delete cascade,
  pickup_pin text not null, delivery_pin text not null, attempts int not null default 0
);
alter table public.order_pins enable row level security;   -- aucune politique : accès par fonctions uniquement

create table public.tracking_events (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  label text not null, actor uuid, created_at timestamptz not null default now()
);
create index on public.tracking_events (order_id, created_at);
alter table public.tracking_events enable row level security;
create policy tracking_read on public.tracking_events for select using (
  exists (select 1 from public.orders o where o.id = order_id and (o.customer_id = auth.uid() or exists (select 1 from public.shops s where s.id = o.shop_id and s.owner_id = auth.uid())))
  or exists (select 1 from public.delivery_jobs j where j.order_id = tracking_events.order_id and j.courier_id = auth.uid()));
create policy orders_admin_read on public.orders for select using (public.admin_unlocked());
create policy jobs_customer_read on public.delivery_jobs for select using (exists (select 1 from public.orders o where o.id = order_id and o.customer_id = auth.uid()));

create table public.ledger_entries (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id),
  user_id uuid references auth.users(id),
  entry_type text not null check (entry_type in ('customer_payment','platform_commission','seller_payable','courier_payable','delivery_fee_held','promo_cost','platform_revenue','referral_reward','payout','reversal','refund_due')),
  amount_minor bigint not null, currency text not null, ref text,
  created_at timestamptz not null default now()
);
create index on public.ledger_entries (user_id, created_at desc);
alter table public.ledger_entries enable row level security;
create policy ledger_self_read on public.ledger_entries for select using (user_id = auth.uid());
create policy ledger_admin_read on public.ledger_entries for select using (public.admin_unlocked());
-- Aucune écriture directe : les écritures ne se corrigent que par écriture compensatoire.

create or replace function public._track(p_order uuid, p_label text, p_actor uuid) returns void
language sql security definer set search_path = public as $$
  insert into public.tracking_events(order_id, label, actor) values (p_order, p_label, p_actor) $$;
revoke all on function public._track(uuid, text, uuid) from public, anon, authenticated;

create or replace function public._set_order_status(p_order uuid, p_to text, p_actor uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare old text;
begin
  select status into old from public.orders where id = p_order for update;
  update public.orders set status = p_to where id = p_order;
  insert into public.order_status_events(order_id, from_status, to_status, actor, reason) values (p_order, old, p_to, p_actor, p_reason);
end $$;
revoke all on function public._set_order_status(uuid, text, uuid, text) from public, anon, authenticated;

-- ===== Coupons =====
create table public.coupons (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code = upper(code) and char_length(code) between 3 and 30),
  percent int check (percent between 1 and 100), fixed_minor bigint check (fixed_minor > 0),
  min_order_minor bigint not null default 0, max_uses int, used_count int not null default 0,
  expires_at timestamptz, active boolean not null default true, created_at timestamptz not null default now(),
  check (num_nonnulls(percent, fixed_minor) = 1)
);
create table public.coupon_redemptions (
  id uuid primary key default gen_random_uuid(),
  coupon_id uuid not null references public.coupons(id),
  order_id uuid not null unique references public.orders(id) on delete cascade,
  user_id uuid not null references auth.users(id), created_at timestamptz not null default now()
);
alter table public.coupons enable row level security;
alter table public.coupon_redemptions enable row level security;
create policy coupons_admin_read on public.coupons for select using (public.admin_unlocked());

create or replace function public.admin_create_coupon(p_code text, p_percent int, p_fixed_minor bigint, p_min bigint, p_max_uses int, p_days int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  insert into public.coupons(code, percent, fixed_minor, min_order_minor, max_uses, expires_at)
  values (upper(trim(p_code)), nullif(p_percent, 0), nullif(p_fixed_minor, 0), coalesce(p_min, 0), nullif(p_max_uses, 0), case when coalesce(p_days, 0) > 0 then now() + make_interval(days => p_days) end);
  insert into public.admin_audit_logs(actor, action, resource, reason) values (auth.uid(), 'create_coupon', 'coupon', upper(trim(p_code)));
end $$;
grant execute on function public.admin_create_coupon(text, int, bigint, bigint, int, int) to authenticated;

-- ===== Annulation (mise à jour : libère aussi le coupon) =====
create or replace function public._cancel_order(p_order uuid, p_actor uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare o public.orders; it record; cid uuid;
begin
  select * into o from public.orders where id = p_order for update;
  if o.id is null or o.status <> 'PENDING_PAYMENT' then return; end if;
  for it in select product_id, qty from public.order_items where order_id = p_order loop
    update public.products set stock = stock + it.qty where id = it.product_id;
    insert into public.inventory_movements(product_id, order_id, delta, reason, actor) values (it.product_id, p_order, it.qty, p_reason, p_actor);
  end loop;
  select coupon_id into cid from public.coupon_redemptions where order_id = p_order;
  if cid is not null then
    update public.coupons set used_count = greatest(used_count - 1, 0) where id = cid;
    delete from public.coupon_redemptions where order_id = p_order;
  end if;
  update public.orders set reserved_until = null where id = p_order;
  perform public._set_order_status(p_order, 'CANCELLED', p_actor, p_reason);
  perform public._track(p_order, 'Commande annulée', p_actor);
end $$;
revoke all on function public._cancel_order(uuid, uuid, text) from public, anon, authenticated;

-- ===== Création de commande (version avec coupon) =====
drop function if exists public.create_orders(jsonb, text, text);
create or replace function public.create_orders(p_items jsonb, p_mode text, p_address text, p_coupon text default null) returns setof public.orders
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); bps int; mins int; fee bigint := 0; v_shop uuid; v_items bigint; v_ncur int; v_cur text; v_comm bigint;
  r record; o public.orders; v_code text := nullif(upper(trim(coalesce(p_coupon, ''))), ''); cp public.coupons; disc bigint; v_shops int;
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
  select count(distinct p.shop_id) into v_shops from public.products p where p.id in (select x.product_id from jsonb_to_recordset(p_items) as x(product_id uuid, qty int));

  if v_code is not null then
    select * into cp from public.coupons c where c.code = v_code and c.active for update;
    if cp.id is null then raise exception 'Coupon invalide'; end if;
    if cp.expires_at is not null and cp.expires_at < now() then raise exception 'Coupon expiré'; end if;
    if cp.max_uses is not null and cp.used_count >= cp.max_uses then raise exception 'Coupon épuisé'; end if;
    if v_shops > 1 then raise exception 'Coupon valable pour une seule boutique à la fois'; end if;
    if exists (select 1 from public.coupon_redemptions where coupon_id = cp.id and user_id = uid) then raise exception 'Coupon déjà utilisé'; end if;
  end if;

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

    disc := 0;
    if v_code is not null then
      if v_items < cp.min_order_minor then raise exception 'Montant minimum non atteint pour ce coupon'; end if;
      disc := case when cp.percent is not null then (v_items * cp.percent) / 100 else least(cp.fixed_minor, v_items) end;
      disc := least(disc, v_items);
    end if;

    v_comm := (v_items * bps + 5000) / 10000;
    insert into public.orders(customer_id, shop_id, delivery_mode, delivery_address, currency, items_minor, discount_minor, coupon_code, delivery_minor, total_minor, commission_bps, commission_minor, seller_net_minor, reserved_until)
    values (uid, v_shop, p_mode, case when p_mode = 'delivery' then trim(p_address) end, v_cur, v_items, disc, v_code, fee, v_items - disc + fee, bps, v_comm, v_items - v_comm, now() + make_interval(mins => mins))
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
    if v_code is not null then
      insert into public.coupon_redemptions(coupon_id, order_id, user_id) values (cp.id, o.id, uid);
      update public.coupons set used_count = used_count + 1 where id = cp.id;
    end if;
    insert into public.order_status_events(order_id, from_status, to_status, actor, reason) values (o.id, null, 'PENDING_PAYMENT', uid, 'order_created');
    perform public._track(o.id, 'Commande créée — en attente de paiement', uid);
    return next o;
  end loop;
  return;
end $$;
grant execute on function public.create_orders(jsonb, text, text, text) to authenticated;

-- ===== Paiements manuels vérifiés =====
create table public.manual_payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  kind text not null check (kind in ('order','listing','shop_plan')),
  target_id uuid not null,
  amount_minor bigint not null check (amount_minor > 0), currency text not null,
  method text not null check (method in ('moncash','natcash','bank','cash')),
  reference text not null check (char_length(reference) between 3 and 80),
  status text not null default 'submitted' check (status in ('submitted','confirmed','rejected')),
  admin_note text, reviewed_by uuid, reviewed_at timestamptz, created_at timestamptz not null default now()
);
create unique index manual_payments_open on public.manual_payments(kind, target_id) where status in ('submitted','confirmed') and kind = 'order';
create unique index manual_payments_ref on public.manual_payments(method, reference) where status <> 'rejected';
alter table public.manual_payments enable row level security;
create policy mp_self_read on public.manual_payments for select using (user_id = auth.uid());
create policy mp_admin_read on public.manual_payments for select using (public.admin_unlocked());

create or replace function public.submit_manual_payment(p_kind text, p_target uuid, p_method text, p_reference text) returns uuid
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); amt bigint; cur text; hrs int; pid uuid; v text;
begin
  if uid is null then raise exception 'Connexion requise'; end if;
  if p_method not in ('moncash','natcash','bank','cash') then raise exception 'Moyen de paiement invalide'; end if;
  if char_length(coalesce(trim(p_reference), '')) < 3 then raise exception 'Référence de transaction requise'; end if;
  if p_kind = 'order' then
    select total_minor, currency into amt, cur from public.orders where id = p_target and customer_id = uid and status = 'PENDING_PAYMENT';
    if amt is null then raise exception 'Commande introuvable ou déjà traitée'; end if;
    select coalesce(value::int, 24) into hrs from public.platform_settings where key = 'payment_review_hours';
    update public.orders set reserved_until = now() + make_interval(hours => coalesce(hrs, 24)) where id = p_target;
    perform public._set_order_status(p_target, 'PAYMENT_PROCESSING', uid, 'manual_payment_submitted');
    perform public._track(p_target, 'Paiement envoyé — vérification en cours', uid);
  elsif p_kind = 'listing' then
    if not exists (select 1 from public.listings where id = p_target and seller_id = uid and status in ('draft','published','expired')) then raise exception 'Annonce introuvable'; end if;
    select value into v from public.platform_settings where key = 'listing_fee_minor'; amt := v::bigint; cur := 'USD';
  elsif p_kind = 'shop_plan' then
    if not exists (select 1 from public.shops where id = p_target and owner_id = uid) then raise exception 'Boutique introuvable'; end if;
    select value into v from public.platform_settings where key = 'shop_plan_fee_minor'; amt := v::bigint; cur := 'USD';
  else
    raise exception 'Type invalide';
  end if;
  insert into public.manual_payments(user_id, kind, target_id, amount_minor, currency, method, reference)
  values (uid, p_kind, p_target, amt, cur, p_method, trim(p_reference)) returning id into pid;
  perform public._notify_admins('Paiement à vérifier', p_kind || ' · ' || amt || ' ' || cur || ' · ' || trim(p_reference), pid);
  return pid;
end $$;
grant execute on function public.submit_manual_payment(text, uuid, text, text) to authenticated;

create or replace function public._mark_order_paid(p_order uuid, p_actor uuid) returns void
language plpgsql security definer set search_path = public as $$
declare o public.orders; owner uuid;
begin
  select * into o from public.orders where id = p_order for update;
  if o.id is null or o.status <> 'PAYMENT_PROCESSING' then raise exception 'Commande non éligible'; end if;
  select owner_id into owner from public.shops where id = o.shop_id;
  update public.orders set reserved_until = null where id = p_order;
  perform public._set_order_status(p_order, 'PAID', p_actor, 'manual_payment_confirmed');
  insert into public.ledger_entries(order_id, user_id, entry_type, amount_minor, currency, ref) values
    (p_order, o.customer_id, 'customer_payment', o.total_minor, o.currency, 'manual'),
    (p_order, null, 'platform_commission', o.commission_minor, o.currency, null),
    (p_order, owner, 'seller_payable', o.seller_net_minor, o.currency, null);
  if o.delivery_minor > 0 then
    insert into public.ledger_entries(order_id, user_id, entry_type, amount_minor, currency) values (p_order, null, 'delivery_fee_held', o.delivery_minor, o.currency);
  end if;
  if o.discount_minor > 0 then
    insert into public.ledger_entries(order_id, user_id, entry_type, amount_minor, currency, ref) values (p_order, null, 'promo_cost', -o.discount_minor, o.currency, o.coupon_code);
  end if;
  insert into public.order_pins(order_id, pickup_pin, delivery_pin)
  values (p_order, lpad((floor(random() * 1000000))::int::text, 6, '0'), lpad((floor(random() * 1000000))::int::text, 6, '0'))
  on conflict do nothing;
  perform public._track(p_order, 'Paiement confirmé', p_actor);
  if o.delivery_mode = 'delivery' then perform public.create_delivery_job(p_order); end if;
  perform public._notify(o.customer_id, 'order', 'Paiement confirmé', 'Votre commande est transmise au vendeur.', p_order);
  perform public._notify(owner, 'order', 'Nouvelle commande payée', 'Confirmez et préparez la commande.', p_order);
end $$;
revoke all on function public._mark_order_paid(uuid, uuid) from public, anon, authenticated;

create or replace function public.admin_review_payment(p_id uuid, p_approve boolean, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare mp public.manual_payments;
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  select * into mp from public.manual_payments where id = p_id for update;
  if mp.id is null or mp.status <> 'submitted' then raise exception 'Paiement introuvable ou déjà traité'; end if;
  if not p_approve and coalesce(trim(p_note), '') = '' then raise exception 'Motif requis'; end if;
  update public.manual_payments set status = case when p_approve then 'confirmed' else 'rejected' end, admin_note = p_note, reviewed_by = auth.uid(), reviewed_at = now() where id = p_id;
  if not p_approve then
    if mp.kind = 'order' then
      update public.orders set reserved_until = now() + interval '2 hours' where id = mp.target_id and status = 'PAYMENT_PROCESSING';
      perform public._set_order_status(mp.target_id, 'PENDING_PAYMENT', auth.uid(), 'payment_rejected');
      perform public._track(mp.target_id, 'Paiement refusé : ' || p_note, auth.uid());
    end if;
    perform public._notify(mp.user_id, 'payment', 'Paiement refusé', p_note, mp.target_id);
  else
    if mp.kind = 'order' then
      perform public._mark_order_paid(mp.target_id, auth.uid());
    elsif mp.kind = 'listing' then
      update public.listings set paid_until = greatest(coalesce(paid_until, now()), now()) + interval '14 days', status = 'published' where id = mp.target_id;
      insert into public.ledger_entries(user_id, entry_type, amount_minor, currency, ref) values (null, 'platform_revenue', mp.amount_minor, mp.currency, 'listing');
      perform public._notify(mp.user_id, 'payment', 'Annonce activée', 'Votre annonce est publiée pour 14 jours.', mp.target_id);
    else
      update public.shops set plan_paid_until = greatest(coalesce(plan_paid_until, now()), now()) + interval '30 days' where id = mp.target_id;
      insert into public.ledger_entries(user_id, entry_type, amount_minor, currency, ref) values (null, 'platform_revenue', mp.amount_minor, mp.currency, 'shop_plan');
      perform public._notify(mp.user_id, 'payment', 'Abonnement boutique reçu', 'Abonnement prolongé de 30 jours.', mp.target_id);
    end if;
  end if;
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason) values (auth.uid(), case when p_approve then 'payment_confirmed' else 'payment_rejected' end, 'manual_payment', p_id, p_note);
end $$;
grant execute on function public.admin_review_payment(uuid, boolean, text) to authenticated;

-- ===== Cycle de commande : vendeur, livreur, client =====
create or replace function public.get_order_pin(p_order uuid) returns text
language plpgsql security definer set search_path = public as $$
declare o public.orders; owner uuid; pins public.order_pins;
begin
  select * into o from public.orders where id = p_order;
  if o.id is null then return null; end if;
  select owner_id into owner from public.shops where id = o.shop_id;
  select * into pins from public.order_pins where order_id = p_order;
  if pins.order_id is null then return null; end if;
  if auth.uid() = o.customer_id and o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT') then return pins.delivery_pin; end if;
  if auth.uid() = owner and o.delivery_mode = 'delivery' and o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP') then return pins.pickup_pin; end if;
  return null;
end $$;
grant execute on function public.get_order_pin(uuid) to authenticated;

create or replace function public._check_pin(p_order uuid, p_pin text, p_which text) returns void
language plpgsql security definer set search_path = public as $$
declare pins public.order_pins; ok boolean;
begin
  select * into pins from public.order_pins where order_id = p_order for update;
  if pins.order_id is null then raise exception 'Code indisponible'; end if;
  if pins.attempts >= 5 then raise exception 'Trop de tentatives : contactez le support'; end if;
  ok := case when p_which = 'pickup' then pins.pickup_pin = trim(coalesce(p_pin, '')) else pins.delivery_pin = trim(coalesce(p_pin, '')) end;
  if not ok then
    update public.order_pins set attempts = attempts + 1 where order_id = p_order;
    perform public._track(p_order, 'Code incorrect saisi', auth.uid());
    raise exception 'Code incorrect';
  end if;
end $$;
revoke all on function public._check_pin(uuid, text, text) from public, anon, authenticated;

create or replace function public.seller_set_order_status(p_order uuid, p_status text) returns void
language plpgsql security definer set search_path = public as $$
declare o public.orders; cur text; lbl text;
begin
  select o2.* into o from public.orders o2 join public.shops s on s.id = o2.shop_id where o2.id = p_order and s.owner_id = auth.uid() for update of o2;
  if o.id is null then raise exception 'Commande introuvable'; end if;
  if not ((o.status = 'PAID' and p_status = 'CONFIRMED') or (o.status = 'CONFIRMED' and p_status = 'PREPARING') or (o.status = 'PREPARING' and p_status = 'READY_FOR_PICKUP')) then
    raise exception 'Transition non autorisée';
  end if;
  lbl := case p_status when 'CONFIRMED' then 'Commande acceptée par le vendeur' when 'PREPARING' then 'Préparation commencée' else 'Colis prêt' end;
  perform public._set_order_status(p_order, p_status, auth.uid(), 'seller_update');
  perform public._track(p_order, lbl, auth.uid());
  perform public._notify(o.customer_id, 'order', lbl, null, p_order);
end $$;
grant execute on function public.seller_set_order_status(uuid, text) to authenticated;

create or replace function public.seller_confirm_handover(p_order uuid, p_pin text) returns void
language plpgsql security definer set search_path = public as $$
declare o public.orders;
begin
  select o2.* into o from public.orders o2 join public.shops s on s.id = o2.shop_id where o2.id = p_order and s.owner_id = auth.uid();
  if o.id is null then raise exception 'Commande introuvable'; end if;
  if o.delivery_mode <> 'pickup' or o.status <> 'READY_FOR_PICKUP' then raise exception 'Remise impossible à cette étape'; end if;
  perform public._check_pin(p_order, p_pin, 'delivery');
  perform public._set_order_status(p_order, 'DELIVERED', auth.uid(), 'pickup_handover');
  perform public._track(p_order, 'Remise confirmée au retrait', auth.uid());
  perform public._notify(o.customer_id, 'order', 'Remise confirmée', 'Confirmez la réception dans votre commande.', p_order);
end $$;
grant execute on function public.seller_confirm_handover(uuid, text) to authenticated;

create or replace function public.courier_confirm_pickup(p_job uuid, p_pin text) returns void
language plpgsql security definer set search_path = public as $$
declare j public.delivery_jobs; o public.orders;
begin
  select * into j from public.delivery_jobs where id = p_job and courier_id = auth.uid() and status = 'assigned' for update;
  if j.id is null then raise exception 'Mission introuvable'; end if;
  select * into o from public.orders where id = j.order_id;
  if o.status <> 'READY_FOR_PICKUP' then raise exception 'Le vendeur n''a pas encore marqué le colis prêt'; end if;
  perform public._check_pin(j.order_id, p_pin, 'pickup');
  update public.delivery_jobs set status = 'picked_up' where id = p_job;
  perform public._set_order_status(j.order_id, 'IN_TRANSIT', auth.uid(), 'courier_pickup');
  perform public._track(j.order_id, 'Colis collecté — en livraison', auth.uid());
  perform public._notify(o.customer_id, 'order', 'Votre colis est en route', 'Gardez votre code de remise.', j.order_id);
end $$;
grant execute on function public.courier_confirm_pickup(uuid, text) to authenticated;

create or replace function public.courier_confirm_delivery(p_job uuid, p_pin text) returns void
language plpgsql security definer set search_path = public as $$
declare j public.delivery_jobs; o public.orders;
begin
  select * into j from public.delivery_jobs where id = p_job and courier_id = auth.uid() and status = 'picked_up' for update;
  if j.id is null then raise exception 'Mission introuvable'; end if;
  select * into o from public.orders where id = j.order_id;
  perform public._check_pin(j.order_id, p_pin, 'delivery');
  update public.delivery_jobs set status = 'delivered' where id = p_job;
  perform public._set_order_status(j.order_id, 'DELIVERED', auth.uid(), 'courier_delivery');
  insert into public.ledger_entries(order_id, user_id, entry_type, amount_minor, currency) values (j.order_id, auth.uid(), 'courier_payable', j.pay_minor, j.currency);
  perform public._track(j.order_id, 'Remise confirmée par le livreur', auth.uid());
  perform public._notify(o.customer_id, 'order', 'Colis remis', 'Confirmez la réception dans votre commande.', j.order_id);
end $$;
grant execute on function public.courier_confirm_delivery(uuid, text) to authenticated;

create table public.delivery_incidents (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.delivery_jobs(id) on delete cascade,
  reporter_id uuid not null references auth.users(id), description text not null check (char_length(description) between 5 and 1000),
  created_at timestamptz not null default now()
);
alter table public.delivery_incidents enable row level security;
create policy incidents_self_read on public.delivery_incidents for select using (reporter_id = auth.uid());
create policy incidents_admin_read on public.delivery_incidents for select using (public.admin_unlocked());

create or replace function public.courier_report_incident(p_job uuid, p_text text) returns void
language plpgsql security definer set search_path = public as $$
declare j public.delivery_jobs; iid uuid;
begin
  select * into j from public.delivery_jobs where id = p_job and courier_id = auth.uid();
  if j.id is null then raise exception 'Mission introuvable'; end if;
  insert into public.delivery_incidents(job_id, reporter_id, description) values (p_job, auth.uid(), p_text) returning id into iid;
  perform public._track(j.order_id, 'Incident signalé par le livreur', auth.uid());
  perform public._notify_admins('Incident de livraison', left(p_text, 120), j.order_id);
end $$;
grant execute on function public.courier_report_incident(uuid, text) to authenticated;

-- Parrainage
create table public.referral_codes (user_id uuid primary key references auth.users(id) on delete cascade, code text not null unique);
create table public.referrals (
  id uuid primary key default gen_random_uuid(),
  referrer_id uuid not null references auth.users(id), referred_id uuid not null unique references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','rewarded')), created_at timestamptz not null default now()
);
alter table public.referral_codes enable row level security;
alter table public.referrals enable row level security;
create policy refcode_self on public.referral_codes for select using (user_id = auth.uid());
create policy referrals_self on public.referrals for select using (referrer_id = auth.uid() or referred_id = auth.uid());

create or replace function public.my_referral_code() returns text
language plpgsql security definer set search_path = public as $$
declare c text;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  select code into c from public.referral_codes where user_id = auth.uid();
  if c is null then
    c := upper(substr(md5(random()::text || auth.uid()::text), 1, 8));
    insert into public.referral_codes(user_id, code) values (auth.uid(), c);
  end if;
  return c;
end $$;
grant execute on function public.my_referral_code() to authenticated;

create or replace function public.apply_referral(p_code text) returns void
language plpgsql security definer set search_path = public as $$
declare ref uuid;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  select user_id into ref from public.referral_codes where code = upper(trim(p_code));
  if ref is null then raise exception 'Code de parrainage invalide'; end if;
  if ref = auth.uid() then raise exception 'Vous ne pouvez pas vous parrainer'; end if;
  if exists (select 1 from public.orders where customer_id = auth.uid()) then raise exception 'Réservé aux comptes sans commande'; end if;
  insert into public.referrals(referrer_id, referred_id) values (ref, auth.uid());
exception when unique_violation then raise exception 'Parrainage déjà enregistré';
end $$;
grant execute on function public.apply_referral(text) to authenticated;

create or replace function public._complete_order(p_order uuid, p_actor uuid) returns void
language plpgsql security definer set search_path = public as $$
declare o public.orders; owner uuid; rf public.referrals; reward bigint;
begin
  select * into o from public.orders where id = p_order for update;
  if o.id is null or o.status <> 'DELIVERED' then return; end if;
  select owner_id into owner from public.shops where id = o.shop_id;
  perform public._set_order_status(p_order, 'COMPLETED', p_actor, 'receipt_confirmed');
  perform public._track(p_order, 'Commande terminée', p_actor);
  perform public._notify(owner, 'order', 'Commande terminée', 'Les fonds de cette commande sont disponibles dans votre portefeuille.', p_order);
  select * into rf from public.referrals where referred_id = o.customer_id and status = 'pending' for update;
  if rf.id is not null then
    select coalesce(value::bigint, 0) into reward from public.platform_settings where key = 'referral_reward_minor';
    if coalesce(reward, 0) > 0 then
      insert into public.ledger_entries(user_id, entry_type, amount_minor, currency, ref) values (rf.referrer_id, 'referral_reward', reward, 'HTG', 'referral');
      update public.referrals set status = 'rewarded' where id = rf.id;
      perform public._notify(rf.referrer_id, 'referral', 'Récompense de parrainage', 'Un filleul a terminé sa première commande.', null);
    end if;
  end if;
end $$;
revoke all on function public._complete_order(uuid, uuid) from public, anon, authenticated;

create or replace function public.confirm_receipt(p_order uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.orders where id = p_order and customer_id = auth.uid() and status = 'DELIVERED') then raise exception 'Commande non confirmable'; end if;
  perform public._complete_order(p_order, auth.uid());
end $$;
grant execute on function public.confirm_receipt(uuid) to authenticated;

create or replace function public.open_dispute(p_order uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare o public.orders;
begin
  select * into o from public.orders where id = p_order and customer_id = auth.uid() for update;
  if o.id is null or o.status not in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED') then raise exception 'Litige impossible à cette étape'; end if;
  if char_length(coalesce(trim(p_reason), '')) < 5 then raise exception 'Décrivez le problème'; end if;
  perform public._set_order_status(p_order, 'DISPUTED', auth.uid(), 'dispute_opened');
  perform public._track(p_order, 'Litige ouvert', auth.uid());
  insert into public.support_tickets(user_id, subject, message) values (auth.uid(), 'Litige commande ' || left(p_order::text, 8), left(trim(p_reason), 2000));
  perform public._notify_admins('Litige ouvert', 'Commande ' || left(p_order::text, 8), p_order);
end $$;
grant execute on function public.open_dispute(uuid, text) to authenticated;

create or replace function public.admin_resolve_dispute(p_order uuid, p_outcome text, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare o public.orders; owner uuid;
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  select * into o from public.orders where id = p_order and status = 'DISPUTED' for update;
  if o.id is null then raise exception 'Litige introuvable'; end if;
  if coalesce(trim(p_note), '') = '' then raise exception 'Motif requis'; end if;
  select owner_id into owner from public.shops where id = o.shop_id;
  if p_outcome = 'complete' then
    perform public._set_order_status(p_order, 'DELIVERED', auth.uid(), 'dispute_resolved_for_seller');
    perform public._complete_order(p_order, auth.uid());
  elsif p_outcome = 'refund' then
    perform public._set_order_status(p_order, 'REFUNDED', auth.uid(), 'dispute_refund');
    insert into public.ledger_entries(order_id, user_id, entry_type, amount_minor, currency, ref) values
      (p_order, owner, 'reversal', -o.seller_net_minor, o.currency, 'dispute_refund'),
      (p_order, null, 'reversal', -o.commission_minor, o.currency, 'dispute_refund'),
      (p_order, o.customer_id, 'refund_due', o.total_minor, o.currency, 'à rembourser manuellement');
    update public.delivery_jobs set status = 'cancelled' where order_id = p_order and status in ('open','assigned');
    perform public._track(p_order, 'Remboursement décidé', auth.uid());
    perform public._notify(o.customer_id, 'order', 'Remboursement accordé', p_note, p_order);
  else
    raise exception 'Décision invalide';
  end if;
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason) values (auth.uid(), 'resolve_dispute:' || p_outcome, 'order', p_order, p_note);
end $$;
grant execute on function public.admin_resolve_dispute(uuid, text, text) to authenticated;

-- ===== Avis vérifiés =====
create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders(id) on delete cascade,
  shop_id uuid not null references public.shops(id),
  reviewer_id uuid not null references auth.users(id),
  rating int not null check (rating between 1 and 5), comment text check (char_length(comment) <= 1000),
  created_at timestamptz not null default now()
);
alter table public.reviews enable row level security;
create policy reviews_public_read on public.reviews for select using (true);

create or replace function public.submit_review(p_order uuid, p_rating int, p_comment text) returns void
language plpgsql security definer set search_path = public as $$
declare o public.orders;
begin
  select * into o from public.orders where id = p_order and customer_id = auth.uid() and status = 'COMPLETED';
  if o.id is null then raise exception 'Avis possible uniquement après une commande terminée'; end if;
  insert into public.reviews(order_id, shop_id, reviewer_id, rating, comment) values (p_order, o.shop_id, auth.uid(), p_rating, nullif(trim(coalesce(p_comment, '')), ''));
exception when unique_violation then raise exception 'Avis déjà publié';
end $$;
grant execute on function public.submit_review(uuid, int, text) to authenticated;

-- ===== Signalements =====
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  target_kind text not null check (target_kind in ('product','listing','shop')),
  target_id uuid not null, reason text not null check (char_length(reason) between 3 and 500),
  status text not null default 'open' check (status in ('open','reviewed','dismissed')),
  created_at timestamptz not null default now()
);
alter table public.reports enable row level security;
create policy reports_insert on public.reports for insert with check (reporter_id = auth.uid() and status = 'open');
create policy reports_self_read on public.reports for select using (reporter_id = auth.uid());
create policy reports_admin_read on public.reports for select using (public.admin_unlocked());

-- ===== Portefeuille et retraits =====
create table public.payout_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  amount_minor bigint not null check (amount_minor > 0), currency text not null,
  method text not null check (method in ('moncash','natcash','bank')), destination text not null check (char_length(destination) between 3 and 120),
  status text not null default 'requested' check (status in ('requested','paid','rejected')),
  admin_note text, created_at timestamptz not null default now()
);
alter table public.payout_requests enable row level security;
create policy payout_self_read on public.payout_requests for select using (user_id = auth.uid());
create policy payout_admin_read on public.payout_requests for select using (public.admin_unlocked());

create or replace function public.wallet_summary() returns table (currency text, pending bigint, available bigint)
language sql stable security definer set search_path = public as $$
  select l.currency,
    coalesce(sum(l.amount_minor) filter (where l.entry_type in ('seller_payable','courier_payable') and o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED')), 0)::bigint,
    (coalesce(sum(l.amount_minor) filter (where l.entry_type in ('seller_payable','courier_payable') and o.status = 'COMPLETED'), 0)
     + coalesce(sum(l.amount_minor) filter (where l.entry_type in ('referral_reward','payout','reversal') and (l.entry_type <> 'reversal' or l.order_id is null)), 0))::bigint
  from public.ledger_entries l left join public.orders o on o.id = l.order_id
  where l.user_id = auth.uid() group by l.currency $$;
grant execute on function public.wallet_summary() to authenticated;

create or replace function public.request_payout(p_amount bigint, p_currency text, p_method text, p_dest text) returns uuid
language plpgsql security definer set search_path = public as $$
declare av bigint; pid uuid;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Montant invalide'; end if;
  select w.available into av from public.wallet_summary() w where w.currency = p_currency;
  if coalesce(av, 0) < p_amount then raise exception 'Solde disponible insuffisant'; end if;
  insert into public.payout_requests(user_id, amount_minor, currency, method, destination) values (auth.uid(), p_amount, p_currency, p_method, trim(p_dest)) returning id into pid;
  insert into public.ledger_entries(user_id, entry_type, amount_minor, currency, ref) values (auth.uid(), 'payout', -p_amount, p_currency, pid::text);
  perform public._notify_admins('Demande de retrait', p_amount || ' ' || p_currency, pid);
  return pid;
end $$;
grant execute on function public.request_payout(bigint, text, text, text) to authenticated;

create or replace function public.admin_review_payout(p_id uuid, p_paid boolean, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare pr public.payout_requests;
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  select * into pr from public.payout_requests where id = p_id and status = 'requested' for update;
  if pr.id is null then raise exception 'Retrait introuvable ou déjà traité'; end if;
  if coalesce(trim(p_note), '') = '' then raise exception 'Référence ou motif requis'; end if;
  update public.payout_requests set status = case when p_paid then 'paid' else 'rejected' end, admin_note = p_note where id = p_id;
  if not p_paid then
    insert into public.ledger_entries(user_id, entry_type, amount_minor, currency, ref) values (pr.user_id, 'reversal', pr.amount_minor, pr.currency, 'payout_rejected');
  end if;
  perform public._notify(pr.user_id, 'payout', case when p_paid then 'Retrait payé' else 'Retrait refusé' end, p_note, p_id);
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason) values (auth.uid(), case when p_paid then 'payout_paid' else 'payout_rejected' end, 'payout', p_id, p_note);
end $$;
grant execute on function public.admin_review_payout(uuid, boolean, text) to authenticated;

-- ===== Statuts admin étendus + réponse support avec notification =====
create or replace function public.admin_set_status(p_kind text, p_id uuid, p_status text, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if p_status in ('suspended','rejected','blocked','closed','removed') and coalesce(trim(p_reason), '') = '' then raise exception 'Motif requis'; end if;
  if p_kind = 'shop' and p_status in ('pending','active','suspended','closed') then
    update public.shops set status = p_status where id = p_id;
  elsif p_kind = 'courier' and p_status in ('verifying','approved','rejected','suspended') then
    update public.courier_applications set status = p_status where id = p_id;
  elsif p_kind = 'listing' and p_status in ('published','blocked','draft') then
    update public.listings set status = p_status where id = p_id;
  elsif p_kind = 'product' and p_status in ('paused','removed','published') then
    update public.products set status = p_status where id = p_id;
  elsif p_kind = 'report' and p_status in ('reviewed','dismissed') then
    update public.reports set status = p_status where id = p_id;
  elsif p_kind = 'coupon' and p_status in ('active','inactive') then
    update public.coupons set active = (p_status = 'active') where id = p_id;
  else
    raise exception 'Action invalide';
  end if;
  get diagnostics n = row_count;
  if n = 0 then raise exception 'Élément introuvable'; end if;
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason) values (auth.uid(), 'set_status:' || p_status, p_kind, p_id, p_reason);
end $$;

create or replace function public.admin_reply_ticket(p_id uuid, p_reply text) returns void
language plpgsql security definer set search_path = public as $$
declare t public.support_tickets;
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if coalesce(trim(p_reply), '') = '' then raise exception 'Réponse vide'; end if;
  update public.support_tickets set admin_reply = trim(p_reply), status = 'RESOLVED' where id = p_id returning * into t;
  if t.id is null then raise exception 'Ticket introuvable'; end if;
  perform public._notify(t.user_id, 'support', 'Réponse du support', left(trim(p_reply), 120), p_id);
  insert into public.admin_audit_logs(actor, action, resource, resource_id) values (auth.uid(), 'reply_ticket', 'support_ticket', p_id);
end $$;

-- ===== Maintenance automatique =====
create or replace function public.run_maintenance() returns void
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  perform public.release_expired_reservations();
  for r in select o.id from public.orders o where o.status = 'DELIVERED'
    and exists (select 1 from public.order_status_events e where e.order_id = o.id and e.to_status = 'DELIVERED' and e.created_at < now() - interval '72 hours') loop
    perform public._complete_order(r.id, null);
  end loop;
  update public.listings set status = 'expired' where status = 'published' and paid_until is not null and paid_until < now();
  update public.listings set status = 'deleted' where status = 'expired' and paid_until is not null and paid_until < now() - interval '30 days';
  update public.shops set status = 'suspended' where status = 'active' and plan_paid_until is not null and plan_paid_until < now();
end $$;
revoke all on function public.run_maintenance() from public, anon, authenticated;
do $$ begin
  create extension if not exists pg_cron;
  perform cron.schedule('haitiket-maintenance', '*/10 * * * *', 'select public.run_maintenance()');
exception when others then raise notice 'pg_cron non disponible : activez-le dans Database > Extensions'; end $$;
