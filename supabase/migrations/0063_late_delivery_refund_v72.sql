-- HAITIKET 0063 : (1) RÉPARATION des réglages admin, (2) délai de livraison/retrait et remboursement automatique en cas de retard.
--
-- (1) La migration 0037 avait remplacé admin_set_setting par une version trop courte : le prestataire de paiement, le délai
--     de livraison immédiate, les extensions de trafic et la durée des offres ne pouvaient plus être enregistrés
--     (« Réglage inconnu »). Cette version réunit tous les réglages.
-- (2) Chaque commande payée reçoit une échéance réglable (72 h livraison / 96 h retrait par défaut) + le retard de trafic
--     déclaré par le livreur. Passé ce délai, le client peut demander le remboursement et le système rembourse automatiquement
--     dans le portefeuille ; les revenus vendeur/livreur encore « en attente » sont annulés. Rien n'est remboursé si un litige
--     est ouvert ou si un revenu a déjà été libéré. Ré-exécutable sans risque.

begin;

insert into public.platform_settings(key, value) values ('late_delivery_hours', '72'), ('late_pickup_hours', '96')
on conflict (key) do nothing;

create or replace function public.admin_set_setting(p_key text, p_value text) returns void
language plpgsql security definer set search_path = public as $$
declare v text := trim(coalesce(p_value, ''));
begin
  if not public.admin_unlocked() then raise exception 'Accès refusé : console verrouillée'; end if;
  if p_key not in (
    'commission_bps','reservation_minutes','delivery_flat_minor','usd_htg_rate',
    'usd_htg_topup_rate','usd_htg_withdraw_rate','bazar_fee_usd','shop_fee_usd',
    'shop_fee_yearly_usd','enforce_shop_plan','referral_reward_minor','payment_provider',
    'delivery_immediate_sla_minutes','delivery_traffic_extension_options',
    'delivery_offer_expiry_minutes','late_delivery_hours','late_pickup_hours'
  ) then raise exception 'Réglage inconnu'; end if;
  if p_key='payment_provider' then
    if v <> 'plopplop' then raise exception 'Le seul prestataire externe autorisé est Plop Plop. Les achats de commandes utilisent le portefeuille interne.'; end if;
  elsif p_key='enforce_shop_plan' then
    if v not in ('true','false') then raise exception 'Valeur attendue : true ou false'; end if;
  elsif p_key='delivery_traffic_extension_options' then
    if v not in ('120,240','120','240') then raise exception 'Valeurs autorisées : 120, 240 ou 120,240'; end if;
  elsif p_key in ('usd_htg_rate','usd_htg_topup_rate','usd_htg_withdraw_rate','bazar_fee_usd','shop_fee_usd','shop_fee_yearly_usd') then
    if v !~ '^[0-9]{1,6}(\.[0-9]{1,4})?$' or v::numeric <= 0 then raise exception 'Nombre positif requis'; end if;
  else
    if v !~ '^[0-9]{1,9}$' then raise exception 'Nombre entier requis'; end if;
    if p_key in ('delivery_immediate_sla_minutes','reservation_minutes') and v::integer < 1 then raise exception 'Une durée positive est requise'; end if;
    if p_key='delivery_offer_expiry_minutes' and v::integer not between 1 and 60 then raise exception 'La durée des offres doit être comprise entre 1 et 60 minutes'; end if;
    if p_key in ('late_delivery_hours','late_pickup_hours') and v::integer not between 1 and 720 then raise exception 'Le délai doit être compris entre 1 et 720 heures'; end if;
    if p_key='commission_bps' and v::integer > 10000 then raise exception 'La commission ne peut dépasser 100 %%'; end if;
  end if;
  insert into public.platform_settings(key,value) values(p_key,v)
  on conflict(key) do update set value=excluded.value,updated_at=now();
  insert into public.admin_audit_logs(actor,action,resource,reason) values(auth.uid(),'set_setting',p_key,left(v,100));
end $$;
revoke all on function public.admin_set_setting(text, text) from public, anon;
grant execute on function public.admin_set_setting(text, text) to authenticated;

alter table public.orders add column if not exists delivery_due_at timestamptz;
create index if not exists orders_delivery_due_idx_v72 on public.orders(delivery_due_at)
  where status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT');

create or replace function public._due_hours_v72(p_mode text) returns integer
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select nullif(value, '')::integer from public.platform_settings
      where key = case when p_mode = 'delivery' then 'late_delivery_hours' else 'late_pickup_hours' end),
    case when p_mode = 'delivery' then 72 else 96 end);
$$;
revoke all on function public._due_hours_v72(text) from public, anon, authenticated;

