# HAITIKET — Sprint Extra Turbo Supraluminique V17

## Ajouts

- Migration `0027_traffic_delay_and_admin_settings.sql` : ajoute au job de livraison un signalement de retard de circulation avec durée autorisée de 120 ou 240 minutes, motif obligatoire, horodatage et verrou empêchant plusieurs prolongations pour une même mission.
- RPC `report_delivery_traffic_delay` : réservée au coursier affecté à une mission `assigned` ou `picked_up`. Le serveur valide le rôle, la durée, le motif et l'unicité du signalement.
- RPC `get_delivery_traffic_delay` : ne révèle le motif qu'au client propriétaire de la commande ou au coursier affecté.
- Écran coursier : menu d'action pour confirmer la collecte/remise ou signaler un retard de circulation.
- Écran de suivi client : affiche le retard, la prolongation et le motif remontés par le serveur.
- Réglages administrateur : la liste blanche SQL accepte désormais les clés affichées dans l'interface V15/V16, avec validations et journalisation. Le réglage d'expiration des offres pilote réellement leur durée (1 à 60 minutes, défaut 10).

## Déploiement

1. Sauvegarder la base Supabase et le code.
2. Vérifier que les migrations précédentes ont été appliquées dans l'ordre, jusqu'à `0026`.
3. Appliquer uniquement `0027_traffic_delay_and_admin_settings.sql` sur une base déjà migrée.
4. Tester avec un coursier approuvé ayant une mission attribuée et un compte client propriétaire de la commande.
5. Vérifier que le client voit le motif, qu'une seconde déclaration est refusée et qu'un autre utilisateur ne peut pas consulter le motif.

## Limites connues

- La prolongation est une information de suivi, pas une garantie ni un calcul de trafic cartographique.
- La modification du réglage `payment_provider` ne connecte pas automatiquement Plop Plop ou Bazik. Les Edge Functions, secrets, signatures et webhooks doivent être configurés et testés séparément.
- La sélection d'une offre de coursier n'est pas encore reliée à un débit de portefeuille/escrow transactionnel. Ne pas annoncer le paiement automatique de la livraison comme fonction terminée.
- Aucun build Flutter ni test sur une base Supabase réelle n'a été possible dans cet environnement. Exécuter les tests de déploiement avant la production.
