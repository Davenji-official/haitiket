# HAITIKET V40 — Contrat du cycle commande et livraison

## Objectif

V40 renforce le contrôle du cycle de vie des commandes et des livraisons avant une recette fonctionnelle. L'audit SQL est strictement en lecture seule et vérifie les tables attendues, les fonctions serveur, leur configuration `SECURITY DEFINER`/`search_path` et la présence de garde-fous importants dans les définitions installées.

## Nouveaux artefacts

- `supabase/tests/order_delivery_contract_v40.sql` : audit structurel SQL en lecture seule.
- `docs/qa/order_delivery_matrix_v40.csv` : scénarios d'acceptation à exécuter sur staging.
- `docs/ETAT_DEVELOPPEMENT_HAITIKET_V40.md` : état des preuves et limites.
- `scripts_validate_v40.sh` : validation locale des artefacts et des gardes du runner.
- `scripts_run_order_delivery_contract_v40.sh` : lanceur staging explicitement protégé.

## Limites

Un contrôle structurel n'est pas un test fonctionnel. Tous les scénarios CSV restent `NOT_RUN` jusqu'à ce qu'une personne les exécute sur une instance de staging, enregistre les preuves anonymisées et renseigne le statut. Le SQL ne modifie ni soldes ni commandes.
