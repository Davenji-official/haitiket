import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../data/repo.dart';
import '../theme.dart';
import 'fx.dart';
import 'screens5.dart';
import 'screens6.dart';
import 'screens9.dart';
import 'specs.dart';
import 'widgets.dart';

/// Photos et vidéos d'un produit (jusqu'à 8, la première sert de couverture).
class MediaPickerField extends StatefulWidget {
  final List<Map<String, String>> items;
  final VoidCallback onChanged;
  const MediaPickerField({super.key, required this.items, required this.onChanged});
  @override
  State<MediaPickerField> createState() => _MediaPickerState();
}

class _MediaPickerState extends State<MediaPickerField> {
  bool busy = false;
  static const imgMime = {'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'webp': 'image/webp'};
  static const vidMime = {'mp4': 'video/mp4', 'webm': 'video/webm', 'mov': 'video/quicktime'};

  Future<void> add(XFile x, bool video) async {
    final ext = x.name.contains('.') ? x.name.split('.').last.toLowerCase() : (video ? 'mp4' : 'jpg');
    final mime = (video ? vidMime : imgMime)[ext];
    if (mime == null) throw video ? 'Format vidéo non pris en charge (MP4, WebM ou MOV).' : 'Format non pris en charge (JPEG, PNG ou WebP).';
    final bytes = await x.readAsBytes();
    final limit = video ? 20 * 1024 * 1024 : 3 * 1024 * 1024;
    if (bytes.length > limit) throw video ? 'Vidéo trop lourde (20 Mo maximum).' : 'Photo trop lourde (3 Mo maximum).';
    final url = await Repo.uploadImage(bytes, ext, mime);
    widget.items.add({'url': url, 'kind': video ? 'video' : 'image'});
  }

  Future<void> pick(bool video) async {
    if (widget.items.length >= 8) return toast(context, '8 médias maximum par produit.');
    setState(() => busy = true);
    try {
      final picker = ImagePicker();
      if (video) {
        final x = await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 60));
        if (x != null) await add(x, true);
      } else {
        final xs = await picker.pickMultiImage(maxWidth: 1600, imageQuality: 80);
        for (final x in xs.take(8 - widget.items.length)) {
          await add(x, false);
        }
      }
      widget.onChanged();
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (widget.items.isNotEmpty)
          SizedBox(
            height: 84,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (var i = 0; i < widget.items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Stack(clipBehavior: Clip.none, children: [
                    Container(
                      width: 84,
                      height: 84,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(color: C.mint, borderRadius: BorderRadius.circular(16), border: Border.all(color: i == 0 ? C.terracotta : C.line, width: i == 0 ? 3 : 1)),
                      child: widget.items[i]['kind'] == 'video' ? const Icon(Icons.play_circle_fill, size: 40, color: C.green) : Image.network(widget.items[i]['url']!, fit: BoxFit.cover),
                    ),
                    Positioned(
                      right: -6,
                      top: -6,
                      child: GestureDetector(
                        onTap: () {
                          setState(() => widget.items.removeAt(i));
                          widget.onChanged();
                        },
                        child: const CircleAvatar(radius: 12, backgroundColor: C.ink, child: Icon(Icons.close, size: 14, color: Colors.white)),
                      ),
                    ),
                  ]),
                ),
            ]),
          ),
        const SizedBox(height: 8),
        Wrap(spacing: 10, children: [
          OutlinedButton.icon(onPressed: busy ? null : () => pick(false), icon: const Icon(Icons.photo_library_outlined), label: Text(busy ? 'Envoi…' : 'Ajouter des photos')),
          OutlinedButton.icon(onPressed: busy ? null : () => pick(true), icon: const Icon(Icons.videocam_outlined), label: const Text('Ajouter une vidéo')),
        ]),
        const Padding(padding: EdgeInsets.only(top: 6), child: Text('La première photo est la couverture du produit.', style: TextStyle(color: C.muted))),
      ]);
}

/// Formulaire de caractéristiques adapté à la catégorie choisie.
class SpecsForm extends StatefulWidget {
  final List<SpecField> fields;
  final Map<String, dynamic> values;
  const SpecsForm({super.key, required this.fields, required this.values});
  @override
  State<SpecsForm> createState() => _SpecsFormState();
}

class _SpecsFormState extends State<SpecsForm> {
  final ctl = <String, TextEditingController>{};
  TextEditingController c(String k) => ctl.putIfAbsent(k, () => TextEditingController(text: (widget.values[k] ?? '').toString()));

  List<String> listOf(String k) => List<String>.from((widget.values[k] as List?) ?? const []);

