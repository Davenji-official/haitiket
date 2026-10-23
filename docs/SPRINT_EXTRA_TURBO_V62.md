# HAITIKET V62 — Contrôle de préparation opérationnelle

V62 ajoute la RPC administrative en lecture seule `admin_release_readiness_v62()` et son wrapper dans le dépôt Dart. Le snapshot réunit le nombre de remboursements non exécutés, ceux en attente depuis plus de 24 heures, les dossiers KYC à examiner, les suppressions de boutiques en attente/délai de réflexion, les suppressions approuvées bloquées par des remboursements, les commandes contestées et les paiements nécessitant une réconciliation de remboursement.

## Garanties et limites

- L'accès est conditionné à `admin_unlocked()`; la fonction est `SECURITY DEFINER` avec `search_path=public`, sans droit d'exécution `PUBLIC` ou `anon`.
- La fonction est strictement en lecture seule : elle ne ferme aucune boutique, ne modifie aucune commande et ne marque aucun remboursement comme exécuté.
- Les compteurs sont un instantané, pas une garantie de cohérence à l'instant du déploiement. Les webhooks et confirmations du prestataire doivent toujours être réconciliés.
- Le wrapper Dart est disponible pour un écran admin; l'intégration visuelle au tableau de bord n'est pas incluse dans V62.

## Validation requise

1. Appliquer les migrations précédentes puis `0052_release_readiness_audit_v62.sql` sur Supabase de staging.
2. Vérifier qu'un utilisateur ordinaire obtient `admin_console_locked` et qu'un administrateur déverrouillé reçoit un JSON cohérent.
3. Créer des cas de test avec remboursement non exécuté, remboursement ancien, KYC en attente, suppression approuvée, commande contestée et paiement `refund_required`; vérifier les compteurs puis confirmer que l'appel ne modifie aucune ligne.
4. Exécuter les tests de concurrence stock, les parcours annulation/remboursement et les tests Flutter en CI.

Les outils PostgreSQL, Supabase et Flutter n'étant pas exécutés ici, V62 n'est pas certifié comme migration appliquée ou parcours testé en conditions réelles.
