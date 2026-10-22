# HAITIKET — audit de couverture du projet V13

Date de l'audit : 2026-10-22. Base inspectée : archive V13 extraite localement, migrations 0001–0023 et code Flutter présent. Cet audit est une inspection statique, pas une certification ni un test de production.

## Déjà présent dans le code (partiel, à valider en environnement réel)

- Choix retrait vendeur ou livraison, adresses enregistrées, GPS actuel et point choisi sur carte au checkout (`CheckoutScreen`).
- Stockage des coordonnées de destination et de position du coursier via RPC; lecture contrôlée de la position du coursier affecté; carte de suivi avec destination et date réelle de dernière position (migrations 0019–0021 et `OrderTrackingScreen`).
- Variantes taille/couleur/public, prix de variante saisi, stock par variante, tarifs par quantité, médias produits et suppression logique.
- Portefeuilles USD/HTG, recharges/retraits Plop Plop et taux distincts de recharge/retrait via les fonctions existantes. Ce constat ne prouve pas la réussite d'un paiement réel.
- Diffusion de missions ouvertes aux coursiers approuvés disponibles avec GPS récent, acceptation atomique et limite codée de trois missions actives (migration 0022). Le rayon de 25 km est à vol d'oiseau, pas routier.
- Audit financier en lecture seule et rapports de contrôles (migration 0023).

## Manques ou écarts importants constatés

1. **Paiement du checkout : BLOQUANT.** Le checkout Flutter affiche encore « Le paiement n'est pas encore disponible » et laisse les commandes en attente. Les fonctions de recharge/retrait Plop Plop ne constituent pas une intégration de paiement de commande, abonnement boutique et promotion Bazar. Le code conserve aussi un chemin `bazik-pay` dans `Repo`; Bazik n'est donc pas entièrement retiré du code.
2. **Offres de prix des coursiers : INCOMPLET.** La V13 attribue une mission au premier coursier qui accepte. Cela ne correspond pas au flux demandé où plusieurs coursiers proposent un prix, puis le client choisit. V14 ajoute le socle SQL/RPC des offres, mais les écrans Flutter ne sont pas encore raccordés et l'ancien bouton d'acceptation reste présent.
3. **Taux vendeur USD/HTG : MANQUANT.** Le prix produit a une devise, mais aucun champ de taux de change propre au vendeur n'a été constaté dans les formulaires/commandes. Il faut conserver le taux et les montants figés dans chaque commande; ne pas convertir un solde sans consentement.
4. **Prix immédiat 45 minutes et délai normal : MANQUANT.** Aucun flux complet de choix de délai/prix vendeur, déclaration de retard +2 h/+4 h et notification correspondante n'a été confirmé.
5. **Carte « vivante » : PARTIELLE.** Le GPS du coursier est publié périodiquement en premier plan et une position autorisée peut être lue. Cela ne prouve pas un suivi en continu de tous les acteurs; pas de garantie de GPS en arrière-plan, pas de trajet routier/ETA réel garanti, ni d'interface unifiée client/vendeur/coursier pour toutes les étapes.
6. **Destination GPS et commande atomiques : PARTIEL.** Le checkout crée la commande puis enregistre ses coordonnées dans un appel séparé. Si le deuxième appel échoue, la commande existe sans destination structurée; l'interface signale ce cas, mais il faut rendre l'opération atomique ou prévoir une reprise fiable.
7. **Administration « tout configurable » : PARTIELLE.** Un système de paramètres existe, mais tous les éléments demandés ne sont pas confirmés comme modifiables depuis une interface : taux vendeur, offres de livraison, délais, exigences KYC par âge/pays, politiques de badge, paramètres de catalogue et flux de paiement.
8. **Boutique officielle HAITIKET : NON CONFIRMÉE.** Aucune boutique officielle dédiée avec produits diffusés sur Marketplace et Bazar, badge permanent spécifique et gestion depuis l'admin n'a été confirmée dans les fichiers inspectés.
9. **Abonnements boutique et Bazar : PARTIELS.** Les parcours de paiement sont présents dans certaines fonctions, mais la confirmation réelle du prestataire et l'activation complète doivent être testées; l'état courant du checkout et le chemin Bazik empêchent de conclure que la politique Plop Plop est unifiée.
10. **Profil complet, âge et KYC : PARTIELS.** La candidature coursier et les outils de documents existent par endroits, mais le contrôle complet qui calcule l'âge et impose les documents spécifiques (majeur/mineur) avant achat/vente/candidature n'est pas validé de bout en bout.
11. **Guides FR/Kreyòl : PARTIELS.** Un guide administrateur brouillon est présent. Des PDF finaux distincts et téléchargeables pour administrateur, boutique professionnelle, vendeur Bazar et coursier, en français et créole haïtien, ne sont pas tous présents/confirmés.
12. **Messagerie et notifications : PARTIELLES.** Des fonctions de messagerie, suppression de notification, pièces jointes et contrôle de catalogue existent, mais la suppression pour tous, conservation des preuves de litige, photos des deux interlocuteurs et contexte complet de commande doivent être vérifiés et raccordés dans l'UI.
13. **Produits, boutiques et médias : PARTIELS.** Les produits peuvent être modifiés et supprimés logiquement. La suppression définitive doit rester compatible avec les commandes/audits; l'édition complète des médias/variantes et la galerie agrandie doivent être testées dans tous les parcours. Formats vidéo et limites de stockage doivent être explicités.
14. **Comptabilité : NON CERTIFIÉE.** V13 est un outil d'audit en lecture seule; le modèle existant `ledger_entries` ne suffit pas à prouver une comptabilité complète en partie double avec débits/crédits équilibrés, réservations et libérations atomiques, remboursements partiels et rapprochement fournisseur.

## V14 : changements ajoutés

- Migration additive `0024_delivery_price_offers.sql` : table d'offres de prix, expiration de 10 minutes, contrôle de coursier approuvé/disponible/GPS récent/rayon de 25 km, liste d'offres accessible au seul client de la commande, sélection atomique du prix et attribution d'un seul coursier.
- Méthodes Flutter `Repo.proposeDeliveryPrice`, `Repo.deliveryPriceOffers` et `Repo.selectDeliveryPriceOffer`.
- Ce socle n'est pas encore exposé dans les écrans Flutter; le parcours de l'offre reste donc incomplet jusqu'à V15.

## Ordre de travail proposé

1. Raccorder les écrans d'offres de livraison et neutraliser le flux d'acceptation directe qui contourne le choix du client.
2. Réparer l'intégration Plop Plop pour checkout, abonnement boutique et promotion Bazar, uniquement après validation de l'API officielle, signatures/webhooks et identifiants.
3. Rendre destination + commande fiables (transaction serveur / reprise idempotente).
4. Ajouter taux de vente propre au vendeur et snapshot du taux/prix à la commande.
5. Construire l'administration de configuration, les contrôles KYC/âge et les guides bilingues finaux.
6. Ajouter tests de sécurité, concurrence, paiements et migration sur un environnement staging avant toute déclaration de production.

## Installation V14

Après les migrations 0001–0023 déjà appliquées, exécuter une seule fois `supabase/migrations/0024_delivery_price_offers.sql` dans Supabase SQL Editor. Vérifier ensuite les RPC avec des comptes de test. Ne pas lancer de test de paiement sur des fonds réels.

**Limite de vérification :** Flutter/Dart CLI n'était pas disponible pendant la création de cette archive; aucune compilation ni exécution distante SQL n'est revendiquée.
