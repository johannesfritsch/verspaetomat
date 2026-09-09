import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

// ---------------------------------------------------------------------------
// Page scaffolding
// ---------------------------------------------------------------------------

/// A page with the standard paper background, page padding and an optional
/// simple header row (back button + title). Use [scroll] for long content.
class VScreen extends StatelessWidget {
  const VScreen({
    super.key,
    required this.child,
    this.title,
    this.eyebrow,
    this.trailing,
    this.showBack = true,
    this.scroll = true,
    this.bottom,
    this.padding = const EdgeInsets.fromLTRB(VSpace.page, VSpace.m, VSpace.page, VSpace.l),
  });

  final Widget child;
  final String? title;
  final String? eyebrow;
  final Widget? trailing;
  final bool showBack;
  final bool scroll;
  final Widget? bottom;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final header = (title != null || eyebrow != null || (showBack && canPop))
        ? Padding(
            padding: const EdgeInsets.fromLTRB(VSpace.m, VSpace.s, VSpace.m, 0),
            child: Row(
              children: [
                if (showBack && canPop)
                  VIconButton(icon: Icons.arrow_back, onTap: () => Navigator.of(context).maybePop())
                else
                  const SizedBox(width: VSpace.s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (eyebrow != null) Text(eyebrow!, style: VText.eyebrow),
                      if (title != null) Text(title!, style: VText.title),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          )
        : null;

    final body = Padding(padding: padding, child: child);

    return Scaffold(
      backgroundColor: VColors.paper,
      body: SafeArea(
        bottom: bottom == null,
        child: Column(
          children: [
            if (header != null) header,
            Expanded(child: scroll ? SingleChildScrollView(child: body) : body),
            if (bottom != null)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(VSpace.page, VSpace.s, VSpace.page, VSpace.m),
                  child: bottom!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class VIconButton extends StatelessWidget {
  const VIconButton({super.key, required this.icon, required this.onTap, this.color = VColors.ink});
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Icon(icon, size: 22, color: color),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rules and spacing
// ---------------------------------------------------------------------------

/// A hairline. `VRule.red()` is the one thick red rule a screen may carry.
class VRule extends StatelessWidget {
  const VRule({super.key})
      : color = VColors.rule,
        thickness = 1;
  const VRule.red({super.key})
      : color = VColors.red,
        thickness = 2;
  const VRule.soft({super.key})
      : color = VColors.ruleSoft,
        thickness = 1;

  final Color color;
  final double thickness;

  @override
  Widget build(BuildContext context) => Container(height: thickness, color: color);
}

class VGap extends StatelessWidget {
  const VGap(this.size, {super.key});
  const VGap.xs({super.key}) : size = VSpace.xs;
  const VGap.s({super.key}) : size = VSpace.s;
  const VGap.m({super.key}) : size = VSpace.m;
  const VGap.l({super.key}) : size = VSpace.l;
  const VGap.xl({super.key}) : size = VSpace.xl;
  const VGap.xxl({super.key}) : size = VSpace.xxl;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(height: size, width: size);
}

// ---------------------------------------------------------------------------
// Buttons
// ---------------------------------------------------------------------------

class VPrimaryButton extends StatelessWidget {
  const VPrimaryButton({super.key, required this.label, this.onTap, this.icon, this.expanded = true});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final child = SizedBox(
      height: 56,
      child: Material(
        color: enabled ? VColors.ink : VColors.rule,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: VSpace.l),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: enabled ? VColors.paper : VColors.ink3),
                  const SizedBox(width: 10),
                ],
                Text(label, style: VText.button.copyWith(color: enabled ? VColors.paper : VColors.ink3)),
              ],
            ),
          ),
        ),
      ),
    );
    return expanded ? SizedBox(width: double.infinity, child: child) : child;
  }
}

class VGhostButton extends StatelessWidget {
  const VGhostButton({super.key, required this.label, this.onTap, this.icon, this.color = VColors.ink});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[Icon(icon, size: 20, color: color), const SizedBox(width: 10)],
            Text(label, style: VText.bodyStrong.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

/// An outlined secondary button for the rare two-button row.
class VOutlineButton extends StatelessWidget {
  const VOutlineButton({super.key, required this.label, this.onTap, this.icon});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: VColors.ink,
          side: const BorderSide(color: VColors.ink, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 10)],
            Text(label, style: VText.button),
          ],
        ),
      ),
    );
  }
}

