import 'package:flutter/material.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';
import '../data/repo.dart';
import 'auth_screens.dart';
import '../theme.dart';
import 'admin_screen.dart';
import 'fx.dart';
import 'home_screen.dart';
import 'screens.dart';
import 'screens2.dart';
import 'screens3.dart';
import 'screens4.dart';
import 'screens5.dart';
import 'screens6.dart';
import '../i18n.dart';
import 'mascot.dart';

enum Sec { home, marketplace, bazar, network, favorites, cart, account, orders, dashboard, admin, messages, courier, profile, settings, support, notifications, wallet }

const _bottom = [Sec.home, Sec.marketplace, Sec.bazar, Sec.network, Sec.messages];
List<NavItem> _bottomItems() => [
      NavItem(Icons.home_outlined, Icons.home_rounded, tr('Accueil')),
      NavItem(Icons.storefront_outlined, Icons.storefront_rounded, tr('Marketplace')),
      const NavItem(Icons.local_offer_outlined, Icons.local_offer_rounded, 'Bazar'),
      NavItem(Icons.local_shipping_outlined, Icons.local_shipping_rounded, tr('Network')),
      NavItem(Icons.chat_bubble_outline, Icons.chat_bubble_rounded, tr('Messages')),
    ];

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  Sec sec = Sec.home;
  Stream<List<Map<String, dynamic>>> notifs = const Stream.empty();
  String? streamUser;
  StreamSubscription<AuthState>? authSub;
  int logoTaps = 0;
  DateTime lastTap = DateTime(2000);

  @override
  void initState() {
    super.initState();
    // Retour de la page de paiement (web) : on ouvre directement « Mes commandes ».
    if (Uri.base.queryParameters['pay'] != null) sec = Sec.orders;
    if (Config.configured) {
      authSub = Supabase.instance.client.auth.onAuthStateChange.listen((st) {
        if (!mounted) return;
        setState(() {});
        if (st.event == AuthChangeEvent.passwordRecovery) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ResetPasswordScreen()));
        }
      });
    }
  }

  @override
  void dispose() {
    authSub?.cancel();
    super.dispose();
  }

  bool _precached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    Mascot.precacheAll(context);
  }

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
      case Sec.notifications:
        return const NotificationsScreen();
      case Sec.wallet:
        return const WalletScreen();
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
              Image.asset(Mascot.badge.path, height: 58, errorBuilder: (_, __, ___) => const SizedBox(width: 58, height: 58)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('HAITIKET', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: C.ink)),
                Text(u?.email ?? tr('Non connecté'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted)),
              ])),
            ]),
          ),
          drawerItem(Icons.person_outline, tr('Mon profil'), Sec.profile),
          drawerItem(Icons.receipt_long_outlined, tr('Mes commandes'), Sec.orders),
          drawerItem(Icons.favorite_border, tr('Mes favoris'), Sec.favorites),
          drawerItem(Icons.store_mall_directory_outlined, tr('Espace vendeur'), Sec.dashboard),
          drawerItem(Icons.two_wheeler_outlined, tr('Espace livreur'), Sec.courier),
          drawerItem(Icons.account_balance_wallet_outlined, 'Portefeuille', Sec.wallet),
          const Divider(height: 28),
          drawerItem(Icons.support_agent_outlined, tr('Support'), Sec.support),
          drawerItem(Icons.settings_outlined, tr('Paramètres'), Sec.settings),
          const Divider(height: 28),
          if (u == null)
            drawerItem(Icons.login, tr('Se connecter'), Sec.account)
          else
            ListTile(
              leading: const Icon(Icons.logout, color: C.terracotta),
              title: Text(tr('Se déconnecter'), style: const TextStyle(fontWeight: FontWeight.w700, color: C.ink, fontSize: 17)),
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
              Image.asset(Mascot.badge.path, height: 46, errorBuilder: (_, __, ___) => const SizedBox(width: 46, height: 46)),
              const SizedBox(width: 8),
              const Text('HAITIKET', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: C.ink)),
            ]),
          ),
          const Spacer(),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: notifs,
            builder: (_, snap) {
              final unread = (snap.data ?? []).where((n) => n['read_at'] == null).length;
              return IconButton(
                onPressed: () => go(Sec.notifications),
                icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.notifications_none, color: C.green, size: 28)),
              );
            },
          ),
          IconButton(onPressed: () => go(Sec.favorites), icon: const Icon(Icons.favorite_border, color: C.green, size: 28)),
          ValueListenableBuilder(
            valueListenable: CartStore.lines,
            builder: (_, __, ___) => IconButton(
              key: CartFly.targetKey,
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
    final uid = currentUser()?.id;
    if (uid != streamUser) {
      streamUser = uid;
      notifs = Repo.notificationStream();
      Repo.loadFavorites();
    }
    return ValueListenableBuilder<String>(
      valueListenable: appLang,
      builder: (_, __, ___) => Scaffold(
      key: scaffoldKey,
      drawer: drawer(),
      bottomNavigationBar: BottomBar(index: bi, items: _bottomItems(), onTap: (i) => go(_bottom[i])),
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
                  child: KeyedSubtree(key: ValueKey('${sec.name}-${appLang.value}'), child: body()),
                ),
              ),
            ]),
          ),
        ),
      ),
    ));
  }
}
