import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// How many walkthroughs are open. [DemoBand] shows while this is above zero.
///
/// A count, not a flag: the walkthrough is one route among several (the Antrag, „Wie geht es
/// weiter", the railway's answers, the PDF), and the band must stand over all of them for as long
/// as the walkthrough that opened them is on the stack.
final ValueNotifier<int> demoWalkthroughs = ValueNotifier<int>(0);

/// The band across the top of the whole app while a walkthrough runs (#72): „VORFÜHRUNG ·
/// Beispieldaten · Nichts wird gesendet". People try the Antrag to see what it would do, and they
/// have to know at every step, and on every sheet, that nothing in it is theirs and nothing leaves.
///
/// It sits above the Navigator, so every route and every sheet of the walkthrough is under it. The
/// app below gets the band's height as its top inset, so screens that respect the safe area start
/// under the band instead of behind it.
class DemoBand extends StatelessWidget {
  const DemoBand({super.key, required this.child});
  final Widget child;

  static const double height = 30;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: demoWalkthroughs,
      child: child,
      builder: (context, open, child) {
        if (open <= 0) return child!;
        final media = MediaQuery.of(context);
        return Stack(
          children: [
            MediaQuery(
              data: media.copyWith(padding: media.padding.copyWith(top: media.padding.top + height)),
              child: child!,
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: _Band(top: media.padding.top),
            ),
          ],
        );
      },
    );
  }
}

class _Band extends StatelessWidget {
  const _Band({required this.top});
  final double top;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('demo-band'),
      color: VColors.surfaceDark,
      child: CustomPaint(
        painter: const _Hatch(),
        child: Padding(
          padding: EdgeInsets.only(top: top),
          child: SizedBox(
            height: DemoBand.height,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: VSpace.s, vertical: 2),
                color: VColors.surfaceDark,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_circle_outline, size: 16, color: VColors.inkOnDark),
                    const SizedBox(width: VSpace.xs),
                    Flexible(
                      child: Text(
                        'VORFÜHRUNG · Beispieldaten · Nichts wird gesendet',
                        style: VText.eyebrow.copyWith(color: VColors.inkOnDark),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Diagonal stripes, like a barrier tape: a band that reads as „not the real thing" before a word
/// of it is read.
class _Hatch extends CustomPainter {
  const _Hatch();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = VColors.surfaceDarkAlt
      ..strokeWidth = 6;
    for (var x = -size.height; x < size.width + size.height; x += 16) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _Hatch oldDelegate) => false;
}
