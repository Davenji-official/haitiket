-- HAITIKET lot 10 : réglages admin, tableau de bord, carnet d'adresses, annulations/litiges/remboursements,
-- signalements, gestion des comptes. Additif : à exécuter après 0001..0009 (chaîne « full_features / payments_bazar »).

-- ===== Utilitaires =====
create or replace function public._notify_admins(t text, b text, r uuid) returns void
language sql security definer set search_path = public as $$
  insert into public.notifications(user_id, kind, title, body, ref) select user_id, 'admin', t, b, r from public.user_roles where role = 'admin' $$;
revoke all on function public._notify_admins(text, text, uuid) from public, anon, authenticated;

-- ===== Réglages modifiables depuis la console =====
drop policy if exists settings_admin_read on public.platform_settings;
create policy settings_admin_read on public.platform_settings for select using (public.admin_unlocked());

create or replace function public.admin_set_setting(p_key text, p_value text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if p_key not in ('commission_bps','reservation_minutes','delivery_flat_minor','usd_htg_rate','bazar_fee_usd','shop_fee_usd','enforce_shop_plan','referral_reward_minor') then
    raise exception 'Réglage inconnu';
  end if;
  if p_key = 'enforce_shop_plan' then
    if p_value not in ('true','false') then raise exception 'Valeur attendue : true ou false'; end if;
  elsif p_key = 'usd_htg_rate' or p_key in ('bazar_fee_usd','shop_fee_usd') then
    if p_value !~ '^[0-9]{1,6}(\.[0-9]{1,4})?$' or p_value::numeric <= 0 then raise exception 'Nombre positif requis'; end if;
  else
    if p_value !~ '^[0-9]{1,9}$' then raise exception 'Nombre entier requis'; end if;
  end if;
  insert into public.platform_settings(key, value) values (p_key, trim(p_value))
  on conflict (key) do update set value = excluded.value, updated_at = now();
  insert into public.admin_audit_logs(actor, action, resource, reason) values (auth.uid(), 'set_setting', p_key, left(p_value, 100));
end $$;
grant execute on function public.admin_set_setting(text, text) to authenticated;

-- ===== Carnet d'adresses =====
create table public.addresses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  label text not null default 'Domicile',
  recipient text not null check (char_length(recipient) between 2 and 80),
  phone text, department text,
  commune text not null check (char_length(commune) between 2 and 80),
  quarter text, street text, landmarks text, instructions text,
  lat double precision, lng double precision,
  is_default boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index on public.addresses (user_id) where active;
alter table public.addresses enable row level security;
create policy addresses_self on public.addresses for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create or replace function public.set_default_address(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.addresses where id = p_id and user_id = auth.uid() and active) then raise exception 'Adresse introuvable'; end if;
  update public.addresses set is_default = (id = p_id) where user_id = auth.uid() and active;
end $$;
grant execute on function public.set_default_address(uuid) to authenticated;

-- ===== Remboursements (exécutés manuellement chez le prestataire, puis confirmés ici) =====
create table public.refund_requests (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id),
  user_id uuid not null references auth.users(id),
  amount_minor bigint not null check (amount_minor > 0),
  reason text,
  status text not null default 'to_execute' check (status in ('to_execute','executed','failed')),
  note text, created_at timestamptz not null default now(), executed_at timestamptz,
  unique (order_id)
);
alter table public.refund_requests enable row level security;
create policy refunds_self on public.refund_requests for select using (user_id = auth.uid());
create policy refunds_admin on public.refund_requests for select using (public.admin_unlocked());

alter table public.ledger_entries drop constraint if exists ledger_entries_kind_check;
alter table public.ledger_entries add constraint ledger_entries_kind_check check (kind in
  ('payment_received','seller_payable','platform_net','courier_payable','bazar_fee','shop_plan_fee',
   'refund_executed','seller_payable_reversal','platform_net_reversal','courier_payable_reversal'));

-- ===== Litiges =====
create table public.order_disputes (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  opened_by uuid not null references auth.users(id),
  reason text not null check (char_length(reason) between 5 and 1000),
  prev_status text not null,
  status text not null default 'open' check (status in ('open','resolved_refund','resolved_no_refund')),
  resolution text, resolved_by uuid references auth.users(id),
  created_at timestamptz not null default now(), resolved_at timestamptz
);
create unique index one_open_dispute on public.order_disputes (order_id) where status = 'open';
alter table public.order_disputes enable row level security;
create policy disputes_parties on public.order_disputes for select using (
  opened_by = auth.uid()
  or exists (select 1 from public.orders o where o.id = order_id and (o.customer_id = auth.uid() or exists (select 1 from public.shops s where s.id = o.shop_id and s.owner_id = auth.uid()))));
