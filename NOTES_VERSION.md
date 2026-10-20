# Notes de version — archive HAITIKET

## Changements réalisés dans cette archive

1. **Galerie produit agrandissable** : toucher une photo ouvre une visionneuse plein écran, avec zoom par pincement/interaction et bouton de fermeture. La navigation des médias existante reste en place.
2. **Migration SQL 0013** : complète le modèle de catalogue avec `unit_label`, `audience`, `attributes`, un prix/SKU/libellé d'unité/attributs par variante et `updated_at` pour les produits.
3. **Notifications** : ajout d'une politique RLS permettant à un utilisateur de supprimer une notification qui lui appartient. La commande source n'est pas supprimée.
4. **Discussions** : ajout de `conversation_user_state` pour stocker le masquage individuel d'une conversation, sans la supprimer chez l'autre participant.
5. **Messages** : ajout de champs de suppression logique (`deleted_at`, `deleted_by`) et d'une politique pour que l'auteur puisse mettre à jour son message. Le client doit utiliser ces champs pour afficher « message supprimé » plutôt que faire un effacement irréversible.
6. **Documentation** : instructions de déploiement et liste de contrôles avant publication.

## Capacités déjà présentes dans la base de code source examinée

- Application Flutter avec Supabase.
- Écrans de catalogue, boutiques, Bazar, fiche produit, ajout de photos/vidéos, champs de caractéristiques.
- Tables de variantes taille/couleur et tarifs par quantité dans la migration 0011.
- Panier/commandes, cartes, messagerie, notifications, écrans administrateur et fonctions de paiement Bazik sont présents sous diverses formes dans le dépôt.

La présence de code ou de tables ne prouve pas que le parcours complet fonctionne en production. Le dépôt lui-même précise que plusieurs éléments (paiement, livraison/matchmaking, portefeuille, messagerie, admin, carte et notifications) ne sont pas encore validés comme fonctionnels de bout en bout. Ces fonctions ne doivent donc pas être annoncées comme garanties avant essais réels.

## Fonctionnalités toujours à terminer / valider

- Ajouter dans les écrans de commande la sélection de prix par variante et le conditionnement (unité/paire/lot/paquet/carton), avec vérification serveur du prix final et du stock.
- Finaliser la suppression/mise à jour des produits et la fermeture de boutique dans l'interface, avec protections pour les commandes historiques.
- Connecter l'interface aux nouvelles colonnes de migration 0013 et intégrer le masquage individuel des conversations ainsi que l'affichage des messages supprimés.
- Afficher les photos de profil des participants et le logo/photo de boutique dans les listes de conversations et les notifications.
- Intégrer Pay'm Plop Plop côté serveur en suivant sa documentation officielle; valider signatures/webhooks, idempotence, remboursements et statuts. Ne pas utiliser une clé privée exposée précédemment.
- Vérifier les migrations déjà appliquées, les politiques RLS, les variables de configuration, les tests Android/Web et les workflows GitHub Actions.
- Valider la livraison réelle, l'acceptation atomique des missions, le GPS en arrière-plan, le suivi temps réel et les preuves de remise avant toute annonce de mise en production.
