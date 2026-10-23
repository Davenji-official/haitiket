# État du développement HAITIKET — V38

## Présent dans le dépôt
- Application Flutter et tests Dart existants.
- Migrations SQL des portefeuilles HTG/USD, du checkout interne, des revenus en attente, des contrôles de livraison et du remboursement interne.
- Fonctions Edge liées à Plop Plop.
- Audits structurels V32–V38 et validateurs statiques.

## À confirmer sur staging
- Migrations réellement appliquées et absence de divergence avec le dépôt.
- Droits réels de `anon` et `authenticated`, configuration des RPC et état des déclencheurs.
- Secrets et webhooks Plop Plop configurés dans l’environnement, sans partager les valeurs secrètes.
- Scénarios de recharge, retrait, double notification, paiement, annulation, livraison, litige et remboursement.
- Compilation Flutter et essais sur appareils réels.

## Statut honnête
Les contrôles statiques peuvent être exécutés localement. Aucun accès à une base Supabase distante n’est fourni dans cet environnement; l’audit SQL V38 n’est donc pas déclaré exécuté. Aucune transaction réelle n’a été effectuée.
