# HAITIKET V24 — rapprochement financier plus fiable

## Changements
- Ajoute `run_financial_reconciliation_v24()` dans `supabase/migrations/0034_financial_reconciliation_v24.sql`.
- Sépare les anomalies comptables (`issue_count`) des alertes opérationnelles (`warning_count`).
- Un rapport ne peut plus afficher « propre » si des litiges, remboursements à traiter, paiements historiques en attente ou transactions anciennes sont détectés.
- Le rapport reste strictement en lecture seule : aucun solde et aucune transaction ne sont corrigés automatiquement.
- L’interface d’administration présente les catégories avec des libellés lisibles plutôt qu’un bloc JSON brut.

## Vérification requise avant production
1. Sauvegarder Supabase et appliquer les migrations dans l’ordre sur une base de staging, jusqu’à `0034`.
2. Vérifier les permissions admin et le verrouillage de la console.
3. Tester les scénarios de recharge HTG/USD, webhook répété, montant erroné, identifiant fournisseur déjà utilisé et délai d’attente.
4. Comparer le rapport avec le tableau marchand Plop Plop et les relevés bancaires/comptables.
5. L’environnement de travail n’a ni Flutter/Dart ni une base Supabase connectée : aucune compilation ni exécution réelle de migration n’a été effectuée ici.

## Point important
Le rapport de HAITIKET ne prouve pas que Plop Plop détient les fonds correspondants. Seul le rapprochement avec le compte marchand et les règlements réels du fournisseur permet de vérifier la liquidité.
