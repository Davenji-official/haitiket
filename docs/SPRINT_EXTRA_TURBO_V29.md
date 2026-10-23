# HAITIKET V29 — audit global de préparation au lancement

## But
Fournir à l'administration un seul rapport agrégé réunissant les audits existants V24, V26, V27 et V28, sans modifier les données métier ni déplacer de fonds.

## Changements
- Migration `0038_launch_readiness_audit_v29.sql` et fonction `run_launch_readiness_audit_v29()`.
- Nouvelle méthode `Repo.adminRunLaunchReadinessAuditV29()`.
- Nouveau bouton « Audit global de préparation au lancement V29 » dans l'administration.
- Statuts globaux : `issues_found`, `warnings`, `clean`.
- Le rapport indique explicitement `production_certified: false`. Un audit sans anomalie ne certifie pas la production.

## Attention sur les journaux
La fonction agrégée appelle les audits V24, V26, V27 et V28; ceux-ci écrivent leurs journaux d'audit. Aucune commande, aucun statut commercial et aucun solde n'est modifié, mais plusieurs lignes de journal sont attendues.

## Installation et validation
1. Sauvegarder la base de staging.
2. Appliquer les migrations dans l'ordre jusqu'à `0038`.
3. Ouvrir l'administration, déverrouiller la console et lancer l'audit global.
4. Examiner chaque sous-rapport; corriger les anomalies manuellement et relancer.
5. Exécuter `scripts_validate_v29.sh` pour les contrôles statiques.
6. Compiler Flutter et tester la fonction SQL sur staging avant production.

## Limites
Contrôles statiques uniquement dans l'environnement de création. Aucune compilation Flutter/Dart ni exécution de migration sur une base Supabase réelle. Ce rapport n'est pas une preuve de couverture des tests, de validité des secrets Plop Plop, de solvabilité du compte marchand ou de conformité réglementaire.
