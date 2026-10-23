# HAITIKET V65 — tests de contrat exécutables

## Objectif
Ajouter une suite Python standard-library qui peut s'exécuter sans dépendances tierces et qui vérifie des invariants source essentiels avant la CI.

## Couverture
- ajustement du stock et garde-fou des réservations;
- présence du scénario de concurrence de stock variante, explicitement limité à une base de staging jetable;
- validation administrative et délai de réflexion pour suppression de boutique;
- contrôles de sécurité à la réactivation;
- revue KYC administrative et journalisation;
- rapport de préparation au lancement;
- présence de `flutter analyze` et `flutter test` dans le workflow.

## Lancement
```bash
./scripts_validate_v65.sh
```

## Limites honnêtes
Les tests V65 inspectent le code et les contrats textuels. Ils ne prouvent pas que PostgreSQL accepte toutes les migrations, que les politiques RLS sont correctes à l'exécution, ni que Flutter compile. Le script `tests/concurrency/run_variant_stock_race_v60.sh` est un test d'intégration distinct et potentiellement modifiant : utiliser exclusivement une base Supabase de staging jetable avec une variante de test stock=1. Ne pas exécuter en production.
