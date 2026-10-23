import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';

/// Les mascottes Haitiket, une par section de l'application.
/// `accent` reprend la couleur de la section sur la planche de référence ;
/// `ratio` = largeur / hauteur de l'image recadrée.
enum Mascot {
  home('home', Color(0xFF1B8A4B), 0.878),
  welcome('welcome', Color(0xFF1B8A4B), 1.127),
  boutiques('boutiques', Color(0xFFF08A1C), 1.018),
  bazar('bazar', Color(0xFF2563EB), 0.997),
  cart('cart', Color(0xFF7C3AED), 1.137),
  orders('orders', Color(0xFFE11D48), 1.163),
  support('support', Color(0xFF0891B2), 1.088),
  messages('messages', Color(0xFFEC4899), 1.134),
  profile('profile', Color(0xFF1E3A8A), 1.007),
  notifications('notifications', Color(0xFF7C3AED), 1.22),
  admin('admin', Color(0xFF334155), 1.159),
  wallet('wallet', Color(0xFF16A34A), 1.196),
  seller('seller', Color(0xFFF08A1C), 0.976),
  badge('badge', Color(0xFF1B8A4B), 0.951);

  final String file;
  final Color accent;
  final double ratio;
  const Mascot(this.file, this.accent, this.ratio);

  String get path => 'assets/mascots/$file.webp';

  /// Charge toutes les images en mémoire pour qu'elles apparaissent sans clignotement.
  static void precacheAll(BuildContext context) {
    for (final m in Mascot.values) {
      precacheImage(AssetImage(m.path), context).catchError((_) {});
    }
  }
}

/// Mascotte animée : apparition « pop », respiration douce, saut au toucher,
/// ombre au sol. Les animations s'arrêtent si l'utilisateur a réduit les animations.
class MascotImage extends StatefulWidget {
  final Mascot mascot;
  final Duration delay;
  final bool shadow;
  const MascotImage(this.mascot, {super.key, this.delay = const Duration(milliseconds: 150), this.shadow = true});
  @override
  State<MascotImage> createState() => _MascotImageState();
}

class _MascotImageState extends State<MascotImage> with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  late final AnimationController _idle = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));
  late final AnimationController _tap = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  bool _started = false;
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduced) {
      _enter.value = 1;
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _enter.forward();
      });
      _idle.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    _idle.dispose();
    _tap.dispose();
    super.dispose();
  }

  void _onTap() {
    if (_reduced) return;
    HapticFeedback.selectionClick();
    _tap.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth.isFinite ? c.maxWidth : 200.0;
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _onTap,
            child: AnimatedBuilder(
              animation: Listenable.merge([_enter, _idle, _tap]),
              builder: (_, __) {
                final e = _enter.value;
                final pop = .6 + .4 * Curves.elasticOut.transform(e);
                final fade = Curves.easeOut.transform((e * 2.2).clamp(0.0, 1.0));
                final breathe = Curves.easeInOut.transform(_idle.value);
                final t = _tap.value;
                final hop = math.sin(math.pi * t) * 22;
                final wobble = math.sin(t * math.pi * 3) * .045 * (1 - t);
                final sx = pop * (1 - .008 * breathe);
                final sy = pop * (1 + .02 * breathe);
                return Opacity(
                  opacity: fade,
                  child: Stack(alignment: Alignment.bottomCenter, children: [
                    if (widget.shadow)
                      Positioned(
                        bottom: 0,
                        child: Opacity(
                          opacity: (1 - hop / 40).clamp(0.3, 1.0),
                          child: Container(
                            width: w * (.5 - hop / 300),
                            height: 12,
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.all(Radius.elliptical(100, 20)),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .16), blurRadius: 14, spreadRadius: 1)],
                            ),
                          ),
                        ),
                      ),
                    Positioned.fill(
                      bottom: 8,
                      child: Transform.translate(
                        offset: Offset(0, -hop),
                        child: Transform.rotate(
                          angle: wobble + (breathe - .5) * .02,
                          alignment: Alignment.bottomCenter,
                          child: Transform.scale(
                            scaleX: sx,
                            scaleY: sy,
                            alignment: Alignment.bottomCenter,
                            child: Image.asset(
                              widget.mascot.path,
                              fit: BoxFit.contain,
                              alignment: Alignment.bottomCenter,
                              filterQuality: FilterQuality.medium,
                              excludeFromSemantics: true,
                              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ]),
                );
              },
            ),
          );
        },
      );
}

/// Halo de couleur très doux qui fond la mascotte dans le décor.
class _Glow extends StatelessWidget {
  final Color color;
  const _Glow(this.color);
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: .26), color.withValues(alpha: .10), color.withValues(alpha: 0)],
            stops: const [0, .6, 1],
          ),
        ),
      );
}

/// En-tête de section : titre à gauche, grande mascotte à droite sur un halo
/// de la couleur de la section. La mascotte prend sa place dans l'en-tête et
/// ne recouvre jamais le contenu qui suit.
class MascotHeader extends StatelessWidget {
  final Mascot mascot;
  final String title;
  final String? subtitle;
  final Widget? action;
  const MascotHeader({super.key, required this.mascot, required this.title, this.subtitle, this.action});

  List<String> _lines() {
    final words = title.split(' ');
    if (words.length <= 2) return words;
    final mid = (words.length / 2).ceil();
    return [words.sublist(0, mid).join(' '), words.sublist(mid).join(' ')];
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth.isFinite ? c.maxWidth : 360.0;
            final mw = (w * .46).clamp(130.0, 270.0);
            final mh = mw / mascot.ratio;
            final glow = mh * 1.3;
            return Stack(clipBehavior: Clip.none, children: [
              Positioned(
                right: mw / 2 - glow / 2,
                bottom: mh / 2 - glow / 2,
                width: glow,
                height: glow,
                child: IgnorePointer(child: _Glow(mascot.accent)),
              ),
              Container(
                constraints: BoxConstraints(minHeight: mh),
                alignment: Alignment.centerLeft,
                padding: EdgeInsets.only(right: mw * .88),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (final l in _lines()) Text(l, style: const TextStyle(fontSize: 38, height: 1.05, fontWeight: FontWeight.w800, color: C.ink, letterSpacing: -1)),
                    ]),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 8),
                    Text(subtitle!, style: const TextStyle(fontSize: 15.5, color: C.muted, height: 1.4)),
                  ],
                  if (action != null) ...[const SizedBox(height: 12), action!],
                ]),
              ),
              Positioned(right: 0, bottom: 0, width: mw, height: mh, child: MascotImage(mascot)),
            ]);
          },
        ),
      );
}
