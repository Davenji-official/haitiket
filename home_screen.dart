import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/repo.dart';
import '../theme.dart';
import 'fx.dart';
import '../i18n.dart';
import 'screens4.dart';
import 'shell.dart';
import 'widgets.dart';
import 'mascot.dart';

class SearchPill extends StatefulWidget {
  final void Function(String) onSubmit;
  final void Function(String)? onChanged;
  const SearchPill({super.key, required this.onSubmit, this.onChanged});
  @override
  State<SearchPill> createState() => _SearchPillState();
}

class _SearchPillState extends State<SearchPill> {
  final c = TextEditingController();
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), border: Border.all(color: C.line), boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 3))]),
    child: Row(children: [
      const Icon(Icons.search, color: C.muted, size: 30),
      const SizedBox(width: 12),
      Expanded(child: TextField(controller: c, onChanged: widget.onChanged, onSubmitted: widget.onSubmit, decoration: InputDecoration(hintText: tr("Que recherchez-vous aujourd'hui ?"), border: InputBorder.none, enabledBorder: InputBorder.none, filled: false, isDense: true))),
      PrimaryButton(label: tr('Rechercher'), onPressed: () => widget.onSubmit(c.text)),
    ]),
  );
}

class HomeScreen extends StatefulWidget {
  final void Function(Sec) go;
  const HomeScreen({super.key, required this.go});
  @override
  State<HomeScreen> createState() => _HomeState();
}

class _HomeState extends State<HomeScreen> {
  Timer? timer;
  late Future<List<Map<String, dynamic>>> disc = Repo.discover();

  void go(Sec s) => widget.go(s);

  @override
  void initState() {
    super.initState();
    // Nouvelle sélection variée (Marketplace et Bazar) toutes les 15 minutes.
    timer = Timer.periodic(const Duration(minutes: 15), (_) {
      if (mounted) setState(() => disc = Repo.discover());
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

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
    final kids = <Widget>[
      RichText(
        text: TextSpan(style: TextStyle(fontSize: 44, height: 1.05, fontWeight: FontWeight.w800, color: C.ink, letterSpacing: -1), children: [
          TextSpan(text: tr("Tout ce qu'Haïti vend, en un seul ")),
          TextSpan(text: tr('endroit.'), style: TextStyle(color: C.terracotta)),
        ]),
      ),
      const SizedBox(height: 20),
      Text(tr("Découvrez des produits uniques, soutenez les commerces d'ici et faites-vous livrer simplement, partout en Haïti."), style: const TextStyle(fontSize: 19, color: C.muted, height: 1.45)),
      const SizedBox(height: 28),
      SearchPill(onSubmit: (q) {
        Repo.search.value = q;
        go(Sec.marketplace);
      }),
      const SizedBox(height: 22),
      Wrap(spacing: 28, runSpacing: 12, children: [
        chip(Icons.local_shipping_outlined, tr('Livraison suivie')),
        chip(Icons.storefront_outlined, tr('Vendeurs vérifiés')),
        chip(Icons.location_on_outlined, tr('Près de chez vous')),
      ]),
      const SizedBox(height: 40),
      FutureBuilder<int>(
        future: Repo.activeShops(),
        builder: (_, s) {
          final n = s.data ?? 0;
          final label = n > 0 ? '$n vendeur${n > 1 ? 's' : ''} local${n > 1 ? 'aux' : ''}' : 'Ouvrez la première boutique';
          return LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            // La mascotte grandit avec l'écran ; sur grand écran elle dépasse du cadre par le haut.
            final mw = (w * (w >= 520 ? .5 : .64)).clamp(190.0, 340.0);
            final mh = mw / Mascot.home.ratio;
            const cardH = 330.0;
            final outerH = math.max(cardH, mh + 12);
            final textW = (w - mw * .74 - 22).clamp(120.0, 420.0);
            final big = textW >= 300;
            final headline = tr('Achetez local.\nVivez mieux.');
            return SizedBox(
              height: outerH,
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: cardH,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(40),
                    child: Container(
                      color: C.mint,
                      child: Stack(children: [
                        Positioned(right: -40, top: -60, child: Container(width: 330, height: 330, decoration: const BoxDecoration(color: C.sun, shape: BoxShape.circle))),
                        Positioned(left: -60, bottom: -110, child: Container(width: 380, height: 380, decoration: const BoxDecoration(color: C.coral, shape: BoxShape.circle))),
                        Positioned(
                          left: 22,
                          top: 22,
                          child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .8), borderRadius: BorderRadius.circular(24)), child: Text(tr('Fait en Haïti'), style: const TextStyle(fontWeight: FontWeight.w700, color: C.green, fontSize: 15))),
                        ),
                        Positioned(
                          left: 22,
                          bottom: 22,
                          width: textW,
                          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(big ? headline : headline.replaceAll(' ', '\n'), style: TextStyle(fontSize: big ? 42 : 30, height: 1.1, fontWeight: FontWeight.w800, color: C.ink)),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: 110,
                              height: 46,
                              child: Stack(children: [
                                Positioned(left: 0, child: avatar('M', C.yellow, C.ink)),
                                Positioned(left: 30, child: avatar('A', C.terracotta, C.ink)),
                                Positioned(left: 60, child: avatar('J', C.ink, Colors.white)),
                              ]),
                            ),
                            const SizedBox(height: 6),
                            Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: C.green, fontSize: 14)),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                ),
                Positioned(right: -6, bottom: 10, width: mw, height: mh, child: const MascotImage(Mascot.home, delay: Duration(milliseconds: 350))),
              ]),
            );
          });
        },
      ),
      const SizedBox(height: 56),
      Text(tr('À DÉCOUVRIR'), style: const TextStyle(color: C.terracotta, fontWeight: FontWeight.w800, letterSpacing: 3, fontSize: 16)),
      const SizedBox(height: 10),
      Text(tr('Les trouvailles du moment'), style: const TextStyle(fontSize: 38, height: 1.1, fontWeight: FontWeight.w800, color: C.ink, letterSpacing: -1)),
      const SizedBox(height: 14),
      InkWell(
        onTap: () => go(Sec.marketplace),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('Voir tout'), style: const TextStyle(color: C.green, fontWeight: FontWeight.w800, fontSize: 18)),
          SizedBox(width: 10),
          Icon(Icons.arrow_forward, color: C.green),
        ]),
      ),
      const SizedBox(height: 20),
      FutureBuilder<List<Map<String, dynamic>>>(
        future: disc,
        builder: (_, s) {
          if (s.connectionState != ConnectionState.done) return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
          if (s.hasError) return ErrorState(s.error);
          final items = s.data ?? [];
          if (items.isEmpty) {
            return EmptyState(title: 'Aucun produit publié pour le moment', text: 'Les produits des boutiques vérifiées apparaîtront ici dès leur publication.', action: 'Ouvrir ma boutique', onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShopRequestScreen())));
          }
          return ProductGrid(items);
        },
      ),
    ];
    return RefreshIndicator(
      onRefresh: () async {
        setState(() => disc = Repo.discover());
        await disc;
      },
      child: ListView(padding: const EdgeInsets.fromLTRB(18, 28, 18, 40), children: [for (var i = 0; i < kids.length; i++) FadeSlideIn(index: i, child: kids[i])]),
    );
  }
}
