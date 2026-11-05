import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mode nuit : préférence mémorisée sur l'appareil, activable/désactivable à tout moment (menu).
class ThemeStore {
  static final ValueNotifier<bool> dark = ValueNotifier<bool>(false);
  static const _key = 'haitiket_dark_mode';

  static Future<void> restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      dark.value = p.getBool(_key) ?? false;
    } catch (_) {}
  }

  static Future<void> set(bool v) async {
    dark.value = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_key, v);
    } catch (_) {}
  }
}

// Inversion de luminosité en conservant les teintes (équivalent de invert(1) hue-rotate(180deg)).
const List<double> _kDarkMatrix = <double>[
  0.574, -1.430, -0.144, 0, 255,
  -0.426, -0.430, -0.144, 0, 255,
  -0.426, -1.430, 0.856, 0, 255,
  0, 0, 0, 1, 0,
];

/// Enveloppe toute l'application (dialogues et menus compris) quand le mode nuit est actif.
class DarkModeScope extends StatelessWidget {
  final Widget child;
  const DarkModeScope({super.key, required this.child});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: ThemeStore.dark,
        builder: (_, on, __) => on ? ColorFiltered(colorFilter: const ColorFilter.matrix(_kDarkMatrix), child: child) : child,
      );
}

/// Les photos ne doivent pas être inversées : on réapplique la même matrice (deux inversions = identité).
class DarkSafe extends StatelessWidget {
  final Widget child;
  const DarkSafe({super.key, required this.child});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: ThemeStore.dark,
        builder: (_, on, __) => on ? ColorFiltered(colorFilter: const ColorFilter.matrix(_kDarkMatrix), child: child) : child,
      );
}
