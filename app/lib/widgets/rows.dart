import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'marks.dart';
import 'surfaces.dart';

// ---------------------------------------------------------------------------
// The rows that fill the cards
// ---------------------------------------------------------------------------
//
// A card is a surface; these are the shapes that live on it. There are four, and between them
// they build every list in the app:
//
//   VSectionHeader  names a block and points somewhere else.
//   VCardRow        a row INSIDE a card: badge, kicker, title, body, chevron.
//   VListCard       a card that IS one row, for a list where every item is its own surface.
//
// Every one of them is built on ONE left edge — its own parent's content edge. The mockups do
// not manage this (antraege's claim card indents its ride rows to one edge and its header text
// to another, set by the operator avatar), and the rule that a surface has one left edge is
// older and better than the drawing.

/// A section label, with an optional link at the far end of it.
///
/// The device that replaced the hairline rule. There is no line under this — a label plus the gap
/// below it separates two blocks better than a rule did, and a rule under a heading is what makes
/// a screen look like a form. The link is red because going somewhere else is an action.
///
/// [onCard] is about where the header stands, not what it looks like. Inside a card the card's own
/// padding already lifts the label off whatever is above it; standing on the page between two
/// blocks it has to claim that air itself, so it takes an extra [VSpace.m] above. The page gutter
/// is the scaffold's business either way — this widget never adds one.
class VSectionHeader extends StatelessWidget {
  const VSectionHeader(
    this.label, {
    super.key,
    this.linkLabel,
    this.onLink,
    this.wide = false,
    this.onCard = true,
    this.heading = false,
  });

  final String label;

  /// The red link at the end of the row: "Alle Wochen", "Mehr erfahren".
  final String? linkLabel;

  final VoidCallback? onLink;

  /// Tracked wider, for a label with nothing around it to hold it together.
  final bool wide;

  /// Whether the header sits inside a card. See the class doc.
  final bool onCard;

  /// Set as a heading rather than a small-caps label.
  ///
  /// Ich names its sections this way — „Abzeichen" in full ink at title size, with the link beside
  /// it — while Wir and Home use the small caps. Both are in the design, so both are here, and the
  /// rule is which kind of thing the label names: a *heading* introduces a part of the screen you
  /// could have navigated to on its own, a *label* names the block right under it.
  final bool heading;

  @override
  Widget build(BuildContext context) {
    final hasLink = linkLabel != null;

    Widget row = Row(
      children: [
        Expanded(
          child: heading
              ? Text(label, style: VText.h3, maxLines: 1, overflow: TextOverflow.ellipsis)
              : VEyebrow(
                  label,
                  size: wide ? VEyebrowSize.wide : VEyebrowSize.m,
                  // A section label is a heading, not a footnote to the block under it.
                  tone: VEyebrowTone.ink,
                ),
        ),
        if (hasLink) ...[
          const SizedBox(width: VSpace.s),
          _VSectionLink(label: linkLabel!, onTap: onLink),
        ],
      ],
    );

    // The link is drawn about 20 pt tall in the mockups. It is built at 44 pt of touch area
    // regardless, and that sets the height of the whole row so the label stays centred on it.
    if (hasLink) {
      row = ConstrainedBox(
        constraints: const BoxConstraints(minHeight: VControl.touch),
        child: Center(child: row),
      );
    }

    if (onCard) return row;
    return Padding(padding: const EdgeInsets.only(top: VSpace.m), child: row);
  }
}

/// The red link inside a section header. Private: a link with no label to belong to has nothing
/// to say, so it is never built on its own.
class _VSectionLink extends StatelessWidget {
  const _VSectionLink({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      // Horizontal air so the tap target is wider than the glyphs, without moving the chevron off
      // the content edge — the icon box already carries its own inset.
      padding: const EdgeInsets.symmetric(horizontal: VSpace.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: VText.link,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
          const VChevron(size: VControl.chevronSmall, tone: VChevronTone.red),
        ],
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VRadius.sm),
        splashColor: VColors.pressedOverlay,
        highlightColor: VColors.pressedOverlay,
        child: SizedBox(height: VControl.touch, child: Center(child: content)),
      ),
    );
  }
}

