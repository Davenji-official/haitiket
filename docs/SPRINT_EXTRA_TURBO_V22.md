# HAITIKET V22 — remboursement interne sécurisé

## Inclus
- Nouvelle RPC `admin_execute_wallet_refund(uuid,text)`.
- Action d'administration « Créditer le portefeuille » pour les demandes de remboursement en attente.
- Crédit du portefeuille de la devise d'origine, seulement si le débit `ORDER:<id>` est une transaction interne réussie et correspond exactement au total de la commande.
- Référence unique `ORDER_REFUND:<id>` pour empêcher un double remboursement.
- Bloque l'opération en cas de litige ouvert, de bénéficiaire/montant incohérent, ou si un gain vendeur/coursier a déjà été libéré.
- Les gains en attente sont inversés avant que la commande soit marquée remboursée.
- Journal d'administration et notification au client.

## Limites et déploiement
- Cette RPC ne rembourse PAS un paiement externe Plop Plop. Pour un paiement externe, l'opérateur doit effectuer le remboursement chez le prestataire, puis utiliser l'action « Confirmer remboursement externe ».
- Si un revenu vendeur/coursier a déjà été libéré, la RPC refuse et exige une revue manuelle; elle ne débite jamais automatiquement un tiers.
- Appliquer la migration `0032_wallet_refund_execution.sql` après `0031_dispute_financial_integrity.sql` sur une base de staging sauvegardée.
- Tester avec des commandes de test HTG et USD, remboursements répétés, litige ouvert, paiement externe, et revenu déjà libéré.
- Les contrôles de code statiques ne remplacent pas un test de compilation Flutter ni l'exécution SQL réelle sur Supabase.
