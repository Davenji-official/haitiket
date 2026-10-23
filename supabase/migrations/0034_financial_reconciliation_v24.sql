-- HAITIKET V24 — évite de déclarer un rapprochement propre si des opérations restent à traiter.
-- À appliquer après 0033 sur staging sauvegardée.

create or replace function public.run_financial_reconciliation_v24()
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
  warning_count bigint;
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

  -- Operational warnings are not necessarily accounting errors, but must prevent a misleading 'clean' result.
  warning_count :=
    coalesce((report#>>'{checks,open_disputes}')::bigint,0) +
    coalesce((report#>>'{checks,pending_over_30_minutes}')::bigint,0) +
    coalesce((report#>>'{refunds,waiting_execution}')::bigint,0) +
    coalesce((report#>>'{refunds,failed}')::bigint,0) +
    coalesce((report#>>'{legacy_external_payment_attempts,pending_count}')::bigint,0) +
    coalesce((report#>>'{legacy_external_payment_attempts,refund_required_count}')::bigint,0);

  insert into public.finance_audit_runs(actor,summary,status)
    values(actor_id,report||jsonb_build_object('issue_count',issue_count,'warning_count',warning_count),
      case when issue_count=0 and warning_count=0 then 'clean' else 'issues_found' end)
    returning id into run_id;
  insert into public.admin_audit_logs(actor,action,resource,resource_id,reason)
    values(actor_id,'financial_reconciliation_v24','finance_audit',run_id,
      'read-only; issue_count='||issue_count::text||'; warning_count='||warning_count::text);
  return report||jsonb_build_object('audit_run_id',run_id,'issue_count',issue_count,'warning_count',warning_count,
    'status',case when issue_count=0 and warning_count=0 then 'clean' else 'issues_found' end);
end $$;
revoke all on function public.run_financial_reconciliation_v24() from public,anon;
grant execute on function public.run_financial_reconciliation_v24() to authenticated;
comment on function public.run_financial_reconciliation_v24() is 'Rapport financier agrégé en lecture seule : sépare anomalies comptables des avertissements opérationnels.';
