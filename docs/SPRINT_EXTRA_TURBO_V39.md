# HAITIKET V39 — Release acceptance & evidence gate

## But
V39 transforme les contrôles existants en une liste de critères de lancement traçables. Elle ne prétend pas remplacer les essais sur Supabase staging, le build Flutter ou les confirmations réelles du fournisseur Plop Plop.

## Livrables
- `docs/ETAT_DEVELOPPEMENT_HAITIKET_V39.md` : distinction entre code présent, contrôles statiques et validation réelle.
- `docs/qa/acceptance_matrix_v39.csv` : scénarios manuels à exécuter et à signer sur staging.
- `docs/qa/RELEASE_CHECKLIST_V39.md` : critères bloquants avant production.
- `scripts_validate_v39.sh` : validation locale des artefacts et de la chaîne statique.

## Règle de décision
Aucun statut `PASS` ne doit être attribué à un scénario tant que la preuve correspondante (journal anonymisé, résultat SQL, test Flutter ou référence fournisseur de test) n'a pas été conservée. Toute ligne `BLOCKED` ou `FAIL` bloque la mise en production.

## Limites de cette version
Le validateur V39 ne se connecte pas à Supabase et ne déclenche aucun paiement. Il vérifie les artefacts et la cohérence du dossier de recette. Les tests d'intégration doivent être exécutés dans un projet Supabase de staging autorisé, avec des identifiants de test et sans argent réel.
