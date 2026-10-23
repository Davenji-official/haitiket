# HAITIKET V43 — Annonces globales, médias et marque

## Ajouts
- Migration `0039_global_announcements_v43.sql` : annonces globales, types info/success/warning/urgent, dates optionnelles, journal d’audit et RPC d’administration protégées par `admin_unlocked()`.
- Nouvel onglet d’administration « Message global » pour publier et désactiver une annonce. Une seule annonce active à la fois.
- Bandeau d’annonce global dans le shell de l’application, alimenté par le flux Supabase Realtime si celui-ci est activé et disponible.
- Mention « Powered by FIBRAXA » dans l’interface principale.
- Diagramme horizontal des statuts de commande dans le tableau de bord admin (instantané des chiffres courants, pas encore une courbe historique).
- Le sélecteur média accepte maintenant GIF en plus de JPEG, PNG et WebP, en préservant les octets originaux afin de ne pas convertir l’animation. La limite de 3 Mo reste appliquée côté application; la validation serveur doit aussi être configurée.

## À déployer et tester
1. Appliquer la migration 0039 après la 0038 sur le projet Supabase de staging puis production selon la procédure de livraison.
2. Vérifier que la publication RPC exige un administrateur déverrouillé, qu’un utilisateur anonyme ne peut pas publier et que les annonces expirées ne sont pas exposées.
3. Activer/valider Realtime sur `platform_announcements` pour que le bandeau se mette à jour sans redémarrage; sinon les utilisateurs verront le message au prochain chargement/rafraîchissement du flux.
4. Tester GIF animé sur Android et Web, les limites de taille, le MIME réel et les politiques de stockage.
5. Les builds Flutter et les tests de staging ne sont pas certifiés depuis cet environnement.
