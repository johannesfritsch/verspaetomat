import 'package:flutter/material.dart';

import '../theme/tokens.dart';

// ---------------------------------------------------------------------------
// The three surfaces
// ---------------------------------------------------------------------------
//
// A screen is a page with cards on it. Where something has to stand out, it stands on one of
// exactly three surfaces and nothing else:
//
//   the CARD  (VCard)   white, rounded, shadowed. The default. Anything that is a block.
//   the BOARD (VBoard)  the dark or red hero. At most one per screen, for the figure the screen
//                       is about.
//   the PANEL (VPanel)  a tinted block *inside* a card, for the one thing in it that matters.
//
// Nesting stops at two deep: a card may hold a panel, a sheet may hold a card. A panel never
// holds a card, and nothing inside a surface gets its own border — the content lines up with the
// surface's own padding, so a screen has one left edge, not three.

/// How a card sits on the page.
enum VCardTone {
  /// The ordinary card.
  plain,

  /// The card that holds the screen's primary action. It takes a red-tinted shadow rather than
  /// the neutral one, so the call to action is lit before you have read a word of it.
  cta,

  /// A card floating above another surface — a card inside a sheet, a row card in a tight stack.
  raised,

  /// A card that sits *below* the page rather than above it: a footnote with a shape. It has no
  /// shadow and leans on its hairline, so use it only where being overlooked is acceptable.
  sunken,

  /// A card tinted red and flattened: the one card in a stack that is *this one*. It keeps the
  /// card's radius and padding and drops only the shadow, because a tinted card that also floats
  /// reads as two emphases for one idea.
  ///
  /// This is a card, not a [VPanel]: a panel is a tinted block inside a card, and these stand on
  /// the page next to their plain siblings — the step that is current on the Antrag overview, the
  /// attachment about to go out with the mail.
  tint,
}

