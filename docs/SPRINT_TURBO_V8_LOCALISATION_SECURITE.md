# HAITIKET — Sprint Turbo v8 : sécurisation de la lecture GPS

## Modifications

- Ajout de la migration `0020_secure_courier_location_read.sql`.
- Suppression de la policy directe `courier_status_related_read` ajoutée par le sprint GPS précédent.
- Ajout de la RPC `get_active_courier_location(p_order)` : le serveur vérifie que l'appelant est le client de la commande ou le propriétaire de la boutique, puis ne retourne que la position du coursier affecté à une mission admissible.
- Ajout de `Repo.activeCourierLocation(orderId)` pour appeler cette RPC depuis Flutter.
- Correction du cycle GPS du coursier : l'abonnement est actif avant la première émission, l'état de disponibilité est suivi et la publication reprend lorsque l'espace coursier est rouvert alors que le coursier est toujours disponible.
- Arrêt du flux GPS lorsque l'application passe en arrière-plan/inactive. Ce choix évite de prétendre fournir un service natif de localisation permanente ; la reprise se fait lorsque l'application revient au premier plan.

## Installation

1. Cette migration dépend de `0019_structured_delivery_gps.sql`, et donc de `orders`, `shops`, `delivery_jobs`, `courier_status` et des colonnes GPS créées précédemment.
2. Vérifier que `0019` a été exécutée sans erreur avant d'exécuter `0020`.
3. Ne pas réexécuter tous les blocs A/B/C ni toutes les migrations à l'aveugle.
4. Après la migration, tester l'accès avec un compte client autorisé, le propriétaire de la boutique, un utilisateur tiers et un coursier non affecté. Les deux derniers doivent être refusés/ne recevoir aucune position.

## Limites honnêtes

- Cette migration ne construit pas encore l'écran cartographique client/vendeur qui affiche la position reçue.
- Elle n'active pas un service GPS natif en arrière-plan.
- La disponibilité Realtime et la réception des changements doivent être vérifiées dans Supabase.
- Aucun `flutter analyze`, test d'intégration ou test SQL réel n'a été exécuté dans cet environnement. Ne pas présenter ce sprint comme certifié production.
