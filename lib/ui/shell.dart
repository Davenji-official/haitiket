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
import 'product_detail.dart';
import 'screens6.dart';
import '../i18n.dart';
import 'mascot.dart';
import 'widgets.dart';

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
  final String? initialProductId;
  const Shell({super.key, this.initialProductId});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  Sec sec = Sec.home;
  Stream<List<Map<String, dynamic>>> notifs = const Stream.empty();
  late Stream<List<Map<String, dynamic>>> announcements;
  String? streamUser;
  StreamSubscription<AuthState>? authSub;
  int logoTaps = 0;
  DateTime lastTap = DateTime(2000);
  bool hideDrawerBalances = false;

  @override
  void initState() {
    super.initState();
    announcements = Config.configured ? Repo.globalAnnouncementStream() : const Stream.empty();
    final sharedProductId = widget.initialProductId;
    if (sharedProductId != null && sharedProductId.isNotEmpty && Config.configured) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        try {
          final product = await Repo.productById(sharedProductId);
          if (!mounted) return;
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductDetailScreen(product)));
        } catch (_) {
          if (mounted) toast(context, 'Ce produit n’est plus disponible ou le lien est invalide.');
        }
      });
    }
    // Retour de la page de paiement (web) : on ouvre directement « Mes commandes ».
    if (Uri.base.queryParameters['pay'] != null) sec = Sec.orders;
    // Retour de la page Plop Plop (recharge) : on ouvre le portefeuille, qui vérifie la recharge automatiquement.
    if (Uri.base.path.contains('/payment/') || Uri.base.queryParameters.containsKey('refference_id') || Uri.base.queryParameters.containsKey('id_transaction')) sec = Sec.wallet;
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
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 18),
                    child: Row(children: [
                      if (u == null)
                        const CircleAvatar(radius: 29, child: Icon(Icons.person_outline, size: 30))
                      else
                        FutureBuilder<Map<String, dynamic>?>(
                          future: Repo.getProfile(),
                          builder: (_, snap) {
                            final url = snap.data?['avatar_url'] as String?;
                            return CircleAvatar(radius: 29, backgroundColor: C.mint,
                              backgroundImage: url != null && url.isNotEmpty ? NetworkImage(url) : null,
                              child: url == null || url.isEmpty ? const Icon(Icons.person_outline, size: 30, color: C.green) : null);
                          },
                        ),
                      const SizedBox(width: 12),
                      Expanded(child: FutureBuilder<Map<String, dynamic>?>(
                        future: u == null ? Future.value(null) : Repo.getProfile(),
                        builder: (_, snap) {
                          final display = (snap.data?['display_name'] as String?)?.trim();
                          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(display == null || display.isEmpty ? (u?.email ?? tr('Non connecté')) : display,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: C.ink)),
                            if (u != null) Text(u.email ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 12)),
                          ]);
                        },
                      )),
                    ]),
                  ),
                  if (u != null) Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                    child: FutureBuilder<Map<String, dynamic>>(
                      future: Repo.myWalletV2(),
                      builder: (_, snap) {
                        final balances = (snap.data?['balances'] as Map?) ?? const {};
                        String value(String currency) {
                          if (hideDrawerBalances) return '••••••';
                          final raw = (balances[currency] as num?)?.toDouble() ?? 0;
                          return '${raw.toStringAsFixed(2)} $currency';
                        }
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [const Icon(Icons.account_balance_wallet_outlined, color: C.green, size: 18), const SizedBox(width: 7), const Expanded(child: Text('Mes soldes', style: TextStyle(fontWeight: FontWeight.w800, color: C.ink))),
                              IconButton(visualDensity: VisualDensity.compact, constraints: const BoxConstraints(), padding: EdgeInsets.zero,
                                onPressed: () => setState(() => hideDrawerBalances = !hideDrawerBalances),
                                icon: Icon(hideDrawerBalances ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 19, color: C.green)),
                            ]),
                            if (snap.connectionState != ConnectionState.done) const LinearProgressIndicator(minHeight: 2)
                            else if (snap.hasError) const Text('Solde indisponible', style: TextStyle(color: C.muted, fontSize: 12))
                            else Row(children: [Expanded(child: Text(value('HTG'), style: const TextStyle(fontWeight: FontWeight.w800, color: C.green))), Expanded(child: Text(value('USD'), style: const TextStyle(fontWeight: FontWeight.w800, color: C.green)))]),
                            Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () { Navigator.pop(context); go(Sec.wallet); }, child: const Text('Ouvrir le portefeuille'))),
                          ]),
                        );
                      },
                    ),
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
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  'Powered by FIBRAXA',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: .7, color: C.muted),
                ),
              ),
            ),
          ],
        ),
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

  Widget globalAnnouncement() => StreamBuilder<List<Map<String, dynamic>>>(
        stream: announcements,
        builder: (context, snapshot) {
          final now = DateTime.now().toUtc();
          final visible = (snapshot.data ?? const <Map<String, dynamic>>[]).where((a) {
            final starts = DateTime.tryParse('${a['starts_at'] ?? ''}')?.toUtc();
            final ends = DateTime.tryParse('${a['ends_at'] ?? ''}')?.toUtc();
            return a['active'] == true && (starts == null || !starts.isAfter(now)) && (ends == null || ends.isAfter(now));
          }).toList();
          if (visible.isEmpty) return const SizedBox.shrink();
          final a = visible.first;
          final sev = '${a['severity'] ?? 'info'}';
          final bg = sev == 'urgent' || sev == 'warning' ? const Color(0xFFFFE9DF) : C.mint;
          final icon = sev == 'urgent' ? Icons.warning_amber_rounded : sev == 'success' ? Icons.check_circle_outline : Icons.campaign_outlined;
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(10, 6, 10, 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: sev == 'urgent' ? C.terracotta : C.line)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: C.ink), const SizedBox(width: 9),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${a['title']}', style: const TextStyle(fontWeight: FontWeight.w900, color: C.ink)),
                const SizedBox(height: 3), Text('${a['body']}', style: const TextStyle(color: C.ink, height: 1.35)),
              ])),
            ]),
          );
        },
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
              globalAnnouncement(),
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
