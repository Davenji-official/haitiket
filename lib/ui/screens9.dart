import 'package:flutter/material.dart';
import '../data/repo.dart';
import '../theme.dart';
import 'fx.dart';
import 'specs.dart';
import 'widgets.dart';

String variantText(Map<String, dynamic> v) => [v['size'], v['color_name']].where((e) => e != null && '$e'.isNotEmpty).join(' · ');

/// Variantes (taille / couleur) avec stock propre à chacune.
class VariantsEditor extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final List<String> sizeOptions;
  final VoidCallback onChanged;
  const VariantsEditor({super.key, required this.items, required this.sizeOptions, required this.onChanged});
  @override
  State<VariantsEditor> createState() => _VariantsState();
}

class _VariantsState extends State<VariantsEditor> {
  final size = TextEditingController(), colorName = TextEditingController(), stock = TextEditingController(text: '1');
  String? colorHex;

  void add() {
    final s = size.text.trim(), c = colorName.text.trim();
    final n = int.tryParse(stock.text);
    if ((s.isEmpty && c.isEmpty) || n == null || n < 0) return toast(context, 'Indiquez une taille ou une couleur, et un stock valide.');
    if (widget.items.any((v) => (v['size'] ?? '') == s && (v['color_name'] ?? '') == c)) return toast(context, 'Cette variante existe déjà.');
    setState(() {
      widget.items.add({'size': s.isEmpty ? null : s, 'color_name': c.isEmpty ? null : c, 'color_hex': c.isEmpty ? null : colorHex, 'stock': n});
      size.clear();
      colorName.clear();
      colorHex = null;
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: C.mint.withValues(alpha: .45), borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Variantes en stock', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: C.ink)),
          const Text('Chaque taille ou couleur a son propre stock. Les acheteurs ne peuvent commander que ce qui est disponible.', style: TextStyle(color: C.muted)),
          const SizedBox(height: 10),
          if (widget.sizeOptions.isNotEmpty)
            Wrap(spacing: 6, children: [for (final o in widget.sizeOptions) ActionChip(label: Text(o), onPressed: () => setState(() => size.text = o))]),
          Field(size, 'Taille / pointure / modèle'),
          Wrap(spacing: 10, runSpacing: 8, children: [
            for (final e in colorPalette.entries)
              Pressable(
                onTap: () => setState(() {
                  colorName.text = e.key;
                  colorHex = e.value;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: colorName.text == e.key ? 40 : 32,
                  height: colorName.text == e.key ? 40 : 32,
                  decoration: BoxDecoration(color: hexColor(e.value), shape: BoxShape.circle, border: Border.all(color: colorName.text == e.key ? C.terracotta : C.line, width: colorName.text == e.key ? 4 : 2)),
                ),
              ),
          ]),
          const SizedBox(height: 10),
          TextField(controller: colorName, onChanged: (_) => setState(() => colorHex = null), decoration: const InputDecoration(labelText: 'Couleur (choisissez ou écrivez)')),
          const SizedBox(height: 10),
          Field(stock, 'Stock de cette variante', type: TextInputType.number),
          OutlinedButton.icon(onPressed: add, icon: const Icon(Icons.add), label: const Text('Ajouter la variante')),
          const SizedBox(height: 8),
          for (var i = 0; i < widget.items.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 12, backgroundColor: hexColor(widget.items[i]['color_hex'] as String?) ?? C.line),
              title: Text(variantText(widget.items[i]), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('Stock : ${widget.items[i]['stock']}'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  setState(() => widget.items.removeAt(i));
                  widget.onChanged();
                },
              ),
            ),
        ]),
      );
}

/// Tarifs par quantité : 3, 6, demi-douzaine, douzaine, x douzaines, lot… (prix total du pack saisi par le vendeur).
class TiersEditor extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final int? basePriceMinor;
  final VoidCallback onChanged;
  const TiersEditor({super.key, required this.items, required this.basePriceMinor, required this.onChanged});
  @override
  State<TiersEditor> createState() => _TiersState();
}

class _TiersState extends State<TiersEditor> {
  final qty = TextEditingController(), total = TextEditingController();
  String? label;
  static const presets = [('3 pièces', 3), ('6 pièces', 6), ('Demi-douzaine', 6), ('Douzaine', 12), ('2 douzaines', 24), ('5 douzaines', 60)];

