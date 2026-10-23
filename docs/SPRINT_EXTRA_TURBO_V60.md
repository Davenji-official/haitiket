# HAITIKET V60 — Traçabilité, cycle de vie boutique, KYC et administration

## Inclus dans le code

- `0050_stock_refs_shop_lifecycle_kyc_admin_v60.sql` ajoute les références de journal pour les mouvements issus des commandes, les remises fournisseurs et les réceptions/retours déclarés par RPC.
- Les écritures de stock se font sous verrou de ligne (`FOR UPDATE`) et vérifient les limites avant mise à jour. Les parcours de commande existants restent la source des changements de stock; la corrélation automatique s'appuie sur `inventory_movements` et doit être testée sur des commandes multi-articles en staging.
- Une suspension ou une demande de suppression gèle la boutique et traite les commandes non terminées. Les commandes payées/en cours produisent une demande de remboursement idempotente. Les remboursements sont **mis en file**, jamais déclarés exécutés par cette migration : un opérateur doit confirmer le remboursement réel chez le prestataire via le flux existant.
- La suppression est logique : délai minimal de 30 jours, décision administrative déverrouillée, vérification de commandes/litiges/remboursements et conservation de l'historique. Les litiges empêchent l'approbation automatique.
- Le KYC stocke les chemins de documents dans un bucket privé `kyc-private`. L'âge est calculé côté serveur. Les majeurs doivent fournir CIN/NINU, passeport ou permis; les mineurs doivent fournir acte de naissance, documents d'un responsable majeur et photo récente. L'approbation est réservée à l'administration déverrouillée.
- Les boutiques et livreurs disposent d'horodatages de vérification pour distinguer les badges de vérification des annonces Bazar. L'administration peut bannir, rétablir ou supprimer logiquement un profil, avec motif et audit.

## Points de sécurité et limites connues

- `soft_delete` conserve les commandes, l'audit et les références KYC; ce n'est pas une suppression physique des données. Une politique de conservation et d'effacement conforme à la loi applicable doit être définie avant lancement.
- Les documents KYC sont sensibles. Seuls le propriétaire du dossier et l'administration déverrouillée ont accès aux objets via les politiques du bucket privé. Ne jamais afficher les chemins ou documents KYC dans des listes publiques ou des exports CSV.
- Le bannissement et la suppression logique mettent aussi `auth.users.banned_until` à une échéance très éloignée (100 ans) pour bloquer les connexions/renouvellements de jeton GoTrue; le rétablissement retire ce blocage. Les sessions déjà émises peuvent rester valides jusqu'à expiration : les gardes applicatifs et RPC doivent être vérifiés en staging.
- Les commandes déjà livrées/terminées sont conservées; elles ne sont pas annulées rétroactivement. Les litiges sont bloqués pour examen humain. Les articles déjà en transit ne sont pas réinjectés dans le stock disponible tant que leur retour physique n’a pas été confirmé.
- La réception fournisseur/retour ajoute du stock à un produit/variante appartenant à la boutique appelante. Les références de réception fournisseur doivent pointer vers une demande de gros remise par le fournisseur et appartenant à la boutique acheteuse; les retours doivent correspondre à une commande livrée/terminée/remboursée et au produit/variante concernés. Les références sont idempotentes par produit/variante/type.
- Les badges ne sont pas un service de vérification d'identité automatisé : la décision et l'horodatage restent administratifs.

## Plan de recette staging obligatoire

1. Appliquer toutes les migrations dans l'ordre sur une copie de staging et confirmer que les fonctions `admin_unlocked`, `_restore_stock`, `_cancel_order`, `inventory_movements`, `refund_requests` et `delivery_jobs` correspondent au schéma.
2. Avec deux sessions, tenter d'acheter les dernières unités simultanément; une seule opération doit réussir, le stock ne doit jamais être négatif et chaque mouvement doit avoir sa référence de commande.
3. Tester plusieurs articles identiques, variantes multiples, annulation, réservation expirée et remise fournisseur; vérifier les liens `reference_type/reference_id` sans doublons erronés.
4. Suspendre une boutique ayant une commande en attente et une commande payée : la première doit être annulée, la seconde annulée avec remboursement en file, et aucune demande ne doit être dupliquée lors d'un nouvel appel.
5. Vérifier que le finaliseur refuse une suppression avant 30 jours, en présence d'un litige ou d'un remboursement non exécuté.
6. Vérifier l'âge au jour anniversaire, les dossiers majeurs et mineurs, l'accès interdit aux documents privés pour un autre utilisateur, l'approbation/refus et le badge affiché seulement après approbation.
7. Vérifier les actions admin ban/unban/suppression logique et confirmer qu'une session déjà ouverte est effectivement bloquée par les gardes applicatifs et API après déploiement.

## Exécution

Lancer `./scripts_validate_v60.sh`. Les contrôles sont statiques; ils ne remplacent ni `flutter analyze`, ni les tests Flutter, ni l'exécution réelle de migrations/tests concurrents Supabase.
