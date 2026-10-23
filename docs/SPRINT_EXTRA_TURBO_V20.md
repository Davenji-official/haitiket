# HAITIKET — Sprint Extra Turbo V20

## Objectif

Compléter la migration V19 vers les portefeuilles internes pour les frais qui restaient bloqués : annonces Bazar, abonnement boutique et ajustement du prix de livraison choisi par le client.

## Changements

- **Bazar** : le paiement est prélevé sur le portefeuille USD. Une annonce payée est publiée pour 14 jours. Une annonce déjà payée, bloquée ou supprimée ne peut pas être débitée à nouveau.
- **Abonnement boutique** : le tarif mensuel (ou annuel via le RPC) est débité du portefeuille USD. Une boutique dont l'abonnement est encore actif ne peut pas être débitée une seconde fois par ce flux.
- **Livraison** : le choix de l'offre et l'ajustement du coût sont atomiques. Si l'offre est plus chère que les frais déjà payés, le supplément est débité du portefeuille de même devise. Si elle est moins chère, la différence est créditée dans ce portefeuille. Aucun taux de change implicite n'est utilisé.
- **Idempotence et concurrence** : les fonctions verrouillent la ligne métier et le compte de portefeuille avant de calculer le solde; les références de transaction sont uniques.
- **UI** : les écrans Bazar et abonnement appellent les RPC internes. Les appels de paiement externes historiques restent bloqués dans l'application.
- **Bazik** : les Edge Functions `bazik-pay` et `bazik-webhook` ont été retirées de cette archive pour éviter un redéploiement accidentel. Si elles sont déjà déployées dans le projet Supabase, les désactiver/supprimer séparément dans Supabase. Plop Plop reste présent pour les recharges et retraits externes.

## Migration

Appliquer `0030_wallet_first_bazar_shop_delivery.sql` après toutes les migrations précédentes, dont `0029_wallet_first_order_checkout.sql`. Sauvegarder la base et effectuer les essais sur une base de staging avant production.

## Tests de staging indispensables

1. Bazar : solde USD suffisant/insuffisant, annonce déjà payée, annonce bloquée, double clic et annonce expirée.
2. Boutique : paiement mensuel, solde insuffisant, abonnement actif et vérification du renouvellement après expiration.
3. Livraison : offre dans la même devise, supplément avec solde suffisant/insuffisant, offre moins chère donnant lieu à remboursement, deux choix concurrents et livraison bloquée en cas de litige.
4. Vérifier les écritures `wallet_transactions`, les soldes HTG/USD, les statuts de commande et la libération des gains après remise confirmée.
5. Vérifier séparément les recharges et retraits Plop Plop avec les confirmations serveur réelles.

## Limites et honnêteté des tests

- Cette archive n'a pas été compilée avec Flutter/Dart et la migration n'a pas été exécutée sur la base Supabase réelle : ces outils/services ne sont pas accessibles dans cet environnement.
- Les tests réalisés localement sont statiques (présence des fonctions, branchements UI, références aux RPC et cohérence textuelle). Ils ne prouvent pas que la migration s'applique sans erreur à la base réelle.
- Le système de remboursements de commandes, les litiges après remise, la réconciliation complète et une comptabilité double-entrée exhaustive restent des chantiers distincts.
- Ne pas accepter de vrais paiements avant tests de staging, revue SQL et vérification des secrets/droits Supabase.