  void add() {
    final q = int.tryParse(qty.text);
    final t = double.tryParse(total.text.replaceAll(',', '.'));
    if (q == null || q < 2 || t == null || t <= 0) return toast(context, 'Quantité (2 ou plus) et prix total valides requis.');
    final unit = (t * 100 / q).round();
    if (widget.basePriceMinor != null && unit >= widget.basePriceMinor!) return toast(context, "Le prix à l'unité de ce pack doit être inférieur au prix normal.");
    if (widget.items.any((x) => x['min_qty'] == q)) return toast(context, 'Un tarif existe déjà pour cette quantité.');
    setState(() {
      widget.items.add({'min_qty': q, 'unit_price_minor': unit, 'label': label});
      widget.items.sort((a, b) => (a['min_qty'] as int).compareTo(b['min_qty'] as int));
      qty.clear();
      total.clear();
      label = null;
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: C.yellow.withValues(alpha: .18), borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Tarifs par quantité (facultatif)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: C.ink)),
          const Text("Le prix à l'unité baisse dès la quantité indiquée. Le serveur applique automatiquement le bon tarif.", style: TextStyle(color: C.muted)),
          const SizedBox(height: 10),
          Wrap(spacing: 6, children: [for (final p in presets) ActionChip(label: Text(p.$1), onPressed: () => setState(() { qty.text = '${p.$2}'; label = p.$1; }))]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Field(qty, 'Quantité du pack', type: TextInputType.number)),
            const SizedBox(width: 10),
            Expanded(child: Field(total, 'Prix total du pack (HTG)', type: TextInputType.number)),
          ]),
          OutlinedButton.icon(onPressed: add, icon: const Icon(Icons.add), label: const Text('Ajouter le tarif')),
          for (var i = 0; i < widget.items.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('Dès ${widget.items[i]['min_qty']} : ${money(widget.items[i]['unit_price_minor'] as num, 'HTG')} / unité', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('Pack de ${widget.items[i]['min_qty']} = ${money((widget.items[i]['unit_price_minor'] as int) * (widget.items[i]['min_qty'] as int), 'HTG')}${widget.items[i]['label'] == null ? '' : ' · ${widget.items[i]['label']}'}'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  setState(() => widget.items.removeAt(i));
                  widget.onChanged();
                },
              ),
            ),
        ]),
      );
}

