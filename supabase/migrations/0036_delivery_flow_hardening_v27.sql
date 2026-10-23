-- HAITIKET V27 — sécurisation du parcours collecte/livraison.
-- Aucun mouvement de fonds n'est créé par cette migration.

-- Le supplément de livraison est réglé dans le portefeuille interne lors de la
-- sélection de l'offre (migration 0030). Ne plus dépendre uniquement de l'ancien
-- payment_attempts/purpose=delivery_fee, qui appartient au parcours historique.
create or replace function public.confirm_pickup(p_job uuid, p_pin text) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  j public.delivery_jobs;
  o public.orders;
  pin_value text;
  has_verified_payment boolean := false;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  select * into j from public.delivery_jobs where id=p_job and courier_id=auth.uid() for update;
  if j.id is null then raise exception 'Mission introuvable ou non attribuée à ce coursier'; end if;
  if j.status <> 'assigned' then raise exception 'Collecte non attendue'; end if;
  if j.failed >= 5 then raise exception 'Trop de tentatives : contactez le support'; end if;

  select * into o from public.orders where id=j.order_id for update;
  if o.id is null then raise exception 'Commande introuvable'; end if;
  if o.delivery_mode <> 'delivery' or o.status <> 'READY_FOR_PICKUP' then
    raise exception 'La commande doit être prête à être collectée';
  end if;
  if j.currency <> o.currency or j.pay_minor <> o.delivery_minor then
    raise exception 'Incohérence entre l’offre de livraison et la commande : contactez le support';
  end if;
  if exists(select 1 from public.order_disputes d where d.order_id=o.id and d.status='open') then
    raise exception 'Collecte bloquée : un litige est ouvert';
  end if;
  if exists(select 1 from public.refund_requests r where r.order_id=o.id and r.status in ('to_execute','executed')) then
    raise exception 'Collecte bloquée : un remboursement est en cours ou a été exécuté';
  end if;

  select exists(
    select 1 from public.wallet_transactions t
    where t.reference='ORDER:'||o.id::text and t.user_id=o.customer_id
      and t.kind='purchase' and t.status='successful'
      and t.amount_minor=o.total_minor and t.currency=o.currency
  ) or exists(
    select 1 from public.payment_attempts a
    where a.order_id=o.id and a.status='successful'
  ) into has_verified_payment;
  if not has_verified_payment then
    raise exception 'Paiement vérifié introuvable : la collecte est bloquée';
  end if;

  if j.pickup_pin=trim(coalesce(p_pin,'')) then
    update public.delivery_jobs set status='picked_up',failed=0 where id=p_job;
    perform public._set_order_status(j.order_id,'IN_TRANSIT',auth.uid(),'pickup_confirmed_v27');
    return true;
  end if;
  update public.delivery_jobs set failed=failed+1 where id=p_job;
  return false;
end $$;
revoke all on function public.confirm_pickup(uuid,text) from public, anon;
grant execute on function public.confirm_pickup(uuid,text) to authenticated;

create or replace function public.confirm_delivery(p_job uuid, p_pin text) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  j public.delivery_jobs;
  o public.orders;
  pin_value text;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  select * into j from public.delivery_jobs where id=p_job and courier_id=auth.uid() for update;
  if j.id is null then raise exception 'Mission introuvable ou non attribuée à ce coursier'; end if;
  if j.status <> 'picked_up' then raise exception 'Remise non attendue'; end if;
  if j.failed >= 5 then raise exception 'Trop de tentatives : contactez le support'; end if;

  select * into o from public.orders where id=j.order_id for update;
  if o.id is null then raise exception 'Commande introuvable'; end if;
  if o.status='DISPUTED' then raise exception 'Commande bloquée par un litige : contactez le support'; end if;
  if o.status <> 'IN_TRANSIT' then raise exception 'Statut de commande incompatible avec la remise'; end if;
  if exists(select 1 from public.order_disputes d where d.order_id=o.id and d.status='open') then
    raise exception 'Remise bloquée : un litige est ouvert';
  end if;
  if exists(select 1 from public.refund_requests r where r.order_id=o.id and r.status in ('to_execute','executed')) then
    raise exception 'Remise bloquée : un remboursement est en cours ou a été exécuté';
  end if;

  select op.pin into pin_value from public.order_pins op where op.order_id=j.order_id;
  if pin_value=trim(coalesce(p_pin,'')) then
    update public.delivery_jobs set status='delivered',failed=0 where id=p_job;
    perform public._set_order_status(j.order_id,'DELIVERED',auth.uid(),'delivery_confirmed_v27');
    return true;
  end if;
  update public.delivery_jobs set failed=failed+1 where id=p_job;
  return false;
