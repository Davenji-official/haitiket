# HAITIKET — Complément de spécification et état d'implémentation

**Référence de travail :** `haitiket-main(4).zip` fourni dans la conversation.  
**Architecture :** Flutter / Dart, Supabase, PostgreSQL, Realtime, Edge Functions.  
**Paiements :** portefeuilles internes HAITIKET pour toutes les opérations de la plateforme ; Pay'm Plop Plop réservé aux recharges et retraits. Le choix éventuel de fournisseur de recharge/retrait (Pay'm Plop Plop ou Bazik) doit être configurable par l'administration et n'affecte pas les paiements internes.

> Ce document est un complément de spécification. Les exigences ci-dessous ne sont pas toutes implémentées. Une fonction n'est considérée comme opérationnelle qu'après migration compatible, intégration UI/backend, tests, et vérification en environnement de test. Aucune donnée ou position ne doit être simulée.

## 1. Livraison à n'importe quel endroit

Le client peut choisir une adresse enregistrée, saisir un lieu ponctuel ou autoriser explicitement la géolocalisation pour choisir sa position actuelle. Le lieu peut être le domicile, une école, une université, un lieu de travail, chez un ami, un camping ou un lieu temporaire. Une commande conserve un instantané de la destination choisi pour cette commande ; modifier ensuite l'adresse du profil ne doit pas modifier une commande existante.

Les données structurées recommandées sont : `dropoff_label`, `dropoff_address`, `dropoff_lat`, `dropoff_lng`, `dropoff_accuracy_m`, `dropoff_captured_at`, `dropoff_instructions`, `recipient_name`, `recipient_phone`, `delivery_location_source`. Les coordonnées précises ne sont visibles que pour les rôles qui en ont besoin pour cette livraison et pendant la durée opérationnelle nécessaire.

Le GPS ne doit jamais être présenté comme exact au centimètre : conserver l'estimation de précision fournie par l'appareil, permettre au client de confirmer ou corriger le point, et afficher un repère manuel si le GPS est imprécis. Sur le Web, les permissions de géolocalisation exigent généralement HTTPS et une autorisation explicite.

## 2. Carte réellement temps réel

Les positions des clients, vendeurs et livreurs ne sont publiées qu'avec consentement, pendant une commande ou mission active et selon les autorisations. Le suivi doit utiliser des événements réels provenant des appareils et du backend, avec horodatage, précision GPS, état réseau et détection des positions périmées. Supabase Realtime diffuse les mises à jour validées ; la carte ne doit pas interpoler des positions fictives ni prétendre que le déplacement est en temps réel si l'appareil est hors ligne.

À implémenter/valider : table de positions avec accès limité, publication Realtime, throttling configurable, historique minimal utile, gestion de perte réseau, reprise, permissions Android/iOS/Web, indicateur « dernière mise à jour », protection contre usurpation basique, limitation de rétention et audit des consultations sensibles. Une mise à jour à chaque pas n'est pas garantie par le GPS mobile, le système d'exploitation, la batterie et le réseau ; l'objectif réaliste est la meilleure fréquence autorisée par l'appareil, avec fraîcheur visible et sans inventer de points.

## 3. Offres de livraison

Deux modes tarifaires configurables :
- **Immédiat** : objectif initial de 45 minutes, estimation affichée avant confirmation et jamais garantie si trafic/distance/sécurité ne le permettent pas.
- **Normal** : créneau/délai de référence configurable par zone, catégorie, heure et capacité.

Le vendeur/particulier peut proposer un tarif et un délai de préparation pour les options immédiate et normale. Pour la livraison par livreur, les livreurs éligibles à proximité reçoivent la mission et peuvent volontairement proposer un prix, accepter ou ignorer/refuser. Le client compare prix, ETA, distance, profil vérifié, note et nombre de missions en cours, puis choisit une offre. L'acceptation finale doit être atomique et une seule offre peut être retenue.

Un livreur peut déclarer un incident de trafic. L'extension de délai (par exemple +2 h ou +4 h) doit être un événement horodaté avec motif, position si autorisée, notification client et possibilité de signalement. Le livreur ne peut pas modifier silencieusement le prix déjà accepté. Les règles d'exception et remboursements doivent être configurables et auditées.

## 4. Modes de remise et parcours de commande

Le client choisit entre retrait autonome chez le vendeur/point partenaire et livraison. Si la livraison est choisie, il peut comparer les offres et sélectionner le mode immédiat ou normal. Les parcours pris en charge doivent inclure vendeur → client, vendeur → livreur → client, et, si le partenaire est activé, vendeur → point partenaire → client ou via livreur.

Chaque commande doit garder un instantané immuable : articles, variantes, quantités, prix unitaires, devise, taux vendeur appliqué, remises, frais, offre de livraison sélectionnée, adresse/destination, règles de commission et versions des conditions.

## 5. Prix, devises et tarifs par quantité

Chaque produit utilise une devise source HTG ou USD. Le vendeur peut définir un taux d'affichage USD→HTG pour ses prix (ex. 130, 135, 140, 145 ou valeur personnalisée validée), indépendant des taux de recharge/retrait. Le client voit prix source, taux et équivalent dans l'autre devise. Le serveur valide le taux et enregistre le taux et les montants de la commande ; aucune modification future ne change une commande payée.

Les prix par lot/quantité sont saisis par le vendeur, jamais inventés par une formule automatique : unité, pack de 3, 6, 12 ou paliers personnalisés, avec prix explicite, quantité minimale, devise, disponibilité et règles de combinaison. Les variantes (taille, couleur, modèle, public cible, conditionnement) ont leur propre stock/prix si applicable. Les commandes existantes gardent leur instantané même si le vendeur modifie ou supprime ensuite l'annonce.

