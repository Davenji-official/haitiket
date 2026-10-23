-- HAITIKET V21 — intégrité financière, litiges et audit des portefeuilles.
-- Les fonctions ci-dessous sont réservées à un administrateur authentifié et déverrouillé.
-- Aucune opération financière n'est exécutée automatiquement par l'audit.

create or replace function public.run_wallet_integrity_audit_v21()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_summary jsonb;
  v_issues bigint;
  v_run uuid;
begin
  if v_actor is null or not public.admin_unlocked() then
    raise exception 'Accès refusé : déverrouillez la console administrateur';
  end if;

  select jsonb_build_object(
    'generated_at', now(),
    'wallet_account_currency_mismatches', (
      select count(*) from public.wallet_transactions t
      join public.wallet_accounts a on a.id=t.account_id
      where t.user_id <> a.user_id or t.currency <> a.currency
    ),
    'successful_internal_orders_without_debit', (
      select count(*) from public.orders o
      where o.status not in ('PENDING_PAYMENT','PAYMENT_PROCESSING','CANCELLED','REFUNDED')
        and not exists (select 1 from public.payment_attempts pa where pa.order_id=o.id and pa.status='successful')
        and not exists (
          select 1 from public.wallet_transactions t
          where t.reference='ORDER:'||o.id::text and t.user_id=o.customer_id
            and t.kind='purchase' and t.status='successful'
            and t.amount_minor=o.total_minor and t.currency=o.currency
        )
    ),
    'order_debits_without_matching_order', (
      select count(*) from public.wallet_transactions t
      where t.reference like 'ORDER:%' and t.kind='purchase' and t.status='successful'
        and not exists (
          select 1 from public.orders o where t.reference='ORDER:'||o.id::text
            and o.customer_id=t.user_id and o.total_minor=t.amount_minor and o.currency=t.currency
        )
    ),
    'negative_wallet_balances', (
      select count(*) from (
        select a.id,
          coalesce(sum(case when t.status='successful' then
            case when t.kind in ('withdrawal','purchase','subscription_fee')
              then -t.amount_minor-t.fee_minor else t.amount_minor-t.fee_minor end
            else 0 end),0) as balance
        from public.wallet_accounts a left join public.wallet_transactions t on t.account_id=a.id
        group by a.id
      ) b where b.balance < 0
    ),
    'seller_earnings_pending_after_resolved_delivery', (
      select count(*) from public.wallet_transactions t
      join public.orders o on t.reference='SELLER_ORDER:'||o.id::text
      where t.kind='seller_credit' and t.status='pending'
        and o.status in ('DELIVERED','COMPLETED')
        and not exists (select 1 from public.order_disputes d where d.order_id=o.id and d.status='open')
        and not exists (select 1 from public.order_disputes d where d.order_id=o.id and d.status='resolved_refund')
    ),
    'courier_credits_missing_after_delivery', (
      select count(*) from public.orders o
      join public.delivery_jobs j on j.order_id=o.id and j.status='delivered'
      where o.status in ('DELIVERED','COMPLETED') and j.courier_id is not null and j.pay_minor>0
        and not exists (select 1 from public.wallet_transactions t
          where t.reference='COURIER_ORDER:'||o.id::text and t.user_id=j.courier_id
            and t.kind='courier_credit' and t.currency=j.currency and t.amount_minor=j.pay_minor
            and t.status in ('successful','pending'))
    ),
    'open_disputes', (select count(*) from public.order_disputes where status='open'),
    'refunds_waiting_manual_execution', (select count(*) from public.refund_requests where status='to_execute'),
    'wallet_transactions_review', (select count(*) from public.wallet_transactions where status='review'),
    'wallet_transactions_pending_over_30m', (select count(*) from public.wallet_transactions where status in ('pending','processing') and created_at < now()-interval '30 minutes')
  ) into v_summary;

  v_issues :=
    coalesce((v_summary->>'wallet_account_currency_mismatches')::bigint,0) +
    coalesce((v_summary->>'successful_internal_orders_without_debit')::bigint,0) +
    coalesce((v_summary->>'order_debits_without_matching_order')::bigint,0) +
    coalesce((v_summary->>'negative_wallet_balances')::bigint,0) +
    coalesce((v_summary->>'seller_earnings_pending_after_resolved_delivery')::bigint,0) +
    coalesce((v_summary->>'courier_credits_missing_after_delivery')::bigint,0) +
    coalesce((v_summary->>'wallet_transactions_review')::bigint,0);

  insert into public.finance_audit_runs(actor,summary,status)
  values(v_actor, v_summary, case when v_issues=0 then 'clean' else 'issues_found' end)
  returning id into v_run;

  insert into public.admin_audit_logs(actor,action,resource,resource_id,reason)
  values(v_actor,'wallet_integrity_audit_v21','finance_audit',v_run,
    'issues='||v_issues::text||'; read-only; pending/disputes are reported separately');

  return v_summary || jsonb_build_object('audit_run_id',v_run,'issue_count',v_issues,'status',case when v_issues=0 then 'clean' else 'issues_found' end);
