# État HAITIKET V37

## Ajouts vérifiables dans le dépôt

- `supabase/tests/staging_integrity_v37.sql`: contrôles structurels SQL en lecture seule.
- `scripts_run_staging_readonly_v37.sh`: lanceur gardé par deux variables d'environnement explicites et sans affichage de l'URL de connexion.
- `docs/SPRINT_EXTRA_TURBO_V37.md`: instructions d'exécution et limites.
- `scripts_validate_v37.sh`: validation statique de la présence et de certains contrats des nouveaux fichiers.
- Workflow qualité mis à jour pour appeler le validateur V37.

## État de validation local

La validation statique et l'intégrité du ZIP peuvent être vérifiées localement. Aucun accès à une base Supabase n'a été effectué ici; aucune sortie SQL réelle n'est disponible. Le runner V37 n'a donc pas été exécuté sur staging et ne certifie pas l'état distant.

## Pour clôturer le jalon

1. Exécuter le runner avec les accès de staging.
2. Examiner les fonctions, grants, politiques RLS et triggers signalés.
3. Compléter la matrice de recette V36 avec des preuves anonymisées.
4. Ajouter ensuite des tests de parcours transactionnels avec utilisateurs et données synthétiques isolés, jamais sur production.