## 6. Abonnements, Bazar et boutique officielle HAITIKET

- Boutique professionnelle : création → vérification documentaire → choix mensuel 20 USD/30 jours ou annuel 200 USD/365 jours → débit confirmé du portefeuille USD côté serveur → activation d'abonnement → badge selon les critères de vérification et d'abonnement → publication autorisée.
- Bazar : informations obligatoires et contrôle préalable, paiement depuis le portefeuille USD à 2 USD/14 jours, activation seulement après débit confirmé. À expiration, l'annonce est bloquée et ne prend plus de commandes ; suppression du catalogue actif après 30 jours sans renouvellement, selon le document de référence et les obligations de conservation.
- Boutique officielle HAITIKET : boutique détenue par l'organisation, aucun abonnement ni frais de publication, produits modérés et badge officiel clairement distinct du badge de boutique professionnelle vérifiée. Catalogue diffusé dans les espaces pertinents Marketplace/Bazar selon la catégorie et les règles de classement.

## 7. Profils, KYC et fermeture volontaire

Calculer l'âge depuis la date de naissance côté serveur. Le formulaire documentaire dépend de l'âge, du pays, du statut et du rôle. Exemples de documents possibles à vérifier avec le cadre légal : pièce d'identité/passeport, matricule fiscal pour les activités qui le requièrent, document de naissance pour les mineurs lorsque légalement accepté, photo de contrôle avec feuille portant « HAITIKET ». Ne jamais afficher publiquement ces documents ; bucket privé, accès restreint, journalisation et durée de conservation configurée. Les règles pour mineurs doivent inclure consentement/tuteur si requis et peuvent interdire certaines activités.

Un compte incomplet ne peut pas acheter, vendre ou candidater comme livreur lorsque les informations essentielles sont requises. Un vendeur ou livreur peut suspendre ses activités ou demander la fermeture de son espace ; les commandes, litiges, fonds dus et obligations légales en cours doivent être résolus avant fermeture définitive.

## 8. Produits, médias et messagerie

Formulaires dynamiques par catégorie : vêtements (public, tailles, couleurs, matière), chaussures (pointures), téléphone/électronique (marque, modèle, état, stockage, garantie), alimentation (poids/volume, conditionnement, péremption), meubles (dimensions/matériaux), services autorisés (durée/conditions). Formats média : JPEG, PNG, WebP et vidéo selon limites serveur configurables ; validation MIME réelle, taille, antivirus/contrôle de contenu lorsque disponible, suppression de métadonnées sensibles et accès privé pour preuves/KYC.

Un vendeur peut modifier une annonce publiée, ajouter/retirer médias et variantes, désactiver ou supprimer. La suppression est bloquée si une obligation transactionnelle exige de conserver l'instantané ; l'annonce peut être retirée du catalogue sans effacer les preuves. La messagerie affiche l'avatar de chaque participant, le logo/photo de boutique ou annonce, lien vers le produit/commande, partage de média, mentions selon permissions, suppression pour soi et suppression pour tous sous réserve d'un tombstone et de la conservation légale/audit.

## 9. Administration complète et guides

Le back-office doit gérer les paramètres commerciaux, pays/zones, devises et taux, frais, abonnements, durée Bazar, fournisseurs de recharge/retrait, commissions, SLA immédiat/normal, trafic, limites, rôles/permissions, KYC, médias, catégories/attributs, boutique officielle, modération, litiges, ledger, retraits, remboursements, notifications, messages, logs, feature flags, rétention, sécurité, exports et documentation. Les modifications sensibles nécessitent permissions, réauthentification/MFA selon le risque, motif et audit. « Tout configurer sans code » ne dispense pas de contrôles de sécurité ni de migrations pour les changements structurels de base de données.

Un guide PDF administrateur doit être téléchargeable depuis le panneau et disponible en français et créole haïtien. Des guides séparés sont également requis pour boutique professionnelle, livreur, vendeur Bazar et client, avec exemples et captures réelles de l'interface. Le document peut être préparé avant l'intégration du bouton de téléchargement, mais ne doit pas prétendre documenter des écrans inexistants.

## 10. Paiements et sécurité financière

Les achats, abonnements, promotions, frais de livraison et remboursements passent par les portefeuilles internes HAITIKET dans la devise de l'opération. Pay'm Plop Plop est réservé aux recharges et retraits ; le fournisseur de recharge/retrait peut être sélectionné dans l'administration entre les intégrations réellement configurées. Toute recharge exige une confirmation du fournisseur avant crédit. Tout retrait exige confirmation réelle avant statut final. Ledger en partie double, idempotence, verrouillage transactionnel, reversals/refunds audités et RLS sont obligatoires.

Une table interne de soldes ne prouve pas à elle seule que des fonds sont conservés légalement. L'architecture de détention/réservation/libération doit être validée avec l'infrastructure financière et le cadre légal applicable avant production.

## 11. État du présent paquet

- Ajouté dans ce paquet : bouton de sélection explicite de la position GPS actuelle dans le formulaire de commande, avec permission système, délai maximal, affichage des coordonnées/précision et stockage du lieu choisi dans le champ d'adresse textuel existant.
- Ajouté : ce complément de spécification et les exigences d'acceptation.
- Non certifié : transmission structurée des coordonnées dans des colonnes SQL dédiées, suivi GPS en direct client/vendeur/livreur, offres tarifaires dynamiques, paiement interne complet, admin complet, KYC réel, guides servis depuis le panel, tests de sécurité et compilation Flutter. Ces travaux exigent des modifications backend/migrations et des tests supplémentaires.
- Aucun SQL nouveau n'est ajouté à exécuter automatiquement dans ce paquet. Les migrations déjà présentes dans le projet doivent être comparées à l'historique réel de Supabase avant tout déploiement.
