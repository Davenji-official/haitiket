import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';

/// Effet « rebond » au toucher + vibration légère.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  const Pressable({super.key, required this.child, this.onTap, this.scale = .94});
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool down = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null ? null : (_) => setState(() => down = true),
        onTapUp: (_) => setState(() => down = false),
        onTapCancel: () => setState(() => down = false),
        onTap: widget.onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onTap!();
              },
        child: AnimatedScale(scale: down ? widget.scale : 1, duration: const Duration(milliseconds: 140), curve: Curves.easeOutBack, child: widget.child),
      );
}

/// Apparition en fondu + glissement, avec délai selon la position.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int index;
  const FadeSlideIn({super.key, required this.child, this.index = 0});
  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  late final Animation<double> curved = CurvedAnimation(parent: ctrl, curve: Curves.easeOutCubic);
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 70 * widget.index.clamp(0, 10)), () {
      if (mounted) ctrl.forward();
    });
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: curved,
        child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, .12), end: Offset.zero).animate(curved), child: widget.child),
      );
}

/// Flottement doux et continu.
class Floating extends StatefulWidget {
  final Widget child;
  final double amplitude;
  const Floating({super.key, required this.child, this.amplitude = 10});
  @override
  State<Floating> createState() => _FloatingState();
}

class _FloatingState extends State<Floating> with SingleTickerProviderStateMixin {
  late final AnimationController ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat(reverse: true);
  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: ctrl,
        builder: (_, ch) => Transform.translate(offset: Offset(0, (Curves.easeInOut.transform(ctrl.value) - .5) * 2 * widget.amplitude), child: Transform.rotate(angle: (ctrl.value - .5) * .12, child: ch)),
        child: widget.child,
      );
}

/// Bouton principal avec reflet animé.
class PrimaryButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  const PrimaryButton({super.key, required this.label, this.icon, this.onPressed});
  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> with SingleTickerProviderStateMixin {
  late final AnimationController ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: widget.onPressed == null ? .45 : 1,
      child: Pressable(
        onTap: widget.onPressed,
        child: AnimatedBuilder(
          animation: ctrl,
          builder: (_, __) {
            final p = ctrl.value;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: const [C.ink, Color(0xFF2C6A5C), C.ink],
                  stops: [(p - .25).clamp(0.0, 1.0), p, (p + .25).clamp(0.0, 1.0)],
                ),
                boxShadow: const [BoxShadow(color: Color(0x3317332E), blurRadius: 14, offset: Offset(0, 6))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                if (widget.icon != null) ...[Icon(widget.icon, color: Colors.white, size: 20), const SizedBox(width: 8)],
                Text(widget.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
              ]),
            );
          },
        ),
      ),
    );
  }
}

class NavItem {
  final IconData icon, activeIcon;
  final String label;
  const NavItem(this.icon, this.activeIcon, this.label);
}

/// Barre de navigation à icônes, avec pastille animée.
class BottomBar extends StatelessWidget {
  final int index;
  final List<NavItem> items;
  final ValueChanged<int> onTap;
  const BottomBar({super.key, required this.index, required this.items, required this.onTap});
  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: C.line)), boxShadow: [BoxShadow(color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, -3))]),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
            child: Row(children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: Pressable(
                    onTap: () => onTap(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(color: i == index ? C.mint : Colors.transparent, borderRadius: BorderRadius.circular(20)),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        AnimatedScale(scale: i == index ? 1.18 : 1, duration: const Duration(milliseconds: 300), curve: Curves.easeOutBack, child: Icon(i == index ? items[i].activeIcon : items[i].icon, color: i == index ? C.ink : C.muted, size: 26)),
                        const SizedBox(height: 2),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 250),
                          style: TextStyle(fontSize: 11, fontWeight: i == index ? FontWeight.w800 : FontWeight.w600, color: i == index ? C.ink : C.muted),
                          child: Text(items[i].label, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      );
}
