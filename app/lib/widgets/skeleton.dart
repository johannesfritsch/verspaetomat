import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'surfaces.dart';

/// What a page looks like before its data arrives.
///
/// It used to be the words „Lädt …" in the top-left corner, on a screen with no header, no cards
/// and no shape — so every tab opened as a blank page with a caption and then jumped into its real
/// layout (#17). A skeleton is that layout already, with the facts left out: the header is the real
/// header, the cards are real cards, and where a figure or a line of text will stand there is a
/// soft bar of the right size. The page does not move when the data lands; it fills in.
///
/// The bars shimmer: one slow band of light passing over them, the same on every screen, so waiting
/// reads as something happening rather than as something stuck. It stands still when the phone asks
/// for reduced motion and under `NO_ANIM=1`, which the screenshot tour sets.

/// A soft light band sweeping over the [VSkeletonBar]s below it.
///
/// Wrap a whole placeholder once: every bar inside picks up the same band, so they shimmer together
/// instead of each on its own clock.
class VShimmer extends StatefulWidget {
  const VShimmer({super.key, required this.child, this.onDark = false});
  final Widget child;

  /// On a dark or red board: bars are a veil of white rather than a grey.
  final bool onDark;

  @override
  State<VShimmer> createState() => _VShimmerState();
}

class _VShimmerState extends State<VShimmer> with SingleTickerProviderStateMixin {
  static const _still = String.fromEnvironment('NO_ANIM') == '1';
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final calm = _still || MediaQuery.disableAnimationsOf(context);
    if (calm) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.onDark ? Colors.white.withValues(alpha: 0.10) : VColors.hairlineStrong;
    final light = widget.onDark ? Colors.white.withValues(alpha: 0.22) : VColors.hairline;
    // One node for a screen reader: the page is loading. The bars themselves say nothing.
    return Semantics(
      label: 'Lädt',
      liveRegion: true,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _c,
          child: widget.child,
          builder: (context, child) {
            // The band travels from well left of the placeholder to well right of it, so it enters
            // and leaves rather than snapping back into view.
            final t = _c.value * 2.2 - 0.6;
            return ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (rect) => LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [base, light, base],
                stops: [(t - 0.25).clamp(0.0, 1.0), t.clamp(0.0, 1.0), (t + 0.25).clamp(0.0, 1.0)],
                transform: const GradientRotation(0.18),
              ).createShader(rect),
              child: child,
            );
          },
        ),
      ),
    );
  }
}

/// One bar where a line of text or a figure will stand. Its colour comes from the [VShimmer] above.
class VSkeletonBar extends StatelessWidget {
  const VSkeletonBar({super.key, this.width, this.widthFactor, this.height = 12, this.radius = 6, this.circle = false});

  /// A fixed width in points, or …
  final double? width;

  /// … a share of the available width.
  final double? widthFactor;
  final double height;
  final double radius;

  /// A round badge rather than a bar ([height] is the diameter).
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: circle ? height : width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: circle ? null : BorderRadius.circular(radius),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
      ),
    );
    if (widthFactor == null || circle) return box;
    return FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: widthFactor, child: box);
  }
}

/// A content card as it will be: a badge on the left, a title and a line under it, and
/// optionally a figure on the right.
class VSkeletonCard extends StatelessWidget {
  const VSkeletonCard({super.key, this.leading = true, this.trailing = false, this.lines = 2, this.button = false});
  final bool leading;
  final bool trailing;
  final int lines;

  /// A primary button under the text, as on the check-in card.
  final bool button;

  @override
  Widget build(BuildContext context) {
    return VCard(
      child: VShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leading) ...[const VSkeletonBar(height: 40, circle: true), const SizedBox(width: VSpace.md)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const VSkeletonBar(widthFactor: 0.34, height: 10),
                      for (var i = 0; i < lines; i++) ...[
                        const SizedBox(height: 10),
                        VSkeletonBar(widthFactor: i == 0 ? 0.8 : 0.55, height: i == 0 ? 18 : 12),
                      ],
                    ],
                  ),
                ),
                if (trailing) ...[const SizedBox(width: VSpace.md), const VSkeletonBar(width: 56, height: 18)],
              ],
            ),
            if (button) ...[const SizedBox(height: VSpace.m), const VSkeletonBar(height: 48, radius: VRadius.button)],
          ],
        ),
      ),
    );
  }
}

