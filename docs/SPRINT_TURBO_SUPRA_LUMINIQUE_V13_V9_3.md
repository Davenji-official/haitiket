# HAITIKET — Sprint Turbo Supra Luminique V13 / V9.3

## Objectif
Ajouter un point d'audit financier administrateur en lecture seule pour repérer les incohérences visibles dans les tables financières existantes.

## Fichier ajouté
- `supabase/migrations/0023_financial_audit_v9_3.sql`

## Contrôles inclus
- transactions de portefeuille en statut `review`;
- identifiants de transactions fournisseur dupliqués;
- incohérences entre utilisateur/devise du compte et celles de la transaction;
- opérations fournisseur réussies sans identifiant de transaction;
- paiements réussis sans écriture de ledger;
- montants/devise du paiement non rapprochés avec `payment_received`;
- incohérences de devise dans les écritures du ledger;
- remboursements échoués ou en revue;
- transactions wallet `pending` / `processing` de plus de 30 minutes (signalées séparément).

## Déploiement
1. Sauvegarder le projet.
2. Vérifier que les migrations 0001 à 0022 sont déjà appliquées.
3. Dans Supabase SQL Editor, exécuter une seule fois `0023_financial_audit_v9_3.sql`.
4. Dans une session administrateur autorisée et déverrouillée, appeler `select public.run_financial_audit();`.
5. Examiner le résultat et la table `finance_audit_runs`; investiguer manuellement les écarts avant toute correction.

## Sécurité et limites
- L'audit ne crédite/débite aucun portefeuille et ne déclenche aucun paiement ni remboursement.
- La fonction est réservée à un utilisateur connecté avec console admin déverrouillée.
- Les transactions en attente sont des alertes de rapprochement, pas automatiquement des erreurs ou fraudes.
- Le ledger actuel `ledger_entries` est un journal d'événements financiers, pas un véritable grand livre en partie double. Cette version ne prétend donc pas prouver `débits = crédits`.
- Les remboursements marqués `executed` doivent toujours correspondre à une confirmation réelle du prestataire; le statut interne seul ne constitue pas une preuve fournisseur.
- Aucune exécution Flutter/SQL sur le projet Supabase distant n'a été effectuée dans cet environnement. Ne pas déclarer le sprint validé en production avant test sur staging.
