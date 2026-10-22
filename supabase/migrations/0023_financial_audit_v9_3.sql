-- HAITIKET V9.3 : audit financier en lecture seule.
-- Cette migration n'émet aucun crédit/débit et ne corrige pas automatiquement les écarts.
-- Pré-requis : migrations 0001 à 0022 déjà appliquées.

create table if not exists public.finance_audit_runs (
  id uuid primary key default gen_random_uuid(),
  actor uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  summary jsonb not null,
  status text not null check (status in ('clean','issues_found'))
);

alter table public.finance_audit_runs enable row level security;
drop policy if exists finance_audit_runs_admin_read on public.finance_audit_runs;
create policy finance_audit_runs_admin_read
  on public.finance_audit_runs for select to authenticated
  using (public.admin_unlocked());
revoke insert, update, delete on public.finance_audit_runs from anon, authenticated;

create or replace function public.run_financial_audit()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_summary jsonb;
  v_issue_count bigint := 0;
  v_run_id uuid;
begin
  if v_actor is null or not public.admin_unlocked() then
    raise exception 'Accès refusé : déverrouillez la console administrateur';
  end if;

  -- Vue d'ensemble, sans renvoyer de coordonnées, numéros de téléphone ou données KYC.
  select jsonb_build_object(
    'generated_at', now(),
    'wallet_transactions', (select count(*) from public.wallet_transactions),
    'wallet_pending_or_processing', (select count(*) from public.wallet_transactions where status in ('pending','processing')),
    'wallet_review', (select count(*) from public.wallet_transactions where status='review'),
    'payment_attempts_successful', (select count(*) from public.payment_attempts where status='successful'),
    'refunds_to_execute', (select count(*) from public.refund_requests where status='to_execute'),
    'duplicate_provider_transaction_ids', (
      select count(*) from (
        select provider, provider_transaction_id
        from public.wallet_transactions
        where provider_transaction_id is not null
        group by provider, provider_transaction_id having count(*) > 1
      ) d
    ),
    'wallet_account_currency_mismatches', (
      select count(*) from public.wallet_transactions t
      join public.wallet_accounts a on a.id=t.account_id
      where t.user_id <> a.user_id or t.currency <> a.currency
    ),
    'successful_provider_transactions_missing_id', (
      select count(*) from public.wallet_transactions
      where status='successful' and provider not in ('internal','manual')
        and coalesce(trim(provider_transaction_id),'')=''
    ),
    'stale_wallet_processing_over_30m', (
      select count(*) from public.wallet_transactions
      where status in ('pending','processing') and created_at < now() - interval '30 minutes'
    ),
    'successful_payments_missing_ledger', (
      select count(*) from public.payment_attempts a
      where a.status='successful' and not exists (
        select 1 from public.ledger_entries l where l.attempt_id=a.id
      )
    ),
    'payment_ledger_payment_amount_mismatches', (
      select count(*) from public.payment_attempts a
      where a.status='successful' and a.purpose='order'
        and not exists (
          select 1 from public.ledger_entries l
          where l.attempt_id=a.id and l.kind='payment_received'
            and l.amount_minor=a.amount_minor and l.currency=a.currency
        )
    ),
    'ledger_currency_mismatches', (
      select count(*) from public.ledger_entries l
      join public.payment_attempts a on a.id=l.attempt_id
      where l.currency <> a.currency
    ),
    'refunds_failed_or_review', (
      select count(*) from public.refund_requests where status in ('failed','review')
    )
  ) into v_summary;

  -- Compte les contrôles qui indiquent un écart. Les opérations en attente sont signalées
  -- séparément mais ne sont pas automatiquement assimilées à une fraude.
  v_issue_count :=
    coalesce((v_summary->>'wallet_review')::bigint,0) +
    coalesce((v_summary->>'duplicate_provider_transaction_ids')::bigint,0) +
    coalesce((v_summary->>'wallet_account_currency_mismatches')::bigint,0) +
    coalesce((v_summary->>'successful_provider_transactions_missing_id')::bigint,0) +
    coalesce((v_summary->>'successful_payments_missing_ledger')::bigint,0) +
    coalesce((v_summary->>'payment_ledger_payment_amount_mismatches')::bigint,0) +
    coalesce((v_summary->>'ledger_currency_mismatches')::bigint,0) +
    coalesce((v_summary->>'refunds_failed_or_review')::bigint,0);

  v_summary := v_summary || jsonb_build_object(
    'issue_count', v_issue_count,
    'note', 'Audit en lecture seule. Les opérations en attente doivent être rapprochées; aucun solde n’a été modifié.'
  );

  insert into public.finance_audit_runs(actor, summary, status)
  values (v_actor, v_summary, case when v_issue_count=0 then 'clean' else 'issues_found' end)
  returning id into v_run_id;

  insert into public.admin_audit_logs(actor, action, resource, resource_id, reason)
  values (v_actor, 'financial_audit_run', 'finance_audit', v_run_id,
          'issue_count=' || v_issue_count::text);

  return v_summary || jsonb_build_object('audit_run_id', v_run_id);
end;
$$;

revoke all on function public.run_financial_audit() from public, anon;
grant execute on function public.run_financial_audit() to authenticated;

comment on function public.run_financial_audit() is
'Exécute des contrôles financiers en lecture seule pour un administrateur déverrouillé. Ne modifie jamais les soldes ni ne déclenche de paiement/remboursement.';
