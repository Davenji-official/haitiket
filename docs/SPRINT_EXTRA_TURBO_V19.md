# HAITIKET — Sprint Extra Turbo V19

## Objectif livré dans cette étape

- Le paiement d'une commande en attente passe par `pay_order_from_wallet`, une fonction SQL serveur, et non par la fonction Edge `bazik-pay`.
- Le portefeuille débité doit correspondre exactement à la devise de la commande (`HTG` ou `USD`). Aucune conversion implicite n'est appliquée.
- Le compte du portefeuille est verrouillé pendant le calcul du solde et le débit. La référence `ORDER:<uuid>` rend le paiement idempotent.
- Le solde est calculé à partir des transactions `successful` seulement. Les revenus vendeur sont créés en `pending` et ne deviennent disponibles qu'après confirmation de remise.
- La commission est enregistrée séparément dans `platform_financial_entries`.
- La confirmation de livraison refuse les commandes en litige et les statuts de commande incompatibles.
- Les recharges/retraits Plop Plop ne sont pas remplacés par ce flux.

## Déploiement

1. Sauvegarder la base Supabase.
2. Appliquer les migrations dans l'ordre, dont `0029_wallet_first_order_checkout.sql`.
3. Vérifier les droits de la fonction `pay_order_from_wallet` et tester sur un environnement de staging avec des comptes HTG et USD distincts.
4. Tester : solde suffisant/insuffisant, double clic, double requête concurrente, réservation expirée, commande en litige, remise pickup, livraison coursier et erreur de devise.
5. Examiner les soldes et les écritures avec l'audit financier avant tout déploiement production.

## Limites connues — ne pas confondre avec une version prête à encaisser en production

- Cette étape migre **le paiement des commandes** vers le portefeuille interne et désactive les appels applicatifs à Bazik. Les frais Bazar, abonnements boutique et suppléments de livraison sont temporairement bloqués avec un message explicite jusqu'à leur migration vers le portefeuille interne. Ne pas les réactiver en redirigeant vers un prestataire externe.
- Le calcul et le règlement des remboursements, la gestion complète des litiges après remise, ainsi que la comptabilité double-entrée complète nécessitent encore une étape dédiée.
- Le flux de retrait Plop Plop doit être validé selon la configuration réelle du fournisseur et ses confirmations serveur.
- Aucune compilation Flutter/Dart ni migration sur une base Supabase réelle n'a été exécutée dans cet environnement. Les contrôles effectués ici sont statiques ; cette archive doit être validée sur staging avant usage réel.
