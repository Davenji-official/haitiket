-- HAITIKET 0054 — index de support pour les vérifications de solde et de paiement.
-- Migration additive et réexécutable : n'ajoute aucune donnée et ne change pas les règles financières.
-- À exécuter après les migrations 0001 à 0053.
create index if not exists wallet_transactions_account_status_idx
  on public.wallet_transactions (account_id, status);

analyze public.wallet_transactions;
