# HAITIKET — Sprint Turbo Supra Luminique V12 (V9.2)

## Périmètre de ce sprint

- La liste des missions ouvertes est diffusée par RPC aux coursiers approuvés et disponibles dont la dernière position GPS serveur date de moins de 3 minutes.
- La boutique doit avoir des coordonnées GPS et être active. Seules les missions situées dans un rayon de 25 km à vol d'oiseau sont proposées.
- L'acceptation revalide côté serveur le statut de la commande, la boutique, la fraîcheur GPS, le rayon et la capacité.
- Un verrou transactionnel par coursier sérialise ses acceptations et évite de dépasser la limite de 3 missions actives.
- Le verrou de la mission et la mise à jour conditionnelle évitent qu'une même mission soit affectée à deux coursiers.
- Les anciennes fonctions restent utilisables par l'écran Flutter via les mêmes signatures RPC.

## Installation Supabase

1. Dans Supabase → SQL Editor, exécuter une seule fois `supabase/migrations/0022_courier_broadcast_atomic_acceptance.sql` après la migration `0021_tracking_destination_timestamp.sql`.
2. Vérifier que les boutiques qui proposent la livraison ont leurs coordonnées `shops.lat` / `shops.lng` renseignées, et que les coursiers autorisés publient réellement leur GPS.
3. Tester avec deux comptes coursiers approuvés et deux appareils/sessions distincts, en lançant des acceptations simultanées sur la même mission puis sur plusieurs missions.

## Limites honnêtes

- La diffusion actuellement disponible est une liste actualisée par appels de l'application, pas une notification push garantie en arrière-plan. L'app doit consulter `list_open_jobs()` pendant que le coursier est actif.
- Le rayon de 25 km est une distance géographique à vol d'oiseau; il ne représente ni la distance routière ni l'ETA. Il est codé dans cette migration et devra devenir un paramètre administrable dans un sprint ultérieur.
- Une mission sans coordonnées de boutique ou avec une position de coursier périmée n'est pas proposée/acceptée. Cela évite de prétendre connaître une proximité inconnue.
- La limite est de 3 missions dont le statut est `assigned` ou `picked_up`. Ce sprint ne crée pas de logique d'optimisation de tournée ni de contrôle de compatibilité de colis.
- Le code Flutter n'a pas été compilé ici, car l'environnement ne dispose pas de Flutter/Dart CLI. Le SQL doit être appliqué et validé dans le projet Supabase avant de considérer le sprint déployé.
- Aucun paiement, solde ou revenu n'est simulé. L'audit financier V9.3 reste à faire.