/// A row inside a card: an icon badge, a red kicker, a title, a line or two of body, a chevron.
///
/// Home builds two of these and they are the screen's rhythm — the badge is what the eye lands on
/// and the kicker is what tells it whether this is an offer or a fact. The whole row is centred on
/// its badge; the mockup centres one of the two rows on the badge and hangs the other off the
/// title, and the centred one is the one that reads.
///
/// The kicker also decides how loud the row is. A row that carries one is the card's headline
/// block — it is the reason the card exists — so its title is set at [VText.h3] and its body at
/// [VText.body]. A row without one is a row among others and drops a step, to [VText.title] and
/// [VText.bodyS]. That is the difference the mockup draws between "Fährst du gleich?" and "Deine
/// Minuten helfen." and it is a statement about rank, not a font size that got away.
class VCardRow extends StatelessWidget {
  const VCardRow({
    super.key,
    this.leading,
    this.eyebrow,
    this.eyebrowTone = VEyebrowTone.red,
    required this.title,
    this.body,
    this.trailing,
    this.chevron = false,
    this.onTap,
  });

  /// The icon badge. A [VIconBadge] at its default 50 pt in every current call site.
  final Widget? leading;

  /// The kicker over the title: "EINCHECKEN". See the class doc — it also sets the row's rank.
  final String? eyebrow;

  final VEyebrowTone eyebrowTone;
  final String title;
  final String? body;

  /// Something before the chevron: an amount, a count.
  final Widget? trailing;

  final bool chevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final headline = eyebrow != null;

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (eyebrow != null) ...[
          VEyebrow(eyebrow!, tone: eyebrowTone),
          const SizedBox(height: VSpace.xs),
        ],
        Text(
          title,
          style: headline ? VText.h3 : VText.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (body != null) ...[
          const SizedBox(height: VSpace.xs),
          // No line cap: the body wraps rather than truncates, because it is the sentence that
          // explains the row and half of it explains nothing.
          Text(body!, style: headline ? VText.body : VText.bodyS),
        ],
      ],
    );

    Widget row = Row(
      children: [
        if (leading != null) ...[
          leading!,
          const SizedBox(width: VSpace.m),
        ],
        Expanded(child: column),
        if (trailing != null) ...[
          const SizedBox(width: VSpace.s),
          trailing!,
        ],
        if (chevron) ...[
          const SizedBox(width: VSpace.s),
          const VChevron(),
        ],
      ],
    );

    if (onTap == null) return row;
    row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: VControl.touch),
      child: row,
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VRadius.md),
        splashColor: VColors.pressedOverlay,
        highlightColor: VColors.pressedOverlay,
        child: row,
      ),
    );
  }
}

/// A card that is one row: the shape Wir uses for its partner NGOs.
///
/// A list where every item is its own surface, stacked four points apart. It costs more ink than
/// rows inside one card and it buys two things: each item is its own tap target with its own
/// shadow, and the list can be reordered or filtered without the hairlines ending up in the wrong
/// places. It is [VCardTone.raised] because a stack this tight needs the shadow to hold the items
/// apart, and it is [VRadius.md] because a card this short looks like a pill at the larger radius.
///
/// The name is capped at two lines. "Bahnhofsmission Köln" and "Kinderhospiz Rheinland" both wrap,
/// and the amount beside them must not be pushed off the edge for it — the text column is the part
/// that gives way, never the figure.
class VListCard extends StatelessWidget {
  const VListCard({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.chevron = true,
    this.onTap,
  });

  /// The identity mark. A [VIconBadge] in the NGO's own colour on Wir.
  final Widget? leading;

  final String title;

  /// The quiet second line: "Geschichte und Zweck".
  final String? subtitle;

  /// The figure at the end of the row — the euro total. It keeps its intrinsic width and the title
  /// wraps around it.
  final Widget? trailing;

  final bool chevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => VCard(
        tone: VCardTone.raised,
        radius: VRadius.md,
        padding: const EdgeInsets.all(VSpace.cardTight),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: VControl.touch),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: VSpace.m),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: VText.bodyStrong,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: VSpace.xs),
                      Text(
                        subtitle!,
                        style: VText.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: VSpace.s),
                trailing!,
              ],
              if (chevron) ...[
                const SizedBox(width: VSpace.s),
                const VChevron(),
              ],
            ],
          ),
        ),
      );
}
