# HAITIKET — état réel du projet V24

Date de l'inspection : 2026-10-23. Ce document est fondé sur le code source, les migrations et les notes présentes dans cette archive. C'est un audit statique : il ne prouve pas que les fonctions marchent sur l'application déployée ni que les migrations sont déjà installées sur le projet Supabase réel.

## 1. Ce qui est déjà présent dans le code

### Application et catalogue
- Application Flutter/Dart structurée avec navigation, écrans d'accueil, catalogue, détail produit, panier/checkout, profil, messagerie, administration et écrans de livraison.
- Modèle de produits avec catégories, variantes, prix, stocks et médias; fonctions de modification/suppression logique existent dans le code.
- Base Supabase/PostgreSQL, règles RLS et migrations versionnées; configuration et données d'administration présentes pour plusieurs fonctions.
- Plusieurs outils d'administration existent : tableaux de bord, paramètres, recherche utilisateurs, suspension, résolution de litiges et traitement de remboursements.

### Livraison et GPS
- Choix entre retrait et livraison dans le parcours de commande.
- Socle de destination GPS structurée, RPC de publication/lecture des coordonnées et restrictions de lecture de la position du coursier affecté.
- Offres de prix de livraison : migrations/RPC de création, consultation et sélection atomique, plus écrans ajoutés dans les versions précédentes.
- Flux de déclaration de retard lié au trafic avec raisons et extensions proposées dans les versions précédentes.
- Ces fonctions ne signifient pas que le suivi GPS est continu sur tous les appareils/rôles, ni que les ETA sont calculés par un service de routage réel.

### Portefeuilles et paiements
- Comptes séparés HTG et USD dans le schéma du portefeuille; les montants sont stockés en unités mineures.
- Parcours de recharge/retrait Plop Plop dans le code, taux de change configurables pour les mouvements de portefeuille concernés et vérification serveur via Edge Functions.
- Fonctions côté serveur pour les débits internes de commande/frais, la gestion de litiges, l'audit d'intégrité et les remboursements internes.
- Migrations V23/V24 pour la confirmation idempotente de recharge et le rapprochement financier en lecture seule. V24 distingue les anomalies comptables des alertes opérationnelles pour éviter d'annoncer « aucun écart » si des opérations restent à traiter.
- L'existence de ces fonctions ne prouve pas que le compte marchand Plop Plop est approvisionné, qu'un retrait est payé, ni que les fonds réels couvrent tous les soldes affichés.

## 2. Dernière amélioration faite dans V24
- Nouvelle migration `0034_financial_reconciliation_v24.sql`, à appliquer après `0033` sur une base de staging sauvegardée.
- Nouvelle RPC `run_financial_reconciliation_v24()` qui reste en lecture seule.
- Séparation des anomalies financières (`issue_count`) et des alertes opérationnelles (`warning_count`) : litiges ouverts, remboursements à exécuter/échoués, anciens paiements en attente et opérations qui stagnent depuis plus de 30 minutes contribuent aux alertes.
- Écran d'administration raccordé à la RPC V24 et affichage des clés du rapport avec des libellés français plus lisibles.
- Documentation de sprint ajoutée.

## 3. Ce qui est partiel ou doit encore être vérifié
- Le flux complet achat → débit du portefeuille → allocation vendeur/coursier/commission → livraison confirmée → libération des revenus doit être testé de bout en bout avec plusieurs comptes.
- La cohérence de tous les chemins historiques de paiement doit être revue : le dépôt contient encore des tables et fonctions de paiement historiques, et il faut vérifier qu'aucun ancien chemin Bazik n'est encore accessible dans l'application ou déployé dans Supabase. Modifier les fichiers locaux ne supprime pas une fonction déjà déployée.
- La gestion des remboursements externes Plop Plop nécessite le processus réel du fournisseur et une réconciliation; le remboursement interne du portefeuille ne remplace pas un remboursement externe.
- Les règles de réservation/libération des sommes dues aux vendeurs et coursiers, la comptabilité en partie double et la concordance des soldes avec les fonds réellement détenus nécessitent un audit spécialisé et des tests de concurrence.
- Les parcours KYC/âge/tuteur et les exigences documentaires pour tous les rôles ne sont pas certifiés de bout en bout.
- La boutique officielle HAITIKET, les badges, les abonnements, les frais Bazar et leur expiration doivent être vérifiés dans les écrans et en base pour confirmer que toutes les règles métier sont appliquées partout.
- Le taux de conversion commercial propre au vendeur et l'instantané complet des prix/taux/frais dans chaque commande doivent être vérifiés et complétés si nécessaire.
- Les notifications, la suppression de messages pour tous, les pièces jointes, la conservation des preuves de litige et les guides bilingues finaux ne sont pas certifiés complets.
- Le bouton de téléchargement des guides depuis le panneau d'administration et les guides finaux français/créole pour chaque rôle restent à confirmer.
- Les déploiements Android/Web, la configuration de stockage privé des documents, les secrets Edge, les règles de sauvegarde et les procédures d'exploitation doivent être validés.

## 4. Ce qui n'est pas encore validé
- Aucune compilation `flutter analyze`, aucun test Flutter et aucun build Android/Web n'ont été exécutés dans cet environnement : Flutter et Dart ne sont pas installés.
- Aucune migration SQL n'a été exécutée sur une vraie base Supabase connectée.
- Aucune transaction Plop Plop réelle n'a été déclenchée ou vérifiée.
- Le rapport financier V24 ne corrige volontairement aucun solde; il faut investiguer chaque anomalie et la rapprocher des relevés réels.

## 5. Ordre conseillé pour la suite
1. **Bloquant financier :** staging Supabase, vérifier l'historique réel des migrations, appliquer `0034`, tester recharge HTG/USD, webhooks répétés, montants erronés, doublons, retraits, pannes et reprises.
2. **Bloquant commande :** tester achat complet depuis portefeuille dans les deux devises, frais, commission, gains en attente, confirmation de remise/livraison, litige et remboursement.
3. **Sécurité :** inventorier les Edge Functions déployées, neutraliser les anciens chemins de paiement inutilisés et auditer les permissions RLS/service role/secrets.
4. **Livraison :** tester les offres concurrentes, les délais, les retards, les notifications et la fraîcheur réelle des positions GPS.
5. **Parcours métier :** compléter/valider KYC, abonnements, Bazar, boutique officielle, taux vendeur et règles d'expiration.
6. **Qualité de livraison :** installer l'environnement Flutter, corriger les erreurs de compilation/analyse, écrire des tests automatiques et produire des builds de staging.
7. **Lancement :** tests d'acceptation, sauvegarde/restauration, supervision, guide admin et guides utilisateurs finaux.

## 6. Verdict
HAITIKET dispose d'une base applicative et backend conséquente, mais il ne faut pas la qualifier de « terminée » ou « prête à encaisser en production » tant que les migrations, la compilation, les paiements réels, les règles de sécurité et le cycle financier complet n'ont pas été validés. Les fonctionnalités listées comme présentes sont des implémentations visibles dans le dépôt, pas une garantie de fonctionnement en production.
