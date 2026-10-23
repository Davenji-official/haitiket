# HAITIKET V38 — Portail de préparation au lancement

## But
Renforcer les contrôles structurels en staging sans modifier les soldes ni exécuter de transactions métier.

## Ajouts
- `supabase/tests/production_readiness_v38.sql` contrôle en lecture seule les tables critiques, les droits d’écriture directs sur les portefeuilles, les propriétés de sécurité des RPC sensibles et inventorie leurs permissions d’exécution.
- `scripts_run_staging_readiness_v38.sh` lance les audits précédents et V38 uniquement si l’environnement est explicitement déclaré `staging`, si l’utilisateur confirme l’audit et si une URL de connexion est fournie. L’URL n’est jamais imprimée.
- `scripts_validate_v38.sh` vérifie les fichiers attendus et les garde-fous statiques.

## Exécution sur un environnement de test
```bash
STAGING_ENVIRONMENT=staging \
ALLOW_STAGING_READONLY_AUDIT=YES \
STAGING_DATABASE_URL='postgresql://…' \
./scripts_run_staging_readiness_v38.sh
```
Ne jamais committer l’URL ni l’ajouter à un rapport. Fournir la variable depuis un gestionnaire de secrets et utiliser exclusivement une base de staging. Les scripts SQL ouvrent des transactions `READ ONLY`.

## Limites
Ces audits vérifient la structure, les privilèges et la configuration des fonctions. Ils ne démontrent pas la justesse du code métier, l’intégration fournisseur Plop Plop, ni le fonctionnement d’un parcours complet. Les tests de bout en bout nécessitent une instance de staging, des comptes de test et des résultats observés.
