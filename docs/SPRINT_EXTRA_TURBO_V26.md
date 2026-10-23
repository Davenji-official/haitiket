# HAITIKET V26 — garde-fous financiers

## Changements
- Durcissement de `pay_order_from_wallet(uuid)` : une commande annulée, remboursée ou en litige ne peut pas être repayée ; un débit existant incohérent déclenche une erreur de revue plutôt qu'une nouvelle tentative ; une réponse idempotente n'est donnée que si le débit et le statut de commande concordent.
- Durcissement de `_release_order_wallet_earnings()` : les gains ne sont pas libérés si un litige ouvert/résolu avec remboursement ou un remboursement en attente/exécuté est associé à la commande.
- Ajout de `run_financial_guard_audit_v26()` (lecture seule) et d'un bouton dans l'administration.
- Aucun appel Plop Plop n'est lancé par cette migration ; aucune balance n'est modifiée par l'audit.

## Migration
Appliquer `supabase/migrations/0035_financial_release_and_checkout_guards_v26.sql` après les migrations précédentes sur un environnement de staging d'abord.

## Contrôles effectués dans cette archive
- intégrité ZIP ;
- présence des migrations et fonctions ;
- raccordement du RPC et du bouton d'administration ;
- vérifications textuelles statiques.

## Limites
Cette version n'est pas certifiée production : Flutter/Dart et une base Supabase de staging n'étaient pas disponibles pour compiler l'application ou exécuter la migration. Il faut tester les statuts réels des litiges et remboursements, les parcours de commande, les transactions concurrentes et les données historiques avant déploiement.
