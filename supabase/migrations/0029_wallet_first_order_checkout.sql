-- HAITIKET V19 — paiement des commandes depuis le portefeuille interne.
-- Plop Plop reste réservé aux recharges/retraits externes. Aucun appel fournisseur ici.

create table if not exists public.platform_financial_entries (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete restrict,
  kind text not null check (kind in ('commission')),
  amount_minor bigint not null check (amount_minor >= 0),
  currency text not null check (currency in ('HTG','USD')),
  created_at timestamptz not null default now(),
  unique(order_id, kind)
);
alter table public.platform_financial_entries enable row level security;
revoke all on public.platform_financial_entries from anon, authenticated;

create or replace function public.pay_order_from_wallet(p_order uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  o public.orders;
  shop_owner uuid;
  aid uuid;
  bal bigint;
  existing public.wallet_transactions;
begin
  if uid is null then raise exception 'Connexion requise'; end if;

  select * into o from public.orders where id = p_order and customer_id = uid for update;
  if o.id is null then raise exception 'Commande introuvable ou non autorisée'; end if;

  select * into existing from public.wallet_transactions
   where reference = 'ORDER:' || p_order::text and user_id = uid;
  if existing.id is not null then
    if existing.status = 'successful' and o.status <> 'PENDING_PAYMENT' then
      return jsonb_build_object('success', true, 'already_paid', true, 'currency', o.currency, 'amount_minor', o.total_minor);
    end if;
    if existing.status <> 'successful' then raise exception 'Paiement existant à vérifier auprès du support'; end if;
  end if;
  if o.status <> 'PENDING_PAYMENT' then raise exception 'Cette commande ne peut plus être payée'; end if;
  if o.reserved_until is null or o.reserved_until <= now() then
    perform public._cancel_order(p_order, uid, 'reservation_expired_before_wallet_payment');
    raise exception 'La réservation a expiré. Recréez votre commande.';
  end if;
  if o.total_minor <= 0 or o.currency not in ('HTG','USD') then raise exception 'Montant ou devise de commande invalide'; end if;

  select s.owner_id into shop_owner from public.shops s where s.id = o.shop_id;
  if shop_owner is null or shop_owner = uid then raise exception 'Boutique invalide'; end if;

  insert into public.wallet_accounts(user_id, currency) values(uid, o.currency)
    on conflict(user_id, currency) do nothing;
  select id into aid from public.wallet_accounts where user_id = uid and currency = o.currency for update;
  if aid is null then raise exception 'Portefeuille % indisponible', o.currency; end if;

  -- Le verrou de compte sérialise les débits. Les transactions pending/processing ne comptent pas.
  select coalesce(sum(case when status='successful' then
      case when kind in ('withdrawal','purchase','subscription_fee') then -amount_minor-fee_minor
           else amount_minor-fee_minor end else 0 end),0)
    into bal from public.wallet_transactions where account_id = aid;
  if bal < o.total_minor then
    raise exception 'Solde % insuffisant : disponible %, requis % (en centimes)', o.currency, bal, o.total_minor;
  end if;

  insert into public.wallet_transactions(account_id,user_id,reference,kind,status,amount_minor,currency,provider,metadata)
  values(aid,uid,'ORDER:' || p_order::text,'purchase','successful',o.total_minor,o.currency,'internal',
         jsonb_build_object('order_id',p_order,'shop_id',o.shop_id,'items_minor',o.items_minor,'delivery_minor',o.delivery_minor));

  -- Revenus vendeur non dépensables tant que la remise n'est pas confirmée.
  insert into public.wallet_accounts(user_id,currency) values(shop_owner,o.currency)
    on conflict(user_id,currency) do nothing;
  if o.seller_net_minor > 0 then
    insert into public.wallet_transactions(account_id,user_id,reference,kind,status,amount_minor,currency,provider,metadata)
    select a.id, shop_owner, 'SELLER_ORDER:' || p_order::text, 'seller_credit', 'pending', o.seller_net_minor, o.currency, 'internal',
           jsonb_build_object('order_id',p_order,'release_rule','delivery_or_handover_confirmation')
      from public.wallet_accounts a where a.user_id=shop_owner and a.currency=o.currency
    on conflict(reference) do nothing;
  end if;

  insert into public.platform_financial_entries(order_id,kind,amount_minor,currency)
  values(p_order,'commission',o.commission_minor,o.currency) on conflict(order_id,kind) do nothing;

  update public.orders set status='PAID', reserved_until=null where id=p_order;
  insert into public.order_status_events(order_id,from_status,to_status,actor,reason)
  values(p_order,'PENDING_PAYMENT','PAID',uid,'paid_from_internal_wallet');

  return jsonb_build_object('success',true,'already_paid',false,'currency',o.currency,'amount_minor',o.total_minor,'status','PAID');
end $$;
revoke all on function public.pay_order_from_wallet(uuid) from public, anon;
grant execute on function public.pay_order_from_wallet(uuid) to authenticated;

-- Les revenus vendeur restent non disponibles jusqu'à confirmation de remise.
create or replace function public._release_order_wallet_earnings() returns trigger
language plpgsql security definer set search_path = public as $$
declare j public.delivery_jobs;
begin
  if new.status in ('DELIVERED','COMPLETED') and old.status is distinct from new.status then
    -- Si la commande sort d'un litige, ne libère jamais automatiquement les fonds.
    if old.status='DISPUTED' then return new; end if;
    update public.wallet_transactions
       set status='successful', updated_at=now()
     where reference='SELLER_ORDER:' || new.id::text and status='pending';

    -- Le revenu coursier n'est créé qu'au moment de la remise confirmée.
    if new.delivery_mode='delivery' then
      select * into j from public.delivery_jobs where order_id=new.id and status='delivered' order by assigned_at desc nulls last limit 1;
      if j.id is not null and j.courier_id is not null and j.pay_minor > 0 then
        insert into public.wallet_accounts(user_id,currency) values(j.courier_id,j.currency)
          on conflict(user_id,currency) do nothing;
        insert into public.wallet_transactions(account_id,user_id,reference,kind,status,amount_minor,currency,provider,metadata)
        select a.id,j.courier_id,'COURIER_ORDER:' || new.id::text,'courier_credit','successful',j.pay_minor,j.currency,'internal',
               jsonb_build_object('order_id',new.id,'job_id',j.id,'release_rule','delivery_confirmed')
          from public.wallet_accounts a where a.user_id=j.courier_id and a.currency=j.currency
        on conflict(reference) do nothing;
      end if;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists release_order_wallet_earnings on public.orders;
create trigger release_order_wallet_earnings after update of status on public.orders
for each row execute function public._release_order_wallet_earnings();
revoke all on function public._release_order_wallet_earnings() from public, anon, authenticated;

comment on function public.pay_order_from_wallet(uuid) is 'Débite le portefeuille interne de même devise et marque la commande payée de manière atomique et idempotente.';


-- Ne pas autoriser la confirmation de livraison d'une commande bloquée en litige.
create or replace function public.confirm_delivery(p_job uuid, p_pin text) returns boolean
language plpgsql security definer set search_path = public as $$
declare j public.delivery_jobs; pin text; order_status text;
begin
  select * into j from public.delivery_jobs where id=p_job and courier_id=auth.uid() for update;
  if j.id is null then raise exception 'Mission introuvable'; end if;
  if j.status <> 'picked_up' then raise exception 'Remise non attendue'; end if;
  select status into order_status from public.orders where id=j.order_id for update;
  if order_status='DISPUTED' then raise exception 'Commande bloquée par un litige : contactez le support'; end if;
  if order_status is distinct from 'IN_TRANSIT' then raise exception 'Statut de commande incompatible avec la remise'; end if;
  if j.failed >= 5 then raise exception 'Trop de tentatives : contactez le support'; end if;
  select op.pin into pin from public.order_pins op where op.order_id=j.order_id;
  if pin=trim(p_pin) then
    update public.delivery_jobs set status='delivered',failed=0 where id=p_job;
    perform public._set_order_status(j.order_id,'DELIVERED',auth.uid(),'delivery_confirmed');
    return true;
  end if;
  update public.delivery_jobs set failed=failed+1 where id=p_job;
  return false;
end $$;
grant execute on function public.confirm_delivery(uuid,text) to authenticated;


-- Retire Bazik de la configuration : Plop Plop reste le prestataire externe choisi.
insert into public.platform_settings(key,value) values('payment_provider','plopplop')
on conflict(key) do update set value='plopplop',updated_at=now();

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
    'delivery_offer_expiry_minutes'
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
    if p_key='commission_bps' and v::integer > 10000 then raise exception 'La commission ne peut dépasser 100 %%'; end if;
  end if;
  insert into public.platform_settings(key,value) values(p_key,v)
  on conflict(key) do update set value=excluded.value,updated_at=now();
  insert into public.admin_audit_logs(actor,action,resource,reason) values(auth.uid(),'set_setting',p_key,left(v,100));
end $$;
grant execute on function public.admin_set_setting(text,text) to authenticated;
