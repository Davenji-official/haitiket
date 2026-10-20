# HAITIKET — Sprint Turbo (20 octobre 2026)

## Changements de code de ce sprint

### Catalogue / achat
- `lib/ui/product_detail.dart`
  - sélecteur de quantité dans la fiche produit ;
  - contrôle de quantité selon le stock du produit ou de la variante sélectionnée ;
  - prix affiché spécifique à la variante si `price_minor` est renseigné ;
  - affichage de l'audience et du public cible ;
  - ouverture de l'image en plein écran avec zoom conservée ;
  - ajout au panier de la quantité sélectionnée.
- `lib/data/repo.dart`
  - `CartStore.add` accepte une quantité ;
  - le prix de base du panier tient compte d'un prix spécifique à la variante ;
  - les requêtes chargent les nouveaux champs de variantes ;
  - ajout de `deleteProduct` (suppression logique par statut `removed`, pour préserver l'historique) ;
  - ajout de `deleteNotification` limité à l'utilisateur connecté ;
  - sécurisation de la liste des champs autorisés par `updateProduct`.
- `lib/ui/screens7.dart`
  - choix du public cible lors de la création d'un produit ou d'une annonce ;
  - choix de davantage d'unités/conditionnements : unité, paire, lot, paquet, carton, douzaine, kg, g, L, m, boîte, sachet.
- `lib/ui/screens2.dart`
  - actions pour modifier les champs principaux d'un produit (nom, prix, stock, description) ;
  - action de suppression du catalogue avec confirmation ;
  - les produits retirés restent dans les historiques, mais ne sont plus listés dans la gestion du catalogue.
- `lib/ui/screens5.dart`
  - action de suppression d'une notification individuelle.
- `supabase/migrations/0013_catalog_messaging_controls.sql`
  - colonnes complémentaires pour variantes, unités, audience, attributs et date de modification ;
  - règles de suppression de notifications personnelles ;
  - état individuel de visibilité d'une conversation ;
  - colonnes de suppression logique des messages.

## Migration Supabase

La migration `0013_catalog_messaging_controls.sql` dépend des migrations précédentes et des blocs SQL A/B/C de ce projet. Ne la lancez pas à l'aveugle sur une base déjà partiellement migrée. Sauvegardez d'abord la base et vérifiez les migrations effectivement appliquées.

## Limites explicites

- Le code n'a pas été compilé ici : Flutter/Dart ne sont pas installés dans l'environnement de préparation.
- Le résultat de GitHub Actions reste la validation de compilation à faire après push.
- L'édition intégrale des variantes et des médias, la lecture vidéo intégrée plein écran, les suppressions de conversations/messages dans l'interface, les paiements réels Pay'm Plop Plop, les webhooks de paiement et les parcours de livraison en production ne sont pas achevés par ce sprint.
- La suppression d'un produit est logique (`status = 'removed'`), et non une suppression physique, pour ne pas casser les commandes existantes.
- Les règles d'autorisation RLS de la base doivent être testées sur le projet Supabase réel.

## Publication

À la racine du dépôt `Davenji-officiel/haitiket`, conserver `pubspec.yaml`, `lib/`, `supabase/`, `.github/` et ce document. Après le push, vérifier l'onglet Actions et ne pas activer les paiements en production avant validation des Edge Functions et renouvellement de toute clé privée déjà exposée.

## Édition vendeur — galerie média
- Le formulaire « Modifier complètement le produit » charge la galerie existante depuis `product_media` (ou reprend `image_url` comme solution de repli).
- Le vendeur peut ajouter plusieurs photos, ajouter une vidéo, retirer un média avec ✕ et enregistrer la galerie; la première image restante devient la couverture `image_url`.
- L'édition couvre aussi nom, prix, stock, description, unité de vente et public concerné.
- L'enregistrement des médias s'appuie sur les politiques RLS de `product_media` et sur le bucket `media` déjà défini dans les migrations. Vérifier que les migrations 0009 et suivantes ont été appliquées avant de tester.
- Limite actuelle : l'éditeur ne permet pas encore de modifier visuellement les variantes individuelles (tailles/couleurs/SKU/prix et stock par variante), la catégorie ni toutes les caractéristiques structurées; ne pas présenter cela comme terminé.
