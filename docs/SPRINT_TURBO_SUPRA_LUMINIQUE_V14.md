# SPRINT TURBO SUPRA LUMINIQUE — V14

## V9.4 — offres de prix de livraison par les coursiers

Cette version ajoute le socle serveur pour que plusieurs coursiers admissibles proposent chacun un prix et un délai, puis que le client sélectionne une offre. La sélection verrouille la mission et la première sélection valide gagne; les autres offres deviennent rejetées.

### Sécurité
- Coursier approuvé, disponible, GPS daté de moins de trois minutes.
- Distance maximale actuelle de 25 km à vol d'oiseau de la boutique.
- Devise identique à la mission, montant strictement positif, délai entre 1 et 1440 minutes.
- Offre expirant après 10 minutes.
- Lecture des offres réservée au client de la commande.
- Sélection atomique avec verrouillage de la mission.
- Pas de paiement ni de crédit effectué par cette migration.

### Fonctions
- `propose_delivery_price(job, amount_minor, currency, eta_minutes, note)`
- `list_delivery_price_offers(job)`
- `select_delivery_price_offer(offer)`

### Important
Le code Flutter expose maintenant les méthodes repository, mais les écrans de proposition et de sélection ne sont pas encore raccordés. L'ancien écran de mission permet encore l'acceptation directe : le parcours client-choisit-l'offre n'est donc pas encore complet. Ne pas considérer cette fonction comme disponible aux utilisateurs avant le sprint d'intégration UI et les tests SQL sur staging.
