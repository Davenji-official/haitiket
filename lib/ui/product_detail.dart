import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/repo.dart';
import '../i18n.dart';
import '../theme.dart';
import 'fx.dart';
import 'screens3.dart';
import 'screens5.dart';
import 'screens8.dart';
import 'screens9.dart';
import 'specs.dart';
import 'widgets.dart';

class _Gallery extends StatefulWidget {
  final String productId;
  final String? cover;
  final Widget overlay;
  const _Gallery({required this.productId, required this.cover, required this.overlay});
  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  late final Future<List<Map<String, dynamic>>> f = Repo.productMedia(widget.productId);
  final pc = PageController();
  int idx = 0;

  @override
  void dispose() {
    pc.dispose();
    super.dispose();
  }

  Widget placeholder() => Container(color: C.mint, child: const Icon(Icons.shopping_basket_outlined, size: 72, color: C.green));

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: AspectRatio(
          aspectRatio: 1,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: f,
            builder: (_, s) {
              var items = s.data ?? [];
              if (items.isEmpty && widget.cover != null && widget.cover!.isNotEmpty) items = [{'url': widget.cover, 'kind': 'image'}];
              return Stack(fit: StackFit.expand, children: [
                if (items.isEmpty)
                  placeholder()
                else
                  PageView.builder(
                    controller: pc,
                    itemCount: items.length,
                    onPageChanged: (i) => setState(() => idx = i),
                    itemBuilder: (_, i) {
                      final it = items[i];
                      if (it['kind'] == 'video') {
                        return GestureDetector(
                          onTap: () => launchUrl(Uri.parse(it['url'] as String), mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication),
                          child: Container(color: C.ink, child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.play_circle_fill, size: 84, color: Colors.white), SizedBox(height: 8), Text('Voir la vidéo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))])),
                        );
                      }
                      return Image.network(it['url'] as String, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder());
                    },
                  ),
                Positioned(right: 6, top: 6, child: widget.overlay),
                if (items.length > 1)
                  Positioned(
                    bottom: 12,
                    left: 0,
                    right: 0,
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      for (var i = 0; i < items.length; i++)
                        AnimatedContainer(duration: const Duration(milliseconds: 250), margin: const EdgeInsets.symmetric(horizontal: 3), width: i == idx ? 22 : 8, height: 8, decoration: BoxDecoration(color: i == idx ? Colors.white : Colors.white54, borderRadius: BorderRadius.circular(6))),
                    ]),
                  ),
              ]);
            },
          ),
        ),
      );
}

class ProductDetailScreen extends StatefulWidget {
  final Map<String, dynamic> p;
  const ProductDetailScreen(this.p, {super.key});
  @override
  State<ProductDetailScreen> createState() => _ProductDetailState();
}

class _ProductDetailState extends State<ProductDetailScreen> {
  Map<String, dynamic> get p => widget.p;
  Map<String, dynamic>? variant;
  late final Future<List<Map<String, dynamic>>> promos = Repo.productPromos(p['id'] as String);

