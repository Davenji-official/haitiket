import 'package:flutter/material.dart';
import '../data/repo.dart';
import '../theme.dart';
import 'admin_screen.dart';
import 'fx.dart';
import 'home_screen.dart';
import 'screens.dart';
import 'screens2.dart';
import 'screens3.dart';
import 'screens4.dart';

enum Sec { home, marketplace, bazar, network, favorites, cart, account, orders, dashboard, admin, messages, courier, profile, settings, support }

const _bottom = [Sec.home, Sec.marketplace, Sec.bazar, Sec.network, Sec.messages];
const _bottomItems = [
  NavItem(Icons.home_outlined, Icons.home_rounded, 'Accueil'),
  NavItem(Icons.storefront_outlined, Icons.storefront_rounded, 'Marketplace'),
  NavItem(Icons.local_offer_outlined, Icons.local_offer_rounded, 'Bazar'),
  NavItem(Icons.local_shipping_outlined, Icons.local_shipping_rounded, 'Network'),
  NavItem(Icons.chat_bubble_outline, Icons.chat_bubble_rounded, 'Messages'),
];

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  Sec sec = Sec.home;
  int logoTaps = 0;
  DateTime lastTap = DateTime(2000);

  void go(Sec s) => setState(() => sec = s);

  // Accès caché : 10 touches rapides sur le logo, puis code vérifié côté serveur.
  Future<void> logoTap() async {
    final now = DateTime.now();
    logoTaps = now.difference(lastTap).inSeconds > 4 ? 1 : logoTaps + 1;
    lastTap = now;
    if (logoTaps < 10) {
      if (logoTaps == 1) go(Sec.home);
      return;
    }
    logoTaps = 0;
    if (currentUser() == null) return go(Sec.home);
    final c = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Code secret'),
        content: TextField(controller: c, obscureText: true, autofocus: true, decoration: const InputDecoration(hintText: 'Entrez le code')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Entrer')),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    try {
      final ok = await Repo.adminUnlock(code);
      if (!mounted) return;
      if (ok) {
        go(Sec.admin);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code incorrect')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Repo.err(e))));
    }
  }

  Widget body() {
    switch (sec) {
      case Sec.home:
        return HomeScreen(go: go);
      case Sec.marketplace:
        return const MarketplaceScreen();
      case Sec.bazar:
        return const BazarScreen();
      case Sec.network:
        return const NetworkScreen();
      case Sec.favorites:
        return const FavoritesScreen();
      case Sec.cart:
        return const CartScreen();
      case Sec.messages:
        return const ConversationsScreen();
      case Sec.courier:
        return const CourierScreen();
      case Sec.admin:
        return const AdminScreen();
      case Sec.orders:
        return const OrdersScreen();
      case Sec.dashboard:
        return const DashboardScreen();
      case Sec.profile:
        return const ProfileScreen();
      case Sec.settings:
        return SettingsScreen(onChanged: () => setState(() {}));
      case Sec.support:
        return const SupportScreen();
      case Sec.account:
        return AccountScreen(onChanged: () => setState(() {}));
    }
  }

  Widget drawerItem(IconData i, String label, Sec s) => ListTile(
        leading: Icon(i, color: sec == s ? C.terracotta : C.green),
        title: Text(label, style: TextStyle(fontWeight: sec == s ? FontWeight.w800 : FontWeight.w600, color: C.ink, fontSize: 17)),
        selected: sec == s,
        selectedTileColor: C.mint.withValues(alpha: .6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onTap: () {
          Navigator.pop(context);
          go(s);
        },
      );

  Widget drawer() {
    final u = currentUser();
    return Drawer(
      backgroundColor: C.bg,
      child: SafeArea(
        child: ListView(padding: const EdgeInsets.all(12), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 18),
            child: Row(children: [
              Image.asset('assets/logo_t.png', height: 54),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('HAITIKET', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: C.ink)),
                Text(u?.email ?? 'Non connecté', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted)),
              ])),
            ]),
          ),
          drawerItem(Icons.person_outline, 'Mon profil', Sec.profile),
          drawerItem(Icons.receipt_long_outlined, 'Mes commandes', Sec.orders),
          drawerItem(Icons.favorite_border, 'Mes favoris', Sec.favorites),
          drawerItem(Icons.store_mall_directory_outlined, 'Espace vendeur', Sec.dashboard),
          drawerItem(Icons.two_wheeler_outlined, 'Espace livreur', Sec.courier),
          const Divider(height: 28),
          drawerItem(Icons.support_agent_outlined, 'Support', Sec.support),
          drawerItem(Icons.settings_outlined, 'Paramètres', Sec.settings),
          const Divider(height: 28),
          if (u == null)
            drawerItem(Icons.login, 'Se connecter', Sec.account)
          else
            ListTile(
              leading: const Icon(Icons.logout, color: C.terracotta),
              title: const Text('Se déconnecter', style: TextStyle(fontWeight: FontWeight.w700, color: C.ink, fontSize: 17)),
              onTap: () async {
                Navigator.pop(context);
                await Repo.signOut();
                if (mounted) go(Sec.home);
              },
            ),
        ]),
      ),
    );
  }

  Widget header() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: const BoxDecoration(color: C.bg, border: Border(bottom: BorderSide(color: C.line))),
        child: Row(children: [
          IconButton(onPressed: () => scaffoldKey.currentState?.openDrawer(), icon: const Icon(Icons.menu, color: C.ink, size: 28)),
          Pressable(
            onTap: logoTap,
            scale: .9,
            child: Row(children: [
              Image.asset('assets/logo_t.png', height: 44),
              const SizedBox(width: 8),
              const Text('HAITIKET', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: C.ink)),
            ]),
          ),
          const Spacer(),
          IconButton(onPressed: () => go(Sec.favorites), icon: const Icon(Icons.favorite_border, color: C.green, size: 28)),
          ValueListenableBuilder(
            valueListenable: CartStore.lines,
            builder: (_, __, ___) => IconButton(
              onPressed: () => go(Sec.cart),
              icon: TweenAnimationBuilder<double>(
                key: ValueKey(CartStore.count),
                tween: Tween(begin: 1.6, end: 1.0),
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (_, v, ch) => Transform.scale(scale: v, child: ch),
                child: Badge(isLabelVisible: CartStore.count > 0, label: Text('${CartStore.count}'), child: const Icon(Icons.shopping_bag_outlined, color: C.green, size: 28)),
              ),
            ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final bi = _bottom.indexOf(sec);
    return Scaffold(
      key: scaffoldKey,
      drawer: drawer(),
      bottomNavigationBar: BottomBar(index: bi, items: _bottomItems, onTap: (i) => go(_bottom[i])),
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(children: [
              header(),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 380),
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, .04), end: Offset.zero).animate(anim), child: child)),
                  child: KeyedSubtree(key: ValueKey(sec), child: body()),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