/// White, rounded, shadowed. The default surface.
class VCard extends StatelessWidget {
  const VCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(VSpace.card),
    this.tone = VCardTone.plain,
    this.onTap,
    this.radius = VRadius.lg,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VCardTone tone;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    final box = Container(
      decoration: BoxDecoration(
        color: switch (tone) {
          VCardTone.sunken => VColors.surfaceMuted,
          VCardTone.tint => VColors.redTintFaint,
          _ => VColors.paperElevated,
        },
        borderRadius: shape,
        border: tone == VCardTone.sunken ? Border.all(color: VColors.hairline) : null,
        boxShadow: switch (tone) {
          VCardTone.plain => VShadow.card,
          VCardTone.cta => VShadow.cardCta,
          VCardTone.raised => VShadow.cardRaised,
          VCardTone.sunken || VCardTone.tint => const <BoxShadow>[],
        },
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return box;
    // The ink has to be clipped to the same corner or the splash squares off the card.
    return Material(
      color: Colors.transparent,
      borderRadius: shape,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          box,
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                splashColor: VColors.pressedOverlay,
                highlightColor: VColors.pressedOverlay,
                borderRadius: shape,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The tint a panel carries.
enum VPanelTone { red, redFaint, neutral, green }

/// A tinted block inside a card: the one thing in the card that the eye should reach first.
/// It has no shadow and no border — the tint is the whole device.
class VPanel extends StatelessWidget {
  const VPanel({
    super.key,
    required this.child,
    this.tone = VPanelTone.red,
    this.padding = const EdgeInsets.all(VSpace.cardTight),
    this.radius = VRadius.md,
  });

  final Widget child;
  final VPanelTone tone;
  final EdgeInsetsGeometry padding;
  final double radius;

  Color get _fill => switch (tone) {
        VPanelTone.red => VColors.redTintSoft,
        VPanelTone.redFaint => VColors.redTintFaint,
        VPanelTone.neutral => VColors.greyFill,
        VPanelTone.green => VColors.greenTint,
      };

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: _fill, borderRadius: BorderRadius.circular(radius)),
        padding: padding,
        child: child,
      );
}

/// Which of the two boards this is.
enum VBoardLook {
  /// The dark one. Home and Ich.
  dark,

  /// The red one. Wir — the same object in the app's own colour, so the pair reads as two looks
  /// of one thing rather than as two different ideas.
  red,
}

/// The hero board: the figure the screen is about, on the one surface that glows.
///
/// At most one per screen. It is the direct descendant of the departure board that came before
/// it — the small-caps label above, the figure, the quiet caption below — rounded now, and lit
/// from underneath rather than ruled with a red hairline.
class VBoard extends StatelessWidget {
  const VBoard({
    super.key,
    required this.child,
    this.look = VBoardLook.dark,
    this.onTap,
    this.aside,
    this.onExplain,
    this.padding = const EdgeInsets.all(VSpace.card),
    this.glow = true,
  });

  final Widget child;
  final VBoardLook look;
  final VoidCallback? onTap;

  /// „Woher weißt du das?" — the source sheet for the figure on the board. Given one, the board
  /// carries a small ⓘ in its top right corner and that corner opens the sheet. Home's board taps
  /// through to Wir, so the mark is its own target rather than the board's (#20).
  final VoidCallback? onExplain;

  /// Something set into the board's right edge: on Wir, the handwritten note and its heart.
  final Widget? aside;

  final EdgeInsetsGeometry padding;

  /// Off where a board stands on something other than the page and the red spill would land on
  /// a surface rather than on paper.
  final bool glow;

  /// How the board divides between its figure and its margin note.
  ///
  /// The note needs enough to set its longest word — „Verspätung" — without breaking it, and the
  /// figure can always shrink inside its FittedBox. So the note gets a fixed share and the figure
  /// takes the rest, rather than the other way round.
  static const _figureFlex = 58;
  static const _asideFlex = 42;

  /// The ⓘ in the corner, and the room the label or the margin note leaves it.
  static const _markSize = 18.0;
  static const markRoom = _markSize + VSpace.xs;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(VRadius.lg);
    final explains = onExplain != null;
    // Without a margin note the figure's own column reaches the corner, so its label is the thing
    // that has to stop short of the mark.
    Widget content = Padding(
      padding: padding,
      child: explains ? _BoardMark(child: child) : child,
    );
    if (aside != null) {
      content = Padding(
        padding: padding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: _figureFlex, child: child),
            const SizedBox(width: VSpace.md),
            // A loose share: the aside may take up to its portion of the board and no more, but
            // it is not made to fill it. Expanded stretched a heart across a third of the card;
            // a bare maximum let the row hand the note sixty points and break a word in half.
            Flexible(
              flex: _asideFlex,
              fit: FlexFit.loose,
              // The corner belongs to the mark, so the note's share stops short of it. At the
              // sizes the app is drawn at the note is far narrower than its share and nothing
              // moves; where large system text grows it into the corner it is set narrower rather
              // than run under the glyph. Pushing it *down* instead cost the board 22 pt, because
              // on Wir the margin note — note, gap and heart — is the taller of the two columns,
              // not the figure.
              child: explains ? Padding(padding: const EdgeInsets.only(right: markRoom), child: aside!) : aside!,
            ),
          ],
        ),
      );
    }

    final box = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: look == VBoardLook.dark ? VGradients.board : VGradients.boardRed,
        borderRadius: shape,
        boxShadow: glow ? VShadow.glowHero : const <BoxShadow>[],
      ),
      child: content,
    );

    if (onTap == null && onExplain == null) return box;
    return Stack(
      children: [
        box,
        if (onTap != null)
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: shape,
                splashColor: const Color(0x14FFFFFF),
                highlightColor: const Color(0x0AFFFFFF),
              ),
            ),
          ),
        // The ⓘ, last so it wins the tap over the whole board underneath it. „Woher weißt du
        // das?" was already there and nothing said so — the answer sat behind a tap nobody had a
        // reason to try (docs/13). It hangs in the corner of the box rather than after the label:
        // beside the words it competed with them for the width of a small phone's eyebrow.
        if (onExplain != null)
          Positioned(
            top: 0,
            right: 0,
            // The glyph is small and quiet; the target around it is a proper one.
            child: SizedBox(
              width: VSpace.card + _markSize / 2 + VControl.touch / 2,
              height: VSpace.card + _markSize / 2 + VControl.touch / 2,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onExplain,
                  customBorder: const CircleBorder(),
                  splashColor: const Color(0x14FFFFFF),
                  highlightColor: const Color(0x0AFFFFFF),
                  child: Padding(
                    padding: const EdgeInsets.only(top: VSpace.card, right: VSpace.card),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Semantics(
                        button: true,
                        label: 'Woher weißt du das?',
                        child: const Icon(Icons.info_outline, size: _markSize, color: VColors.inkOnDark3),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Tells the label above the figure that the board's corner is taken by the ⓘ, so a long eyebrow
/// stops before it instead of running underneath it.
class _BoardMark extends InheritedWidget {
  const _BoardMark({required super.child});

  static bool above(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_BoardMark>() != null;

  @override
  bool updateShouldNotify(_BoardMark oldWidget) => false;
}

/// The label over a board's figure. Small caps, quiet, with an optional glyph in front of it.
///
/// The ⓘ that says the figure explains itself is [VBoard]'s, drawn in the corner of the box:
/// beside the label it ate the width a long eyebrow needs on a small phone, and „ZUSAMMEN
/// GEWARTET" came out as „ZUSAMME…". The label only keeps the corner clear.
class VBoardLabel extends StatelessWidget {
  const VBoardLabel(this.text, {super.key, this.icon, this.look = VBoardLook.dark});
  final String text;
  final IconData? icon;
  final VBoardLook look;

  @override
  Widget build(BuildContext context) {
    final style = VText.eyebrow.copyWith(color: VColors.inkOnDark2);
    final label = Text(text.toUpperCase(), style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    // The board's own mark hangs in the top right corner; on a board without a margin note the
    // label would otherwise run straight under it.
    final room = _BoardMark.above(context) ? VBoard.markRoom : 0.0;
    if (icon == null) return Padding(padding: EdgeInsets.only(right: room), child: label);
    return Padding(
      padding: EdgeInsets.only(right: room),
      child: Row(
        children: [
          Icon(icon, size: 17, color: VColors.inkOnDark2),
          const SizedBox(width: VSpace.s),
          Flexible(child: label),
        ],
      ),
    );
  }
}

/// A line under a board's figure: where the number comes from, or what it is worth.
class VBoardCaption extends StatelessWidget {
  const VBoardCaption(this.text, {super.key, this.look = VBoardLook.dark, this.maxLines = 2});
  final String text;
  final VBoardLook look;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: VText.bodyS.copyWith(color: VColors.inkOnDark3),
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
}

// ---------------------------------------------------------------------------
// Lines
// ---------------------------------------------------------------------------

/// The only divider left in the app, and it lives *inside* a card, between the rows of one list.
/// Never on the page, and never after the last row — a line under the last row is a line under
/// nothing, and it is what makes a list look like a form.
class VDivider extends StatelessWidget {
  const VDivider({super.key, this.strong = false, this.indent = 0});

  /// The heavier rule, for closing a block rather than separating two rows.
  final bool strong;

  /// How far in from the card's content edge the line starts.
  final double indent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(left: indent),
        child: Container(
          height: VControl.hairline,
          color: strong ? VColors.hairlineStrong : VColors.hairline,
        ),
      );
}

// ---------------------------------------------------------------------------
// Small shared parts
// ---------------------------------------------------------------------------

/// How loud a disclosure arrow is.
enum VChevronTone { quiet, ink, red, onDark }

/// The disclosure arrow. Almost every card in the app carries one now, so it is a widget rather
/// than a literal icon with a colour guessed at each call site.
class VChevron extends StatelessWidget {
  const VChevron({super.key, this.size = VControl.chevron, this.tone = VChevronTone.quiet});
  final double size;
  final VChevronTone tone;

  @override
  Widget build(BuildContext context) => Icon(
        Icons.chevron_right,
        size: size,
        color: switch (tone) {
          VChevronTone.quiet => VColors.ink3,
          VChevronTone.ink => VColors.ink,
          VChevronTone.red => VColors.red,
          VChevronTone.onDark => VColors.inkOnDark3,
        },
      );
}

/// How wide a small-caps label is tracked.
enum VEyebrowSize {
  /// Inside a tinted panel: the smallest label there is.
  s,

  /// Welded to a figure, or heading a section inside a card.
  m,

  /// Standing on the page with nothing around it, so tracked wider to hold itself together.
  wide,
}

enum VEyebrowTone {
  /// The quiet one, and the default: a label welded to a figure or sitting inside a panel, where
  /// the figure is the thing being read and the label only names it.
  muted,

  /// Full ink. A section label standing on the page is a heading, and a heading is not a footnote.
  ink,

  red,
  onDark,
}

/// A small-caps label. The device that replaced the hairline rule under a section heading.
class VEyebrow extends StatelessWidget {
  const VEyebrow(this.text, {super.key, this.size = VEyebrowSize.m, this.tone = VEyebrowTone.muted});
  final String text;
  final VEyebrowSize size;
  final VEyebrowTone tone;

  @override
  Widget build(BuildContext context) {
    final base = switch (size) {
      VEyebrowSize.s => VText.eyebrowS,
      VEyebrowSize.m => VText.eyebrow,
      VEyebrowSize.wide => VText.eyebrowWide,
    };
    final color = switch (tone) {
      VEyebrowTone.muted => null,
      VEyebrowTone.ink => VColors.ink,
      VEyebrowTone.red => VColors.red,
      VEyebrowTone.onDark => VColors.inkOnDark2,
    };
    return Text(
      text.toUpperCase(),
      style: color == null ? base : base.copyWith(color: color),
    );
  }
}
