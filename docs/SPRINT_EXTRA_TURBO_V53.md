# HAITIKET V53 — outils vendeur, identité de boutique et publics multiples

## Livré dans le code source

- Le formulaire de nouveau produit accepte plusieurs publics simultanément : homme, femme, enfant, adolescent et unisexe. Le filtre Marketplace permet de sélectionner un public et les fiches produit affichent les publics ciblés.
- Migration `0044_seller_tools_audiences_shop_identity_v53.sql` ajoute `products.audiences text[]`, recopie les valeurs de l'ancien champ `audience` et crée un index GIN.
- Les formulaires de caractéristiques spécifiques par catégorie existants (`SpecsForm` / `specsFor`) restent intégrés au parcours de création.
- Une recherche de boutiques actives propose des correspondances et ouvre la vitrine publique correspondante.
- Les boutiques professionnelles non personnelles obtiennent aussi le tableau de bord catalogue/stock/commandes HTG-USD, auparavant réservé à la boutique officielle.
- Les vendeurs peuvent renommer leur boutique à tout moment si le nom normalisé est disponible, la suspendre ou la fermer définitivement. L'index unique en base empêche deux noms identiques après normalisation (majuscules/minuscules et espaces). La migration échoue volontairement si des doublons historiques existent : il faut les renommer avant de la relancer.
- La fermeture est une fermeture logique (`status = closed`) afin de préserver l'historique des commandes et l'audit financier. La suppression physique directe n'est pas exposée.
- Un livreur peut retirer sa candidature. Le statut `withdrawn` conserve l'historique de candidature.
- Sur la version Web, « Copier le lien du produit » copie l'URL du site courant avec l'identifiant produit ; au chargement, l'application retrouve le produit publié et ouvre sa fiche. Le contact vendeur reste lié au produit spécifique.

## Limites à traiter ensuite

- Les liens directs natifs Android/iOS nécessitent la configuration de liens universels/app links sur le domaine officiel, qui doit être confirmé et configuré avant de produire un lien mobile durable.
- Un vendeur peut acheter dans le Marketplace avec son compte utilisateur et les tarifs par quantité existants sont disponibles ; un flux B2B séparé avec prix de gros, commande fournisseur et réapprovisionnement automatique reste un sprint distinct.
- La suppression physique d'une boutique ne doit pas effacer les commandes, remboursements ou journaux. Définir une politique de rétention et un processus administrateur avant de proposer cette action.
- Le schéma SQL et les autorisations RLS/RPC doivent être appliqués et testés en staging. La migration vérifie les noms en doublon avant de créer l'index unique.

## Recette requise

1. Sauvegarder staging et exécuter la migration V53 après avoir résolu d'éventuels doublons de noms.
2. Tester deux créations/renommages concurrents avec la même identité de boutique : une seule doit réussir.
3. Tester les publics multiples et le filtre Marketplace pour tous les publics, y compris les anciens produits migrés.
4. Tester recherche/suggestions de boutiques, boutique suspendue/fermée, et absence de produits visibles depuis une boutique inactive.
5. Retirer une candidature livreur et confirmer que le suivi GPS/disponibilité s'arrête sans supprimer l'historique.
6. Depuis un navigateur Web déployé, copier un lien produit, l'ouvrir en navigation privée et vérifier que la fiche correspondante s'ouvre. Tester ensuite les liens universels natifs séparément.
7. Exécuter `flutter analyze` et `flutter test`, puis vérifier RLS/RPC sur staging avant la production.

Les contrôles statiques ne constituent pas une compilation, une recette Supabase, un audit de sécurité ou une preuve de fonctionnement en production.
