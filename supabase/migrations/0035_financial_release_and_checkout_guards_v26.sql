-- HAITIKET V26 — garde-fous de paiement et de libération des gains.
-- Cette migration ne déplace pas de fonds et ne confirme aucun paiement externe.

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

  select * into o from public.orders
   where id = p_order and customer_id = uid for update;
  if o.id is null then raise exception 'Commande introuvable ou non autorisée'; end if;

  select * into existing from public.wallet_transactions
   where reference = 'ORDER:' || p_order::text and user_id = uid for update;

  if existing.id is not null then
    if existing.kind <> 'purchase' or existing.amount_minor <> o.total_minor
       or existing.currency <> o.currency then
      raise exception 'Incohérence entre le débit enregistré et la commande : vérification administrative requise';
    end if;
    if existing.status = 'successful' then
      if o.status in ('PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP','IN_TRANSIT','DELIVERED','COMPLETED') then
        return jsonb_build_object('success',true,'already_paid',true,'currency',o.currency,
          'amount_minor',o.total_minor,'status',o.status);
      elsif o.status in ('CANCELLED','REFUNDED','DISPUTED') then
        raise exception 'Cette commande est % : aucun nouveau débit ne sera effectué', o.status;
      else
        raise exception 'Débit déjà enregistré mais statut de commande incohérent : contactez le support';
      end if;
    end if;
    raise exception 'Une tentative de paiement existe déjà avec le statut % : vérification requise', existing.status;
  end if;

  if o.status <> 'PENDING_PAYMENT' then raise exception 'Cette commande ne peut plus être payée'; end if;
  if o.reserved_until is null or o.reserved_until <= now() then
    perform public._cancel_order(p_order, uid, 'reservation_expired_before_wallet_payment');
    raise exception 'La réservation a expiré. Recréez votre commande.';
  end if;
  if o.total_minor <= 0 or o.currency not in ('HTG','USD') then
    raise exception 'Montant ou devise de commande invalide';
  end if;

  select s.owner_id into shop_owner from public.shops s where s.id = o.shop_id;
  if shop_owner is null or shop_owner = uid then raise exception 'Boutique invalide'; end if;

  insert into public.wallet_accounts(user_id, currency) values(uid, o.currency)
    on conflict(user_id, currency) do nothing;
  select id into aid from public.wallet_accounts where user_id = uid and currency = o.currency for update;
  if aid is null then raise exception 'Portefeuille % indisponible', o.currency; end if;

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

  insert into public.wallet_accounts(user_id,currency) values(shop_owner,o.currency)
    on conflict(user_id,currency) do nothing;
  if o.seller_net_minor > 0 then
    insert into public.wallet_transactions(account_id,user_id,reference,kind,status,amount_minor,currency,provider,metadata)
    select a.id,shop_owner,'SELLER_ORDER:' || p_order::text,'seller_credit','pending',o.seller_net_minor,o.currency,'internal',
      jsonb_build_object('order_id',p_order,'release_rule','delivery_or_handover_confirmation')
    from public.wallet_accounts a where a.user_id=shop_owner and a.currency=o.currency
    on conflict(reference) do nothing;
  end if;

  insert into public.platform_financial_entries(order_id,kind,amount_minor,currency)
  values(p_order,'commission',o.commission_minor,o.currency) on conflict(order_id,kind) do nothing;

  update public.orders set status='PAID', reserved_until=null where id=p_order;
  insert into public.order_status_events(order_id,from_status,to_status,actor,reason)
  values(p_order,'PENDING_PAYMENT','PAID',uid,'paid_from_internal_wallet');

  return jsonb_build_object('success',true,'already_paid',false,'currency',o.currency,
    'amount_minor',o.total_minor,'status','PAID');
end $$;
revoke all on function public.pay_order_from_wallet(uuid) from public, anon;
grant execute on function public.pay_order_from_wallet(uuid) to authenticated;

