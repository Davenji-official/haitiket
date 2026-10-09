import 'package:flutter/material.dart';

class C {
  static const bg = Color(0xFFFCFAF6);
  static const ink = Color(0xFF17332E);
  static const terracotta = Color(0xFFE8694A);
  static const yellow = Color(0xFFF2B63D);
  static const mint = Color(0xFFDCEADF);
  static const green = Color(0xFF2F6B52);
  static const muted = Color(0xFF6B8077);
  static const coral = Color(0xFFE8896F);
  static const sun = Color(0xFFEFC060);
  static const line = Color(0xFFE6E8E3);
}

ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: C.bg,
      colorScheme: ColorScheme.fromSeed(seedColor: C.green, surface: C.bg),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(backgroundColor: C.bg, elevation: 0),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: C.ink,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: C.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: C.line)),
      ),
    );
