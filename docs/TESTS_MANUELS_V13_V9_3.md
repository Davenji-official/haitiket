# Tests manuels V13 / V9.3

## Avant le test
- Utiliser staging, pas de transactions réelles.
- Vérifier que `0023_financial_audit_v9_3.sql` s'applique sans erreur.
- Se connecter avec un compte administrateur disposant de l'accès admin déverrouillé.

## Cas à vérifier
1. Appeler `select public.run_financial_audit();` et vérifier que le JSON contient les compteurs et `audit_run_id`.
2. Avec un compte client ordinaire, vérifier que la fonction échoue avec accès refusé.
3. Vérifier qu'une ligne est créée dans `finance_audit_runs` et dans `admin_audit_logs`.
4. Vérifier que les soldes des portefeuilles sont strictement identiques avant et après l'audit.
5. Créer uniquement en staging un jeu de données de test contrôlé avec un paiement réussi sans ledger et vérifier que le compteur augmente.
6. Tester les anomalies de devise et les identifiants fournisseur dupliqués dans une base jetable/staging, puis supprimer le jeu de test selon la procédure de test.
7. Vérifier que les transactions en attente de plus de 30 minutes sont signalées séparément.
8. Vérifier que le résultat ne révèle ni téléphone destinataire, ni document KYC, ni payload complet de webhook.

## Critère de sortie
Aucun déploiement production tant que la migration, les droits, les résultats d'audit et l'absence d'effet sur les soldes ne sont pas confirmés sur staging.
