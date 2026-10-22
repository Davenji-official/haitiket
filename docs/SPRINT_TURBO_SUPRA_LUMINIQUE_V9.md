# HAITIKET — Sprint Turbo Supra Luminique V9

## Ajouts de cette archive

- Ajout d'un écran de suivi client accessible depuis les commandes confirmées et les étapes de livraison.
- La carte OpenStreetMap affiche la dernière position autorisée du coursier affecté, via la RPC existante `get_active_courier_location`.
- Actualisation automatique toutes les 10 secondes lorsque l'application est au premier plan, plus un bouton d'actualisation manuelle.
- Arrêt du polling à la fermeture de l'écran. Aucun accès direct Flutter à la table `courier_status` n'est ajouté.
- Aucun nouveau SQL n'est requis pour l'écran : il réutilise la migration `0020_secure_courier_location_read.sql` déjà présente dans cette archive.

## Limites connues — à ne pas présenter comme une certification production

- L'écran montre une position reçue, pas une navigation routée ni une ETA calculée.
- La position ne sera disponible que si une mission est affectée, si le statut de commande autorise la lecture et si le coursier publie réellement sa position depuis l'application ouverte.
- L'écran n'affiche pas encore en direct l'itinéraire client-vendeur-coursier, les coordonnées de destination, ni les profils/avatars.
- Le dépôt inclut les migrations 0019 et 0020. Si elles ont déjà été exécutées dans Supabase, ne les relance pas inutilement.
- Aucun résultat de `flutter analyze`, test automatisé, build Android/Web ou test terrain n'est revendiqué dans cette archive.

## Contrôles après téléchargement

1. `flutter pub get`
2. `flutter analyze`
3. `flutter test`
4. `flutter build web --release`
5. Vérifier avec un compte client autorisé et une commande avec coursier affecté.
6. Vérifier qu'un utilisateur tiers ne peut pas lire la position du coursier.
