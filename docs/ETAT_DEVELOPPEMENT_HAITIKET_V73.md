# HAITIKET V73 — livraison, contacts, centre de contrôle admin

**Aucune compilation Flutter ni exécution SQL n'a été possible dans l'environnement de création** (pas de Flutter/Dart/PostgreSQL).
Tout est à valider : `flutter analyze` (GitHub Actions) puis migration sur un Supabase de test.

## Livré
1. **Livraison HAITIKET** : `create_orders` ne lève plus « aucun tarif configuré ». Le tarif forfaitaire devient optionnel
   (`delivery_flat_minor`, défaut 0). Le livreur propose son prix/délai, le client choisit une offre, l'écart est réglé via le portefeuille (mécanisme V14/0030 existant).
2. **Contacts** : colonne `profiles.whatsapp`, RPC `order_contacts` / `job_contacts` (réservées aux participants d'une commande payée),
   boutons Appeler + WhatsApp dans le suivi client, les missions du livreur et les commandes du vendeur. Champ WhatsApp dans le profil.
3. **Présence** : `touch_presence()` appelé toutes les 60 s ; « en ligne » = vu il y a < 3 min.
4. **Centre de contrôle admin** (`lib/ui/admin_pro.dart`) : Analytique (16 indicateurs + 6 graphiques + statuts), Clients (recherche nom/e-mail/téléphone/WhatsApp/ville/ID,
   filtres en ligne/actifs/inactifs/bloqués/vendeurs/livreurs, fiche 360°, modification, blocage, rôles, appel/WhatsApp, **prise de contrôle**),
   Commandes, Catalogue (produits + catégories CRUD), Diffusion, Réglages libres, et « Modules » = les 18 onglets existants.
5. **Prise de contrôle** : Edge Function `admin-impersonate` (motif obligatoire, journal d'audit, refus sur les admins), bandeau rouge « Quitter ».
6. **Diffusion** : notification à tous / clients / vendeurs / livreurs / actifs / inactifs avec image, lien https, coupon, bandeau global optionnel.
7. **APK** : signature permanente + numéro de version croissant (`docs/APK_INSTALLATION.md`). **Guides** : servis par GitHub Pages (+ repli raw GitHub) et lien ajouté au menu.

## Déploiement
1. SQL : exécuter `supabase/migrations/0064_admin_pro_delivery_contacts_v73.sql`.
2. `supabase functions deploy admin-impersonate`.
3. Secrets GitHub `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`.
4. Push sur `main` → build Web + APK. Activer GitHub Pages (Source : GitHub Actions).

## Audit du cahier des charges (état honnête)
| Section | État |
|---|---|
| 3 Auth/rôles/profil | Présent (limitation des tentatives de connexion : **absente**) |
| 5 Catalogue/variantes/stock | Présent (V58/V59) |
| 6–7 Boutiques, abonnements, Bazar (14 j, purge 30 j) | Présent, cron `purge_expired_bazar` ; rappels d'expiration à vérifier |
| 8–9 Panier, commandes, stock atomique | Présent |
| 10–12 Portefeuilles HTG/USD, commissions | Présent ; revalider en staging (scripts V35/V38) |
| 11 Pay'm Plop Plop / Bazik | Plop Plop présent ; **Bazik à ne pas proposer tant que non testé** |
| 13 Livraison, offres, affectation atomique | Corrigé V73 |
| 14 Centres, partenaires, tournées multi-commandes | **Partiel** (pas d'interface de tournées complète) |
| 15–16 Carte, PIN, QR | Présent |
| 17 Messagerie | Présent ; **mentions** absentes |
| 18 Notifications | Internes OK ; **push système (Firebase) non intégré** |
| 19 Favoris, avis, coupons, parrainage | Présent |
| 20 Administration | Refondu V73 |
| 21–22 Support, litiges, KYC, antifraude | Présent ; antifraude automatique limité |
| 24–25 RLS, intégrité | Présent ; tester SELECT/INSERT/UPDATE/DELETE inter-comptes |
| 29 Tests obligatoires | **Non exécutés** — à faire sur appareils réels |

## Pourquoi « Guides » semblait absent
L'écran existait (Accueil → bouton Guides) mais ouvrait des PDF sur `github.com/.../raw/main/guides/`. Si le dépôt est privé ou si le dossier
`guides/` n'est pas poussé, le lien échoue. V73 : lien dans le menu + PDF publiés sur GitHub Pages via le workflow.

## V74
* Fiche 360° : cause du bug = fonction SQL STABLE qui écrit dans le journal ; corrigée (0064 + 0065). Ajouts : KYC, adresses, tickets, signalements, journal, message individuel, réinitialisation du mot de passe, suppression de compte.
* Boutique officielle sur la carte : position réglable dans Admin → Boutique officielle (coordonnées ou GPS) ; pin vert « vérifié ».
* Alertes de livraison : notifications correctes (prix à proposer), client averti à chaque offre, livreur averti quand son offre est retenue, son + vibration à l'arrivée d'une mission (écran livreur ouvert).
* Anti-force-brute de connexion : blocage progressif après 5 échecs.

## V75
* Push FCM : `lib/push.dart`, fonction Edge `send-push`, table `push_tokens` (voir docs/CONFIGURATION_FIREBASE_PUSH.md).
* QR sécurisé (HKT1:<commande>:<code>) affiché par `showPin`, scanné par le livreur (`confirm_*_qr`), journal `qr_scan_log`. Le code à 6 chiffres reste disponible.
* Centres logistiques, tournées multi-commandes, scans (admin → Logistique ; livreur → « Mes tournées »).
* Antifraude automatique (doubles paiements, coupons, parrainage, remboursements, codes erronés) + écran admin.
* Mentions @prénom / @tous dans la messagerie (notification).
* Alertes de mission filtrées par distance (réglage courier_alert_radius_km, défaut 15 km), repli sur tous les livreurs disponibles.
* Position des boutiques pro : précision ~1 m ; particuliers : ~100 m.
* Carte client rafraîchie toutes les 30 s + GPS continu ; carte LIVE admin (livreurs, missions, livraisons, boutiques, centres) toutes les 10 s.
* Fournisseur de cartes/itinéraires configurable (secrets MAP_TILE_URL, ROUTE_BASE_URL).
* Mode nuit (menu) : filtre d'inversion global, photos préservées.

## V76
* Prise de contrôle : comptes bloqués/supprimés par l'admin (session de support 20 min, rétablissement automatique) — migration 0067 + fonction Edge mise à jour.
* Mode nuit : vrai thème sombre (palette dynamique C.*, reconstruction complète à la bascule) à la place du filtre « négatif ». Fond de carte sombre par filtre de tuiles.
* Carte client : GPS direct au chargement, cap, cercle de précision, suivi caméra, panneau de navigation (distance, durée, heure d'arrivée, vitesse), réacheminement automatique hors itinéraire, durée par mode (marche/moto/voiture).
