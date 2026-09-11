import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Lochzangen-Konfetti (docs/27 §4).
///
/// The little discs a conductor's ticket punch leaves behind, falling once when an Antrag goes
/// out. Party confetti in twelve colours would be the first thing in this app to look like every
/// other app; this is made of the right material — paper white, ink, and the one red.
///
/// Once, on sending. Never on an arrival and never on a delay: nothing here is pleased that a
/// train was late (docs/12), and the Antrag is the one moment that is the passenger's own doing.
/// No sound.
class Konfetti extends StatefulWidget {
  const Konfetti({super.key, this.count = 44, this.duration = const Duration(milliseconds: 1500), this.onDone});
  final int count;
  final Duration duration;
  final VoidCallback? onDone;

  @override
  State<Konfetti> createState() => _KonfettiState();
}

class _KonfettiState extends State<Konfetti> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone?.call();
    })
    ..forward();

  late final List<_Disc> _discs = _make(widget.count);

  static List<_Disc> _make(int n) {
    // Seeded: the same celebration every time is easier to look at in a screenshot tour than a
    // different one on every run.
    final r = math.Random(7);
    return List.generate(n, (i) {
      return _Disc(
        x: r.nextDouble(),
        size: 5 + r.nextDouble() * 5,
        delay: r.nextDouble() * 0.35,
        fall: 0.75 + r.nextDouble() * 0.25,
        drift: (r.nextDouble() - 0.5) * 0.22,
        spin: (r.nextDouble() - 0.5) * 5,
        // Mostly paper and ink; the red is the accent it is everywhere else in this app.
        color: switch (i % 7) {
          0 => VColors.red,
          1 || 2 => VColors.ink,
          _ => VColors.paper,
        },
      );
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(painter: _KonfettiPainter(_discs, _c.value), size: Size.infinite),
      ),
    );
  }
}

class _Disc {
  const _Disc({
    required this.x,
    required this.size,
    required this.delay,
    required this.fall,
    required this.drift,
    required this.spin,
    required this.color,
  });
  final double x, size, delay, fall, drift, spin;
  final Color color;
}

class _KonfettiPainter extends CustomPainter {
  _KonfettiPainter(this.discs, this.t);
  final List<_Disc> discs;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in discs) {
      final local = ((t - d.delay) / d.fall).clamp(0.0, 1.0);
      if (local <= 0) continue;
      // Ease in: they are punched out, not thrown.
      final y = size.height * (local * local * 0.9 + local * 0.1) - d.size;
      final x = size.width * (d.x + d.drift * local);
      // Fading only at the very end, so the last frame is not a cliff.
      final fade = local > 0.85 ? 1 - (local - 0.85) / 0.15 : 1.0;
      final paint = Paint()..color = d.color.withValues(alpha: fade);
      canvas.save();
      canvas.translate(x, y);
      // A disc seen edge-on as it turns: an ellipse that narrows and widens.
      final squash = math.cos(local * d.spin * math.pi).abs().clamp(0.15, 1.0);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: d.size, height: d.size * squash),
        paint,
      );
      if (d.color == VColors.paper) {
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: d.size, height: d.size * squash),
          Paint()
            ..color = VColors.rule.withValues(alpha: fade)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _KonfettiPainter old) => old.t != t;
}
