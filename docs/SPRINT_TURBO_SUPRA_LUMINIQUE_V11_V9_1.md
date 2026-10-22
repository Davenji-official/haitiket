# SPRINT TURBO SUPRA LUMINIQUE — V11 (V9.1 GPS)

## Modifications
- L'écran de suivi lit désormais l'horodatage `location_updated_at` renvoyé par le serveur, au lieu de présenter l'heure de consultation comme l'heure de position.
- L'écran affiche un avertissement lorsque la dernière position connue a plus de deux minutes.
- La carte affiche le marqueur du coursier et, lorsque les coordonnées sont réellement enregistrées, le marqueur de destination.
- Si la destination ou la position n'existe pas, l'écran l'indique explicitement et ne fabrique pas de coordonnées.
- Migration `0021_tracking_destination_timestamp.sql` : la RPC sécurisée retourne les coordonnées de destination et leur horodatage avec la position du coursier.

## Installation
1. Ouvrir Supabase → SQL Editor.
2. Exécuter une seule fois `supabase/migrations/0021_tracking_destination_timestamp.sql` après les migrations 0019 et 0020 déjà appliquées.
3. Construire et tester l'application avec Flutter dans l'environnement du projet.

## Limites à ne pas masquer
- Cette archive n'a pas été compilée ici : Flutter/Dart CLI n'est pas disponible dans l'environnement de création.
- Le suivi dépend du GPS autorisé, du réseau, de l'affectation du coursier et de l'envoi réel de ses coordonnées.
- La migration ajoute les coordonnées de destination à la réponse de la RPC, mais ne remplit pas les coordonnées absentes des anciennes commandes.
- La carte ne calcule pas encore un itinéraire routier ni une ETA réelle.
- V9.2 (diffusion/acceptation concurrente et tournées multiples) et V9.3 (audit financier complet) ne sont pas déclarées terminées dans cette version.
- Aucun paiement, solde ou événement financier n'est simulé.