  Widget title(String t) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 8), child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, color: C.ink, fontSize: 16)));

  Widget field(SpecField f) {
    switch (f.type) {
      case 'choice':
        final curChoice = widget.values[f.key] as String?;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          title(f.label),
          Wrap(spacing: 8, children: [
            for (final o in f.options)
              ChoiceChip(label: Text(o), selected: curChoice == o, onSelected: (_) => setState(() => widget.values[f.key] = o)),
          ]),
        ]);
      case 'multi':
      case 'sizes':
        final curList = listOf(f.key);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          title(f.label),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final o in f.options)
              FilterChip(
                label: Text(o),
                selected: curList.contains(o),
                onSelected: (v) => setState(() {
                  final l = listOf(f.key);
                  v ? l.add(o) : l.remove(o);
                  widget.values[f.key] = l;
                }),
              ),
          ]),
        ]);
      case 'colors':
        final curColors = List<Map<String, dynamic>>.from(((widget.values['colors'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          title(f.label),
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (final e in colorPalette.entries)
              Pressable(
                onTap: () => setState(() {
                  final l = List<Map<String, dynamic>>.from(curColors);
                  final i = l.indexWhere((x) => x['name'] == e.key);
                  if (i >= 0) {
                    l.removeAt(i);
                  } else {
                    l.add({'name': e.key, 'hex': e.value});
                  }
                  widget.values['colors'] = l;
                }),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutBack,
                    width: curColors.any((x) => x['name'] == e.key) ? 46 : 38,
                    height: curColors.any((x) => x['name'] == e.key) ? 46 : 38,
                    decoration: BoxDecoration(color: hexColor(e.value), shape: BoxShape.circle, border: Border.all(color: curColors.any((x) => x['name'] == e.key) ? C.terracotta : C.line, width: curColors.any((x) => x['name'] == e.key) ? 4 : 2)),
                    child: curColors.any((x) => x['name'] == e.key) ? Icon(Icons.check, size: 20, color: e.key == 'Blanc' || e.key == 'Jaune' || e.key == 'Beige' ? Colors.black : Colors.white) : null,
                  ),
                  const SizedBox(height: 2),
                  Text(e.key, style: const TextStyle(fontSize: 11, color: C.muted)),
                ]),
              ),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: c('_colors_extra'),
            onChanged: (v) => widget.values['_colors_extra'] = v,
            decoration: const InputDecoration(labelText: 'Autres couleurs (écrivez-les, séparées par des virgules)'),
          ),
        ]);
      default:
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: TextField(
            controller: c(f.key),
            keyboardType: f.type == 'number' ? TextInputType.number : TextInputType.text,
            onChanged: (v) => v.trim().isEmpty ? widget.values.remove(f.key) : widget.values[f.key] = v.trim(),
            decoration: InputDecoration(labelText: f.label),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final f in widget.fields) field(f)]);
}

/// Création d'un produit (boutique pro) ou d'une annonce (Bazar) : photos, vidéos, caractéristiques par catégorie.
class NewProductScreen extends StatefulWidget {
  final String shopId;
  final bool bazar;
  const NewProductScreen({super.key, required this.shopId, required this.bazar});
  @override
  State<NewProductScreen> createState() => _NewProductState();
}

class _NewProductState extends State<NewProductScreen> {
  final name = TextEditingController(), desc = TextEditingController(), price = TextEditingController(), stock = TextEditingController(text: '1');
  late final Future<List<Map<String, dynamic>>> cats = Repo.categories();
  Map<String, dynamic>? cat;
  String unit = 'unité';
  final specs = <String, dynamic>{};
  final media = <Map<String, String>>[];
  final variants = <Map<String, dynamic>>[];
  final tiers = <Map<String, dynamic>>[];
  bool busy = false;