end $$;
revoke all on function public.run_wallet_integrity_audit_v21() from public, anon;
grant execute on function public.run_wallet_integrity_audit_v21() to authenticated;

-- Après résolution explicite d'un litige sans remboursement, un administrateur peut
-- libérer les gains restés en attente. Aucune libération pendant un litige ouvert.
create or replace function public.admin_release_disputed_order_earnings(p_order uuid, p_note text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  o public.orders;
  j public.delivery_jobs;
  own uuid;
  seller_released bigint := 0;
  courier_created bigint := 0;
begin
  if auth.uid() is null or not public.admin_unlocked() then
    raise exception 'Accès refusé : déverrouillez la console administrateur';
  end if;
  if coalesce(length(trim(p_note)),0) < 5 then raise exception 'Une justification de 5 caractères minimum est requise'; end if;

  select * into o from public.orders where id=p_order for update;
  if o.id is null then raise exception 'Commande introuvable'; end if;
  if o.status not in ('DELIVERED','COMPLETED') then raise exception 'La remise doit être confirmée avant la libération'; end if;
  if exists(select 1 from public.order_disputes d where d.order_id=o.id and d.status='open') then
    raise exception 'Libération interdite : un litige est encore ouvert';
  end if;
  if not exists(select 1 from public.order_disputes d where d.order_id=o.id and d.status='resolved_no_refund') then
    raise exception 'Cette commande ne possède pas de litige résolu sans remboursement';
  end if;
  if exists(select 1 from public.order_disputes d where d.order_id=o.id and d.status='resolved_refund')
     or exists(select 1 from public.refund_requests r where r.order_id=o.id and r.status in ('to_execute','executed')) then
    raise exception 'Libération interdite : un remboursement est demandé ou exécuté';
  end if;

  update public.wallet_transactions set status='successful',updated_at=now(),
    metadata=metadata||jsonb_build_object('released_after_dispute',true,'admin_note',left(trim(p_note),300))
  where reference='SELLER_ORDER:'||o.id::text and status='pending';
  get diagnostics seller_released = row_count;

  if o.delivery_mode='delivery' then
    select * into j from public.delivery_jobs where order_id=o.id and status='delivered'
      order by assigned_at desc nulls last limit 1;
    if j.id is null or j.courier_id is null or j.pay_minor<=0 then
      raise exception 'Mission livrée ou rémunération du coursier introuvable';
    end if;
    insert into public.wallet_accounts(user_id,currency) values(j.courier_id,j.currency)
      on conflict(user_id,currency) do nothing;
    insert into public.wallet_transactions(account_id,user_id,reference,kind,status,amount_minor,currency,provider,metadata)
    select a.id,j.courier_id,'COURIER_ORDER:'||o.id::text,'courier_credit','successful',j.pay_minor,j.currency,'internal',
      jsonb_build_object('order_id',o.id,'job_id',j.id,'release_rule','admin_release_after_dispute','admin_note',left(trim(p_note),300))
    from public.wallet_accounts a where a.user_id=j.courier_id and a.currency=j.currency
    on conflict(reference) do nothing;
    get diagnostics courier_created = row_count;
  end if;

  insert into public.admin_audit_logs(actor,action,resource,resource_id,reason)
  values(auth.uid(),'release_disputed_order_earnings','order',o.id,left(trim(p_note),300));
  return jsonb_build_object('success',true,'order_id',o.id,'seller_transactions_released',seller_released,
    'courier_credit_created',courier_created,'note',left(trim(p_note),300));
end $$;
revoke all on function public.admin_release_disputed_order_earnings(uuid,text) from public, anon;
grant execute on function public.admin_release_disputed_order_earnings(uuid,text) to authenticated;

comment on function public.run_wallet_integrity_audit_v21() is 'Audit en lecture seule des soldes, débits de commande, gains différés et litiges; aucun mouvement financier créé.';
comment on function public.admin_release_disputed_order_earnings(uuid,text) is 'Libération manuelle idempotente des gains après remise confirmée et litige résolu sans remboursement.';
