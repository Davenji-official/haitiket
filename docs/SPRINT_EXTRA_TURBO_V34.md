# HAITIKET V34 — audit de déploiement, de migration et des intégrations

## Objectif

V33 vérifiait un contrat SQL de sécurité financière. V34 ajoute un inventaire **en lecture seule** à exécuter sur un vrai projet Supabase pour comparer l’état déployé avec le code source.

## Nouveaux éléments

- `supabase/tests/deployment_inventory_v34.sql` : affiche l’historique de migrations lorsqu’il est accessible, la présence des tables attendues, les fonctions sensibles et leurs paramètres de sécurité, l’activation de RLS et les triggers métier pertinents.
- `scripts_validate_v34.sh` : rejoue les contrôles statiques V25–V33, vérifie le contrat V34, contrôle que l’application Flutter n’invoque pas les endpoints de checkout Bazik retirés et vérifie que les trois fonctions Plop Plop attendues sont dans l’archive.
- Workflow CI mis à jour pour lancer le validateur V34.

## Procédure de contrôle sur STAGING

1. Utiliser l’URL de base de données du projet **STAGING** avec un rôle autorisé à lire les catalogues PostgreSQL. Ne pas coller de mot de passe ni de clé secrète dans un dépôt ou un chat.
2. Exécuter les migrations du dépôt selon la procédure Supabase déjà utilisée par le projet, après sauvegarde et revue. L’inventaire V34 **n’applique pas** les migrations.
3. Exécuter `psql "$STAGING_DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/financial_preflight_v32.sql`.
4. Exécuter `psql "$STAGING_DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/financial_regression_v33.sql`.
5. Exécuter `psql "$STAGING_DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/deployment_inventory_v34.sql` et conserver le résultat dans le dossier de release sécurisé.
6. Dans Supabase Dashboard ou via les outils CLI autorisés, inventorier séparément les **Edge Functions réellement déployées**, leurs versions, secrets configurés, URLs de webhook et journaux. Une fonction absente du ZIP peut encore exister dans le projet distant.
7. Tester les parcours financiers sur un environnement de test et des comptes de test : recharge Plop Plop confirmée/refusée, callback dupliqué, retrait confirmé/échoué, solde insuffisant, devise incorrecte, paiement de commande, litige, livraison confirmée et remboursement. Ne pas utiliser de vrais fonds pour le test.
8. Ne passer en production qu’après examen des écarts, validation des politiques RLS/grants, sauvegarde et procédure de retour arrière.

## Limites et interprétation

- Le validateur shell est un contrôle statique local; il ne prouve pas que les migrations SQL s’exécutent correctement sur une instance réelle.
- L’inventaire SQL est en lecture seule, mais ses résultats doivent être interprétés par rapport aux migrations et à la configuration du projet.
- Les catalogues PostgreSQL ne listent pas les Edge Functions hébergées séparément; leur présence réelle doit être contrôlée dans Supabase.
- La présence de `plopplop-wallet`, `plopplop-webhook` et `plopplop-withdraw` dans le ZIP ne prouve ni que ces fonctions sont déployées, ni que les secrets/webhooks sont configurés, ni que Plop Plop a confirmé un paiement.
- Aucun mouvement d’argent n’est effectué par le script V34. Aucune compilation Flutter, migration distante ou transaction réelle n’est prétendue comme réussie dans cette livraison.