-- Ne libérer aucun revenu si un litige ou un remboursement est encore actif,
-- même si un autre chemin de statut tente de marquer la commande livrée/terminée.
create or replace function public._release_order_wallet_earnings() returns trigger
language plpgsql security definer set search_path = public as $$
declare j public.delivery_jobs;
begin
  if new.status in ('DELIVERED','COMPLETED') and old.status is distinct from new.status then
    -- Une commande qui sort directement d'un statut DISPUTED exige la libération administrative explicite.
    if old.status='DISPUTED' then return new; end if;
    if exists(select 1 from public.order_disputes d
      where d.order_id=new.id and d.status in ('open','resolved_refund')) then
      return new;
    end if;
    if exists(select 1 from public.refund_requests r
      where r.order_id=new.id and r.status in ('to_execute','executed')) then
      return new;
    end if;

    update public.wallet_transactions
       set status='successful', updated_at=now()
     where reference='SELLER_ORDER:' || new.id::text and status='pending';

    if new.delivery_mode='delivery' then
      select * into j from public.delivery_jobs
       where order_id=new.id and status='delivered'
       order by assigned_at desc nulls last limit 1;
      if j.id is not null and j.courier_id is not null and j.pay_minor > 0 then
        insert into public.wallet_accounts(user_id,currency) values(j.courier_id,j.currency)
          on conflict(user_id,currency) do nothing;
        insert into public.wallet_transactions(account_id,user_id,reference,kind,status,amount_minor,currency,provider,metadata)
        select a.id,j.courier_id,'COURIER_ORDER:' || new.id::text,'courier_credit','successful',
          j.pay_minor,j.currency,'internal',
          jsonb_build_object('order_id',new.id,'job_id',j.id,'release_rule','delivery_confirmed')
        from public.wallet_accounts a where a.user_id=j.courier_id and a.currency=j.currency
        on conflict(reference) do nothing;
      end if;
    end if;
  end if;
  return new;
end $$;
revoke all on function public._release_order_wallet_earnings() from public, anon, authenticated;

-- Rapport en lecture seule des nouvelles incohérences de libération.
create or replace function public.run_financial_guard_audit_v26() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_actor uuid := auth.uid(); v_summary jsonb;
begin
  if v_actor is null or not public.admin_unlocked() then
    raise exception 'Accès refusé : déverrouillez la console administrateur';
  end if;
  select jsonb_build_object(
    'generated_at',now(),
    'successful_order_debit_status_mismatch',(
      select count(*) from public.wallet_transactions t
      join public.orders o on t.reference='ORDER:'||o.id::text
      where t.kind='purchase' and t.status='successful'
        and (t.amount_minor<>o.total_minor or t.currency<>o.currency
          or o.status in ('PENDING_PAYMENT','CANCELLED'))
    ),
    'seller_earnings_released_during_open_dispute',(
      select count(*) from public.wallet_transactions t
      join public.order_disputes d on t.reference='SELLER_ORDER:'||d.order_id::text
      where t.kind='seller_credit' and t.status='successful' and d.status='open'
    ),
    'courier_earnings_released_during_open_dispute',(
      select count(*) from public.wallet_transactions t
      join public.order_disputes d on t.reference='COURIER_ORDER:'||d.order_id::text
      where t.kind='courier_credit' and t.status='successful' and d.status='open'
    ),
    'seller_earnings_pending_after_delivery_without_active_hold',(
      select count(*) from public.wallet_transactions t
      join public.orders o on t.reference='SELLER_ORDER:'||o.id::text
      where t.kind='seller_credit' and t.status='pending' and o.status in ('DELIVERED','COMPLETED')
        and not exists(select 1 from public.order_disputes d where d.order_id=o.id and d.status in ('open','resolved_refund'))
        and not exists(select 1 from public.refund_requests r where r.order_id=o.id and r.status in ('to_execute','executed'))
    )
  ) into v_summary;
  insert into public.admin_audit_logs(actor,action,resource,resource_id,reason)
  values(v_actor,'financial_guard_audit_v26','finance_audit',null,'read-only; summary='||left(v_summary::text,1500));
  return v_summary || jsonb_build_object('status',case when
    coalesce((v_summary->>'successful_order_debit_status_mismatch')::bigint,0)+
    coalesce((v_summary->>'seller_earnings_released_during_open_dispute')::bigint,0)+
    coalesce((v_summary->>'courier_earnings_released_during_open_dispute')::bigint,0)+
    coalesce((v_summary->>'seller_earnings_pending_after_delivery_without_active_hold')::bigint,0)=0
    then 'clean' else 'issues_found' end);
end $$;
revoke all on function public.run_financial_guard_audit_v26() from public, anon;
grant execute on function public.run_financial_guard_audit_v26() to authenticated;

comment on function public.pay_order_from_wallet(uuid) is
'Paiement interne atomique; bloque les nouvelles tentatives incohérentes et ne débite jamais une commande annulée ou remboursée.';
comment on function public._release_order_wallet_earnings() is
'Libère les revenus après remise confirmée uniquement en absence de litige ou remboursement actif.';
comment on function public.run_financial_guard_audit_v26() is
'Audit financier en lecture seule des incohérences de paiement et des gains libérés pendant un litige.';
