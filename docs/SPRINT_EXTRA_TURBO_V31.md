# HAITIKET V31 — Tests de base et portes qualité

## Objectif

Réduire les régressions en ajoutant des tests Flutter simples pour le dictionnaire de traduction et la configuration cliente Supabase, puis exécuter l'analyse Dart et les tests automatiquement dans GitHub Actions.

## Changements

- `test/i18n_test.dart` vérifie la langue française, deux traductions créoles et le retour à la chaîne française si une traduction manque.
- `test/config_test.dart` vérifie la forme de l'URL Supabase et la présence d'une clé cliente non vide, sans exposer ni valider de secret serveur.
- `.github/workflows/quality-gates.yml` exécute les contrôles statiques, `flutter analyze` et `flutter test` sur push, pull request et lancement manuel.
- `scripts_validate_v31.sh` relance les validations statiques V25–V30 et vérifie les fichiers de tests et la continuité de nommage des migrations.

## Limites connues

- L'environnement de génération ne dispose pas de Flutter/Dart ni d'une base PostgreSQL/Supabase; les tests Flutter n'ont pas été exécutés localement.
- Le workflow GitHub doit s'exécuter pour confirmer l'analyse et les tests dans CI.
- Les tests ajoutés sont des tests de base, pas des tests de paiements, de livraison, de sécurité RLS ou de Plop Plop.
- Les migrations SQL ne sont pas appliquées par ce sprint et aucun paiement réel n'est effectué.