/// A visibly "showcase only" control. Dashed outline, grey. Use it for
/// buttons that stand in for the real world (simulate arrival, etc.).
class VDemoControl extends StatelessWidget {
  const VDemoControl({super.key, required this.label, required this.onTap, this.icon = Icons.play_arrow_outlined});
  final String label;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(),
      child: SizedBox(
        height: 44,
        width: double.infinity,
        child: InkWell(
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: VColors.ink2),
              const SizedBox(width: 8),
              Text('Demo: $label', style: VText.caption),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = VColors.ink3
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const dash = 5.0, gap = 4.0;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4));
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, math.min(d + dash, metric.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Numbers, chips, rows
// ---------------------------------------------------------------------------

/// The delay figure: a red "+" and the minutes. `size` picks the scale.
class VDelay extends StatelessWidget {
  const VDelay(this.minutes, {super.key, this.size = VDelaySize.medium, this.cancelled = false});
  final int minutes;
  final VDelaySize size;
  final bool cancelled;

  @override
  Widget build(BuildContext context) {
    if (cancelled) {
      return Text('Ausfall', style: _style().copyWith(color: VColors.red));
    }
    if (minutes <= 0) {
      return Text('pünktlich', style: _style().copyWith(color: VColors.green, fontWeight: FontWeight.w600));
    }
    final s = _style();
    return RichText(
      text: TextSpan(
        style: s,
        children: [
          TextSpan(text: '+', style: s.copyWith(color: VColors.red)),
          TextSpan(text: '$minutes'),
        ],
      ),
    );
  }

  TextStyle _style() => switch (size) {
        VDelaySize.display => VText.display,
        VDelaySize.large => VText.number,
        VDelaySize.medium => VText.numberM,
        VDelaySize.small => VText.mono.copyWith(fontWeight: FontWeight.w700),
      };
}

enum VDelaySize { display, large, medium, small }

/// A small status chip. Ink outline by default; [tone] colours it.
class VChip extends StatelessWidget {
  const VChip(this.label, {super.key, this.tone = VTone.neutral});
  final String label;
  final VTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      VTone.neutral => (VColors.ruleSoft, VColors.ink2),
      VTone.ink => (VColors.ink, VColors.paper),
      VTone.red => (VColors.redSoft, VColors.red),
      VTone.green => (VColors.greenSoft, VColors.green),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(3)),
      child: Text(label, style: VText.tab.copyWith(color: fg)),
    );
  }
}

enum VTone { neutral, ink, red, green }

/// Label on the left, value on the right, on one baseline.
class VKeyValue extends StatelessWidget {
  const VKeyValue(this.label, this.value, {super.key, this.strong = false, this.valueStyle});
  final String label;
  final String value;
  final bool strong;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(child: Text(label, style: VText.bodyS.copyWith(color: VColors.ink2))),
          Text(value, style: valueStyle ?? (strong ? VText.bodySStrong : VText.bodyS).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}

/// Section heading: an eyebrow with a hairline under it.
class VSection extends StatelessWidget {
  const VSection(this.label, {super.key, this.trailing});
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label.toUpperCase(), style: VText.eyebrow)),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 8),
        const VRule(),
      ],
    );
  }
}

/// A tappable list row with optional leading/trailing, hairline below.
class VListRow extends StatelessWidget {
  const VListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.chevron = false,
  });
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 14)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: VText.bodyStrong),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: VText.caption),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 12), trailing!],
                if (chevron) ...[const SizedBox(width: 8), const Icon(Icons.chevron_right, size: 20, color: VColors.ink3)],
              ],
            ),
          ),
          const VRule(),
        ],
      ),
    );
  }
}