create policy disputes_admin on public.order_disputes for select using (public.admin_unlocked());

create or replace function public.open_dispute(p_order uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare o public.orders; uid uuid := auth.uid(); own uuid;
begin
  if uid is null then raise exception 'Connexion requise'; end if;
  select * into o from public.orders where id = p_order for update;
  if o.id is null then raise exception 'Commande introuvable'; end if;
  select owner_id into own from public.shops where id = o.shop_id;
  if uid is distinct from o.customer_id and uid is distinct from own then raise exception 'Accès refusé'; end if;
  if o.status not in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED') then raise exception 'Litige impossible pour une commande « % »', public._status_label(o.status); end if;
  insert into public.order_disputes(order_id, opened_by, reason, prev_status) values (p_order, uid, trim(p_reason), o.status);
  perform public._set_order_status(p_order, 'DISPUTED', uid, 'dispute_opened');
  perform public._notify_admins('Nouveau litige', left(trim(p_reason), 80), p_order);
exception when unique_violation then raise exception 'Un litige est déjà ouvert pour cette commande';
end $$;
grant execute on function public.open_dispute(uuid, text) to authenticated;

create or replace function public.admin_resolve_dispute(p_id uuid, p_outcome text, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare d public.order_disputes; o public.orders; own uuid;
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if coalesce(trim(p_note), '') = '' then raise exception 'Décision à motiver'; end if;
  select * into d from public.order_disputes where id = p_id and status = 'open' for update;
  if d.id is null then raise exception 'Litige introuvable ou déjà traité'; end if;
  select * into o from public.orders where id = d.order_id for update;
  select owner_id into own from public.shops where id = o.shop_id;
  if p_outcome = 'refund' then
    update public.order_disputes set status = 'resolved_refund', resolution = trim(p_note), resolved_by = auth.uid(), resolved_at = now() where id = p_id;
    insert into public.refund_requests(order_id, user_id, amount_minor, reason) values (o.id, o.customer_id, o.total_minor, 'Litige : ' || left(trim(p_note), 200)) on conflict (order_id) do nothing;
  elsif p_outcome = 'no_refund' then
    update public.order_disputes set status = 'resolved_no_refund', resolution = trim(p_note), resolved_by = auth.uid(), resolved_at = now() where id = p_id;
    perform public._set_order_status(o.id, d.prev_status, auth.uid(), 'dispute_rejected');
  else
    raise exception 'Décision invalide';
  end if;
  perform public._notify(o.customer_id, 'order', 'Litige traité', left(trim(p_note), 80), o.id);
  perform public._notify(own, 'order', 'Litige traité', left(trim(p_note), 80), o.id);
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason) values (auth.uid(), 'resolve_dispute:' || p_outcome, 'dispute', p_id, left(trim(p_note), 200));
end $$;
grant execute on function public.admin_resolve_dispute(uuid, text, text) to authenticated;

-- Annulation par le client : possible tant que le vendeur n'a pas confirmé (commande payée).
create or replace function public.request_cancellation(p_order uuid) returns void
language plpgsql security definer set search_path = public as $$
declare o public.orders; it record; own uuid; uid uuid := auth.uid();
begin
  if uid is null then raise exception 'Connexion requise'; end if;
  select * into o from public.orders where id = p_order and customer_id = uid for update;
  if o.id is null then raise exception 'Commande introuvable'; end if;
  if o.status <> 'PAID' then raise exception 'Annulation directe impossible : utilisez « Signaler un problème »'; end if;
  for it in select product_id, qty from public.order_items where order_id = o.id loop
    update public.products set stock = stock + it.qty where id = it.product_id;
    insert into public.inventory_movements(product_id, order_id, delta, reason, actor) values (it.product_id, o.id, it.qty, 'cancelled_after_payment', uid);
  end loop;
  update public.delivery_jobs set status = 'cancelled' where order_id = o.id and status = 'open';
  perform public._set_order_status(o.id, 'CANCELLED', uid, 'customer_cancellation');
  insert into public.refund_requests(order_id, user_id, amount_minor, reason) values (o.id, uid, o.total_minor, 'Annulation avant confirmation du vendeur') on conflict (order_id) do nothing;
  select owner_id into own from public.shops where id = o.shop_id;
  perform public._notify(own, 'order', 'Commande annulée par le client', null, o.id);
  perform public._notify_admins('Remboursement à exécuter', 'Annulation client', o.id);
end $$;
grant execute on function public.request_cancellation(uuid) to authenticated;

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
        (att, o.id, 'platform_net_reversal', -(o.commission_minor - o.discount_minor), o.currency),
        (att, o.id, 'courier_payable_reversal', -o.delivery_minor, o.currency)
      on conflict do nothing;
      update public.payment_attempts set status = 'cancelled', updated_at = now() where id = att and status = 'refund_required';
    end if;
    perform public._notify(r.user_id, 'order', 'Remboursement effectué', null, o.id);
  end if;
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason) values (auth.uid(), case when p_executed then 'refund_executed' else 'refund_failed' end, 'refund', p_id, left(coalesce(p_note, ''), 200));
end $$;
grant execute on function public.admin_mark_refund(uuid, boolean, text) to authenticated;