/// A list inside one card: [rows] rows with a badge, a line and a short line, hairlines between.
class VSkeletonList extends StatelessWidget {
  const VSkeletonList({super.key, this.rows = 3, this.trailing = true});
  final int rows;
  final bool trailing;

  @override
  Widget build(BuildContext context) {
    return VCard(
      padding: const EdgeInsets.symmetric(horizontal: VSpace.card, vertical: VSpace.xs),
      child: VShimmer(
        child: Column(
          children: [
            for (var i = 0; i < rows; i++) ...[
              if (i > 0) Container(height: VControl.hairline, color: Colors.black),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: VSpace.md),
                child: Row(
                  children: [
                    const VSkeletonBar(height: 32, circle: true),
                    const SizedBox(width: VSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          VSkeletonBar(widthFactor: i.isEven ? 0.7 : 0.55, height: 14),
                          const SizedBox(height: 8),
                          VSkeletonBar(widthFactor: i.isEven ? 0.4 : 0.5, height: 10),
                        ],
                      ),
                    ),
                    if (trailing) ...[const SizedBox(width: VSpace.md), const VSkeletonBar(width: 44, height: 14)],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A hero board before its number: the board itself, in its own look, with the label, the big
/// figure and the caption as veils of light.
class VSkeletonBoard extends StatelessWidget {
  const VSkeletonBoard({super.key, this.look = VBoardLook.dark});
  final VBoardLook look;

  @override
  Widget build(BuildContext context) {
    return VBoard(
      look: look,
      child: const VShimmer(
        onDark: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VSkeletonBar(widthFactor: 0.45, height: 10),
            SizedBox(height: VSpace.md),
            VSkeletonBar(widthFactor: 0.6, height: 44, radius: 8),
            SizedBox(height: VSpace.md),
            VSkeletonBar(widthFactor: 0.35, height: 10),
          ],
        ),
      ),
    );
  }
}

/// The stops of a train, before the train is in the feed: dots on a line, a name and a time each.
class VSkeletonStops extends StatelessWidget {
  const VSkeletonStops({super.key, this.stops = 4});
  final int stops;

  @override
  Widget build(BuildContext context) {
    return VShimmer(
      child: Column(
        children: [
          for (var i = 0; i < stops; i++)
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 44,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (i < stops - 1) Positioned(top: 22, bottom: 0, child: Container(width: 2, color: Colors.black)),
                        if (i > 0) Positioned(top: 0, height: 22, child: Container(width: 2, color: Colors.black)),
                        const VSkeletonBar(height: 12, circle: true),
                      ],
                    ),
                  ),
                  const SizedBox(width: VSpace.md),
                  Expanded(child: VSkeletonBar(widthFactor: i.isEven ? 0.55 : 0.4, height: 13)),
                  const VSkeletonBar(width: 40, height: 13),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A page of the form before the PDF is drawn: a sheet of paper with lines where the text goes.
class VSkeletonPaper extends StatelessWidget {
  const VSkeletonPaper({super.key});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1 / 1.414,
      child: Container(
        padding: const EdgeInsets.all(VSpace.l),
        decoration: BoxDecoration(color: VColors.paperElevated, borderRadius: BorderRadius.circular(VRadius.sm), boxShadow: VShadow.card),
        // Clipped rather than counted: the sheet is as tall as the space it is given, and the lines
        // simply run out at its edge, as they would on a page too long for the preview.
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxHeight: double.infinity,
            child: VShimmer(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const VSkeletonBar(widthFactor: 0.6, height: 16),
                  const SizedBox(height: VSpace.l),
                  for (var i = 0; i < 24; i++) ...[
                    VSkeletonBar(widthFactor: [0.9, 0.75, 0.85, 0.5][i % 4], height: 8),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
