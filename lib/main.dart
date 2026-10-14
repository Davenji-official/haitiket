import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'i18n.dart';
import 'theme.dart';
import 'ui/splash.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Config.configured) {
    await Supabase.initialize(
      url: Config.supabaseUrl,
      anonKey: Config.supabaseAnonKey,
    );
  }

  await loadLang();
  runApp(const HaitiketApp());
}

class HaitiketApp extends StatelessWidget {
  const HaitiketApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'HAITIKET',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const SplashGate(),
      );
}
