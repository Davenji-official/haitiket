import 'package:flutter/material.dart';
import '../theme.dart';
import 'shell.dart';

class SplashGate extends StatefulWidget {
  const SplashGate({super.key});
  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000));
  bool done = false;

  @override
  void initState() {
    super.initState();
    c.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted) setState(() => done = true);
        });
      }
    });
    c.forward();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  double t(double a, double b, Curve cv) => cv.transform(((c.value - a) / (b - a)).clamp(0.0, 1.0));

  Widget ring(double a, double b) {
    final v = t(a, b, Curves.easeOut);
    return Opacity(
      opacity: (1 - v) * .5,
      child: Container(width: 120 + 260 * v, height: 120 + 260 * v, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: C.terracotta, width: 3))),
    );
  }

  Widget splash() {
    const word = 'HAITIKET';
    return Scaffold(
      key: const ValueKey('splash'),
      backgroundColor: Colors.white,
      body: AnimatedBuilder(
        animation: c,
        builder: (_, __) {
          final logoScale = t(0, .5, Curves.elasticOut);
          final logoFade = t(0, .2, Curves.easeOut);
          return Stack(alignment: Alignment.center, children: [
            Center(child: Stack(alignment: Alignment.center, children: [ring(.15, .6), ring(.3, .8), ring(.45, 1)])),
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Opacity(
                opacity: logoFade,
                child: Transform.rotate(
                  angle: (1 - logoScale) * -.35,
                  child: Transform.scale(scale: logoScale.clamp(0.0, 1.3), child: Image.asset('assets/logo_t.png', height: 190)),
                ),
              ),
              const SizedBox(height: 26),
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < word.length; i++)
                  Opacity(
                    opacity: t(.35 + i * .04, .5 + i * .04, Curves.easeOut),
                    child: Transform.translate(
                      offset: Offset(0, 24 * (1 - t(.35 + i * .04, .55 + i * .04, Curves.easeOutBack))),
                      child: Text(word[i], style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: C.ink, letterSpacing: 2)),
                    ),
                  ),
              ]),
              const SizedBox(height: 10),
              Opacity(
                opacity: t(.65, .85, Curves.easeOut),
                child: Transform.translate(offset: Offset(0, 12 * (1 - t(.65, .9, Curves.easeOut))), child: const Text('LE COMMERCE AVANCE, HAÏTI SE RAPPROCHE.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 2, color: C.terracotta))),
              ),
            ]),
            Positioned(
              bottom: 60,
              left: 60,
              right: 60,
              child: ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: c.value, minHeight: 5, backgroundColor: C.mint, color: C.terracotta)),
            ),
          ]);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 800),
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: ScaleTransition(scale: Tween<double>(begin: .96, end: 1).animate(anim), child: child)),
        child: done ? const Shell(key: ValueKey('shell')) : splash(),
      );
}