/// Red dots for "3 von 3". Filled = counted, outline = missing.
class VDots extends StatelessWidget {
  const VDots({super.key, required this.filled, required this.total});
  final int filled;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          Padding(
            padding: EdgeInsets.only(right: i == total - 1 ? 0 : 6),
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < filled ? VColors.red : Colors.transparent,
                border: Border.all(color: i < filled ? VColors.red : VColors.rule, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}

/// A thin progress bar: confirmed solid red, submitted as a lighter segment.
class VProgress extends StatelessWidget {
  const VProgress({super.key, required this.confirmed, this.submitted = 0});
  final double confirmed; // 0..1
  final double submitted; // 0..1, drawn behind confirmed

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 6,
        child: Stack(
          children: [
            Container(color: VColors.ruleSoft),
            FractionallySizedBox(widthFactor: (confirmed + submitted).clamp(0, 1), child: Container(color: VColors.redSoft)),
            FractionallySizedBox(widthFactor: confirmed.clamp(0, 1), child: Container(color: VColors.red)),
          ],
        ),
      ),
    );
  }
}

/// A big selectable card for the setup screens (ticket type, NGO).
class VChoiceCard extends StatelessWidget {
  const VChoiceCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.trailing,
  });
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.all(VSpace.m),
        decoration: BoxDecoration(
          color: selected ? VColors.paperElevated : Colors.transparent,
          border: Border.all(color: selected ? VColors.ink : VColors.rule, width: selected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: VText.title),
                  const SizedBox(height: 4),
                  Text(subtitle, style: VText.caption),
                ],
              ),
            ),
            const SizedBox(width: 12),
            trailing ??
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? VColors.red : Colors.transparent,
                    border: Border.all(color: selected ? VColors.red : VColors.rule, width: 1.5),
                  ),
                  child: selected ? const Icon(Icons.check, size: 14, color: VColors.paper) : null,
                ),
          ],
        ),
      ),
    );
  }
}