end $$;
revoke all on function public.confirm_delivery(uuid,text) from public, anon;
grant execute on function public.confirm_delivery(uuid,text) to authenticated;

-- Audit en lecture seule du cycle livraison/offres : il ne modifie ni statuts,
-- ni soldes, ni rémunérations.
create or replace function public.run_delivery_flow_audit_v27() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_actor uuid := auth.uid();
  v_summary jsonb;
  v_issues bigint;
  v_warnings bigint;
begin
  if v_actor is null or not public.admin_unlocked() then
    raise exception 'Accès refusé : déverrouillez la console administrateur';
  end if;

  select jsonb_build_object(
    'generated_at', now(),
    'assigned_jobs_missing_courier', (
      select count(*) from public.delivery_jobs j where j.status in ('assigned','picked_up') and j.courier_id is null
    ),
    'picked_up_jobs_wrong_order_status', (
      select count(*) from public.delivery_jobs j join public.orders o on o.id=j.order_id
      where j.status='picked_up' and o.status<>'IN_TRANSIT'
    ),
    'delivered_jobs_wrong_order_status', (
      select count(*) from public.delivery_jobs j join public.orders o on o.id=j.order_id
      where j.status='delivered' and o.status not in ('DELIVERED','COMPLETED','DISPUTED','REFUNDED')
    ),
    'selected_offer_job_mismatch', (
      select count(*) from public.delivery_job_offers f join public.delivery_jobs j on j.id=f.job_id
      where f.status='selected' and (j.status not in ('assigned','picked_up','delivered')
        or j.courier_id is distinct from f.courier_id or j.pay_minor<>f.amount_minor or j.currency<>f.currency)
    ),
    'expired_pending_offers', (
      select count(*) from public.delivery_job_offers where status='pending' and expires_at<=now()
    ),
    'ready_delivery_orders_without_job', (
      select count(*) from public.orders o where o.delivery_mode='delivery'
        and o.status in ('READY_FOR_PICKUP','IN_TRANSIT','DELIVERED','COMPLETED')
        and not exists(select 1 from public.delivery_jobs j where j.order_id=o.id)
    ),
    'delivery_jobs_with_currency_or_fee_mismatch', (
      select count(*) from public.delivery_jobs j join public.orders o on o.id=j.order_id
      where j.status in ('assigned','picked_up','delivered')
        and (j.currency<>o.currency or j.pay_minor<>o.delivery_minor)
    ),
    'open_delivery_disputes', (
      select count(*) from public.order_disputes d join public.orders o on o.id=d.order_id
      where d.status='open' and o.delivery_mode='delivery'
    )
  ) into v_summary;

  v_issues :=
    coalesce((v_summary->>'assigned_jobs_missing_courier')::bigint,0) +
    coalesce((v_summary->>'picked_up_jobs_wrong_order_status')::bigint,0) +
    coalesce((v_summary->>'delivered_jobs_wrong_order_status')::bigint,0) +
    coalesce((v_summary->>'selected_offer_job_mismatch')::bigint,0) +
    coalesce((v_summary->>'ready_delivery_orders_without_job')::bigint,0) +
    coalesce((v_summary->>'delivery_jobs_with_currency_or_fee_mismatch')::bigint,0);

  v_warnings :=
    coalesce((v_summary->>'expired_pending_offers')::bigint,0) +
    coalesce((v_summary->>'open_delivery_disputes')::bigint,0);

  insert into public.admin_audit_logs(actor,action,resource,resource_id,reason)
  values(v_actor,'delivery_flow_audit_v27','delivery_audit',null,
    'issues='||v_issues::text||'; warnings='||v_warnings::text||'; read-only');

  return v_summary || jsonb_build_object('issue_count',v_issues,'warning_count',v_warnings,
    'status',case when v_issues>0 then 'issues_found' when v_warnings>0 then 'warnings' else 'clean' end,
    'note','Audit en lecture seule : aucune correction automatique ni mouvement financier.');
end $$;
revoke all on function public.run_delivery_flow_audit_v27() from public, anon;
grant execute on function public.run_delivery_flow_audit_v27() to authenticated;

comment on function public.confirm_pickup(uuid,text) is 'V27: collecte uniquement si commande prête, paiement vérifié, frais/devise cohérents et aucun litige/remboursement actif.';
comment on function public.confirm_delivery(uuid,text) is 'V27: remise uniquement depuis IN_TRANSIT, avec PIN client et sans litige/remboursement actif.';
comment on function public.run_delivery_flow_audit_v27() is 'V27: audit de livraison en lecture seule réservé à l’administration déverrouillée.';
