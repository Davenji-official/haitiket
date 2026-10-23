# Mascottes HAITIKET — intégration

- Images : `lib/assets/mascots/*.webp` (recadrées, 720 px max, ~2 Mo au total). Le CI copie déjà `lib/assets` vers `assets`.
- Code : `lib/ui/mascot.dart` (`Mascot`, `MascotImage`, `MascotHeader`).
- Pour changer une mascotte d'écran : modifier l'argument `mascot:` du `MascotHeader` concerné.
- Animations : apparition « pop », respiration douce, saut au toucher ; désactivées si « réduire les animations » est actif.

| Écran | Mascotte |
|---|---|
| Accueil | home (grande, dans la carte verte/mint) |
| Marketplace, Ouvrir ma boutique | boutiques |
| Bazar | bazar |
| Panier | cart |
| Mes commandes, HAITIKET Network, Espace livreur | orders |
| Messages | messages |
| Support | support |
| Mon profil, Mon compte | profile |
| Connexion (Bienvenue) | welcome |
| Notifications | notifications |
| Portefeuille | wallet |
| Espace vendeur | seller |
| Favoris, logo en-tête/menu/splash | badge |
| Administration (onglet Tableau) | admin |
