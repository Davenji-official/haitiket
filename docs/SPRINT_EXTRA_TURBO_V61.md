# HAITIKET V61 — Reprise explicite et sûre d'une boutique

## Changement
Un refus administratif de suppression ne doit pas réactiver automatiquement une boutique : les commandes ont pu être annulées et des remboursements ont pu être engagés. Le trigger `keep_rejected_shop_suspended_v61` garde donc la boutique suspendue lorsque la demande est refusée.

Le propriétaire peut ensuite demander une réactivation explicite via `seller_reactivate_shop_v61`. Le serveur vérifie la propriété, l'absence de suppression en attente, un KYC approuvé et l'absence de remboursements non exécutés. La réactivation remet à zéro les champs du cycle de suppression et est auditée.

## Vérifications avant production
- Appliquer les migrations V60 et V61 sur une base Supabase de staging.
- Vérifier qu'un refus administratif laisse la boutique suspendue.
- Vérifier que l'appel direct de la RPC échoue pour un non-propriétaire, un KYC non approuvé ou des remboursements en attente.
- Vérifier que la réactivation réussie rétablit l'état actif et efface les métadonnées de suppression.
- Confirmer que les politiques de statut existantes et le trigger KYC sont compatibles avec la réactivation.
- Exécuter les tests Flutter et d'intégration sur staging.

Ces vérifications statiques ne prouvent pas l'exécution réelle de la migration. Aucun appel à Supabase, aucune transaction réelle et aucun test Flutter n'ont été exécutés dans cet environnement.
