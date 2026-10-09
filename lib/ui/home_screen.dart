import 'package:flutter/material.dart';
import '../data/repo.dart';
import '../theme.dart';
import 'shell.dart';
import 'widgets.dart';

class SearchPill extends StatelessWidget {
  final void Function(String) onSubmit;
  const SearchPill({super.key, required this.onSubmit});
  @override
  Widget build(BuildContext context) {
    final c = TextEditingController();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), border: Border.all(color: C.line), boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 3))]),
      child: Row(children: [
        const Icon(Icons.search, color: C.muted, size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: c,
            onSubmitted: onSubmit,
            decoration: const InputDecoration(hintText: "Que recherchez-vous aujourd'hui ?", border: InputBorder.none, enabledBorder: InputBorder.none, filled: false, isDense: true),
          ),
        ),
        FilledButton(onPressed: () => onSubmit(c.text), child: const Text('Rechercher')),
      ]),
    );
  }
}

class HomeScreen extends StatelessWidget {
  final void Function(Sec) go;
  const HomeScreen({super.key, required this.go});

  Widget chip(IconData i, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, color: C.terracotta, size: 22),
        const SizedBox(width: 8),
        Text(t, style: const TextStyle(fontWeight: FontWeight.w700, color: C.muted, fontSize: 16)),
      ]);

  Widget avatar(String l, Color bg, Color fg) => Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle, border: Border.all(color: C.mint, width: 3)),
        child: Text(l, style: TextStyle(color: fg, fontSize: 18)),
      );

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(18, 28, 18, 40), children: [
      RichText(
        text: const TextSpan(style: TextStyle(fontSize: 44, height: 1.05, fontWeight: FontWeight.w800, color: C.ink, letterSpacing: -1), children: [
          TextSpan(text: "Tout ce qu'Haïti vend, en un seul "),
          TextSpan(text: 'endroit.', style: TextStyle(color: C.terracotta)),
        ]),
      ),
      const SizedBox(height: 20),
      const Text("Découvrez des produits uniques, soutenez les commerces d'ici et faites-vous livrer simplement, partout en Haïti.", style: TextStyle(fontSize: 19, color: C.muted, height: 1.45)),
      const SizedBox(height: 28),
      SearchPill(onSubmit: (q) {
        Repo.search.value = q;
        go(Sec.marketplace);
      }),
      const SizedBox(height: 22),
      Wrap(spacing: 28, runSpacing: 12, children: [
        chip(Icons.local_shipping_outlined, 'Livraison suivie'),
        chip(Icons.storefront_outlined, 'Vendeurs vérifiés'),
        chip(Icons.location_on_outlined, 'Près de chez vous'),
      ]),
      const SizedBox(height: 40),
      FutureBuilder<int>(
        future: Repo.activeShops(),
        builder: (_, s) {
          final n = s.data ?? 0;
          return ClipRRect(
            borderRadius: BorderRadius.circular(40),
            child: Container(
              height: 280,
              color: C.mint,
              child: Stack(children: [
                Positioned(right: -40, top: -60, child: Container(width: 330, height: 330, decoration: const BoxDecoration(color: C.sun, shape: BoxShape.circle))),
                Positioned(left: -60, bottom: -110, child: Container(width: 380, height: 380, decoration: const BoxDecoration(color: C.coral, shape: BoxShape.circle))),
                const Positioned(right: 50, top: 28, child: Text('🧺', style: TextStyle(fontSize: 76))),
                Positioned(
                  left: 24,
                  top: 24,
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .8), borderRadius: BorderRadius.circular(24)), child: const Text('Fait en Haïti', style: TextStyle(fontWeight: FontWeight.w700, color: C.green, fontSize: 16))),
                ),
                Positioned(
                  left: 24,
                  bottom: 24,
                  right: 24,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Achetez local.\nVivez mieux.', style: TextStyle(fontSize: 42, height: 1.1, fontWeight: FontWeight.w800, color: C.ink)),
                    const SizedBox(height: 16),
                    Row(children: [
                      SizedBox(
                        width: 110,
                        height: 46,
                        child: Stack(children: [
                          Positioned(left: 0, child: avatar('M', C.yellow, C.ink)),
                          Positioned(left: 30, child: avatar('A', C.terracotta, C.ink)),
                          Positioned(left: 60, child: avatar('J', C.ink, Colors.white)),
                        ]),
                      ),
                      Expanded(child: Text(n > 0 ? '$n vendeur${n > 1 ? 's' : ''} local${n > 1 ? 'aux' : ''}' : 'Ouvrez la première boutique', style: const TextStyle(fontWeight: FontWeight.w700, color: C.green, fontSize: 16))),
                    ]),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
      const SizedBox(height: 56),
      const Text('À DÉCOUVRIR', style: TextStyle(color: C.terracotta, fontWeight: FontWeight.w800, letterSpacing: 3, fontSize: 16)),
      const SizedBox(height: 10),
      const Text('Les trouvailles du moment', style: TextStyle(fontSize: 38, height: 1.1, fontWeight: FontWeight.w800, color: C.ink, letterSpacing: -1)),
      const SizedBox(height: 14),
      InkWell(
        onTap: () => go(Sec.marketplace),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Text('Voir tout', style: TextStyle(color: C.green, fontWeight: FontWeight.w800, fontSize: 18)),
          SizedBox(width: 10),
          Icon(Icons.arrow_forward, color: C.green),
        ]),
      ),
      const SizedBox(height: 20),
      FutureBuilder<List<Map<String, dynamic>>>(
        future: Repo.products(limit: 8),
        builder: (_, s) {
          if (s.connectionState != ConnectionState.done) return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
          if (s.hasError) return const EmptyState(title: 'Chargement impossible', text: 'Vérifiez votre connexion puis réessayez.');
          final items = s.data ?? [];
          if (items.isEmpty) {
            return EmptyState(title: 'Aucun produit publié pour le moment', text: 'Les produits des boutiques vérifiées apparaîtront ici dès leur publication.', action: 'Ouvrir ma boutique', onAction: () => go(Sec.sell));
          }
          return ProductGrid(items);
        },
      ),
    ]);
  }
}
