# HAITIKET — complément GPS structuré v6

## Ajouts dans cette version

- Migration additive `0019_structured_delivery_gps.sql` : ajoute des colonnes GPS séparées à `orders` et `courier_status`, sans supprimer les anciennes données.
- RPC `set_order_delivery_location` : autorise un client connecté à enregistrer les coordonnées de sa propre commande en livraison, avec validation serveur des coordonnées et de l'état de la commande.
- RPC `publish_courier_location` : permet à un coursier approuvé de publier ses coordonnées via RPC plutôt que par écriture directe.
- Politique de lecture des positions : le client et le propriétaire de la boutique ne peuvent lire la position d'un coursier que si celui-ci est affecté à une commande active qui les concerne.
- Publication Realtime de `courier_status` demandée à Supabase si les permissions le permettent.
- Checkout : bouton « Utiliser ma position actuelle », récupération GPS avec demande de permission, et envoi des coordonnées structurées après création de commande. Une adresse enregistrée avec latitude/longitude sélectionnée utilise aussi ses coordonnées.
- Repository : méthodes pour appeler les deux RPC GPS.

## Limites importantes

- Cette version ne prétend pas livrer un suivi GPS continu complet. Elle prépare les colonnes, les RPC et le contrôle d'accès ; la boucle de partage en continu, les abonnements Realtime sur les écrans client/vendeur, la géolocalisation des offres et les tests de terrain restent à faire.
- Les commandes déjà créées conservent leurs coordonnées GPS à `NULL` jusqu'à ce qu'une destination soit explicitement enregistrée. Les anciennes adresses texte ne sont pas converties automatiquement.
- La commande reste en attente de paiement tant que le paiement interne réel n'est pas implémenté et validé. Ce complément GPS ne marque aucun paiement comme réussi.
- L'application Flutter n'a pas été compilée ici : aucun résultat de `flutter analyze` ou de tests n'est revendiqué.

## Migration Supabase

Ne pas exécuter à l'aveugle. Avant toute exécution, vérifier dans la base réelle que les migrations précédentes sont appliquées et que `public.orders`, `public.courier_status`, `public.delivery_jobs`, `public.shops` ainsi que `public._is_approved_courier()` existent. Si le SQL Editor retourne une erreur, arrêter et faire examiner l'erreur avant de relancer.
