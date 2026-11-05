import 'package:flutter/material.dart';

/// Palette HAITIKET. Les neutres (fond, texte, surfaces…) s'adaptent au mode nuit ; les couleurs de marque restent identiques.
class C {
  static bool dark = false;

  static Color get bg => dark ? const Color(0xFF0E1714) : const Color(0xFFFCFAF6);
  static Color get ink => dark ? const Color(0xFFE9F1ED) : const Color(0xFF17332E);
  /// Version « fond » de ink : fond sombre en mode jour, vert profond en mode nuit (texte blanc par-dessus).
  static Color get deep => dark ? const Color(0xFF2A6B54) : const Color(0xFF17332E);
  static Color get mint => dark ? const Color(0xFF1E3A30) : const Color(0xFFDCEADF);
  static Color get green => dark ? const Color(0xFF4FAE85) : const Color(0xFF2F6B52);
  static Color get muted => dark ? const Color(0xFF9DB4AA) : const Color(0xFF6B8077);
  static Color get line => dark ? const Color(0xFF2B403A) : const Color(0xFFE6E8E3);
  /// Surface des cartes, champs et fenêtres.
  static Color get card => dark ? const Color(0xFF16241F) : Colors.white;
  static Color get tint => dark ? const Color(0xFF3B2822) : const Color(0xFFFFF1EC);
  static Color get soft => dark ? const Color(0xFF1C2B26) : const Color(0xFFF1F1F1);

  static const terracotta = Color(0xFFE8694A);
  static const yellow = Color(0xFFF2B63D);
  static const coral = Color(0xFFE8896F);
  static const sun = Color(0xFFEFC060);
}

ThemeData buildTheme() {
  final d = C.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF2F6B52),
    brightness: d ? Brightness.dark : Brightness.light,
    surface: C.bg,
  ).copyWith(
    onSurface: C.ink,
    onSurfaceVariant: C.muted,
    primary: C.green,
    outline: C.line,
    outlineVariant: C.line,
    surfaceContainerLowest: C.bg,
    surfaceContainerLow: C.card,
    surfaceContainer: C.card,
    surfaceContainerHigh: C.card,
    surfaceContainerHighest: C.soft,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: d ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: C.bg,
    canvasColor: C.bg,
    colorScheme: scheme,
    fontFamily: 'Roboto',
    pageTransitionsTheme: PageTransitionsTheme(builders: {for (final p in TargetPlatform.values) p: const ZoomPageTransitionsBuilder()}),
    splashFactory: InkRipple.splashFactory,
    dividerColor: C.line,
    appBarTheme: AppBarTheme(backgroundColor: C.bg, foregroundColor: C.ink, elevation: 0, scrolledUnderElevation: 0, surfaceTintColor: Colors.transparent),
    drawerTheme: DrawerThemeData(backgroundColor: C.bg),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.deep,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.card,
      hintStyle: TextStyle(color: C.muted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: C.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: C.line)),
    ),
  );
}

/// '#RRGGBB' -> Color (null si invalide).
Color? hexColor(String? h) {
  if (h == null || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(h)) return null;
  return Color(int.parse('FF${h.substring(1)}', radix: 16));
}
