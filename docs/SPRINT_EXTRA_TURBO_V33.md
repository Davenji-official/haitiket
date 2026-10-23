# HAITIKET V33 — contrat de régression financier

## But
Ajouter un contrôle SQL reproductible des invariants de sécurité du circuit financier : RLS, droits de mutation du portefeuille, références idempotentes, unicité des identifiants fournisseur et privilèges des fonctions sensibles.

## Fichiers
- `supabase/tests/financial_regression_v33.sql` : contrôle SQL en lecture seule, sans création de commandes, de comptes ou de transactions.
- `scripts_validate_v33.sh` : contrôles statiques précédents + présence des nouvelles assertions.
- `.github/workflows/quality-gates.yml` : workflow qualité mis à jour pour exécuter le validateur V33.

## Exécution sur staging
Après avoir sauvegardé la base de staging et appliqué toutes les migrations :

```bash
psql "$STAGING_DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/financial_preflight_v32.sql
psql "$STAGING_DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/financial_regression_v33.sql
```

Le SQL doit être exécuté avec un rôle d'inspection autorisé à lire les métadonnées et à consulter les privilèges. Le test ne fait aucun mouvement financier et ne teste pas les paiements en direct.

## Limites explicites
- Ce contrat vérifie la structure et les grants présents sur la base interrogée, pas le résultat d'une transaction réelle.
- Les tests de concurrence, doubles appels, taux de change, callbacks Plop Plop et remboursements nécessitent une suite d'intégration sur staging avec des fixtures dédiées et un faux fournisseur ou un environnement sandbox.
- Les migrations ne doivent pas être appliquées en production sans sauvegarde, revue et test de staging.
- Une réussite du script statique ne signifie pas que le SQL a été exécuté. Les résultats de l'action GitHub doivent être consultés séparément.