/// Bottom navigation in the paper style: a hairline on top, icons + labels.
class VBottomNav extends StatelessWidget {
  const VBottomNav({super.key, required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;

  static const items = [
    (Icons.train_outlined, Icons.train, 'Bahnsteig'),
    (Icons.receipt_long_outlined, Icons.receipt_long, 'Konto'),
    (Icons.groups_outlined, Icons.groups, 'Wir'),
    (Icons.person_outline, Icons.person, 'Ich'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: VColors.paper,
        border: Border(top: BorderSide(color: VColors.rule)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onTap(i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(i == index ? items[i].$2 : items[i].$1, size: 24, color: i == index ? VColors.ink : VColors.ink3),
                        const SizedBox(height: 4),
                        Text(items[i].$3, style: VText.tab.copyWith(color: i == index ? VColors.ink : VColors.ink3)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The station clock
// ---------------------------------------------------------------------------

/// The German station clock. The red second hand sweeps to twelve, waits,
/// and only then does the minute hand jump. [animated] runs that cycle
/// (compressed to ~12 s so it reads in a demo); otherwise it is still.
class VStationClock extends StatefulWidget {
  const VStationClock({super.key, this.size = 44, this.animated = false, this.time});
  final double size;
  final bool animated;

  /// Optional fixed time to show (hour, minute). Defaults to 10:08 which
  /// reads well and is the classic "clock face" pose.
  final TimeOfDay? time;

  @override
  State<VStationClock> createState() => _VStationClockState();
}

class _VStationClockState extends State<VStationClock> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 12));

  @override
  void initState() {
    super.initState();
    if (widget.animated) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant VStationClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animated && !_c.isAnimating) _c.repeat();
    if (!widget.animated && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.time ?? const TimeOfDay(hour: 10, minute: 8);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        // Sweep for 88% of the cycle, then hold at twelve.
        final v = _c.value;
        final sweep = (v / 0.88).clamp(0.0, 1.0);
        final minuteJump = v >= 0.985 ? 1 : 0;
        return CustomPaint(
          size: Size.square(widget.size),
          painter: _ClockPainter(
            hour: t.hour,
            minute: t.minute + minuteJump,
            secondFraction: widget.animated ? sweep : 0,
          ),
        );
      },
    );
  }
}

class _ClockPainter extends CustomPainter {
  _ClockPainter({required this.hour, required this.minute, required this.secondFraction});
  final int hour;
  final int minute;
  final double secondFraction;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final ring = Paint()
      ..color = VColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.09;
    canvas.drawCircle(c, r - ring.strokeWidth / 2, Paint()..color = VColors.paperElevated);
    canvas.drawCircle(c, r - ring.strokeWidth / 2, ring);

    final mark = Paint()..color = VColors.ink;
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final big = i % 3 == 0;
      final len = big ? r * 0.22 : r * 0.14;
      final w = big ? r * 0.09 : r * 0.06;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(a);
      canvas.drawRect(Rect.fromLTWH(-w / 2, -r + ring.strokeWidth * 1.4, w, len), mark);
      canvas.restore();
    }

    void hand(double angle, double length, double width, Color color) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(angle);
      canvas.drawRect(Rect.fromLTWH(-width / 2, -length, width, length + width * 1.2), Paint()..color = color);
      canvas.restore();
    }

    final hourAngle = ((hour % 12) + minute / 60) * math.pi / 6;
    final minuteAngle = minute * math.pi / 30;
    hand(hourAngle, r * 0.52, r * 0.12, VColors.ink);
    hand(minuteAngle, r * 0.76, r * 0.09, VColors.ink);

    // Red second hand with the disc at its tip.
    final sa = secondFraction * 2 * math.pi;
    hand(sa, r * 0.68, r * 0.045, VColors.red);
    final tip = c + Offset(math.sin(sa), -math.cos(sa)) * (r * 0.68);
    canvas.drawCircle(tip, r * 0.1, Paint()..color = VColors.red);
    canvas.drawCircle(c, r * 0.07, Paint()..color = VColors.red);
  }

  @override
  bool shouldRepaint(covariant _ClockPainter old) =>
      old.hour != hour || old.minute != minute || old.secondFraction != secondFraction;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// German number formatting without intl: 1208311 -> "1.208.311".
String fmtInt(int n) {
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final fromEnd = s.length - i;
    b.write(s[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) b.write('.');
  }
  return (n < 0 ? '-' : '') + b.toString();
}

/// 4.5 -> "4,50 €"
String fmtEuro(double v) {
  final cents = (v * 100).round();
  final whole = cents ~/ 100;
  final frac = (cents % 100).toString().padLeft(2, '0');
  return '${fmtInt(whole)},$frac €';
}

/// 48320.0 -> "48.320 €" (community and campaign figures)
String fmtEuroWhole(double v) => '${fmtInt(v.round())} €';

/// TimeOfDay -> "08:52"
String fmtTime(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

TimeOfDay addMinutes(TimeOfDay t, int minutes) {
  final total = (t.hour * 60 + t.minute + minutes) % (24 * 60);
  return TimeOfDay(hour: total ~/ 60, minute: total % 60);
}

/// Show a standard bottom sheet in the paper style.
Future<T?> showVSheet<T>(BuildContext context, {required WidgetBuilder builder, bool expand = false}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => expand
        ? FractionallySizedBox(heightFactor: 0.92, child: builder(ctx))
        : Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom), child: builder(ctx)),
  );
}

/// The little grabber + optional title at the top of a sheet.
class VSheetHeader extends StatelessWidget {
  const VSheetHeader({super.key, this.title, this.subtitle, this.trailing});
  final String? title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(VSpace.page, 10, VSpace.page, VSpace.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: VColors.rule, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          if (title != null) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title!, style: VText.h2),
                      if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: VText.caption)],
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ],
        ],
      ),
    );
  }
}