/// Ajuste le stock de chaque variante d'un produit existant.
Future<void> variantStockDialog(BuildContext context, Map<String, dynamic> product) async {
  final vs = List<Map<String, dynamic>>.from(((product['product_variants'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
  await showDialog<void>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (_, set) => AlertDialog(
        title: Text('Stock : ${product['name']}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final v in vs)
              Row(children: [
                Expanded(child: Text(variantText(v), style: const TextStyle(fontWeight: FontWeight.w700))),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: (v['stock'] as int) > 0
                      ? () async {
                          try {
                            await Repo.updateVariantStock(v['id'] as String, (v['stock'] as int) - 1);
                            set(() => v['stock'] = (v['stock'] as int) - 1);
                          } catch (e) {
                            if (context.mounted) toast(context, Repo.err(e));
                          }
                        }
                      : null,
                ),
                Text('${v['stock']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () async {
                    try {
                      await Repo.updateVariantStock(v['id'] as String, (v['stock'] as int) + 1);
                      set(() => v['stock'] = (v['stock'] as int) + 1);
                    } catch (e) {
                      if (context.mounted) toast(context, Repo.err(e));
                    }
                  },
                ),
              ]),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Fermer'))],
      ),
    ),
  );
}

/// Promotions de la boutique : coupons sur toute la boutique ou sur certains produits, avec durée et activation.
class ShopCouponsScreen extends StatefulWidget {
  final String shopId;
  const ShopCouponsScreen({super.key, required this.shopId});
  @override
  State<ShopCouponsScreen> createState() => _ShopCouponsState();
}

class _ShopCouponsState extends State<ShopCouponsScreen> {
  late Future<List<Map<String, dynamic>>> f = Repo.shopCoupons(widget.shopId);
  void reload() => setState(() => f = Repo.shopCoupons(widget.shopId));

  Future<void> create() async {
    final code = TextEditingController(), value = TextEditingController(), min = TextEditingController(), uses = TextEditingController(), days = TextEditingController();
    String kind = 'percent';
    bool visible = true, allProducts = true;
    final chosen = <String>{};
    final products = await Repo.shopProducts(widget.shopId);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (_, set) => AlertDialog(
          title: const Text('Nouvelle promotion'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Field(code, 'Code (ex. SOLDES10)'),
              DropdownButtonFormField<String>(
                initialValue: kind,
                decoration: const InputDecoration(labelText: 'Type de réduction'),
                items: const [DropdownMenuItem(value: 'percent', child: Text('Pourcentage')), DropdownMenuItem(value: 'fixed', child: Text('Montant fixe (HTG)'))],
                onChanged: (v) => set(() => kind = v ?? 'percent'),
              ),
              const SizedBox(height: 12),
              Field(value, kind == 'percent' ? 'Pourcentage (1 à 100)' : 'Montant en HTG', type: TextInputType.number),
              Field(min, 'Achat minimum en HTG (facultatif)', type: TextInputType.number),
              Field(uses, "Nombre d'utilisations max (facultatif)", type: TextInputType.number),
              Field(days, 'Durée en jours (facultatif : sans limite)', type: TextInputType.number),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Afficher la promotion sur les produits'), value: visible, onChanged: (v) => set(() => visible = v)),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Valable sur tous mes produits'), value: allProducts, onChanged: (v) => set(() => allProducts = v)),
              if (!allProducts)
                for (final p in products)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${p['name']}'),
                    value: chosen.contains(p['id']),
                    onChanged: (v) => set(() => v == true ? chosen.add(p['id'] as String) : chosen.remove(p['id'])),
                  ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Créer')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final v = double.tryParse(value.text.replaceAll(',', '.'));
    if (v == null || v <= 0) return toast(context, 'Valeur invalide.');
    if (!allProducts && chosen.isEmpty) return toast(context, 'Choisissez au moins un produit.');
    try {
      await Repo.shopCreateCoupon(
        shopId: widget.shopId,
        code: code.text.trim(),
        kind: kind,
        value: kind == 'percent' ? v.round() : (v * 100).round(),
        minMinor: ((double.tryParse(min.text.replaceAll(',', '.')) ?? 0) * 100).round(),
        maxUses: int.tryParse(uses.text),
        days: int.tryParse(days.text) ?? 0,
        productIds: allProducts ? null : chosen.toList(),
        visible: visible,
      );
      reload();
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Promotions de la boutique', style: TextStyle(fontWeight: FontWeight.w800, color: C.ink))),
        floatingActionButton: FloatingActionButton.extended(backgroundColor: C.ink, foregroundColor: Colors.white, onPressed: create, icon: const Icon(Icons.local_offer_outlined), label: const Text('Créer')),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: f,
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            final l = s.data ?? [];
            if (l.isEmpty) return const Padding(padding: EdgeInsets.all(18), child: EmptyState(title: 'Aucune promotion', text: "Créez un code de réduction : sur toute la boutique ou sur certains produits, pour la durée de votre choix. La réduction est à votre charge."));
            return ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 100), children: [
              for (final c in l)
                Card(
                  color: Colors.white,
                  child: ListTile(
                    title: Text('${c['code']} · ${c['kind'] == 'percent' ? '${c['value']} %' : money(c['value'] as num, 'HTG')}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('Utilisé ${c['used_count']}${c['max_uses'] == null ? '' : ' / ${c['max_uses']}'} fois · ${c['product_ids'] == null ? 'toute la boutique' : '${(c['product_ids'] as List).length} produit(s)'}${c['expires_at'] == null ? '' : '\nJusqu\'au ${(c['expires_at'] as String).substring(0, 10)}'}'),
                    trailing: Switch(
                      value: c['active'] == true,
                      onChanged: (v) async {
                        try {
                          await Repo.shopSetCouponActive(c['id'] as String, v);
                          reload();
                        } catch (e) {
                          if (context.mounted) toast(context, Repo.err(e));
                        }
                      },
                    ),
                  ),
                ),
            ]);
          },
        ),
      );
}
