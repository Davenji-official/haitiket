import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'data/repo.dart';
import 'i18n.dart';
import 'theme.dart';
import 'ui/dark_mode.dart';
import 'ui/notif_router.dart';
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
  await ThemeStore.restore();
  await BalancePrivacy.restore();
  await CartStore.restore();
  CartStore.lines.addListener(CartStore.persist);
  runApp(const HaitiketApp());
}

class HaitiketApp extends StatelessWidget {
  const HaitiketApp({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: ThemeStore.dark,
        builder: (_, __, ___) => MaterialApp(
          title: 'HAITIKET',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          navigatorKey: appNavKey,
          home: const SplashGate(),
        ),
      );
}
