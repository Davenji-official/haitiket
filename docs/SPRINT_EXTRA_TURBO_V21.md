# HAITIKET V21 — Intégrité financière et litiges

## Objectif
Ajouter un audit en lecture seule pour les portefeuilles internes et une procédure administrative explicite pour libérer les gains restés en attente après résolution d'un litige sans remboursement.

## Changements
- Migration `0031_dispute_financial_integrity.sql`.
- RPC `run_wallet_integrity_audit_v21()` : vérifie les incohérences devise/compte, commandes payées sans débit wallet correspondant (en excluant les paiements historiques réussis par fournisseur), débits orphelins, soldes négatifs, gains vendeur en attente, rémunérations coursier manquantes, remboursements à traiter et opérations en revue/en attente.
- L'audit est en lecture seule pour les soldes : il enregistre uniquement un rapport dans `finance_audit_runs` et une ligne dans `admin_audit_logs`.
- Bouton dans le tableau de bord administrateur pour lancer l'audit et lire le rapport retourné.
- RPC `admin_release_disputed_order_earnings(p_order, p_note)` : libération manuelle avec justification uniquement si la commande est remise (`DELIVERED`/`COMPLETED`), aucun litige n'est ouvert et un litige a été explicitement résolu sans remboursement. Bloque les remboursements en attente ou déjà exécutés. La transaction est atomique et le crédit coursier est idempotent via sa référence unique.

## Limites importantes
- La fonction de libération après litige est exposée comme RPC mais n'a pas encore de formulaire dédié demandant l'identifiant de commande dans l'interface. Elle doit être appelée par un outil admin contrôlé ou raccordée à l'écran de résolution des litiges avant usage opérationnel.
- Si des revenus ont déjà été dépensés avant qu'un litige post-livraison soit ouvert, cette migration ne tente pas de récupérer ces fonds automatiquement. Cela demande une procédure comptable séparée et une décision explicite.
- Le rapport d'audit signale des anomalies ; il ne corrige aucun solde automatiquement et n'est pas une preuve de conformité complète.
- Migration non exécutée contre le projet Supabase réel. Compilation Flutter et tests bout en bout non effectués dans cet environnement.

## Déploiement prudent
1. Sauvegarder la base et déployer sur un projet Supabase de staging.
2. Appliquer les migrations 0001 à 0031 dans l'ordre.
3. Vérifier les permissions et exécuter l'audit depuis une session administrateur déverrouillée.
4. Tester les scénarios de litige ouvert, résolution sans remboursement, résolution avec remboursement, et double appel de libération.
5. Ne pas utiliser en production avant validation SQL et tests de flux réels.
