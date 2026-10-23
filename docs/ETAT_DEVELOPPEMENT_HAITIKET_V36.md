# État du développement HAITIKET — revue du dépôt V36

Cette revue décrit ce qui est visible dans l'archive source. « Présent dans le code » ne signifie pas « déployé », « testé en production » ou « garanti opérationnel ».

## Présent dans le dépôt

- Application Flutter avec authentification, navigation, écrans catalogue/boutiques, détail produit, commandes, profil, messagerie, notifications, carte et écrans d'administration.
- Assets de marque et mascottes : accueil, panier, commandes, Bazar, boutiques, messagerie, notifications, profil, administration, portefeuille, vendeur, support.
- Modèle de commande avec statuts `PENDING_PAYMENT`, `PAYMENT_PROCESSING`, `PAID`, `CONFIRMED`, `PREPARING`, `READY_FOR_PICKUP`, `IN_TRANSIT`, `DELIVERED`, `COMPLETED`, `CANCELLED`, `DISPUTED`, `REFUNDED`.
- Portefeuilles internes HTG/USD et ledger de transactions dans les migrations; opérations prévues de recharge/retrait; fonctions de paiement commande, frais Bazar, abonnement boutique et frais de livraison.
- Intégration source Plop Plop via trois Edge Functions : wallet, webhook et retrait.
- Flux de livraison avec offres de coursiers, coordonnées/GPS dans le schéma, confirmation de collecte et de livraison par PIN, et garde-fous litige/remboursement dans les migrations.
- Fonctions d'administration/audit et actions de remboursement internes/externes dans le code.
- Tests Flutter visibles dans le dépôt : `test/i18n_test.dart` et `test/config_test.dart`; contrôles statiques et workflow CI.

## Présent mais à vérifier avant de le considérer prêt

- Exécution réelle de toutes les migrations sur la base Supabase qui sert l'application.
- Déploiement des Edge Functions, configuration des secrets, URLs de webhook et signatures/authenticité des notifications Plop Plop.
- Exécution de la matrice V36 sur staging, notamment idempotence, montants divergents, retraits, remboursements et litiges.
- Compilation Flutter, `flutter analyze` et `flutter test` dans un environnement avec Flutter installé.
- Parcours GPS sur appareils réels, permissions de localisation, précision/rafraîchissement, et gestion de la perte de réseau.
- Revue des politiques RLS/grants et tests de rôles client/vendeur/coursier/admin sur staging.

## Partiellement ou pas démontré par le dépôt seul

- Un vrai paiement Plop Plop de bout en bout, une recharge ou un retrait réellement réussi.
- Confirmation que les migrations sont synchronisées avec le projet distant.
- Garantie de libération de tous les revenus dans chaque cas d'exception; les règles SQL doivent être testées avec des données de scénario.
- SLA de livraison de 45 minutes, disponibilité de coursiers, notifications temps réel et suivi GPS réellement continu.
- Publication Android/iOS, conformité juridique/comptable, support de production et disponibilité opérationnelle.
- Les revenus futurs de la plateforme : ils dépendent du volume réel de commandes, des commissions, frais, coûts et de l'adoption.

## Ordre recommandé avant lancement

1. Réaliser sauvegarde et staging isolé.
2. Appliquer/contrôler les migrations et les permissions.
3. Déployer et vérifier les trois Edge Functions Plop Plop.
4. Exécuter la matrice `SPRINT_EXTRA_TURBO_V36.md` sans argent réel.
5. Corriger les échecs puis répéter les tests.
6. Faire revue de sécurité indépendante et test Flutter/Android.
7. Lancer progressivement avec plafonds, surveillance et procédure de rapprochement/remboursement.
