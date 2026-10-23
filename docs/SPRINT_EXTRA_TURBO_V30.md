# HAITIKET V30 — garde-fous qualité et préparation des livraisons

## Objectif

Ajouter une porte qualité reproductible afin que les contrôles statiques des sprints V25 à V29 s'exécutent ensemble, que les migrations SQL numérotées restent séquentielles, et que certains noms de secrets côté serveur ne soient pas introduits dans le code Flutter.

## Changements

- `scripts_validate_v30.sh` exécute les validateurs statiques V25–V29.
- Le script vérifie la séquence des migrations numérotées jusqu'à `0038`.
- Le script vérifie la présence du raccordement de l'audit global et cherche certains noms de secrets sensibles dans `lib/**/*.dart`.
- `.github/workflows/quality-gates.yml` lance ces contrôles sur push, pull request et déclenchement manuel, y compris lorsque seul le SQL change.

## Utilisation locale

```bash
./scripts_validate_v30.sh
```

## Limites importantes

- Ce sont des contrôles statiques, pas une analyse de sécurité exhaustive.
- Le contrôle des noms de secrets ne prouve pas qu'aucun secret n'existe dans l'historique Git, les fichiers de configuration ou les journaux.
- Cette CI ne remplace pas `flutter pub get`, `flutter analyze`, `flutter test`, la compilation Android/Web ni les tests d'intégration Supabase.
- Les migrations doivent être appliquées d'abord sur une base de staging sauvegardée.
- La réussite des audits V24–V29 ne certifie pas que les fonds réels du compte marchand Plop Plop couvrent les soldes internes.
- Aucun mouvement d'argent n'est déclenché par les contrôles ajoutés en V30.
