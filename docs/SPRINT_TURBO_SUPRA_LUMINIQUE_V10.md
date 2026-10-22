# HAITIKET — Sprint Turbo Supra Luminique V10

## Travail ajouté : destination choisie sur carte au checkout

Le checkout permet maintenant au client de choisir le lieu réel de remise du colis, au lieu de dépendre uniquement de son adresse domicile enregistrée.

### Parcours utilisateur

1. Choisir « Livraison HAITIKET ».
2. Saisir une adresse/repères, sélectionner une adresse sauvegardée, utiliser le GPS actuel ou toucher la carte pour choisir le point de remise.
3. Confirmer le point choisi et vérifier les coordonnées affichées.
4. Les coordonnées sont ensuite envoyées via la RPC existante `set_order_delivery_location` pour chaque commande, lorsque la commande et son statut l'autorisent.

Cela convient à une destination ponctuelle telle que l'université, l'école, le travail, un domicile différent, chez un ami ou un lieu de déplacement. Le client doit toujours fournir des repères lisibles pour que le livreur retrouve l'entrée exacte.

## Limites connues

- Il s'agit d'une sélection réelle de coordonnées via carte/GPS, pas d'un géocodage automatique du nom de rue.
- Le client doit vérifier le point sélectionné. Une carte OSM ne garantit pas que chaque ruelle ou bâtiment d'Haïti soit cartographié.
- L'écran ne calcule pas encore l'ETA routière réelle ni le coût d'offres de plusieurs livreurs.
- L'enregistrement de commande et l'enregistrement de coordonnées sont encore deux appels distincts : si la seconde opération échoue, la commande peut exister sans coordonnées enregistrées. L'interface affiche un avertissement dans ce cas. Une future migration métier devra rendre ce flux atomique.
- Le suivi en direct dépend de l'autorisation GPS, de la publication effective de la position par le coursier et de la disponibilité réseau. Il ne faut pas promettre une précision « à chaque pas » : la fréquence dépend de l'appareil, du système, du réseau et des autorisations d'arrière-plan.
- Aucun test `flutter analyze`, test automatisé, build Android/iOS/Web ni test terrain n'est revendiqué, car Flutter/Dart n'est pas installé dans l'environnement de préparation.

## Paiements

Le cahier des charges utilisateur demande de privilégier Pay'm Plop Plop et de retirer Bazik. Dans l'archive de base, les achats, abonnements et promotions appellent encore la fonction Edge `bazik-pay`; les fonctions `plopplop-wallet` visibles dans le dépôt concernent la recharge/retrait du portefeuille, pas une intégration complète du checkout marchand. Pour éviter de déclarer un paiement disponible à tort, le fournisseur de checkout n'est pas silencieusement basculé dans cette version. Il faut implémenter et tester les actions serveur de création/vérification du paiement marchand Plop Plop, ses webhooks signés et l'idempotence avant d'activer le bouton en production.

## Contrôles recommandés

- `flutter pub get`
- `flutter analyze`
- `flutter test`
- `flutter build web --release`
- vérifier le checkout avec destination domicile, destination GPS courante, point sur carte, et retrait chez le vendeur ;
- vérifier côté Supabase que la destination n'est modifiable que par le client propriétaire avant les étapes autorisées ;
- tester refus d'autorisation GPS, GPS désactivé, réseau interrompu et erreur RPC.
