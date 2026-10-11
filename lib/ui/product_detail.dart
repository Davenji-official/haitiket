import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/repo.dart';
import '../i18n.dart';
import '../theme.dart';
import 'fx.dart';
import 'screens3.dart';
import 'screens5.dart';
import 'widgets.dart';

class ProductDetailScreen extends StatelessWidget {
  final Map<String, dynamic> p;
  const ProductDetailScreen(this.p, {super.key});

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

  @override
  Widget build(BuildContext context) {
    final img = p['image_url'] as String?;
    final shop = (p['shops'] as Map?)?['name'] ?? '';
    final shopId = (p['shop_id'] ?? (p['shops'] as Map?)?['id']) as String?;
    final desc = (p['description'] as String?) ?? '';
    final stock = (p['stock'] as num?)?.toInt() ?? 0;
    final bazar = p['source'] == 'bazar';
    return Scaffold(
      appBar: AppBar(title: Text('$shop', style: const TextStyle(fontWeight: FontWeight.w800, color: C.ink))),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: AspectRatio(
            aspectRatio: 1,
            child: Stack(fit: StackFit.expand, children: [
              img == null || img.isEmpty
                  ? Container(color: C.mint, child: const Icon(Icons.shopping_basket_outlined, size: 72, color: C.green))
                  : Image.network(img, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: C.mint)),
              Positioned(right: 6, top: 6, child: HeartButton(p['id'] as String, onImage: true)),
            ]),
          ),
        ),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: Text('${p['name']}', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: C.ink))),
          if (bazar) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: C.yellow, borderRadius: BorderRadius.circular(12)), child: const Text('Bazar', style: TextStyle(fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 6),
        Text(money(p['price_minor'] as num, (p['currency'] ?? 'HTG') as String), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: C.green)),
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
        if (desc.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(desc, style: const TextStyle(fontSize: 17, color: C.muted, height: 1.45)),
        ],
        const SizedBox(height: 24),
        Builder(
          builder: (bc) => PrimaryButton(
            label: tr('Ajouter au panier'),
            icon: Icons.add_shopping_cart,
            onPressed: () {
              CartStore.add(p);
              HapticFeedback.lightImpact();
              CartFly.fly(bc);
              Repo.trackCart(p['id'] as String);
            },
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: () => openChat(context, 'product', p['id'] as String), icon: const Icon(Icons.chat_bubble_outline), label: const Text('Contacter le vendeur')),
      ]),
    );
  }
}
