import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'marks.dart';
import 'surfaces.dart';

// ---------------------------------------------------------------------------
// The Ich tab
// ---------------------------------------------------------------------------
//
// Three blocks, in the order the screen reads them:
//
//   VStatQuad          four figures in one card: what the patience has been worth.
//   VAchievementStrip  the badges, as a row of discs that scrolls sideways.
//   VMenuCard          the settings list at the foot.
//
// They share one habit and it is worth naming: none of them is a hero. The board above them is
// the screen's figure, so everything here stays a step quieter than it could be — small type,
// hairlines instead of gaps, and the one tint that already means "yours".

/// One cell of [VStatQuad]: a tinted mark, a figure, and a label of one or two lines.
///
/// The badge is the smaller of the two sizes. A stat cell is a quarter of a card and the 50 pt
/// badge that heads a block would take a third of the cell's width away from the figure, which is
/// the part being read.
///
/// The figure is set in [VText.numberS] — the euro-total style — because three of the four figures
/// on this screen are amounts and the fourth ("7 Fahrten") has to line up with them. Figures in
/// pairs share one size, and four in a grid are two pairs.
///
/// The label wraps to two lines and only then gives up. "Bestätigt, durch dich gespendet" is three
/// words too long for one line at a quarter of a phone, and a cell that clipped it would be saying
/// something shorter and wronger than what it means.
class VStat extends StatelessWidget {
  const VStat({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.tone = VBadgeTone.red,
  });

  final IconData icon;

  /// Already formatted, and formatted the German way: "0,00 €", "+274", "7". The backend owns
  /// every money rule, so this widget never sees a number it could round.
  final String value;

  final String label;

