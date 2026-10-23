# HAITIKET V37 — staging read-only integrity gate

## But

V37 ajoute un lanceur de contrôles SQL en lecture seule, avec une double confirmation explicite que la cible est un environnement de staging. Il regroupe l'inventaire V34, la garde financière V35 et un contrôle structurel supplémentaire V37.

## Lancement sur staging uniquement

```bash
STAGING_ENVIRONMENT=staging \
ALLOW_STAGING_READONLY_AUDIT=YES \
STAGING_DATABASE_URL="$STAGING_DATABASE_URL" \
./scripts_run_staging_readonly_v37.sh
```

Le script ne doit pas afficher ni copier l'URL de connexion dans les journaux. Il s'arrête si la variable d'environnement ou `psql` manque. Les fichiers SQL appelés ne doivent ni modifier des données, ni lancer des RPC métier. Utiliser un rôle de staging en lecture seule lorsque cela est compatible avec l'inspection des catalogues PostgreSQL.

## Contrôles ajoutés

- Présence des tables clés portefeuille/commandes/livraisons/remboursements.
- RLS activé et politiques existantes sur les deux tables de portefeuille.
- Référence unique des transactions, index anti-doublon fournisseur et contrainte de devise.
- Présence des fonctions sensibles de recharge, retrait, commande, collecte, livraison et remboursement.
- Inventaire des triggers sur commandes, livraisons et remboursements pour revue humaine.

## Limites

Ce sont des contrôles structurels, pas des tests transactionnels de bout en bout. La présence d'une politique RLS ne prouve pas à elle seule qu'elle est correcte. La présence d'une fonction ne prouve pas qu'elle est correctement autorisée ni que le fournisseur Plop Plop est configuré. V37 ne réalise aucune recharge, aucun retrait, aucun achat, aucun remboursement et aucune livraison. Les sorties réelles doivent être archivées après exécution sur staging et examinées par une personne autorisée.