  List<Map<String, dynamic>> get variants => List<Map<String, dynamic>>.from(((p['product_variants'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
  List<Map<String, dynamic>> get tiers {
    final l = List<Map<String, dynamic>>.from(((p['product_tiers'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
    l.sort((a, b) => (a['min_qty'] as num).compareTo(b['min_qty'] as num));
    return l;
  }

  List<Widget> variantsUi() {
    final v = variants;
    if (v.isEmpty) return [];
    return [
      heading('Choisissez une option'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final x in v)
          ChoiceChip(
            avatar: x['color_hex'] == null ? null : CircleAvatar(radius: 8, backgroundColor: hexColor(x['color_hex'] as String?)),
            label: Text('${variantText(x)}${(x['stock'] as num) <= 0 ? ' (épuisé)' : ''}'),
            selected: variant?['id'] == x['id'],
            onSelected: (x['stock'] as num) <= 0 ? null : (_) => setState(() => variant = x),
          ),
      ]),
    ];
  }

  List<Widget> tiersUi() {
    final t = tiers;
    if (t.isEmpty) return [];
    return [
      heading('Tarifs par quantité'),
      for (final x in t)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            const Icon(Icons.local_offer_outlined, size: 18, color: C.terracotta),
            const SizedBox(width: 8),
            Expanded(child: Text('Dès ${x['min_qty']}${x['label'] == null ? '' : ' (${x['label']})'} : ${money(x['unit_price_minor'] as num, 'HTG')} / unité', style: const TextStyle(fontWeight: FontWeight.w700, color: C.ink))),
          ]),
        ),
    ];
  }

  List<Widget> promosUi() => [
        FutureBuilder<List<Map<String, dynamic>>>(
          future: promos,
          builder: (_, s) {
            final l = s.data ?? [];
            if (l.isEmpty) return const SizedBox();
            return Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in l)
                  ActionChip(
                    avatar: const Icon(Icons.sell_outlined, size: 18, color: C.terracotta),
                    label: Text('Code ${c['code']} : −${c['kind'] == 'percent' ? '${c['value']} %' : money(c['value'] as num, 'HTG')}${c['expires_at'] == null ? '' : ' jusqu\'au ${(c['expires_at'] as String).substring(0, 10)}'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: '${c['code']}'));
                      toast(context, 'Code copié : saisissez-le au moment de commander.');
                    },
                  ),
              ]),
            );
          },
        ),
      ];

  Future<Map<String, dynamic>> loadStats(String? shopId) async {
    final s = await Repo.productStats(p['id'] as String);
    Map<String, dynamic> r = {'avg_rating': null, 'n': 0};
    if (shopId != null) r = await Repo.shopRating(shopId);
    return {'stats': s, 'rating': r};
  }

  Widget chip(IconData i, String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: C.mint, borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(i, size: 18, color: C.green), const SizedBox(width: 6), Text(t, style: const TextStyle(fontWeight: FontWeight.w800, color: C.ink))]),
      );

  Widget heading(String t) => Padding(padding: const EdgeInsets.only(top: 18, bottom: 8), child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: C.ink)));

  List<Widget> specs() {
    final attrs = Map<String, dynamic>.from((p['attributes'] as Map?) ?? const {});
    if (attrs.isEmpty) return [];
    final cat = (p['categories'] as Map?)?['name'] as String?;
    final out = <Widget>[];
    final colors = ((attrs.remove('colors') as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final sizes = List<String>.from((attrs.remove('sizes') as List?) ?? const []);
    final pub = List<String>.from((attrs.remove('public') as List?) ?? const []);
    if (pub.isNotEmpty) out.addAll([heading('Pour'), Wrap(spacing: 8, children: [for (final x in pub) Chip(label: Text(x))])]);
    if (sizes.isNotEmpty) out.addAll([heading('Tailles disponibles'), Wrap(spacing: 8, runSpacing: 4, children: [for (final x in sizes) Chip(label: Text(x, style: const TextStyle(fontWeight: FontWeight.w800)))])]);
    if (colors.isNotEmpty) {
      out.addAll([
        heading('Couleurs disponibles'),
        Wrap(spacing: 14, runSpacing: 10, children: [
          for (final c in colors)
            Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 38, height: 38, decoration: BoxDecoration(color: hexColor(c['hex'] as String?) ?? C.line, shape: BoxShape.circle, border: Border.all(color: C.line, width: 2)), child: hexColor(c['hex'] as String?) == null ? const Icon(Icons.palette_outlined, size: 18, color: C.muted) : null),
              const SizedBox(height: 2),
              Text('${c['name']}', style: const TextStyle(fontSize: 12, color: C.muted)),
            ]),
        ]),
      ]);
    }
    if (attrs.isNotEmpty) {
      out.add(heading('Caractéristiques'));
      for (final e in attrs.entries) {
        final v = e.value is List ? (e.value as List).join(', ') : '${e.value}';
        out.add(Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 140, child: Text(specLabel(cat, e.key), style: const TextStyle(color: C.muted))), Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w700, color: C.ink)))])));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final shop = (p['shops'] as Map?)?['name'] ?? '';
    final shopId = (p['shop_id'] ?? (p['shops'] as Map?)?['id']) as String?;
    final desc = (p['description'] as String?) ?? '';
    final stock = (p['stock'] as num?)?.toInt() ?? 0;
    final bazar = p['source'] == 'bazar';
    final unit = (p['unit_label'] as String?) ?? 'unité';
    return Scaffold(
      appBar: AppBar(title: Text('$shop', style: const TextStyle(fontWeight: FontWeight.w800, color: C.ink)), actions: [IconButton(tooltip: 'Signaler', icon: const Icon(Icons.flag_outlined), onPressed: () => reportDialog(context, 'product', p['id'] as String))]),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        _Gallery(productId: p['id'] as String, cover: p['image_url'] as String?, overlay: HeartButton(p['id'] as String, onImage: true)),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: Text('${p['name']}', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: C.ink))),
          if (bazar) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: C.yellow, borderRadius: BorderRadius.circular(12)), child: const Text('Bazar', style: TextStyle(fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 6),
        Text('${money(p['price_minor'] as num, (p['currency'] ?? 'HTG') as String)}${unit == 'unité' ? '' : ' / $unit'}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: C.green)),
        const SizedBox(height: 10),
        FutureBuilder<Map<String, dynamic>>(
          future: loadStats(shopId),
          builder: (_, s) {
            if (!s.hasData) return const SizedBox(height: 40);
            final st = s.data!['stats'] as Map<String, dynamic>;
            final r = s.data!['rating'] as Map<String, dynamic>;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              chip(Icons.shopping_bag_outlined, 'Acheté ${st['purchases']} fois'),
              chip(Icons.favorite_border, '${st['favorites']} favoris'),
              chip(Icons.add_shopping_cart, 'Mis au panier par ${st['cart_adds']}'),
              chip(Icons.star_rounded, (r['n'] as num) == 0 ? 'Vendeur non noté' : 'Vendeur ${r['avg_rating']}/5 (${r['n']})'),
            ]);
          },
        ),
        const SizedBox(height: 12),
        Pressable(
          onTap: () {
            if (shopId != null) Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShopScreen(shopId)));
          },
          child: Row(children: [
            const Icon(Icons.storefront, color: C.green, size: 20),
            const SizedBox(width: 6),
            Text('Voir la boutique $shop', style: const TextStyle(color: C.green, fontWeight: FontWeight.w800, decoration: TextDecoration.underline)),
          ]),
        ),
        const SizedBox(height: 6),
        Text(stock <= 5 ? 'Stock faible : $stock disponible(s)' : 'En stock', style: TextStyle(color: stock <= 5 ? C.terracotta : C.muted, fontWeight: FontWeight.w700)),
        ...promosUi(),
        ...variantsUi(),
        ...tiersUi(),
        if (desc.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(desc, style: const TextStyle(fontSize: 17, color: C.muted, height: 1.45)),
        ],
        ...specs(),
        const SizedBox(height: 24),
        Builder(
          builder: (bc) => PrimaryButton(
            label: tr('Ajouter au panier'),
            icon: Icons.add_shopping_cart,
            onPressed: () {
              if (variants.isNotEmpty && variant == null) return toast(context, 'Choisissez une option (taille ou couleur).');
              CartStore.add(p, variant: variant);
              HapticFeedback.lightImpact();
              CartFly.fly(bc);
              Repo.trackCart(p['id'] as String);
            },
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: () => openChat(context, 'product', p['id'] as String), icon: const Icon(Icons.chat_bubble_outline), label: const Text('Contacter le vendeur')),
        const SizedBox(height: 30),
      ]),
    );
  }
}
