# HAITIKET V59 — Registre des variantes de stock

## Livré dans le code source

- Migration `0049_variant_stock_ledger_v59.sql` : les mouvements de `product_variants.stock` sont consignés avec `variant_id`, le produit et la boutique concernés.
- La table de journal conserve des références métier facultatives (`reference_type`, `reference_id`) pour préparer le rattachement à une commande, une remise fournisseur ou un retour quand les chemins métier transmettront un identifiant fiable.
- RPC `seller_adjust_variant_stock_v59` : vérifie l'utilisateur, la boutique professionnelle active, le motif, la variation et les limites du stock; les ajustements sont exécutés côté serveur.
- L'écran Inventaire affiche maintenant les variantes (taille/couleur) et permet d'ajuster individuellement leur stock.
- Le déclencheur existant de synchronisation des variantes vers `products.stock` continue de fonctionner. Le journal peut donc afficher un mouvement de variante et un mouvement agrégé du produit pour la même opération; ce sont deux niveaux différents, pas deux ventes.
- Aucun paiement, débit de portefeuille ni conversion de devise n'est ajouté.

## Limites et précautions

Le stock agrégé `products.stock` est recalculé par le déclencheur existant quand une variante change. La protection contre les réservations de gros est prudente au niveau du produit, car `wholesale_requests` ne désigne pas une variante particulière. Les colonnes de référence métier sont facultatives et ne sont pas encore automatiquement remplies par tous les parcours de commande, remise ou retour. La migration ne fabrique pas de transitions historiques de variantes; les nouveaux mouvements sont tracés après installation.

Les accès directs déjà autorisés aux propriétaires dans les politiques RLS de `product_variants` peuvent encore produire des mouvements avec un motif générique; pour une traçabilité avec motif, utiliser la RPC V59.

## Validation et déploiement

1. Sauvegarder la base de staging et vérifier le schéma réel avant migration.
2. Appliquer `0049_variant_stock_ledger_v59.sql` après les migrations V58 et précédentes.
3. Tester insert/update/delete de variante, synchronisation du stock produit, visibilité par propriétaire et refus d'accès croisé entre boutiques.
4. Tester variation positive/négative, stock négatif, limite numérique, motif invalide et stock réservé aux achats fournisseurs.
5. Exécuter `flutter pub get`, `flutter analyze` et `flutter test`, puis les tests SQL d'intégration sur staging.

Les validations locales sont statiques : elles ne prouvent pas que la migration s'exécute sur une base distante ni que le build Flutter compile.
