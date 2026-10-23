# HAITIKET V25 — parcours commande vers paiement interne

## Changements
- Après création et réservation des commandes, le client est dirigé vers « Mes commandes » au lieu de rester sur un écran indiquant à tort que le paiement n'est pas disponible.
- Le message de confirmation explique que chaque commande doit être payée avec le portefeuille de même devise (HTG ou USD), sans conversion automatique.
- Le bouton de paiement est désactivé pendant l'appel RPC pour éviter les doubles clics côté interface. La protection définitive reste côté serveur via la référence idempotente de commande.
- La confirmation de paiement reste basée sur la réponse du RPC `pay_order_from_wallet`, pas sur une action locale de l'application.

## Contrôles effectués
- Archive V24 valide avant modification.
- Vérification statique des modifications, du branchement `Repo.payOrderFromWallet` et de la présence de la migration financière V24.
- Recherche des appels Bazik dans le code applicatif : l'ancienne méthode `Repo.startPayment` est un garde-fou qui échoue volontairement sans appeler de fournisseur.

## Limites connues
- Flutter/Dart et PostgreSQL (`psql`) ne sont pas installés dans l'environnement de travail : aucune compilation Flutter ni exécution de migrations n'a été possible.
- Les transactions doivent encore être testées sur une base Supabase de staging avec comptes HTG/USD, stock, réservations expirées, doubles requêtes, remboursements et litiges.
- Les migrations historiques et les anciennes fonctions peuvent exister dans un projet Supabase déjà déployé. Cette archive ne désactive pas automatiquement des fonctions Edge distantes.
