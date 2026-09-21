import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../widgets/kit.dart';

/// The shape every screen between Willkommen and the Bahnsteig shares (#43).
///
/// One illustration, one question, one paragraph or two, one red button and one quiet one. The
/// screens differ in their words and their picture and in nothing else, which is the point: the
/// old setup asked its two questions with two different kinds of control on one page — a button
/// for notifications, three cards for location — and read as a form rather than as being asked
/// something.
///
/// **The screen does not move until the system dialog is answered.** Every dialog used to land
/// one screen late: tapping „Weiter" on the permissions page opened the location dialog over it,
/// and the Always upgrade and the notification prompt both arrived on „Dein Ticket, dein Zweck".
/// So people answered a location question while reading about Bahnhofsmission Köln. Each screen
/// here awaits its own answer and only then goes on.
class SetupStep extends StatelessWidget {
  const SetupStep({
    super.key,
    this.step,
    this.total = 3,
    this.onBack,
    required this.asset,
    required this.title,
    this.centred = false,
    this.body = const [],
    required this.primary,
    required this.onPrimary,
    this.secondary,
    this.onSecondary,
    this.footnote,
    this.busy = false,
    this.imageHeight = 250,
  });

  /// Which numbered step this is, or null for the two that are not steps: „Fast geschafft" is a
  /// second state of the Standort question, and „Los geht's" is the end rather than a stage of it.
  final int? step;
  final int total;

  /// The arrow „Fast geschafft" carries in place of a counter.
  final VoidCallback? onBack;

  final String asset;
  final String title;
  final bool centred;
  final List<Widget> body;
  final String primary;
  final VoidCallback? onPrimary;
  final String? secondary;
  final VoidCallback? onSecondary;
  final String? footnote;
  final bool busy;

  /// Smaller where the screen's content is the point rather than its picture: the Verein list is
  /// as long as the table of Vereine, and the picture must not push it under the button.
  final double imageHeight;

  @override
  Widget build(BuildContext context) {
    return VScreen(
      showBack: false,
      scroll: true,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          VPrimaryButton(label: primary, busy: busy, onTap: onPrimary),
          if (secondary != null) ...[
            const VGap.s(),
            VTintButton(label: secondary!, tone: VTintTone.neutral, onTap: onSecondary),
          ],
          if (footnote != null) ...[
            const VGap.s(),
            Text(footnote!, style: VText.caption, textAlign: TextAlign.center),
          ],
        ],
      ),
      child: Column(
        crossAxisAlignment: centred ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
        children: [
          if (step != null) ...[
            const VGap.s(),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Schritt $step von $total', style: VText.bodyS),
            ),
            const VGap.s(),
            _Progress(step: step!, total: total),
          ],
          if (onBack != null)
            Align(
              alignment: Alignment.centerLeft,
              child: VIconButton(icon: Icons.arrow_back, onTap: onBack!),
            ),
          const VGap.m(),
          // A fixed height and `contain`, not a cropped landscape card. The drawings are portrait
          // with a soft blob of their own and transparent margins, so the page shows through and
          // the artwork floats the way it was drawn; cropping them to a wide card would cut the
          // speech bubbles off the top of the first one.
          // 250 pt, and the number is arithmetic rather than taste. A 393 pt phone has about
          // 609 pt above the buttons; the longest of these screens — a two-line title and three
          // paragraphs — needs about 360 of it. Drawn full width the artwork would be 410 tall on
          // its own and push the last line under the button, which is the very fault the old
          // screen had: the one sentence saying nothing is gated was the one you had to scroll
          // for. Same height on all of them, because the picture is the constant here.
          SizedBox(
            height: imageHeight,
            child: Image.asset(
              asset,
              fit: BoxFit.contain,
              // A missing picture leaves the question standing rather than the screen broken.
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          const VGap.l(),
          Text(
            title,
            style: VText.h2,
            textAlign: centred ? TextAlign.center : TextAlign.start,
          ),
          const VGap.m(),
          ...body,
          const VGap.m(),
        ],
      ),
    );
  }
}

/// How far along the four questions this is. Drawn rather than a `LinearProgressIndicator`, which
/// brings Material's own colours and height with it.
class _Progress extends StatelessWidget {
  const _Progress({required this.step, required this.total});
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Container(
        height: 6,
        color: VColors.hairline,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: step / total,
          child: Container(color: VColors.red),
        ),
      ),
    );
  }
}

/// A paragraph of the explanation under a question.
class SetupText extends StatelessWidget {
  const SetupText(this.text, {super.key, this.centred = false});
  final String text;
  final bool centred;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: VSpace.m),
        child: Text(
          text,
          style: VText.bodyL.copyWith(color: VColors.ink2),
          textAlign: centred ? TextAlign.center : TextAlign.start,
        ),
      );
}
