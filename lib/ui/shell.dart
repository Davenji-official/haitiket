import 'package:flutter/material.dart';
import '../data/repo.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'screens.dart';
import 'screens2.dart';
import 'admin_screen.dart';

enum Sec { home, marketplace, bazar, network, sell, favorites, cart, account, orders, dashboard, admin }

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  Sec sec = Sec.home;
  bool menu = false;
  bool admin = false;

  @override
  void initState() {
    super.initState();
    checkAdmin();
  }

  Future<void> checkAdmin() async {
    final a = await Repo.isAdmin();
    if (mounted) setState(() => admin = a);
  }

  void go(Sec s) => setState(() {
        sec = s;
        menu = false;
      });

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
      case Sec.sell:
        return const SellScreen();
      case Sec.favorites:
        return const FavoritesScreen();
      case Sec.cart:
        return const CartScreen();
      case Sec.admin:
        return const AdminScreen();
      case Sec.orders:
        return const OrdersScreen();
      case Sec.dashboard:
        return const DashboardScreen();
      case Sec.account:
        return AccountScreen(onChanged: () {
          setState(() {});
          checkAdmin();
        });
    }
  }

  Widget item(String label, Sec s) => InkWell(
        onTap: () => go(s),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          child: Align(alignment: Alignment.centerLeft, child: Text(label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: sec == s ? C.ink : C.muted))),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final logged = currentUser() != null;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.line))),
            child: Row(children: [
              IconButton(onPressed: () => setState(() => menu = !menu), icon: Icon(menu ? Icons.close : Icons.menu, color: C.ink, size: 28)),
              const SizedBox(width: 4),
              InkWell(
                onTap: () => go(Sec.home),
                child: Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: C.yellow, borderRadius: BorderRadius.circular(14)),
                    child: const Text('H', style: TextStyle(fontWeight: FontWeight.w800, color: C.ink, fontSize: 18)),
                  ),
                  const SizedBox(width: 10),
                  const Text('HAITIKET', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 24, color: C.ink)),
                ]),
              ),
              const Spacer(),
              IconButton(onPressed: () => go(Sec.favorites), icon: const Icon(Icons.favorite_border, color: C.green, size: 28)),
              ValueListenableBuilder(
                valueListenable: CartStore.lines,
                builder: (_, __, ___) => IconButton(
                  onPressed: () => go(Sec.cart),
                  icon: Badge(isLabelVisible: CartStore.count > 0, label: Text('${CartStore.count}'), child: const Icon(Icons.shopping_bag_outlined, color: C.green, size: 28)),
                ),
              ),
            ]),
          ),
          if (menu)
            Container(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.line))),
              child: Column(children: [
                item('Marketplace', Sec.marketplace),
                item('Bazar', Sec.bazar),
                item('HAITIKET Network', Sec.network),
                item('Vendre', Sec.sell),
                item('Espace vendeur', Sec.dashboard),
                item('Mes commandes', Sec.orders),
                if (admin) item('Administration', Sec.admin),
                item(logged ? 'Mon compte' : 'Se connecter', Sec.account),
                const SizedBox(height: 8),
              ]),
            ),
          Expanded(child: body()),
        ]),
      ),
    );
  }
}