  /// Red for anything of the app's own; an identity hue only where the cell names somebody else.
  final VBadgeTone tone;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Measured 40.7 pt across, which is [VControl.badgeSmall] to within a rounding error.
          VIconBadge(icon: icon, tone: tone, size: VControl.badgeSmall),
          // Measured 14.8 pt between the disc and the figure.
          const SizedBox(width: VSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Measured 18.2 pt of Archivo; numberS (20) is the nearest token and the only one
                // in the figure family that is not a hero size.
                Text(
                  value,
                  style: VText.numberS,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // Measured 3.2 pt between the figure's line box and the label's.
                const SizedBox(height: VSpace.xs),
                Text(
                  label,
                  // Measured 10.7–11.5 pt in #74–79 grey: caption's size, ink2's weight of grey.
                  style: VText.caption.copyWith(color: VColors.ink2),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      );
}

/// The 2×2 of figures, as one card rather than four.
///
/// The whole device is the pair of hairlines. Four separate cards would read as four things you
/// could act on; one card divided in quarters reads as one statement with four parts, which is
/// what it is — nothing in here is tappable. The mockup draws only the vertical hairline and lets
/// the rows float; the horizontal one is here because without it the second row reads as an
/// afterthought stuck under the first rather than as the other half of a grid.
///
/// All four cells share one height, and that is not cosmetic: the labels are the part that wraps,
/// so a cell whose label runs to two lines would otherwise push its own row taller and leave the
/// hairline stepping down the middle of the card. The layout measures the tallest cell at its real
/// width — text wrapping included — and gives every cell that height.
///
/// Exactly four is the shape. Fewer draws what it has and leaves the rest of the grid empty rather
/// than redistributing, so a card with three stats still lines up with a card that has four; a
/// hairline is drawn only where two filled cells meet.
class VStatQuad extends StatelessWidget {
  const VStatQuad({super.key, required this.stats});

  final List<VStat> stats;

  static const _columns = 2;
  static const _maxCells = 4;

  @override
  Widget build(BuildContext context) {
    final cells = stats.length > _maxCells ? stats.sublist(0, _maxCells) : stats;
    if (cells.isEmpty) return const SizedBox.shrink();

    final rowCount = (cells.length + _columns - 1) ~/ _columns;
    final twoColumns = cells.length > 1;

    return VCard(
      // Measured 14.3 pt at the sides and 11.1 pt top and bottom. The card token is the nearest
      // for the one and the tight one for the other, and a grid of cells is closer to a list of
      // rows than to a block of prose.
      padding: const EdgeInsets.symmetric(
        horizontal: VSpace.card,
        vertical: VSpace.cardTight,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _column(cells, rowCount, 0, twoColumns)),
            if (twoColumns) ...[
              // Measured one pixel of #F2F4F6 down the card's exact centre.
              Container(width: VControl.hairline, color: VColors.hairline),
              Expanded(child: _column(cells, rowCount, 1, twoColumns)),
            ],
          ],
        ),
      ),
    );
  }

  /// One side of the grid. Every slot is an [Expanded], so the two rows split the card's height
  /// evenly whichever of them is carrying the longer label.
  Widget _column(List<VStat> cells, int rowCount, int col, bool twoColumns) {
    final children = <Widget>[];
    for (var row = 0; row < rowCount; row++) {
      final index = row * _columns + col;
      final stat = index < cells.length ? cells[index] : null;

      if (row > 0) {
        final above = (row - 1) * _columns + col < cells.length;
        children.add(
          above && stat != null
              // A line under an empty half is a line under nothing, so the gap keeps the height
              // and drops the ink.
              ? const VDivider()
              : const SizedBox(height: VControl.hairline),
        );
      }

      children.add(
        Expanded(
          child: stat == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: EdgeInsets.only(
                    // Measured 9.7 pt between the hairline and the cell beside it.
                    left: col == 1 ? VSpace.md : 0,
                    right: col == 0 && twoColumns ? VSpace.md : 0,
                    // Measured 17.6 pt between the two rows, split either side of the line.
                    top: row == 0 ? 0 : VSpace.s,
                    bottom: row == rowCount - 1 ? 0 : VSpace.s,
                  ),
                  child: stat,
                ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

/// One badge: a disc with the art in it and the name of the thing under it.
///
/// The art is passed in because the app already ships the badge PNGs in `assets/achievements/`,
/// and a widget that knew what "Bagatellgrenze geknackt" looks like would have to be edited every
/// time a new badge is drawn. This widget knows only two things about a badge: how big the disc is
/// and whether you have it.
///
/// Earned and unearned are told apart twice over, by the disc and by the art. A red tint with the
/// art in its own colours, or a grey disc with the art desaturated — greyed rather than faded,
/// because a half-transparent badge reads as loading rather than as locked. The label follows: ink
/// for something you have, grey for something you do not.
class VAchievement extends StatelessWidget {
  const VAchievement({
    super.key,
    required this.label,
    required this.art,
    required this.earned,
  });

  /// The disc. Measured 56.9 pt, which no control token carries: it is bigger than
  /// [VControl.badge] because it holds a drawn badge rather than a glyph, and it is built out of
  /// the badge and a small space so that it still moves if the badge size ever does.
  static const circle = VControl.badge + VSpace.s;

  /// How much of the disc the art is given. Measured 0.60 to 0.77 across the four badges in the
  /// mockup — the flatter the artwork the more width it takes — so this is the middle of them
  /// rather than any one of them.
  static const _artRatio = 0.72;

  /// Luminance weights. A badge you have not earned is the same drawing in grey, not a paler
  /// version of the same drawing.
  static const _desaturate = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  final String label;

  /// The badge artwork, usually an `Image.asset`. Drawn inside a square of [_artRatio] of the
  /// disc, so artwork of any aspect lands on the same optical size.
  final Widget art;

  final bool earned;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: circle,
            height: circle,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // Measured #FEF0F0 earned and #F3F3F3 unearned. redTintSoft and greyCircle are the
              // nearest tokens; both are within two levels of what the mockup draws.
              color: earned ? VColors.redTintSoft : VColors.greyCircle,
              shape: BoxShape.circle,
            ),
            child: SizedBox(
              width: circle * _artRatio,
              height: circle * _artRatio,
              child: earned
                  ? art
                  : ColorFiltered(colorFilter: _desaturate, child: art),
            ),
          ),
          // Measured 6.5 pt between the disc and the label's line box.
          const SizedBox(height: VSpace.s),
          Text(
            label,
            // Measured 11.5 pt, near-black earned and #72–7F grey unearned.
            style: earned
                ? VText.captionInk
                : VText.caption.copyWith(color: VColors.ink2),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
}

/// The row of badges.
///
/// It scrolls sideways rather than shrinking the discs. A badge is a piece of artwork with a face
/// on it and there is a size below which it stops being one, so the strip would rather run off the
/// right edge than hand you six grey buttons. [visible] is how many are meant to fill the card:
/// the slot width comes out of that, the discs keep their size inside it, and everything past the
/// count is a swipe away.
///
/// The slot is a little wider than the disc, which is what gives the labels their room. They are
/// centred under the disc and they are allowed to be wider than it — "Bagatellgrenze geknackt" is
/// wider than any disc at any size — so the label, not the disc, is what sets the rhythm.
class VAchievementStrip extends StatelessWidget {
  const VAchievementStrip({super.key, required this.items, this.visible = 4});

  final List<VAchievement> items;

  /// How many slots fill the card's width. Four is what the mockup draws, and four slots come out
  /// 87 pt apart, which is what it measures.
  final int visible;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final slots = visible < 1 ? 1 : visible;

    return VCard(
      padding: const EdgeInsets.symmetric(
        horizontal: VSpace.card,
        vertical: VSpace.cardTight,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fitted = constraints.hasBoundedWidth
              ? (constraints.maxWidth - (slots - 1) * VSpace.m) / slots
              : VAchievement.circle + VSpace.m;
          // The disc never gives way. Ask for eight across a phone and the strip scrolls.
          final width =
              fitted < VAchievement.circle ? VAchievement.circle : fitted;

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            // The card's own padding is the strip's gutter; adding one here would double it.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(width: VSpace.m),
                  SizedBox(width: width, child: items[i]),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One line of the settings list: an outlined glyph, a label, a chevron.
///
/// The glyph is outlined and inked rather than filled in a tinted circle, and that is the whole
/// distinction the design draws between navigation and naming. A badge says "this block is about
/// money"; a glyph in a settings row says "this is the door to your profile" and then gets out of
/// the way.
///
/// Drawn at 33 pt tall and built at 44, because a row you can see is a row somebody will aim at.
class VMenuRow extends StatelessWidget {
  const VMenuRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashColor: VColors.pressedOverlay,
          highlightColor: VColors.pressedOverlay,
          borderRadius: BorderRadius.circular(VRadius.sm),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: VControl.touch),
            child: Row(
              children: [
                // Measured a 20 pt icon box. There is no icon-size token at 20 except the
                // chevron's, which is exactly that size.
                Icon(icon, size: VControl.chevron, color: VColors.ink),
                // Measured 22.6 pt between the glyph's box and the label.
                const SizedBox(width: VSpace.l),
                Expanded(
                  child: Text(
                    label,
                    // Measured 11.6–12.4 pt of regular weight in full ink. bodyS is that size;
                    // its default grey is not, because a menu label is the row, not a footnote.
                    style: VText.bodyS.copyWith(color: VColors.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: VSpace.s),
                const VChevron(),
              ],
            ),
          ),
        ),
      );
}

/// The settings card at the foot of the screen.
///
/// The plainest object on the tab, and it should stay that way. Everything above it is carrying a
/// figure or a picture; this is a list of doors, and a list of doors that decorated itself would
/// start competing with the things worth looking at. So: no badges, no tints, no kickers, one
/// hairline between rows and none after the last.
///
/// The hairline starts at the label rather than at the card's edge, so the glyphs read as a column
/// running down the left of the list instead of as four separate rows that each happen to begin
/// with a picture.
class VMenuCard extends StatelessWidget {
  const VMenuCard({super.key, required this.rows});

  final List<VMenuRow> rows;

  /// Where the hairline starts, measured from the card's content edge: past the glyph box and the
  /// gap after it, which lands on the label's own left edge. Measured 42.2 pt.
  static const _indent = VControl.chevron + VSpace.l;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    return VCard(
      // Measured 16.6 pt at the sides and 8.1 pt top and bottom: the rows carry their own height,
      // so the card only has to keep them off its corners.
      padding: const EdgeInsets.symmetric(
        horizontal: VSpace.card,
        vertical: VSpace.s,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const VDivider(indent: _indent),
            rows[i],
          ],
        ],
      ),
    );
  }
}
