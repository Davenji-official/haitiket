import 'package:flutter/material.dart';
import '../data/repo.dart';
import '../theme.dart';

class ProductDetailScreen extends StatelessWidget {
  final Map<String, dynamic> p;
  const ProductDetailScreen(this.p, {super.key});
  @override
  Widget build(BuildContext context) {
    final img = p['image_url'] as String?;
    final shop = (p['shops'] as Map?)?['name'] ?? '';
    final desc = (p['description'] as String?) ?? '';
    final stock = (p['stock'] as num?)?.toInt() ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text('$shop', style: const TextStyle(fontWeight: FontWeight.w800, color: C.ink))),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: AspectRatio(
            aspectRatio: 1,
            child: img == null || img.isEmpty
                ? Container(color: C.mint, child: const Icon(Icons.shopping_basket_outlined, size: 72, color: C.green))
                : Image.network(img, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: C.mint)),
          ),
        ),
        const SizedBox(height: 18),
        Text('${p['name']}', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: C.ink)),
        const SizedBox(height: 6),
        Text(money(p['price_minor'] as num, (p['currency'] ?? 'HTG') as String), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: C.green)),
        const SizedBox(height: 6),
        Text(stock <= 5 ? 'Stock faible : $stock disponible(s)' : 'En stock', style: TextStyle(color: stock <= 5 ? C.terracotta : C.muted, fontWeight: FontWeight.w700)),
        if (desc.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(desc, style: const TextStyle(fontSize: 17, color: C.muted, height: 1.45)),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () {
            CartStore.add(p);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ajouté au panier')));
          },
          child: const Text('Ajouter au panier'),
        ),
      ]),
    );
  }
}
