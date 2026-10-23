# HAITIKET V66 — Bazar KYC et icône de l’application

## Changements
- Le parcours de publication au Bazar vérifie d’abord que le compte est connecté et que `my_verification_badges_v60()` indique `identity_status = approved`.
- Une migration ajoute un trigger serveur sur `products` : les insertions/modifications avec `source = 'bazar'` sont refusées si le propriétaire de la boutique n’a pas un dossier KYC approuvé. Le contrôle UI seul n’est donc pas l’unique protection.
- Le panda vert fourni a été préparé en PNG 1024 × 1024 dans `assets/logo.png`. `pubspec.yaml` configure `flutter_launcher_icons` pour Android et le web, avec un fond adaptatif vert. Les coins arrondis du launcher Android sont normalement appliqués par le système.
- Le dossier `assets/mascots/` est créé car il est référencé par `pubspec.yaml`.

## Mise en place
1. Exécuter les migrations dans l’ordre sur une base de staging.
2. `flutter pub get`
3. `dart run flutter_launcher_icons`
4. `flutter analyze`
5. `flutter test`
6. Tester sur un appareil Android réel et un navigateur web.

## État du projet — ce que les sources permettent d’affirmer
- Les sources contiennent des fonctions de portefeuille, commandes, candidatures de livreur, badges de vérification, KYC, confirmations de livraison et administration, ajoutées sur plusieurs versions.
- Le code source seul ne prouve pas que les paiements, remboursements, notifications, suivi GPS ou confirmations de livraison fonctionnent de bout en bout en production.
- Ce paquet ne marque pas les tests Flutter, migrations Supabase ni paiements réels comme réussis. Ils doivent être exécutés sur staging.
- Le contrôle KYC du Bazar porte sur la dernière vérification associée au propriétaire. Tester les cas d’approbation, rejet, changement de boutique et utilisateur sans dossier avant déploiement.
