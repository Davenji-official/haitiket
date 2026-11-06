import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

class ChartSeries {
  final String name;
  final Color color;
  final List<double> values;
  const ChartSeries(this.name, this.color, this.values);
}

String _defaultFmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

/// Graphique interactif et vivant : toucher/survoler pour lire une valeur, animation à chaque mise à jour des données,
/// point pulsant sur la dernière valeur.
class LiveChart extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<ChartSeries> series;
  final List<String> labels;
  final bool bars;
  final String Function(double)? fmt;
  final double height;
  const LiveChart({super.key, required this.title, required this.series, required this.labels, this.subtitle = '', this.bars = false, this.fmt, this.height = 170});
  @override
  State<LiveChart> createState() => _LiveChartState();
}

class _LiveChartState extends State<LiveChart> with TickerProviderStateMixin {
  late final AnimationController pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  late final AnimationController draw = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  List<List<double>> from = [];
  List<List<double>> to = [];
  int? hover;

  @override
  void initState() {
    super.initState();
    to = [for (final s in widget.series) List<double>.from(s.values)];
    from = [for (final s in to) List<double>.filled(s.length, 0)];
    draw.forward();
  }

  List<List<double>> current() {
    final t = Curves.easeOutCubic.transform(draw.value);
    return [
      for (var i = 0; i < to.length; i++)
        [for (var j = 0; j < to[i].length; j++) (i < from.length && j < from[i].length ? from[i][j] : 0) + (to[i][j] - (i < from.length && j < from[i].length ? from[i][j] : 0)) * t]
    ];
  }

