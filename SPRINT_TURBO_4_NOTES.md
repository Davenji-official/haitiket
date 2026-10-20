# Sprint Turbo 4

- Éditeur produit enrichi : catégorie, devise affichée, statut (publié/masqué/brouillon), caractéristiques JSON, en plus du nom, prix, stock, unité, audience, description et médias.
- Portefeuille : schéma de compte/transactions, solde dérivé, flux de recharge Plop Plop, vérification API et webhook signé.
- Éditeurs visuels des variantes (taille/couleur/SKU/prix/stock/attributs) et tarifs par quantité ajoutés à l’édition des produits existants. Les variantes utilisées par des commandes historiques sont conservées pour éviter de casser les clés étrangères.
- Edge Function `plopplop-withdraw` et interface de retrait MonCash/NatCash ajoutées, avec signature HMAC et vérification d’un retrait en cours. La production reste bloquée tant que le solde prépayé marchand, le rapprochement et les tests réels ne sont pas validés.
- Les revenus vendeur/livreur, paiements de commande et abonnements ne sont pas encore entièrement connectés au portefeuille ; voir `PLOPPLOP-INTEGRATION.md`.
- Flutter/Dart ne sont pas installés dans l'environnement de préparation : aucune compilation Flutter n'a pu être certifiée. Vérifier GitHub Actions avant déploiement.