create or replace function public._orders_set_due_v72() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'PAID' and old.status is distinct from 'PAID' and new.delivery_due_at is null then
    new.delivery_due_at := now() + make_interval(hours => public._due_hours_v72(new.delivery_mode));
  end if;
  return new;
end $$;
drop trigger if exists orders_set_due_v72 on public.orders;
create trigger orders_set_due_v72 before update of status on public.orders
  for each row execute function public._orders_set_due_v72();

-- Commandes déjà payées avant cette migration : échéance calculée depuis leur création.
update public.orders set delivery_due_at = created_at + make_interval(hours => public._due_hours_v72(delivery_mode))
 where delivery_due_at is null and status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT');

-- Échéance effective = échéance + retard de trafic déclaré par le livreur.
create or replace function public._effective_due_v72(p_order uuid) returns timestamptz
language sql stable security definer set search_path = public as $$
  select o.delivery_due_at + make_interval(mins => coalesce(
           (select j.traffic_delay_minutes from public.delivery_jobs j where j.order_id = o.id order by j.created_at desc limit 1), 0))
    from public.orders o where o.id = p_order;
$$;
revoke all on function public._effective_due_v72(uuid) from public, anon, authenticated;

-- Cœur : rembourse une commande en retard dans le portefeuille du client (retourne vrai si remboursée).
create or replace function public._refund_late_order_v72(p_order uuid, p_actor uuid, p_source text) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  o public.orders;
  purchase_tx public.wallet_transactions;
  aid uuid;
  due timestamptz;
  v_owner uuid;
begin
  select * into o from public.orders where id = p_order for update;
  if o.id is null or o.status not in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT') then return false; end if;
  due := public._effective_due_v72(o.id);
  if due is null or due > now() then return false; end if;
  if o.status = 'IN_TRANSIT' and due + interval '24 hours' > now() then return false; end if;
  if exists (select 1 from public.order_disputes d where d.order_id = o.id and d.status = 'open') then return false; end if;
  if exists (select 1 from public.wallet_transactions where reference = 'ORDER_REFUND:' || o.id::text) then return false; end if;
  if exists (select 1 from public.wallet_transactions t
              where t.reference in ('SELLER_ORDER:' || o.id::text, 'COURIER_ORDER:' || o.id::text)
                and t.status = 'successful' and t.kind in ('seller_credit', 'courier_credit')) then return false; end if;

  select * into purchase_tx from public.wallet_transactions
   where reference = 'ORDER:' || o.id::text and user_id = o.customer_id and kind = 'purchase' and status = 'successful'
     and amount_minor = o.total_minor and currency = o.currency
   for update;
  if purchase_tx.id is null then return false; end if;

  insert into public.wallet_accounts(user_id, currency) values (o.customer_id, o.currency) on conflict (user_id, currency) do nothing;
  select id into aid from public.wallet_accounts where user_id = o.customer_id and currency = o.currency for update;

  insert into public.wallet_transactions(account_id, user_id, reference, kind, status, amount_minor, currency, provider, metadata)
  values (aid, o.customer_id, 'ORDER_REFUND:' || o.id::text, 'refund', 'successful', o.total_minor, o.currency, 'internal',
          jsonb_build_object('order_id', o.id, 'source', p_source, 'reason', 'late_delivery'));

  update public.wallet_transactions set status = 'reversed', updated_at = now(),
         metadata = metadata || jsonb_build_object('reversed_for_late_refund', true)
   where reference in ('SELLER_ORDER:' || o.id::text, 'COURIER_ORDER:' || o.id::text)
     and status = 'pending' and kind in ('seller_credit', 'courier_credit');

  begin perform public._restore_stock(o.id, 'late_refund', p_actor); exception when others then null; end;
  update public.delivery_jobs set status = 'cancelled' where order_id = o.id and status in ('open', 'assigned');
  perform public._set_order_status(o.id, 'REFUNDED', p_actor, 'late_delivery_refund');

  select s.owner_id into v_owner from public.shops s where s.id = o.shop_id;
  perform public._notify(o.customer_id, 'order', 'Commande en retard : remboursée dans votre portefeuille', null, o.id);
  if v_owner is not null then perform public._notify(v_owner, 'order', 'Une commande a été remboursée pour retard de livraison', null, o.id); end if;
  return true;
end $$;
revoke all on function public._refund_late_order_v72(uuid, uuid, text) from public, anon, authenticated;

