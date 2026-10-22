# HAITIKET — Audit statique SQL et sprint GPS v7

## Ce qui a été inspecté

Audit statique des fichiers SQL présents dans cette archive (`0001` à `0019`, `SQL_bloc_A.sql`, `SQL_bloc_B.sql`, `SQL_bloc_C.sql`, `diagnostic_base.sql`) et des appels Flutter liés à la disponibilité et à la position du coursier.

## Limite de vérification

Cet audit inspecte les fichiers locaux. Il ne prouve pas que ces scripts ont tous été appliqués à l'instance Supabase réelle : aucune connexion SQL directe n'est disponible depuis cet environnement. Ne pas interpréter ce document comme un certificat de migration exécutée.

## Risque important de double exécution

Les blocs `SQL_bloc_A.sql`, `SQL_bloc_B.sql`, `SQL_bloc_C.sql` contiennent des définitions qui recoupent des migrations numérotées, notamment les objets de coursiers (`courier_status`, `delivery_jobs`, fonctions d'acceptation) et plusieurs objets opérationnels. Les blocs ne doivent pas être considérés automatiquement comme des migrations supplémentaires à rejouer après les migrations numérotées. Certaines instructions `CREATE TABLE` / `CREATE POLICY` sans `IF NOT EXISTS` échoueront si l'objet existe déjà. Ne pas relancer tous les fichiers en aveugle.

## Sprint v7 livré dans le code

- L'espace coursier démarre un flux GPS quand le coursier est déjà disponible à l'ouverture de l'écran.
- L'interrupteur de disponibilité démarre/arrête le partage GPS.
- Le flux demande la permission, vérifie le service de localisation, publie les coordonnées par la RPC `publish_courier_location` et limite les publications rapprochées à une publication au plus toutes les 12 secondes, avec un filtre de déplacement de 15 m.
- Les erreurs réseau ponctuelles de publication sont journalisées sans arrêter immédiatement le flux.
- La souscription GPS est annulée lorsque l'écran coursier est détruit ou lorsque le coursier passe indisponible.

## Limites restantes

- Ce flux fonctionne tant que l'écran/appareil permet à l'application de recevoir des positions. Il ne garantit pas le suivi en arrière-plan lorsque le système suspend l'application.
- Les clients/vendeurs n'ont pas encore un écran de carte qui consomme en temps réel la position du coursier.
- Le filtrage géographique des missions, les offres concurrentes de prix/délai, et le choix d'une offre par le client ne sont pas implémentés ici.
- L'intégration des paiements de commandes sur le portefeuille interne n'est pas validée par ce sprint.
- Aucun test Flutter/Dart ni test d'intégration Supabase n'a été exécuté dans cet environnement : le SDK Flutter/Dart n'y est pas disponible.

## Vérification requise côté Supabase

Confirmer via le SQL Editor les objets attendus (colonnes GPS, fonctions, politiques) et l'état de la publication Realtime. Une erreur `duplicate_object` sur la publication n'est pas une preuve d'échec ; elle signifie que la table est déjà dans la publication. Si les fonctions RPC renvoient une erreur, conserver le code et le message exacts avant toute correction.
