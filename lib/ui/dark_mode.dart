import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';

/// Mode nuit : vrai thème sombre (palette C.*), préférence mémorisée sur l'appareil.
class ThemeStore {
  static final ValueNotifier<bool> dark = ValueNotifier<bool>(false);
  static const _key = 'haitiket_dark_mode';

  static Future<void> restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getBool(_key) ?? false;
      C.dark = v;
      dark.value = v;
    } catch (_) {}
  }

  static Future<void> set(bool v) async {
    C.dark = v;
    dark.value = v;
    _repaintAll();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_key, v);
    } catch (_) {}
  }

  /// Les couleurs C.* sont lues à la construction des widgets : on force la reconstruction de tout l'arbre
  /// (sans perdre l'état des écrans ni la navigation).
  static void _repaintAll() {
    void visit(Element e) {
      e.markNeedsBuild();
      e.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
  }
}

/// Conservé pour compatibilité : plus aucun filtre n'est appliqué (le thème sombre est natif).
class DarkModeScope extends StatelessWidget {
  final Widget child;
  const DarkModeScope({super.key, required this.child});
  @override
  Widget build(BuildContext context) => child;
}

class DarkSafe extends StatelessWidget {
  final Widget child;
  const DarkSafe({super.key, required this.child});
  @override
  Widget build(BuildContext context) => child;
}

// Fond de carte sombre : inversion de luminosité des tuiles, avec adoucissement (pas de blanc éclatant).
const List<double> _kTileDark = <double>[
  -0.62, -0.60, -0.20, 0, 232,
  -0.20, -0.66, -0.16, 0, 238,
  -0.20, -0.60, -0.22, 0, 236,
  0, 0, 0, 1, 0,
];

Widget darkTileBuilder(BuildContext context, Widget tileWidget, TileImage tile) =>
    ThemeStore.dark.value ? ColorFiltered(colorFilter: const ColorFilter.matrix(_kTileDark), child: tileWidget) : tileWidget;

/// Masquage des soldes (portefeuille, menu) : préférence mémorisée sur l'appareil, conservée entre les écrans et les lancements.
class BalancePrivacy {
  static final ValueNotifier<bool> hidden = ValueNotifier<bool>(false);
  static const _key = 'haitiket_hide_balances';

  static Future<void> restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      hidden.value = p.getBool(_key) ?? false;
    } catch (_) {}
  }

  static Future<void> set(bool v) async {
    hidden.value = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_key, v);
    } catch (_) {}
  }
}