-- Le client demande lui-même le remboursement d'une commande en retard.
create or replace function public.refund_late_order_v72(p_order uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.orders; due timestamptz; ok boolean;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  select * into o from public.orders where id = p_order;
  if o.id is null or o.customer_id <> auth.uid() then raise exception 'order_not_found'; end if;
  due := public._effective_due_v72(o.id);
  if o.status not in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT') then
    return jsonb_build_object('refunded', false, 'reason', 'not_refundable_status');
  end if;
  if due is null or due > now() then
    return jsonb_build_object('refunded', false, 'reason', 'not_late_yet', 'due_at', due);
  end if;
  ok := public._refund_late_order_v72(o.id, auth.uid(), 'customer_request');
  return jsonb_build_object('refunded', ok, 'reason', case when ok then 'refunded' else 'blocked' end, 'due_at', due);
end $$;
revoke all on function public.refund_late_order_v72(uuid) from public, anon;
grant execute on function public.refund_late_order_v72(uuid) to authenticated;

-- Traitement automatique des retards (appelé à l'ouverture des commandes et par l'administration ; idempotent).
create or replace function public.process_late_orders_v72() returns jsonb
language plpgsql security definer set search_path = public as $$
declare r record; n integer := 0;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  for r in
    select o.id from public.orders o
     where o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT')
       and o.delivery_due_at is not null and o.delivery_due_at < now()
     order by o.delivery_due_at limit 25
  loop
    if public._refund_late_order_v72(r.id, null, 'auto_late') then n := n + 1; end if;
  end loop;
  return jsonb_build_object('refunded', n);
end $$;
revoke all on function public.process_late_orders_v72() from public, anon;
grant execute on function public.process_late_orders_v72() to authenticated;

-- Tableau de bord : nombre de commandes en retard
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
    'gmv_minor', coalesce((select sum(total_minor) from public.orders where currency = 'HTG' and status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED','COMPLETED')), 0)::bigint,
    'gmv_usd_minor', coalesce((select sum(total_minor) from public.orders where currency = 'USD' and status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED','COMPLETED')), 0)::bigint,
    'commission_minor', coalesce((select sum(amount_minor) from public.platform_financial_entries where kind = 'commission' and currency = 'HTG'), 0)::bigint,
    'commission_usd_minor', coalesce((select sum(amount_minor) from public.platform_financial_entries where kind = 'commission' and currency = 'USD'), 0)::bigint,
    'fees_minor', coalesce((select sum(amount_minor) from public.wallet_transactions where kind = 'subscription_fee' and status = 'successful' and currency = 'HTG'), 0)::bigint,
    'fees_usd_minor', coalesce((select sum(amount_minor) from public.wallet_transactions where kind = 'subscription_fee' and status = 'successful' and currency = 'USD'), 0)::bigint,
    'payments_pending', (select count(*) from public.wallet_transactions where status in ('pending','processing')),
    'payments_failed', (select count(*) from public.wallet_transactions where status = 'failed'),
    'payments_refund_required', (select count(*) from public.wallet_transactions where status = 'review'),
    'topups_pending', (select count(*) from public.wallet_transactions where kind = 'topup' and status in ('pending','processing')),
    'withdrawals_pending', (select count(*) from public.wallet_transactions where kind = 'withdrawal' and status in ('pending','processing','review')),
    'refunds_to_execute', (select count(*) from public.refund_requests where status = 'to_execute'),
    'shops_active', (select count(*) from public.shops where status = 'active' and kind = 'pro'),
    'shops_pending', (select count(*) from public.shops where status = 'pending'),
    'shop_deletions_pending', (select count(*) from public.shops where deletion_review_status = 'pending_admin'),
    'kyc_pending', (select count(*) from public.identity_verifications where status in ('pending','needs_changes')),
    'bazar_active', (select count(*) from public.products where source = 'bazar' and status = 'published' and paid_until > now()),
    'couriers_approved', (select count(*) from public.courier_applications where status = 'approved'),
    'couriers_available', (select count(*) from public.courier_status where available),
    'jobs_open', (select count(*) from public.delivery_jobs where status = 'open'),
    'jobs_active', (select count(*) from public.delivery_jobs where status in ('assigned','picked_up')),
    'tickets_open', (select count(*) from public.support_tickets where status in ('OPEN','ASSIGNED')),
    'disputes_open', (select count(*) from public.order_disputes where status = 'open'),
    'reports_open', (select count(*) from public.reports where status = 'open'),
    'orders_late', (select count(*) from public.orders o where o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT') and o.delivery_due_at is not null and o.delivery_due_at < now()),
    'users_total', (select count(*) from public.profiles));
end $$;
grant execute on function public.admin_dashboard() to authenticated;

commit;

notify pgrst, 'reload schema';