  Future<void> save() async {
    final p = double.tryParse(price.text.replaceAll(',', '.'));
    final st = variants.isNotEmpty ? variants.fold<int>(0, (a, v) => a + (v['stock'] as int)) : int.tryParse(stock.text);
    if (name.text.trim().length < 2 || p == null || p < 0 || st == null || st < 0) return toast(context, 'Nom, prix et stock valides requis.');
    if (tiers.any((t) => (t['unit_price_minor'] as int) >= (p * 100).round())) return toast(context, "Chaque tarif par quantité doit être inférieur au prix normal.");
    setState(() => busy = true);
    try {
      final attrs = Map<String, dynamic>.from(specs);
      final extra = (attrs.remove('_colors_extra') ?? '').toString();
      final colors = List<Map<String, dynamic>>.from(((attrs['colors'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
      for (final n in extra.split(',')) {
        if (n.trim().isNotEmpty) colors.add({'name': n.trim(), 'hex': null});
      }
      if (colors.isNotEmpty) attrs['colors'] = colors;
      attrs.removeWhere((k, v) => v == null || (v is List && v.isEmpty) || (v is String && v.isEmpty));
      final cover = media.where((m) => m['kind'] == 'image').map((m) => m['url']).firstOrNull;
      final id = await Repo.addProduct(widget.shopId, name.text.trim(), (p * 100).round(), st, cover, !widget.bazar,
          description: desc.text, categoryId: cat?['id'] as String?, source: widget.bazar ? 'bazar' : 'marketplace', attributes: attrs, unitLabel: unit);
      if (media.isNotEmpty) await Repo.addProductMedia(id, media);
      await Repo.addVariants(id, variants);
      await Repo.addTiers(id, tiers);
      if (mounted) Navigator.of(context).pop(id);
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.bazar ? 'Nouvelle annonce' : 'Nouveau produit', style: const TextStyle(fontWeight: FontWeight.w800, color: C.ink))),
        body: ListView(padding: const EdgeInsets.all(18), children: [
          Field(name, 'Nom du produit'),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: cats,
            builder: (_, cs) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Catégorie'),
                items: [for (final c in cs.data ?? []) DropdownMenuItem(value: c['id'] as String, child: Text('${c['name']}'))],
                onChanged: (v) => setState(() {
                  cat = (cs.data ?? []).firstWhere((c) => c['id'] == v);
                  specs.clear();
                }),
              ),
            ),
          ),
          Field(desc, 'Description'),
          Row(children: [
            Expanded(flex: 3, child: Field(price, 'Prix en HTG', type: TextInputType.number)),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DropdownButtonFormField<String>(
                  initialValue: unit,
                  decoration: const InputDecoration(labelText: 'Vendu par'),
                  items: [for (final u in ['unité', 'kg', 'L', 'lot', 'douzaine', 'paire']) DropdownMenuItem(value: u, child: Text(u))],
                  onChanged: (v) => setState(() => unit = v ?? 'unité'),
                ),
              ),
            ),
          ]),
          if (variants.isEmpty) Field(stock, 'Quantité disponible', type: TextInputType.number),
          const Text('Photos et vidéos', style: TextStyle(fontWeight: FontWeight.w800, color: C.ink, fontSize: 16)),
          const SizedBox(height: 8),
          MediaPickerField(items: media, onChanged: () => setState(() {})),
          if (cat != null) ...[
            const SizedBox(height: 18),
            Text('Caractéristiques : ${cat!['name']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: C.ink)),
            SpecsForm(key: ValueKey(cat!['id']), fields: specsFor(cat!['name'] as String), values: specs),
          ],
          const SizedBox(height: 18),
          VariantsEditor(
            items: variants,
            sizeOptions: [for (final f in specsFor(cat?['name'] as String?)) if (f.type == 'sizes') ...f.options],
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 14),
          TiersEditor(items: tiers, basePriceMinor: double.tryParse(price.text.replaceAll(',', '.')) == null ? null : (double.parse(price.text.replaceAll(',', '.')) * 100).round(), onChanged: () => setState(() {})),
          const SizedBox(height: 24),
          PrimaryButton(label: busy ? 'Enregistrement…' : (widget.bazar ? "Enregistrer l'annonce" : 'Publier le produit'), icon: Icons.check, onPressed: busy ? null : save),
          const SizedBox(height: 30),
        ]),
      );
}

/// Parcours « publier au Bazar » : boutique personnelle, formulaire riche, puis paiement des 2 USD.
Future<void> startBazarListing(BuildContext context) async {
  if (currentUser() == null) return toast(context, 'Connectez-vous pour publier une annonce.');
  try {
    final shops = await Repo.myShops();
    final mine = shops.where((s) => s['kind'] == 'personal');
    String shopId;
    if (mine.isNotEmpty) {
      shopId = mine.first['id'] as String;
    } else {
      if (!context.mounted) return;
      final city = await askText(context, 'Votre ville', hint: 'ex. Delmas');
      if (city == null || city.isEmpty) return;
      shopId = await Repo.ensurePersonalShop(city);
      if (!context.mounted) return;
      final share = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Position sur la carte'),
          content: const Text('Afficher votre position approximative (arrondie à environ 100 m) sur la carte du Bazar ? Les acheteurs proches vous trouveront plus facilement.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Non')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Oui')),
          ],
        ),
      );
      if (share == true && context.mounted) {
        final pos = await myPosition(context);
        if (pos != null) await Repo.setShopLocation(shopId, pos.latitude, pos.longitude);
      }
    }
    if (!context.mounted) return;
    final id = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => NewProductScreen(shopId: shopId, bazar: true)));
    if (id == null || !context.mounted) return;
    final fq = await Repo.quoteFee('bazar_listing');
    if (!context.mounted) return;
    final pay = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Annonce enregistrée'),
        content: Text('Pour la publier pendant 14 jours : ${feeText(fq, '2')}.\nVous pouvez aussi payer plus tard depuis « Espace vendeur ».'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Plus tard')),
          if (fq != null) FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Payer maintenant')),
        ],
      ),
    );
    if (pay == true && context.mounted) await payAndOpen(context, 'bazar_listing', id);
  } catch (e) {
    if (context.mounted) toast(context, Repo.err(e));
  }
}
