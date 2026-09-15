import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'marks.dart';
import 'surfaces.dart';

// ---------------------------------------------------------------------------
// What a sheet has at the top of it
// ---------------------------------------------------------------------------
//
// Two things, and they are here together because they are both the sheet's voice rather than its
// content: the drawing the sheet opens with, and the line the reader is about to send in their own
// name. Neither is ever the thing the sheet is for.

/// Which station the drawing behind a sheet shows.
enum VSheetSceneArt {
  /// A platform, a canopy, a blank sign and the Cologne skyline. The check-in sheet, where the
  /// reader is standing on a platform and has not looked at a clock yet.
  platform,

  /// The same station with a station clock over the platform. The sheet that is about a time —
  /// how late the train was, what that is worth.
  clock,
}

/// The drawing laid behind the top of a bottom sheet.
///
/// It is the sibling of VHeaderScene, and it solves the same problem one surface further in: a
/// sheet opens on a picture, the picture has to stop somewhere, and a picture that stops on a
/// straight line reads as a banner glued to the top of a form. So it dissolves instead.
///
/// The drawings are built to be written over. Their ink runs out a little past halfway down the
/// file and everything below that is a pale wash, which is where the eyebrow, the title and the
/// first control of the sheet land. That is also why the fade is longer than the header band's:
/// VHeaderScene ends on a drawing that is darker than the paper, this one ends on a wash
/// measuring #F9FBFC — four levels *brighter* than [VColors.paper] and bluer — and a bright edge
/// on a pale ground is the one a straight cut shows most.
///
/// Neither file carries a railway's livery. The sign over the platform is blank on purpose: this
/// app files claims against railways, and the mockup's DB mark on that sign would say something
/// untrue about who we are.
class VSheetScene extends StatelessWidget {
  const VSheetScene({super.key, required this.art, this.height});

  final VSheetSceneArt art;

  /// How tall the band is. Null means *be as tall as the drawing*, which is what a sheet wants:
  /// the sheet is a column of content, not a header with a fixed band, so the picture has to know
  /// its own size rather than wait to be told one.
  final double? height;

  static const _platform = 'assets/header/checkin-platform.webp';
  static const _clock = 'assets/header/checkin-clock.webp';

  /// The band as a fraction of the width it is given. Measured: both files are 1089 px wide by
  /// about 1445 tall — 1.327 times as tall as they are wide — and their ink runs out at 56.8 % of
  /// that height (row 820 on the clock, row 800 on the platform). 1.327 × 0.568 is 0.754, so the
  /// whole drawing plus a little of its own wash is about three quarters of the width. At 393 pt
  /// that is a 296 pt band.
  static const _bandOfWidth = 0.754;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => IgnorePointer(
        child: SizedBox(
          width: double.infinity,
          height: height ?? constraints.maxWidth * _bandOfWidth,
          // One mask, at the bottom. Nothing fades at the top or the sides: the drawing is meant
          // to run edge to edge under the sheet's own corners and be clipped by them.
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, Colors.white, Colors.transparent],
              stops: [0, 0.82, 1],
            ).createShader(rect),
            child: ClipRect(
              child: Image.asset(
                switch (art) {
                  VSheetSceneArt.platform => _platform,
                  VSheetSceneArt.clock => _clock,
                },
                // fitWidth and topCenter, the same pair VHeaderScene uses and for the same
                // reason: the drawing is shipped at the proportions it was drawn at, so tying it
                // to the width puts every element at its drawn size. Cover would scale it to the
                // band's height instead and the train would grow out of the frame.
                fit: BoxFit.fitWidth,
                alignment: Alignment.topCenter,
                filterQuality: FilterQuality.medium,
                excludeFromSemantics: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The line the reader is about to send, shown back to them before they send it.
///
/// It is a [VPanel] rather than a card because it is not a second block in the sheet — it is the
/// one thing inside the share card that is in the reader's own voice, and the panel's tint is the
/// whole device that says so. The mark at its left is the same tinted circle the rest of the app
/// heads a block with, so the quote reads as one more block and not as a new invention.
///
/// The German quotation marks belong to the caller's string. Punctuation is copy, and copy is
/// written where the rest of the copy is written, not assembled out of a widget's opinion about
/// which country it is in.
class VQuoteBlock extends StatelessWidget {
  const VQuoteBlock({super.key, required this.text, this.attribution});

  /// The quoted lines, quotation marks and all.
  final String text;

  /// Who said it, set quiet under the quote. The share sheet passes nothing: there the speaker is
  /// the reader, and signing your own sentence back to yourself is noise.
  final String? attribution;

  @override
  Widget build(BuildContext context) {
    return VPanel(
      // Measured #F4F6F9 at a 8.8 pt corner. [VColors.greyFill] (#F3F4F6) is the nearest tint in
      // the palette and [VRadius.md] the nearest corner, which are the panel's own defaults.
      tone: VPanelTone.neutral,
      child: Row(
        // Top-aligned, not centred: the mockup starts the circle and the first line within a point
        // of each other, and a centred mark drifts down the block as the quote grows a third line.
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VIconBadge(
            icon: Icons.format_quote,
            tone: VBadgeTone.red,
            // Measured: a 31.8 pt circle holding 14.3 × 11.1 pt of drawn glyph, in a tint fainter
            // than anything in the palette (#F5ECED against [VColors.redTintSoft]'s #FBF0F1) and a
            // half-strength red (#F17979 against [VColors.red]). The system's red circle is kept —
            // a one-off washed red is not a colour this app owns. [VControl.circleButton] (34) is
            // the nearest size token and [VControl.badgeIcon] (22) the nearest glyph one; 22 is
            // asked for because format_quote's ink is 58 % of its box, so the ratio the badge
            // would pick on its own lands the mark visibly smaller than it is drawn.
            size: VControl.circleButton,
            iconSize: VControl.badgeIcon,
          ),
          const SizedBox(width: VSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Full ink, because this is the sentence the sheet is about. No maxLines: a quote
                // that is cut off is a different quote, so it wraps for as long as it needs and the
                // panel grows with it. Measured at a 18.9 pt line pitch against [VText.body]'s
                // 19.6 — the mockup sets it a shade heavier than regular, and the leading won,
                // because [VText.bodyStrong] would have set two lines a point and a half tighter.
                Text(text, style: VText.body.copyWith(color: VColors.ink)),
                if (attribution != null) ...[
                  const SizedBox(height: VSpace.s),
                  Text(
                    attribution!,
                    style: VText.caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
