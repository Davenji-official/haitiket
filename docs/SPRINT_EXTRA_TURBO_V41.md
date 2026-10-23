# HAITIKET V41 — Tests bloquants avant compilation et publication

## Objectif

Le workflow de build (`.github/workflows/build.yml`) pouvait compiler et publier Web/Android sans lancer la suite `flutter test`. V41 ajoute explicitement cette étape aux jobs Web et Android, après la résolution des dépendances et avant l'analyse/la compilation. Un test en échec arrête le job et bloque les étapes suivantes.

## Changements

- Job Web : exécution de `flutter test` avant l'analyse et le build Web.
- Job Android : exécution de `flutter test` avant l'analyse et le build APK.
- Workflow qualité : validation statique du contrat V41.
- Checklist de livraison : exigences minimales de preuve pour analyse, tests, builds, staging Supabase et fournisseur Plop Plop.

## Limites

Le contrôle V41 local vérifie la présence et l'ordre des étapes dans les fichiers YAML; il ne lance pas Flutter lui-même. Les tests Flutter doivent s'exécuter sur GitHub Actions ou dans un environnement avec Flutter installé. La réussite des tests unitaires ne prouve pas à elle seule que les paiements, webhooks ou migrations fonctionnent sur Supabase.
