# HAITIKET V47 — Statistiques historiques administratives

## Livrable
- Historique quotidien des commandes sur 7, 30 ou 90 jours.
- Graphiques de volume des commandes et montants des commandes dans les statuts payés.
- Séries affichées séparément pour HTG et USD : aucune conversion ni somme inter-devises.
- Filtre de devise et actualisation de la période.
- Fonction SQL en lecture seule, accessible uniquement aux utilisateurs authentifiés dont la console administrateur est déverrouillée.
- Fenêtre serveur limitée à 90 jours, index sur `orders(created_at, currency)`.

## Installation
Appliquer `supabase/migrations/0041_admin_order_history_v47.sql` en environnement de staging après sauvegarde et revue de la migration. La migration crée un index et une fonction d'agrégation, sans modifier les commandes existantes.

## Vérification
`./scripts_validate_v47.sh` vérifie statiquement la présence du RPC, de ses contrôles d'accès, des limites et des graphiques.

## Limites honnêtes
- Flutter/Dart et PostgreSQL n'étant pas disponibles dans l'environnement de préparation, l'analyse Flutter, les tests Flutter, l'exécution SQL et les tests intégrés n'ont pas été exécutés ici.
- L'écran n'est opérationnel qu'après application de la migration et validation CI/staging.
- Les montants `paid_total_minor` sont en unités mineures, agrégés selon les statuts payés définis par l'application. Ils ne remplacent pas le rapprochement financier du grand livre.
- La fonction s'appuie sur `admin_unlocked()` et la table `orders` du schéma existant ; vérifier ces dépendances dans la base cible avant déploiement.
