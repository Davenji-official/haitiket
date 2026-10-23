# HAITIKET V58 — Registre des mouvements de stock

## Livré dans le code source

- Migration `0048_product_stock_ledger_v58.sql` : journal des mouvements par produit et boutique, indexé par date.
- Déclencheur SQL qui trace les stocks initiaux positifs et chaque variation ultérieure du champ `products.stock`.
- RLS en lecture pour les seuls propriétaires de la boutique concernée; aucune écriture directe accordée aux rôles client.
- RPC `seller_adjust_product_stock_v58` qui vérifie l'authentification, la propriété de la boutique professionnelle active, le motif, l'amplitude de variation et l'interdiction d'un stock négatif.
- Écran Inventaire et mouvements de stock accessible depuis le centre fournisseurs, avec sélection d'un produit, ajustement positif/négatif, motif obligatoire et journal des 200 derniers mouvements accessibles.
- Aucun débit de portefeuille, paiement fournisseur ou conversion de devise n'est déclenché.

## Sémantique et limites

Le journal capture la variation du stock enregistrée sur `products.stock`. Il n'attribue pas automatiquement chaque mouvement à une commande de détail précise, car toutes les voies de mutation de stock n'exposent pas nécessairement un identifiant de commande commun. Les variantes de produits possèdent leur propre stock : V58 agissait sur `products.stock`; la migration V59 ajoute le journal et les ajustements dédiés à `product_variants.stock`. L'historique commence à l'installation; la migration enregistre un stock de référence pour les produits existants dont le stock est positif, sans inventer les mouvements passés.

## Déploiement prudent

1. Sauvegarder la base Supabase de staging.
2. Vérifier les types/contraintes de `products.stock`, `products.shop_id`, `shops.owner_id` et la séquence générée de la table de mouvements.
3. Appliquer `0048_product_stock_ledger_v58.sql` sur staging.
4. Tester avec deux comptes et deux boutiques : lecture autorisée au propriétaire, refus pour un autre utilisateur, variation positive, variation négative, refus de stock négatif, refus de descendre sous le stock réservé aux fournisseurs, motif trop court, mises à jour de stock concurrentes.
5. Vérifier que le stock et le journal sont cohérents après chaque mutation (y compris vente, livraison et remise fournisseur).
6. Exécuter `flutter pub get`, `flutter analyze` et `flutter test` dans CI.

Les contrôles statiques du dépôt ne remplacent pas la compilation Dart, l'exécution SQL réelle ou les tests d'intégration Supabase.