-- Paiement reçu après expiration, sans stock : on le met en file de remboursement.
create or replace function public.admin_queue_refund(p_attempt uuid) returns void
language plpgsql security definer set search_path = public as $$
declare a public.payment_attempts;
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  select * into a from public.payment_attempts where id = p_attempt and status = 'refund_required' and purpose = 'order';
  if a.id is null then raise exception 'Paiement introuvable'; end if;
  insert into public.refund_requests(order_id, user_id, amount_minor, reason) values (a.order_id, a.user_id, a.amount_minor, 'Paiement tardif sans stock') on conflict (order_id) do nothing;
  insert into public.admin_audit_logs(actor, action, resource, resource_id) values (auth.uid(), 'queue_refund', 'payment', p_attempt);
end $$;
grant execute on function public.admin_queue_refund(uuid) to authenticated;

-- ===== Signalements =====
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('product','shop','user','message')),
  target_id uuid not null,
  reason text not null check (char_length(reason) between 5 and 500),
  status text not null default 'open' check (status in ('open','actioned','dismissed')),
  note text, created_at timestamptz not null default now(),
  unique (reporter_id, kind, target_id)
);
alter table public.reports enable row level security;
create policy reports_self on public.reports for select using (reporter_id = auth.uid());
create policy reports_admin on public.reports for select using (public.admin_unlocked());
create or replace function public.submit_report(p_kind text, p_target uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  insert into public.reports(reporter_id, kind, target_id, reason) values (auth.uid(), p_kind, p_target, trim(p_reason));
  perform public._notify_admins('Nouveau signalement', p_kind || ' : ' || left(trim(p_reason), 60), p_target);
exception when unique_violation then raise exception 'Vous avez déjà signalé cet élément';
end $$;
grant execute on function public.submit_report(text, uuid, text) to authenticated;
create or replace function public.admin_resolve_report(p_id uuid, p_status text, p_note text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if p_status not in ('actioned','dismissed') then raise exception 'Statut invalide'; end if;
  update public.reports set status = p_status, note = left(coalesce(p_note, ''), 300) where id = p_id and status = 'open';
  if not found then raise exception 'Signalement introuvable'; end if;
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason) values (auth.uid(), 'report:' || p_status, 'report', p_id, left(coalesce(p_note, ''), 200));
end $$;
grant execute on function public.admin_resolve_report(uuid, text, text) to authenticated;

-- ===== Gestion des comptes =====
alter table public.profiles add column if not exists suspended boolean not null default false, add column if not exists suspended_reason text;
create or replace function public.admin_search_users(p_q text) returns table (id uuid, email text, display_name text, suspended boolean, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  return query select p.id, u.email::text, p.display_name, p.suspended, p.created_at from public.profiles p join auth.users u on u.id = p.id
    where coalesce(trim(p_q), '') = '' or u.email ilike '%' || trim(p_q) || '%' or p.display_name ilike '%' || trim(p_q) || '%'
    order by p.created_at desc limit 50;
end $$;
grant execute on function public.admin_search_users(text) to authenticated;

create or replace function public.admin_set_user_suspended(p_user uuid, p_suspended boolean, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if p_user = auth.uid() then raise exception 'Vous ne pouvez pas vous suspendre vous-même'; end if;
  if p_suspended and coalesce(trim(p_reason), '') = '' then raise exception 'Motif requis'; end if;
  update public.profiles set suspended = p_suspended, suspended_reason = case when p_suspended then left(trim(p_reason), 200) end where id = p_user;
  if not found then raise exception 'Compte introuvable'; end if;
  if p_suspended then update public.shops set status = 'suspended' where owner_id = p_user and status = 'active'; end if;
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason) values (auth.uid(), case when p_suspended then 'suspend_user' else 'unsuspend_user' end, 'user', p_user, left(coalesce(p_reason, ''), 200));
end $$;
grant execute on function public.admin_set_user_suspended(uuid, boolean, text) to authenticated;

create or replace function public._guard_suspended() returns trigger language plpgsql security definer set search_path = public as $$
declare uid uuid;
begin
  if tg_table_name = 'orders' then uid := new.customer_id;
  elsif tg_table_name = 'messages' then uid := new.sender_id;
  end if;
  if exists (select 1 from public.profiles where id = uid and suspended) then raise exception 'Compte suspendu : contactez le support'; end if;
  return new;
end $$;
drop trigger if exists orders_guard_suspended on public.orders;
create trigger orders_guard_suspended before insert on public.orders for each row execute function public._guard_suspended();
drop trigger if exists messages_guard_suspended on public.messages;
create trigger messages_guard_suspended before insert on public.messages for each row execute function public._guard_suspended();

-- ===== Modération : tout produit peut être bloqué =====
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
  elsif p_kind = 'product' and p_status in ('blocked','paused') then
    update public.products set status = p_status where id = p_id;
  else
    raise exception 'Action invalide';
  end if;
  get diagnostics n = row_count;
  if n = 0 then raise exception 'Élément introuvable'; end if;
  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason) values (auth.uid(), 'set_status:' || p_status, p_kind, p_id, p_reason);
end $$;

-- ===== Tableau de bord administrateur =====
create or replace function public.admin_dashboard() returns json
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  return json_build_object(
    'orders_total', (select count(*) from public.orders),
    'orders_pending_payment', (select count(*) from public.orders where status = 'PENDING_PAYMENT'),
    'orders_paid', (select count(*) from public.orders where status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED','COMPLETED')),
    'orders_delivered', (select count(*) from public.orders where status in ('DELIVERED','COMPLETED')),
    'orders_cancelled', (select count(*) from public.orders where status in ('CANCELLED','REFUNDED')),
    'gmv_minor', coalesce((select sum(amount_minor) from public.ledger_entries where kind = 'payment_received'), 0),
    'commission_minor', coalesce((select sum(amount_minor) from public.ledger_entries where kind in ('platform_net','platform_net_reversal')), 0),
    'fees_minor', coalesce((select sum(amount_minor) from public.ledger_entries where kind in ('bazar_fee','shop_plan_fee')), 0),
    'payments_pending', (select count(*) from public.payment_attempts where status in ('created','pending')),
    'payments_failed', (select count(*) from public.payment_attempts where status = 'failed'),
    'payments_refund_required', (select count(*) from public.payment_attempts where status = 'refund_required'),
    'refunds_to_execute', (select count(*) from public.refund_requests where status = 'to_execute'),
    'shops_active', (select count(*) from public.shops where status = 'active' and kind = 'pro'),
    'shops_pending', (select count(*) from public.shops where status = 'pending'),
    'bazar_active', (select count(*) from public.products where source = 'bazar' and status = 'published' and paid_until > now()),
    'couriers_approved', (select count(*) from public.courier_applications where status = 'approved'),
    'couriers_available', (select count(*) from public.courier_status where available),
    'jobs_open', (select count(*) from public.delivery_jobs where status = 'open'),
    'jobs_active', (select count(*) from public.delivery_jobs where status in ('assigned','picked_up')),
    'tickets_open', (select count(*) from public.support_tickets where status in ('OPEN','ASSIGNED')),
    'disputes_open', (select count(*) from public.order_disputes where status = 'open'),
    'reports_open', (select count(*) from public.reports where status = 'open'),
    'users_total', (select count(*) from public.profiles));
end $$;
grant execute on function public.admin_dashboard() to authenticated;
