-- HAITIKET V23 — confirmation idempotente Plop Plop + rapprochement financier en lecture seule.
-- À appliquer après 0032 sur une base de staging sauvegardée.

-- Corrige la comparaison des recharges USD : le montant débité par Plop Plop est en HTG,
-- tandis que le crédit du portefeuille peut être en USD. Les deux montants sont distincts.
create or replace function public.confirm_wallet_topup(
  p_reference text,
  p_provider_transaction_id text,
  p_provider_amount_minor bigint
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  t public.wallet_transactions;
  expected_provider_minor bigint;
  provider_tx text := nullif(trim(coalesce(p_provider_transaction_id,'')), '');
begin
  if provider_tx is null then raise exception 'Identifiant de transaction Plop Plop obligatoire'; end if;
  if p_provider_amount_minor is null or p_provider_amount_minor <= 0 then raise exception 'Montant fournisseur invalide'; end if;

  select * into t from public.wallet_transactions
   where reference=p_reference and kind='topup' and provider='plopplop'
   for update;
  if t.id is null then raise exception 'Recharge Plop Plop inconnue'; end if;

  expected_provider_minor := coalesce((t.metadata->>'provider_amount_minor')::bigint, t.amount_minor);
  if t.metadata->>'payment_currency' is not null and t.metadata->>'payment_currency' <> 'HTG' then
    update public.wallet_transactions set status='review',updated_at=now(),
      metadata=metadata||jsonb_build_object('review_reason','unexpected_provider_currency') where id=t.id;
    return false;
  end if;
  if expected_provider_minor <> p_provider_amount_minor then
    if t.status <> 'successful' then
      update public.wallet_transactions set status='review',updated_at=now(),
        metadata=metadata||jsonb_build_object('review_reason','provider_amount_mismatch','received_provider_amount_minor',p_provider_amount_minor)
      where id=t.id;
    end if;
    return false;
  end if;

  -- Répétition strictement identique autorisée; toute différence exige une revue manuelle.
  if t.status='successful' then
    if t.provider_transaction_id=provider_tx then return true; end if;
    update public.wallet_transactions set status='review',updated_at=now(),
      metadata=metadata||jsonb_build_object('review_reason','successful_topup_reconfirmed_with_different_provider_id') where id=t.id;
    return false;
  end if;
  if t.status not in ('pending','processing') then raise exception 'Recharge non payable'; end if;

  update public.wallet_transactions set status='successful',provider_transaction_id=provider_tx,updated_at=now()
   where id=t.id;
  return true;
exception when unique_violation then
  raise exception 'Cet identifiant de transaction Plop Plop est déjà associé à une autre opération';
end $$;
revoke all on function public.confirm_wallet_topup(text,text,bigint) from public,anon,authenticated;
grant execute on function public.confirm_wallet_topup(text,text,bigint) to service_role;

-- Rapport agrégé et non mutatif : aucun solde n'est corrigé par cette fonction.
create or replace function public.run_financial_reconciliation_v23()
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  actor_id uuid := auth.uid();
  report jsonb;
  run_id uuid;
  issue_count bigint;
begin
  if actor_id is null or not public.admin_unlocked() then
    raise exception 'Accès refusé : déverrouillez la console administrateur';
  end if;

  select jsonb_build_object(
    'generated_at', now(),
    'wallet_by_currency', coalesce((
      select jsonb_agg(jsonb_build_object(
        'currency', x.currency,
        'successful_topups_minor', x.successful_topups,
        'successful_purchases_minor', x.successful_purchases,
        'successful_withdrawals_minor', x.successful_withdrawals,
        'successful_refunds_minor', x.successful_refunds,
        'pending_or_processing_count', x.pending_count,
        'review_count', x.review_count
      ) order by x.currency)
      from (
        select a.currency,
          coalesce(sum(t.amount_minor) filter(where t.kind='topup' and t.status='successful'),0) successful_topups,
          coalesce(sum(t.amount_minor) filter(where t.kind='purchase' and t.status='successful'),0) successful_purchases,
          coalesce(sum(t.amount_minor) filter(where t.kind='withdrawal' and t.status='successful'),0) successful_withdrawals,
          coalesce(sum(t.amount_minor) filter(where t.kind='refund' and t.status='successful'),0) successful_refunds,
          count(*) filter(where t.status in ('pending','processing')) pending_count,
          count(*) filter(where t.status='review') review_count
        from public.wallet_accounts a left join public.wallet_transactions t on t.account_id=a.id
        group by a.currency
      ) x
    ), '[]'::jsonb),
    'wallet_provider_status', coalesce((
      select jsonb_agg(jsonb_build_object('provider',p.provider,'status',p.status,'count',p.tx_count,'amount_minor',p.amount_minor)
        order by p.provider,p.status)
      from (select provider,status,count(*) tx_count,coalesce(sum(amount_minor),0) amount_minor
        from public.wallet_transactions group by provider,status) p
    ), '[]'::jsonb),
    'legacy_external_payment_attempts', jsonb_build_object(
      'successful_count',(select count(*) from public.payment_attempts where status='successful'),
      'pending_count',(select count(*) from public.payment_attempts where status in ('created','pending')),
      'refund_required_count',(select count(*) from public.payment_attempts where status='refund_required'),
      'legacy_provider_names',coalesce((select jsonb_agg(jsonb_build_object('provider',provider,'count',n)) from
        (select provider,count(*) n from public.payment_attempts group by provider) p),'[]'::jsonb)
    ),
    'refunds', jsonb_build_object(
      'waiting_execution',(select count(*) from public.refund_requests where status='to_execute'),
      'executed',(select count(*) from public.refund_requests where status='executed'),
      'failed',(select count(*) from public.refund_requests where status='failed')
    ),
    'checks', jsonb_build_object(
      'wallet_account_currency_mismatch',(select count(*) from public.wallet_transactions t join public.wallet_accounts a on a.id=t.account_id where t.user_id<>a.user_id or t.currency<>a.currency),
      'duplicate_provider_transaction_ids',(select count(*) from (select provider,provider_transaction_id from public.wallet_transactions where provider_transaction_id is not null group by provider,provider_transaction_id having count(*)>1) d),
      'successful_topups_missing_provider_id',(select count(*) from public.wallet_transactions where kind='topup' and provider='plopplop' and status='successful' and coalesce(provider_transaction_id,'')=''),
      'negative_wallet_accounts',(select count(*) from (select a.id,coalesce(sum(case when t.status='successful' then case when t.kind in ('purchase','subscription_fee','withdrawal') then -t.amount_minor-t.fee_minor else t.amount_minor-t.fee_minor end else 0 end),0) bal from public.wallet_accounts a left join public.wallet_transactions t on t.account_id=a.id group by a.id) b where bal<0),
      'open_disputes',(select count(*) from public.order_disputes where status='open'),
      'pending_over_30_minutes',(select count(*) from public.wallet_transactions where status in ('pending','processing') and created_at<now()-interval '30 minutes'),
      'review_transactions',(select count(*) from public.wallet_transactions where status='review')
    ),
    'mutations_performed', false
  ) into report;

  issue_count :=
    coalesce((report#>>'{checks,wallet_account_currency_mismatch}')::bigint,0) +
    coalesce((report#>>'{checks,duplicate_provider_transaction_ids}')::bigint,0) +
    coalesce((report#>>'{checks,successful_topups_missing_provider_id}')::bigint,0) +
    coalesce((report#>>'{checks,negative_wallet_accounts}')::bigint,0) +
    coalesce((report#>>'{checks,review_transactions}')::bigint,0);

  insert into public.finance_audit_runs(actor,summary,status)
    values(actor_id,report||jsonb_build_object('issue_count',issue_count),case when issue_count=0 then 'clean' else 'issues_found' end)
    returning id into run_id;
  insert into public.admin_audit_logs(actor,action,resource,resource_id,reason)
    values(actor_id,'financial_reconciliation_v23','finance_audit',run_id,'read-only; issue_count='||issue_count::text);
  return report||jsonb_build_object('audit_run_id',run_id,'issue_count',issue_count,'status',case when issue_count=0 then 'clean' else 'issues_found' end);
end $$;
revoke all on function public.run_financial_reconciliation_v23() from public,anon;
grant execute on function public.run_financial_reconciliation_v23() to authenticated;
comment on function public.run_financial_reconciliation_v23() is 'Rapport financier agrégé en lecture seule : portefeuilles, transactions Plop Plop, paiements historiques et remboursements.';