  bool changed(List<ChartSeries> a) {
    if (a.length != to.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i].values.length != to[i].length) return true;
      for (var j = 0; j < a[i].values.length; j++) {
        if (a[i].values[j] != to[i][j]) return true;
      }
    }
    return false;
  }

  @override
  void didUpdateWidget(covariant LiveChart old) {
    super.didUpdateWidget(old);
    if (changed(widget.series)) {
      from = current();
      to = [for (final s in widget.series) List<double>.from(s.values)];
      draw.forward(from: 0);
    }
  }

  @override
  void dispose() {
    pulse.dispose();
    draw.dispose();
    super.dispose();
  }

  void setHover(double dx, double width) {
    final count = to.isEmpty ? 0 : to.first.length;
    if (count == 0) return;
    const padL = 6.0;
    final w = width - padL;
    int idx;
    if (widget.bars) {
      idx = ((dx - padL) / (w / count)).floor();
    } else {
      idx = count == 1 ? 0 : ((dx - padL) / w * (count - 1)).round();
    }
    idx = idx.clamp(0, count - 1);
    if (idx != hover) setState(() => hover = idx);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = widget.fmt ?? _defaultFmt;
    final total = widget.series.isEmpty ? 0.0 : widget.series.first.values.fold<double>(0, (a, b) => a + b);
    return Card(
      color: C.card,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(widget.title, style: TextStyle(fontWeight: FontWeight.w900, color: C.ink, fontSize: 15))),
            Text(widget.subtitle.isEmpty ? fmt(total) : widget.subtitle, style: TextStyle(fontWeight: FontWeight.w800, color: C.green)),
          ]),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (_, c) {
            final width = c.maxWidth;
            return MouseRegion(
              onHover: (e) => setHover(e.localPosition.dx, width),
              onExit: (_) => setState(() => hover = null),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => setHover(d.localPosition.dx, width),
                onPanStart: (d) => setHover(d.localPosition.dx, width),
                onPanUpdate: (d) => setHover(d.localPosition.dx, width),
                onPanEnd: (_) => setState(() => hover = null),
                onTapUp: (_) => Future<void>.delayed(const Duration(seconds: 2), () {
                  if (mounted) setState(() => hover = null);
                }),
                child: SizedBox(
                  height: widget.height,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _ChartPainter(
                      repaint: Listenable.merge([pulse, draw]),
                      series: widget.series,
                      data: current,
                      bars: widget.bars,
                      labels: widget.labels,
                      hover: hover,
                      fmt: fmt,
                      pulse: () => pulse.value,
                      grid: C.line,
                      ink: C.ink,
                      muted: C.muted,
                      tipBg: C.deep,
                    ),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 6),
          Row(children: [
            Text(widget.labels.isEmpty ? '' : widget.labels.first, style: TextStyle(fontSize: 11, color: C.muted)),
            const Spacer(),
            Text(widget.labels.isEmpty ? '' : widget.labels.last, style: TextStyle(fontSize: 11, color: C.muted)),
          ]),
          if (widget.series.length > 1)
            Wrap(spacing: 12, children: [
              for (final s in widget.series)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text(s.name, style: TextStyle(fontSize: 11, color: C.muted)),
                ]),
            ]),
          Text('Touchez ou glissez le doigt sur le graphique pour lire les valeurs.', style: TextStyle(fontSize: 10, color: C.muted)),
        ]),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<ChartSeries> series;
  final List<List<double>> Function() data;
  final bool bars;
  final List<String> labels;
  final int? hover;
  final String Function(double) fmt;
  final double Function() pulse;
  final Color grid, ink, muted, tipBg;

  _ChartPainter({
    required Listenable repaint,
    required this.series,
    required this.data,
    required this.bars,
    required this.labels,
    required this.hover,
    required this.fmt,
    required this.pulse,
    required this.grid,
    required this.ink,
    required this.muted,
    required this.tipBg,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 6.0, padB = 4.0, padT = 6.0;
    final w = size.width - padL, h = size.height - padB - padT;
    final vals = data();
    var maxV = 0.0;
    for (final s in vals) {
      for (final v in s) {
        if (v > maxV) maxV = v;
      }
    }
    for (final s in series) {
      for (final v in s.values) {
        if (v > maxV) maxV = v;
      }
    }
    if (maxV <= 0) maxV = 1;
    final gridPaint = Paint()..color = grid..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = padT + h * i / 4;
      canvas.drawLine(Offset(padL, y), Offset(size.width, y), gridPaint);
    }
    _text(canvas, fmt(maxV), Offset(padL + 2, padT - 2), muted, 9);
    final count = vals.isEmpty ? 0 : vals.first.length;
    if (count == 0) return;

    double xAt(int i) => bars ? padL + (w / count) * (i + .5) : padL + (count == 1 ? w / 2 : w * i / (count - 1));
    double yAt(double v) => padT + h - h * (v / maxV);

    for (var si = 0; si < series.length && si < vals.length; si++) {
      final s = series[si];
      final v = vals[si];
      if (bars) {
        final slot = w / count;
        final bw = (slot * .7) / series.length;
        for (var i = 0; i < count; i++) {
          final bh = h * v[i] / maxV;
          final x = padL + slot * i + slot * .15 + bw * si;
          final active = hover == i;
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(x, padT + h - bh, bw, bh), const Radius.circular(2)),
            Paint()..color = active ? s.color : s.color.withValues(alpha: hover == null ? 1 : .55),
          );
        }
      } else {
        final path = Path();
        final fill = Path();
        for (var i = 0; i < count; i++) {
          final x = xAt(i), y = yAt(v[i]);
          if (i == 0) {
            path.moveTo(x, y);
            fill.moveTo(x, padT + h);
            fill.lineTo(x, y);
          } else {
            path.lineTo(x, y);
            fill.lineTo(x, y);
          }
          if (i == count - 1) {
            fill.lineTo(x, padT + h);
            fill.close();
          }
        }
        canvas.drawPath(fill, Paint()..color = s.color.withValues(alpha: .12));
        canvas.drawPath(path, Paint()..color = s.color..style = PaintingStyle.stroke..strokeWidth = 2.4..strokeJoin = StrokeJoin.round);
        // point pulsant « en direct » sur la dernière valeur
        final lx = xAt(count - 1), ly = yAt(v[count - 1]);
        final p = pulse();
        canvas.drawCircle(Offset(lx, ly), 4 + 7 * p, Paint()..color = s.color.withValues(alpha: .28 * (1 - p)));
        canvas.drawCircle(Offset(lx, ly), 3.6, Paint()..color = s.color);
      }
    }

    final hv = hover;
    if (hv != null && hv >= 0 && hv < count) {
      final x = xAt(hv);
      if (!bars) {
        canvas.drawLine(Offset(x, padT), Offset(x, padT + h), Paint()..color = muted.withValues(alpha: .6)..strokeWidth = 1);
        for (var si = 0; si < series.length && si < vals.length; si++) {
          canvas.drawCircle(Offset(x, yAt(vals[si][hv])), 4.5, Paint()..color = series[si].color);
          canvas.drawCircle(Offset(x, yAt(vals[si][hv])), 2, Paint()..color = Colors.white);
        }
      }
      // infobulle
      final lines = <String>[hv < labels.length ? labels[hv] : '#${hv + 1}', for (var si = 0; si < series.length && si < vals.length; si++) '${series[si].name}: ${fmt(vals[si][hv])}'];
      var tw = 0.0;
      final painters = <TextPainter>[];
      for (var i = 0; i < lines.length; i++) {
        final tp = TextPainter(text: TextSpan(text: lines[i], style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w600)), textDirection: TextDirection.ltr)..layout();
        painters.add(tp);
        tw = math.max(tw, tp.width);
      }
      final bw = tw + 16, bh = painters.fold<double>(0, (a, b) => a + b.height) + 12;
      var bx = x + 10;
      if (bx + bw > size.width) bx = x - 10 - bw;
      if (bx < 0) bx = 0;
      final rect = RRect.fromRectAndRadius(Rect.fromLTWH(bx, padT, bw, bh), const Radius.circular(8));
      canvas.drawRRect(rect, Paint()..color = tipBg.withValues(alpha: .94));
      var ty = padT + 6;
      for (final tp in painters) {
        tp.paint(canvas, Offset(bx + 8, ty));
        ty += tp.height;
      }
    }
  }

  void _text(Canvas canvas, String t, Offset o, Color c, double size) {
    final tp = TextPainter(text: TextSpan(text: t, style: TextStyle(color: c, fontSize: size)), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, o);
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => true;
}
