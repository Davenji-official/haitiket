# HAITIKET V27 — sécurisation du parcours de livraison

## Changements

- `confirm_pickup` vérifie maintenant que la commande est en `READY_FOR_PICKUP`, que le paiement est retrouvé dans le portefeuille interne (débit `ORDER:<id>`) ou dans un paiement historique marqué `successful`, que le montant/devise du job correspondent à la commande et qu'aucun litige/remboursement actif ne bloque la collecte.
- Le contrôle de supplément n'utilise plus exclusivement l'ancien parcours `payment_attempts.purpose='delivery_fee'`. Le prix d'une offre choisie est déjà réglé/ajusté par `select_delivery_price_offer` dans le portefeuille interne (migration 0030).
- `confirm_delivery` exige une mission `picked_up`, une commande `IN_TRANSIT`, le PIN client, et bloque en présence d'un litige ouvert ou d'un remboursement en cours/exécuté.
- `run_delivery_flow_audit_v27()` ajoute un audit admin en lecture seule : missions sans coursier, statuts commande/mission incompatibles, offres sélectionnées incohérentes, offres expirées encore en attente, commandes de livraison sans mission, frais/devise incohérents et litiges actifs.
- Nouveau bouton « Audit du parcours de livraison V27 » dans l'administration et méthode RPC associée dans `Repo`.

## Validation effectuée

- Contrôle de l'intégrité de l'archive ZIP après génération.
- Contrôles statiques de présence des fonctions SQL, de la méthode RPC et du bouton d'administration.
- Revue des dépendances avec les migrations V26, V24 et V30.

## Limites

Cette migration n'a pas été exécutée sur une instance PostgreSQL/Supabase réelle. Flutter/Dart ne sont pas installés dans l'environnement, donc aucune compilation Flutter n'a été réalisée. Avant production, appliquer la migration sur une base de staging et tester les cas normaux, les PIN erronés, les litiges, les remboursements, les offres expirées et les paiements historiques.

L'audit est en lecture seule. Il ne corrige pas automatiquement les incohérences, ne crée aucun paiement et ne libère aucun revenu.
