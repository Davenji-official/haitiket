/// Champs de description adaptés à chaque catégorie de produit.
class SpecField {
  final String key, label, type; // text | number | choice | multi | colors | sizes
  final List<String> options;
  const SpecField(this.key, this.label, {this.type = 'text', this.options = const []});
}

const colorPalette = <String, String>{
  'Noir': '#111111', 'Blanc': '#FFFFFF', 'Gris': '#9CA3AF', 'Rouge': '#DC2626', 'Bordeaux': '#7F1D1D', 'Orange': '#F97316',
  'Jaune': '#FACC15', 'Vert': '#16A34A', 'Turquoise': '#14B8A6', 'Bleu': '#2563EB', 'Marine': '#1E3A8A', 'Violet': '#7C3AED',
  'Rose': '#EC4899', 'Marron': '#92400E', 'Beige': '#E7D3B0', 'Or': '#D4AF37', 'Argent': '#C0C0C0',
};

const _clothSizes = ['XS', 'S', 'M', 'L', 'XL', 'XXL', '3XL', '36', '37', '38', '39', '40', '41', '42', '43', '44', '45', '46'];
const _publics = ['Homme', 'Femme', 'Enfant', 'Adolescent', 'Femme enceinte', 'Mixte'];
const _states = ['Neuf', 'Occasion', 'Reconditionné'];

List<SpecField> specsFor(String? categoryName) {
  final n = (categoryName ?? '').toLowerCase();
  if (n.contains('vêtement')) {
    return const [SpecField('public', 'Public concerné', type: 'multi', options: _publics), SpecField('sizes', 'Tailles / pointures disponibles', type: 'sizes', options: _clothSizes), SpecField('colors', 'Couleurs disponibles', type: 'colors'), SpecField('brand', 'Marque'), SpecField('material', 'Matière'), SpecField('condition', 'État', type: 'choice', options: _states)];
  }
  if (n.contains('nourriture')) {
    return const [SpecField('weight', 'Poids ou volume (ex. 500 g, 1 L)'), SpecField('packaging', 'Conditionnement (ex. sachet, bouteille, carton de 12)'), SpecField('ingredients', 'Ingrédients'), SpecField('shelf', 'Conservation / date limite'), SpecField('origin', 'Origine (ex. Fait en Haïti)')];
  }
  if (n.contains('téléphone')) {
    return const [SpecField('brand', 'Marque'), SpecField('model', 'Modèle'), SpecField('storage', 'Stockage (ex. 128 Go)'), SpecField('ram', 'Mémoire RAM'), SpecField('colors', 'Couleurs disponibles', type: 'colors'), SpecField('condition', 'État', type: 'choice', options: _states), SpecField('included', 'Accessoires inclus'), SpecField('warranty', 'Garantie')];
  }
  if (n.contains('électron')) {
    return const [SpecField('brand', 'Marque'), SpecField('model', 'Modèle'), SpecField('power', 'Puissance / tension'), SpecField('colors', 'Couleurs disponibles', type: 'colors'), SpecField('condition', 'État', type: 'choice', options: _states), SpecField('warranty', 'Garantie'), SpecField('features', 'Caractéristiques principales')];
  }
  if (n.contains('ménager')) {
    return const [SpecField('brand', 'Marque'), SpecField('model', 'Modèle'), SpecField('power', 'Puissance / capacité'), SpecField('dimensions', 'Dimensions'), SpecField('colors', 'Couleurs disponibles', type: 'colors'), SpecField('condition', 'État', type: 'choice', options: _states), SpecField('warranty', 'Garantie')];
  }
  if (n.contains('maison')) {
    return const [SpecField('dimensions', 'Dimensions'), SpecField('material', 'Matière'), SpecField('colors', 'Couleurs disponibles', type: 'colors'), SpecField('condition', 'État', type: 'choice', options: _states)];
  }
  if (n.contains('beauté')) {
    return const [SpecField('brand', 'Marque'), SpecField('volume', 'Volume / contenance'), SpecField('skin', 'Type de peau / cheveux'), SpecField('ingredients', 'Ingrédients'), SpecField('expiry', "Date d'expiration")];
  }
  if (n.contains('livre')) {
    return const [SpecField('author', 'Auteur'), SpecField('publisher', 'Éditeur'), SpecField('language', 'Langue'), SpecField('pages', 'Nombre de pages', type: 'number'), SpecField('condition', 'État', type: 'choice', options: _states)];
  }
  if (n.contains('enceinte')) {
    return const [SpecField('sizes', 'Tailles disponibles', type: 'sizes', options: _clothSizes), SpecField('colors', 'Couleurs disponibles', type: 'colors'), SpecField('material', 'Matière'), SpecField('brand', 'Marque')];
  }
  if (n.contains('enfant')) {
    return const [SpecField('age', 'Âge conseillé (ex. 3-5 ans)'), SpecField('sizes', 'Tailles disponibles', type: 'sizes', options: _clothSizes), SpecField('colors', 'Couleurs disponibles', type: 'colors'), SpecField('brand', 'Marque'), SpecField('condition', 'État', type: 'choice', options: _states)];
  }
  if (n.contains('animaux')) {
    return const [SpecField('animal', 'Animal concerné (chien, chat…)'), SpecField('brand', 'Marque'), SpecField('weight', 'Poids / contenance'), SpecField('expiry', "Date d'expiration")];
  }
  if (n.contains('sport')) {
    return const [SpecField('brand', 'Marque'), SpecField('sizes', 'Tailles disponibles', type: 'sizes', options: _clothSizes), SpecField('colors', 'Couleurs disponibles', type: 'colors'), SpecField('condition', 'État', type: 'choice', options: _states)];
  }
  if (n.contains('outil')) {
    return const [SpecField('brand', 'Marque'), SpecField('model', 'Modèle'), SpecField('power', 'Puissance / dimensions'), SpecField('condition', 'État', type: 'choice', options: _states), SpecField('warranty', 'Garantie')];
  }
  if (n.contains('pièces')) {
    return const [SpecField('vehicle', 'Véhicule compatible (marque)'), SpecField('model', 'Modèle et année compatibles'), SpecField('reference', 'Référence de la pièce'), SpecField('condition', 'État', type: 'choice', options: _states), SpecField('warranty', 'Garantie')];
  }
  if (n.contains('service')) {
    return const [SpecField('duration', 'Durée de la prestation'), SpecField('zone', 'Zone couverte'), SpecField('availability', 'Disponibilités')];
  }
  return const [SpecField('brand', 'Marque'), SpecField('condition', 'État', type: 'choice', options: _states), SpecField('details', 'Autres caractéristiques')];
}

String specLabel(String? category, String key) {
  for (final f in specsFor(category)) {
    if (f.key == key) return f.label;
  }
  return key;
}
