# Inventaire honnête — HAITIKET V76

Légende : **Code** = écran + règles serveur présents dans le dépôt. **Testé** = vérifié sur appareil réel/staging avec de vrais services.
À ce jour **aucune fonction n'est marquée « testé »** : le code n'a pas pu être exécuté dans l'environnement de développement assisté.

| Domaine | Code | Détail |
|---|---|---|
| Inscription, connexion, récupération, profil, WhatsApp | Oui | écrans `auth_screens`, `screens4` ; blocage après 5 échecs de connexion |
| Catalogue, variantes, tarifs par quantité, stock | Oui | `screens7/9`, `product_detail`, migrations V58/V59 |
| Boutiques, abonnement, boutique officielle | Oui | `screens2/6`, admin « Boutique officielle » (position carte ajoutée) |
| Bazar (14 j, expiration, purge 30 j) | Oui | rappels d'expiration à vérifier en staging |
| Panier, commande, stock atomique | Oui | `CheckoutScreen`, `create_orders` |
| Portefeuilles HTG/USD, recharge, retrait | Oui | `WalletScreen`, fonctions Edge Plop Plop |
| Paiement Bazik | Oui (fonctions `bazik-pay`, `bazik-webhook`) | jamais testé en production : ne l'activer qu'après test |
| Livraison : offres des livreurs, affectation, retard, remboursement | Oui | V14, V27, V72, V73 |
| Codes PIN collecte/remise + QR | Oui | PIN 6 chiffres sans expiration ; QR HKT1 (V75) |
| Contacts téléphone/WhatsApp entre participants | Oui | V73 |
| Tournées, centres, scans | Oui | admin « Logistique », livreur « Mes tournées » (V75) |
| Carte client (GPS direct, cap, suivi, ETA, réacheminement) | Oui | V76 |
| Carte live admin | Oui | V75 |
| Messagerie, mentions @prénom/@tous | Oui | V75 |
| Notifications internes | Oui | image, lien, coupon |
| Notifications push (téléphone verrouillé) | Code prêt | inactif tant que Firebase + webhook ne sont pas configurés |
| Favoris, avis, coupons, parrainage | Oui | |
| Support, litiges, signalements, KYC | Oui | |
| Antifraude | Oui | détection + examen manuel (aucun blocage automatique) |
| Administration (analytique, clients 360°, commandes, catalogue, logistique, antifraude, diffusion, réglages, 18 modules) | Oui | V73–V76 |
| Prise de contrôle de compte | Oui | comptes bloqués/supprimés par l'admin : accès temporaire 20 min (V76) ; comptes supprimés par leur propriétaire : impossible (consultation seule) |
| Mode nuit | Oui | vrai thème sombre (V76) ; certaines couleurs personnalisées de boutiques ne s'adaptent pas |
| Web / Android | Oui | iOS non couvert (pas de dossier ios/ dans le dépôt) |

## Non fait ou limité
* Expiration des codes PIN/QR (cahier §16) ; zones de livraison par commune ; tarification par distance.
* Fournisseur de cartes sous contrat (OSM/OSRM publics aujourd'hui) — secrets `MAP_TILE_URL` / `ROUTE_BASE_URL`.
* Tests obligatoires du cahier §29, publication stores, pages légales finalisées, iOS.
