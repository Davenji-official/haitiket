# HAITIKET V32 — pré-vol financier de staging

## Objectif

Ajouter un contrôle reproductible, en lecture seule, à exécuter sur une base Supabase de **staging** après application des migrations. Le contrôle vérifie la présence des principales tables financières, les signatures des RPC de paiement/remboursement, `SECURITY DEFINER`, le `search_path` et des privilèges de base.

## Fichiers

- `supabase/tests/financial_preflight_v32.sql` : pré-vol SQL en lecture seule.
- `scripts_validate_v32.sh` : conserve les contrôles statiques V25–V31 et vérifie que le pré-vol V32 reste présent et sans instructions DML/DDL.
- `.github/workflows/quality-gates.yml` : appelle le validateur V32.

## Exécution sur staging

1. Appliquer les migrations sur une base Supabase de staging, jamais directement sur la production pour le premier essai.
2. Vérifier que le rôle de connexion peut lire le catalogue PostgreSQL.
3. Exécuter : `psql "$STAGING_DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/financial_preflight_v32.sql`.
4. Enregistrer la sortie du test et corriger les anomalies avant de poursuivre.
5. Tester ensuite séparément les parcours avec des comptes de test : achat HTG, achat USD, solde insuffisant, double appel de paiement, remboursement interne, litige, libération des revenus et erreurs de confirmation Plop Plop.

## Limites

Le pré-vol ne déplace aucun fonds et ne prouve pas le bon fonctionnement métier des RPC. Il vérifie l'existence et quelques propriétés de sécurité des fonctions, pas chaque chemin d'exécution. Le test SQL n'a pas été exécuté contre une vraie base dans cet environnement. Les tests Flutter, l'analyse Dart, la compilation et les tests de bout en bout doivent être exécutés par CI ou sur l'environnement de staging.

## Critère de réussite

Le script statique V32 passe, puis le pré-vol SQL affiche `V32 PREFLIGHT OK` sur staging. Les transactions financières réelles restent bloquées au lancement jusqu'à réussite des tests de bout en bout et validation des clés/secrets Plop Plop.
