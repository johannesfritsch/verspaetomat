import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'kit.dart';

// ---------------------------------------------------------------------------
// Where you are in something with five parts
// ---------------------------------------------------------------------------
//
// Two objects, and the difference between them is whether you can leave:
//
//   VStepIndicator  the thin ribbon over a step you are already inside. It reports; it is not a
//                   control. Five words and five bars, and nothing to press.
//   VStepList       the numbered stack the Antrag opens on, before the first step. Each step is
//                   a card you can read and — if the caller says so — press.

/// The ribbon over a step of the Antrag: the five names, and a bar under each.
///
/// Three states, and the colours say something specific. A step you have **done** goes red,
/// because the red run along the bottom is the distance already covered and the words belong to
/// it. The step you are **on** is ink and bold — the one thing on the ribbon you are actually
/// looking at, and the only one that must not compete with the title above it. The steps
/// **ahead** are grey and say nothing yet.
///
/// The bar under the current step is red too: the run covers done *and* here, so it reads as
/// progress rather than as a cursor.
///
/// There are no separators between the names. An earlier version set a „·" between them, which
/// at caption size on a five-item row reads as a sixth thing rather than as punctuation; the
/// gap does that work.
class VStepIndicator extends StatelessWidget {
  const VStepIndicator({super.key, required this.steps, required this.current});

  final List<String> steps;
  final int current;

  /// Measured between 19 and 22 pt across the mockups. It is one gap, so it takes one token.
  static const _labelGap = VSpace.l;

  /// The bar is drawn at 3–4 pt. [VControl.progress] is twice that: a progress bar is a figure
  /// you read, this is a rule you notice.
  static const _barHeight = 3.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: _labelGap,
          runSpacing: VSpace.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < steps.length; i++)
              Text(
                '${i + 1} ${steps[i]}',
                style: VText.caption.copyWith(
                  color: switch (i.compareTo(current)) {
                    < 0 => VColors.red,
                    0 => VColors.ink,
                    _ => VColors.ink3,
                  },
                  fontWeight: i == current ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 0; i < steps.length; i++)
              Expanded(
                child: Container(
                  height: _barHeight,
                  margin: EdgeInsets.only(right: i < steps.length - 1 ? VSpace.xs : 0),
                  decoration: BoxDecoration(
                    color: i <= current ? VColors.red : VColors.hairline,
                    borderRadius: BorderRadius.circular(VRadius.full),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// One step in a [VStepList].
class VStep {
  const VStep({required this.title, required this.text, required this.icon, this.onTap});

  final String title;
  final String text;
  final IconData icon;
  final VoidCallback? onTap;
}

/// The numbered stack: what is about to happen, before any of it has.
///
/// A left rail of numbered discs joined by a dashed line, and a card beside each. The disc for
/// the step you are about to take is filled and its card is tinted; the rest are quiet. The line
/// is dashed rather than solid because none of it has happened yet — the solid red spine belongs
/// to [VStop], where the train really did call at those stations.
class VStepList extends StatelessWidget {
  const VStepList({super.key, required this.steps, this.active = 0});

  final List<VStep> steps;

  /// Which step is next. −1 marks none of them.
  final int active;

  /// The rail: a 28 pt disc with air either side of it, so the dashed line falls down its middle
  /// and the cards all start on one left edge.
  static const _disc = 28.0;
  static const _rail = _disc + VSpace.md;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: _rail,
                  child: Column(
                    children: [
                      VIconBadge(
                        size: _disc,
                        tone: i == active ? VBadgeTone.red : VBadgeTone.neutral,
                        filled: i == active,
                        child: Center(
                          child: Text(
                            '${i + 1}',
                            style: VText.captionInk.copyWith(
                              fontWeight: FontWeight.w700,
                              color: i == active ? VColors.inkOnDark : VColors.ink2,
                            ),
                          ),
                        ),
                      ),
                      // The connector runs from under this disc to the next one. The last step
                      // has nothing to join, and an Expanded of nothing keeps the row's height.
                      Expanded(
                        child: i == steps.length - 1
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.symmetric(vertical: VSpace.xs),
                                child: CustomPaint(
                                  painter: const VDashedLine(),
                                  size: const Size(_disc, double.infinity),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: i < steps.length - 1 ? VSpace.s : 0),
                    child: VCard(
                      tone: i == active ? VCardTone.tint : VCardTone.plain,
                      padding: const EdgeInsets.all(VSpace.cardTight),
                      onTap: steps[i].onTap,
                      child: Row(
                        children: [
                          VIconBadge(
                            icon: steps[i].icon,
                            size: VControl.badgeSmall,
                            tone: i == active ? VBadgeTone.red : VBadgeTone.neutral,
                            iconColor: i == active ? null : VColors.ink,
                          ),
                          const SizedBox(width: VSpace.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(steps[i].title, style: VText.title),
                                const SizedBox(height: 2),
                                Text(steps[i].text, style: VText.bodyS.copyWith(color: VColors.ink2)),
                              ],
                            ),
                          ),
                          if (steps[i].onTap != null) ...[
                            const SizedBox(width: VSpace.s),
                            const VChevron(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A dashed box waiting for a file.
///
/// Dashed, because the app's one meaning for a dashed outline is *nothing here yet* — the same
/// reason the showcase controls wear it. Once something has been dropped in, the caller replaces
/// this with the thing itself; the dropzone never shows a filled state.
class VDropzone extends StatelessWidget {
  const VDropzone({
    super.key,
    required this.title,
    required this.onTap,
    this.text,
    this.hint,
    this.icon = Icons.photo_camera_outlined,
    this.busy = false,
  });

  final String title;
  final VoidCallback? onTap;

  /// One line under the title: what pressing it does.
  final String? text;

  /// The quietest line: which formats are taken.
  final String? hint;

  final IconData icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const VDashedBorder(radius: VRadius.md, color: VColors.rule),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(VRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: VSpace.l, horizontal: VSpace.m),
            child: Column(
              children: [
                VIconBadge(
                  icon: icon,
                  size: VControl.badgeSmall,
                  tone: VBadgeTone.neutral,
                  iconColor: VColors.ink,
                ),
                const SizedBox(height: VSpace.s),
                Text(title, style: VText.bodyStrong, textAlign: TextAlign.center),
                if (text != null) ...[
                  const SizedBox(height: 2),
                  Text(text!, style: VText.bodyS.copyWith(color: VColors.ink2), textAlign: TextAlign.center),
                ],
                if (hint != null) ...[
                  const SizedBox(height: VSpace.xs),
                  Text(hint!, style: VText.caption.copyWith(color: VColors.ink3), textAlign: TextAlign.center),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
