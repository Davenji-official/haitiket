# HAITIKET V50 — Tableau de gestion de la boutique officielle

## Livré dans le code
- Ajout d'une vue d'ensemble dans le panneau de la boutique officielle HAITIKET.
- Indicateurs catalogue : nombre de produits chargés, produits publiés et produits publiés dont le stock est inférieur ou égal à 3.
- Alertes de réapprovisionnement listant jusqu'à cinq produits à stock faible.
- Comptage des commandes par statut pour les commandes les plus récentes chargées par le dépôt.
- Totaux des montants de commandes HTG et USD calculés séparément, sans conversion implicite.
- Mention explicite que les commandes visibles sont limitées aux 50 plus récentes et que ces totaux ne sont pas un relevé comptable.

## Limites importantes
- La vue réutilise les produits du dépôt et `Repo.shopOrders`, qui ne charge que 50 commandes au maximum. Les totaux ne sont donc pas des statistiques historiques complètes.
- Les totaux représentent les `total_minor` des commandes chargées, quels que soient leurs statuts; ils ne doivent pas être interprétés comme des revenus encaissés ou libérés.
- Aucun changement de schéma SQL ni aucun traitement de paiement n'est introduit dans V50.
- Flutter analyze/test/build, essais sur appareil, et vérifications des permissions et données réelles Supabase restent à exécuter dans l'environnement de staging/CI. Les validations locales sont statiques.

## Vérifications
Lancer `./scripts_validate_v50.sh`. Ce script vérifie les contrats statiques de V50 et les versions précédentes; il ne remplace pas les tests Flutter ni la recette de staging.
