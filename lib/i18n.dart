import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Langue de l'interface : 'fr' (par défaut) ou 'ht' (Kreyòl ayisyen).
final ValueNotifier<String> appLang = ValueNotifier<String>('fr');

Future<void> loadLang() async {
  final p = await SharedPreferences.getInstance();
  appLang.value = p.getString('lang') ?? 'fr';
}

Future<void> setLang(String l) async {
  appLang.value = l;
  final p = await SharedPreferences.getInstance();
  await p.setString('lang', l);
}

/// Traduit une phrase française. Sans traduction connue, renvoie le français.
String tr(String fr) => appLang.value == 'ht' ? (_ht[fr] ?? fr) : fr;

const _ht = <String, String>{
  'Accueil': 'Akèy',
  'Marketplace': 'Mache',
  'Network': 'Rezo',
  'Messages': 'Mesaj',
  'Mon profil': 'Pwofil mwen',
  'Mes commandes': 'Kòmand mwen yo',
  'Mes favoris': 'Favori mwen yo',
  'Espace vendeur': 'Espas machann',
  'Espace livreur': 'Espas livrè',
  'Support': 'Sipò',
  'Paramètres': 'Paramèt',
  'Se connecter': 'Konekte',
  'Se déconnecter': 'Dekonekte',
  'Non connecté': 'Pa konekte',
  "Tout ce qu'Haïti vend, en un seul ": 'Tout sa Ayiti vann, nan yon sèl ',
  'endroit.': 'kote.',
  "Découvrez des produits uniques, soutenez les commerces d'ici et faites-vous livrer simplement, partout en Haïti.": 'Dekouvri pwodui inik, sipòte biznis lokal yo epi fè yo livre w fasil, toupatou an Ayiti.',
  "Que recherchez-vous aujourd'hui ?": 'Kisa w ap chèche jodi a ?',
  'Rechercher': 'Chèche',
  'Livraison suivie': 'Livrezon swiv',
  'Vendeurs vérifiés': 'Machann verifye',
  'Près de chez vous': 'Tou pre w',
  'Fait en Haïti': 'Fèt an Ayiti',
  "Achetez local.\nVivez mieux.": 'Achte lokal.\nViv pi byen.',
  'À DÉCOUVRIR': 'POU DEKOUVRI',
  'Les trouvailles du moment': 'Dekouvèt moman an',
  'Voir tout': 'Wè tout',
  'Vous êtes commerçant ?': 'Ou se komèsan ?',
  'Ouvrir ma boutique': 'Louvri boutik mwen',
  'Vous êtes particulier ?': 'Ou se yon moun òdinè ?',
  'Publier une annonce': 'Pibliye yon anons',
  'Langue': 'Lang',
  'Ajouter au panier': 'Ajoute nan panye',
  'Passer commande': 'Pase kòmand',
  'Panier': 'Panye',
  'Favoris': 'Favori',
  'Notifications': 'Notifikasyon',
  'Carte': 'Kat',
  'Filtres': 'Filt',
  'Prix croissant': 'Pri k ap monte',
  'Prix décroissant': 'Pri k ap desann',
  'Plus récents': 'Pi resan yo',
  'Près de moi': 'Pre mwen',
  'Toutes': 'Tout',
};
