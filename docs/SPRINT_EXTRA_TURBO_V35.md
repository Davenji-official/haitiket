# HAITIKET V35 — Financial staging gates

## Livrable

V35 ajoute un gate SQL structurel à exécuter sur **STAGING uniquement**, et un lanceur reproductible qui collecte les sorties V32, V33, V34 et V35 dans un rapport local.

- `supabase/tests/financial_staging_gate_v35.sql` : échoue explicitement si les tables financières attendues, RLS, fonctions RPC sensibles, `SECURITY DEFINER`, `search_path=public` ou l'index d'idempotence provider sont absents. Affiche aussi les grants des rôles `anon`/`authenticated` à examiner.
- `scripts_run_staging_financial_gates_v35.sh` : exige `HAITIKET_ENV=staging`, `STAGING_DATABASE_URL` et `psql`; s'arrête au premier échec et enregistre les résultats.
- `scripts_validate_v35.sh` : contrôles statiques et validation de la chaîne des scripts.
- Workflow CI mis à jour pour exécuter le validateur V35.

## Exécution par une personne ayant accès au projet de test

```bash
export HAITIKET_ENV=staging
export STAGING_DATABASE_URL='URL_DE_CONNEXION_STAGING'
./scripts_run_staging_financial_gates_v35.sh
```

Ne commite pas l'URL de connexion et ne la partage pas dans un chat. Le lanceur n'applique aucune migration et n'appelle aucune fonction de paiement. Les scripts SQL exécutent des lectures/catalogues et des blocs `DO` d'assertion; ils ne doivent pas être interprétés comme des tests transactionnels de recharge, retrait, achat ou remboursement.

## Limites honnêtes

Le validateur statique local ne remplace pas l'exécution sur Supabase. Le script staging n'a pas été exécuté dans cet environnement, car aucun accès base de données/`psql` n'est disponible ici. Les paiements Plop Plop, webhooks, Flutter build et tests end-to-end restent à vérifier. Les résultats de permissions doivent être examinés; la présence d'un rapport sans erreur ne constitue pas à elle seule une autorisation de mise en production.

## Scénarios end-to-end à exécuter ensuite

Avec des comptes marchands/acheteurs/coursiers de test et sans fonds réels : recharge confirmée une fois malgré webhook dupliqué; recharge au montant divergent mise en revue; retrait refusé si solde insuffisant; commande refusée si devise différente; débit de commande non dupliqué; revenus retenus pendant litige; revenus libérés seulement après livraison autorisée; remboursement interne sans double crédit; annulation et reprise sur erreur fournisseur.
