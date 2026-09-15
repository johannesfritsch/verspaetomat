import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'surfaces.dart';

// ---------------------------------------------------------------------------
// The controls you pick a station with
// ---------------------------------------------------------------------------
//
// The check-in sheet asks three questions in a row — from where, to where, which train — and every
// one of them is answered by picking one thing out of a list. So the file holds one control for
// each move the reader can make:
//
//   VSearchField    type, or tap to go somewhere you can type.
//   VLocationButton let the phone answer instead of you.
//   VNoticeRow      what the app already believes, above the list, with a way to argue.
//   VSelectCard     one option out of a set, and it stays chosen.
//   VOptionRow      one option out of a list, and tapping it moves you on.
//
// The last two look similar and mean opposite things. A card you SELECT carries a tick and no
// chevron: it holds a decision, and the screen's own button is what advances. A row you TAP
// carries a chevron and no tick: it advances, and there is nothing to hold. Never put both marks
// on one thing.
//
// Sizes below are measured off `docs/assets/redesign/start-ride-step-1-from-station.png` and
// `…step-2-to-station.png` at 2.167 px per logical point. Where the two mockups disagree, the
// disagreement is written down rather than averaged away.

// ---------------------------------------------------------------------------
// Typing, and not typing
// ---------------------------------------------------------------------------

/// The rounded grey search box: a magnifier, then whatever you have typed.
///
/// One widget serves two jobs, and [readOnly] is the switch between them. On step 1 it is a real
/// field and the keyboard comes up; on a screen that hands the search to a full page of its own it
/// is a button that happens to look like a field, and then it takes [onTap] and refuses the caret.
/// Both look identical on purpose — a reader should not have to learn that one grey box types and
/// the other one navigates.
///
/// The hint and the typed value share one style. A placeholder that is set smaller than the text
/// replacing it makes the field jump the moment someone starts typing, which is the one thing a
/// search field must not do.
///
/// The mockups draw the box 40 pt tall on step 1 and 38 pt on step 2, and they disagree about the
/// corner too — 12 pt on step 1, 7 pt on step 2. It is built at [VControl.button] and
/// [VRadius.button]: the taller reading, the corner that has a token, and a hit target that clears
/// 44 pt either way.
class VSearchField extends StatelessWidget {
  const VSearchField({
    super.key,
    this.hint = 'Bahnhof suchen …',
    this.onChanged,
    this.controller,
    this.onTap,
    this.readOnly = false,
  });

  /// The placeholder. German, and it names the thing being searched rather than the act of
  /// searching — "Bahnhof suchen …", not "Suchen".
  final String hint;

  final ValueChanged<String>? onChanged;
  final TextEditingController? controller;

  /// Where a tap goes. Set together with [readOnly] to make the field a door rather than a field.
  final VoidCallback? onTap;

  /// No keyboard, no caret, no selection. The box still reads as a field.
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    // Measured #F0F1F3 against the token's #F3F4F6. Three levels, and the token is the one the
    // rest of the app's quiet controls already stand on.
    return Container(
      height: VControl.button,
      // Measured 16.6 pt on step 1 and 12.9 pt on step 2. The wider one: the magnifier needs the
      // air or it sits on the corner's curve.
      padding: const EdgeInsets.symmetric(horizontal: VSpace.m),
      decoration: BoxDecoration(
        color: VColors.greyFill,
        borderRadius: BorderRadius.circular(VRadius.button),
      ),
      child: Row(
        children: [
          // A 20 pt icon box: the magnifier's drawn ink measures 13.5 pt, and Icons.search fills
          // about three quarters of its box.
          const Icon(Icons.search, size: VControl.chevron, color: VColors.ink2),
          const SizedBox(width: VSpace.md),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              onTap: onTap,
              readOnly: readOnly,
              showCursor: !readOnly,
              enableInteractiveSelection: !readOnly,
              maxLines: 1,
              style: VText.bodyL,
              cursorColor: VColors.red,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                isCollapsed: true,
                // All three, and filled off. The app's theme gives every field a white fill and an
                // outline; `border` alone does not override `enabledBorder`, so the field came out
                // as a white box floating inside its own grey one.
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: hint,
                hintStyle: VText.bodyL.copyWith(color: VColors.ink2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Aktueller Standort": let the phone answer the question instead of you.
///
/// Step 1 draws this as a bare glyph and a label beside the search field; step 2 draws it as a
/// filled grey block. The filled one is what is built, because the bare one is not a control — it
/// is two pieces of ink with no edge, and nothing tells a thumb where to land. The block is the
/// same grey and the same corner as [VSearchField] so the pair reads as one row of two controls.
///
/// It takes only the width it is given. The label is allowed two lines, because "Aktueller
/// Standort" does not fit on one at the width step 2 leaves it, and the caller is the one who
/// knows how much room there is.
class VLocationButton extends StatelessWidget {
  const VLocationButton({super.key, required this.onTap, this.label = 'Aktueller Standort'});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(VRadius.button);
    return ConstrainedBox(
      // Drawn 38.8 pt. Built at 44, like every other control in the app that the mockups draw short.
      constraints: const BoxConstraints(minHeight: VControl.button),
      child: Material(
        color: VColors.greyFill,
        borderRadius: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: VColors.pressedOverlay,
          highlightColor: VColors.pressedOverlay,
          child: Padding(
            // Measured 11.5 pt at the glyph and 14.8 pt at the label's far side. The block is
            // narrow and the label needs the width more than the edges do.
            padding: const EdgeInsets.symmetric(horizontal: VSpace.md, vertical: VSpace.s),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drawn ink 17.5 pt; Icons.my_location nearly fills its box, so the box is 20.
                const Icon(Icons.my_location, size: VControl.chevron, color: VColors.ink),
                const SizedBox(width: VSpace.md),
                Flexible(
                  child: Text(
                    label,
                    style: VText.buttonS,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// What the app already thinks
// ---------------------------------------------------------------------------

/// What ground a notice stands on.
enum VNoticeTone {
  /// The app has worked something out and is telling you: a station it found, a connection it
  /// recognised. Red because it is the app's own voice, not because anything is wrong.
  red,

  /// The same shape with no claim behind it: a hint, a state, a line of explanation.
  neutral,
}

/// The tinted full-width row that sits above a list and says what the app already believes.
///
/// It is always a statement the reader might want to overrule, so it always ends in something they
/// can reach: step 1 ends in a pill that only labels ("In deiner Nähe"), step 2 ends in a red
/// action that undoes ("Ändern ›"). Hence two ways to fill the end of the row — [trailing] takes
/// any mark, [actionLabel] builds the red action — and [trailing] wins if both are given, because
/// a row with two endings has no ending.
///
/// The tint is the whole device: no border, no shadow, [VRadius.md]. That is a [VPanel], so this
/// is a [VPanel] rather than a second rounded box with the same measurements.
class VNoticeRow extends StatelessWidget {
  const VNoticeRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.trailing,
    this.tone = VNoticeTone.red,
    this.onTap,
  });

  /// The whole row as one target. On step 1 the row *is* the station the phone found, so tapping
  /// anywhere on it picks that station; [onAction] is for the smaller case where only the word at
  /// the end does something.
  final VoidCallback? onTap;

  /// The glyph at the left: an arrow for a place near you, a pin for a place you came from.
  final IconData icon;

  /// The claim itself: "St.-Martin-Straße", "Ab Köln Hbf".
  final String title;

  /// Where the claim comes from: "448 m entfernt", "Zugverbindung erkannt".
  final String? subtitle;

  /// The red action at the end of the row. Ignored when [trailing] is set.
  final String? actionLabel;

  final VoidCallback? onAction;

  /// Anything else at the end of the row — a [VPill], a figure. Takes precedence over
  /// [actionLabel].
  final Widget? trailing;

  final VNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final red = tone == VNoticeTone.red;

    final Widget? end = trailing ??
        (actionLabel == null ? null : _VNoticeAction(label: actionLabel!, onTap: onAction));

    final panel = VPanel(
      tone: red ? VPanelTone.red : VPanelTone.neutral,
      radius: VRadius.md,
      // Measured 14.4 pt across and 12.2 pt down. The nearest token either side of 14.4 is a
      // coin toss; the wider one keeps the glyph off the corner.
      padding: const EdgeInsets.symmetric(horizontal: VSpace.m, vertical: VSpace.cardTight),
      child: Row(
        children: [
          Icon(icon, size: VControl.chevron, color: red ? VColors.red : VColors.ink2),
          const SizedBox(width: VSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  // The two mockups set this at 15 pt and 13.7 pt. One size, and it is the one the
                  // app already uses for the strong line of a row.
                  style: VText.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: VSpace.xs),
                  Text(
                    subtitle!,
                    // Measured 13 pt, which falls between two tokens. The smaller one keeps a
                    // clear step under the title.
                    style: VText.bodyS,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (end != null) ...[
            const SizedBox(width: VSpace.s),
            end,
          ],
        ],
      ),
    );
    if (onTap == null) return panel;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(VRadius.md),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          panel,
          Positioned.fill(
            child: InkWell(
              onTap: onTap,
              splashColor: VColors.pressedOverlay,
              highlightColor: VColors.pressedOverlay,
            ),
          ),
        ],
      ),
    );
  }

}

/// The red action at the end of a notice. Private: an action with no notice to belong to is a
/// link, and the app already has one of those in [VSectionHeader].
class _VNoticeAction extends StatelessWidget {
  const _VNoticeAction({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: VText.link, maxLines: 1, softWrap: false),
        // Drawn ink 4.6 × 7.8 pt, which is a 16 pt icon box.
        const VChevron(size: VControl.chevronSmall, tone: VChevronTone.red),
      ],
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VRadius.sm),
        splashColor: VColors.pressedOverlay,
        highlightColor: VColors.pressedOverlay,
        // Drawn about 20 pt tall; built at 44 like every other action in the app.
        child: SizedBox(height: VControl.touch, child: Center(child: content)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Picking one
// ---------------------------------------------------------------------------

/// One option in a list you pick from: white until it is chosen, pink with a tick afterwards.
///
/// The tick is the selection mark and there is no chevron, because this card does not go anywhere
/// — it holds a decision until the screen's own button acts on it. A chevron here would promise a
/// next screen that never arrives.
///
/// Both states are the same size to the point, so a list does not shift when the reader changes
/// their mind: the chosen one is a [VPanel] in the same [VRadius.md] and the same padding as the
/// [VCard] the others are, and its border is painted over the box rather than added around it.
///
/// A note on that border. The mockup draws the chosen card as a flat pink block with no stroke at
/// all — measured at every edge, there is none. It has one here anyway: the card it replaces has
/// a drawn ring on its tick, and a state that trades a drawn edge for a tint alone is a state that
/// disappears for anyone who reads colour poorly.
///
/// [leading] is the caller's, and the caller should change it with the state: the mockup puts a
/// white disc under the chosen card's glyph and a grey one under the rest.
class VSelectCard extends StatelessWidget {
  const VSelectCard({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.selected,
    required this.onTap,
  });

  /// The identity mark. A [VIconBadge]; the mockup draws it 33 pt across, where the nearest token
  /// is [VControl.badgeSmall].
  final Widget? leading;

  final String title;

  /// The quiet second line: "78 km · ~ 1:12 h".
  final String? subtitle;

  /// Something between the text and the tick — a figure, a pill. Rarely used: the tick is already
  /// at that end of the row.
  final Widget? trailing;

  final bool selected;
  final VoidCallback onTap;

  static const _padding = EdgeInsets.all(VSpace.cardTight);

  @override
  Widget build(BuildContext context) {
    final row = ConstrainedBox(
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
                    style: VText.bodyS,
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
          const SizedBox(width: VSpace.s),
          _VSelectMark(selected: selected),
        ],
      ),
    );

    // Measured 9.0 pt on the chosen card and 8.3 pt on the rest — one corner, and it is the one a
    // list card in this app already has.
    final shape = BorderRadius.circular(VRadius.md);

    if (!selected) {
      return VCard(
        tone: VCardTone.raised,
        radius: VRadius.md,
        padding: _padding,
        onTap: onTap,
        child: row,
      );
    }

    return Container(
      // A foreground decoration paints over the box without taking a point of layout, which is
      // what keeps the two states the same height.
      foregroundDecoration: BoxDecoration(
        borderRadius: shape,
        // The only stroke measured anywhere in the pair is the unselected tick's ring, at 1.4 pt.
        // The card's edge stays under it: twice the hairline is the nearest the token set has.
        border: Border.all(color: VColors.red, width: VControl.hairline * 2),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: shape,
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Measured #FBEAEA. redTintSoft (#FBF0F1) is the nearest tint in the palette, and it
            // is the one the notice above this list already stands on.
            VPanel(tone: VPanelTone.red, radius: VRadius.md, padding: _padding, child: row),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: shape,
                  splashColor: VColors.pressedOverlay,
                  highlightColor: VColors.pressedOverlay,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The tick on a [VSelectCard]: a filled red disc when chosen, a hollow grey ring when not.
///
/// One box either way, so the card's text never shifts sideways as the state changes. Drawn at
/// 18.3 pt in the mockup; [VControl.pill] is the nearest size the token set carries.
class _VSelectMark extends StatelessWidget {
  const _VSelectMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: VControl.pill,
        height: VControl.pill,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? VColors.red : null,
            border: selected
                ? null
                // Measured 1.4 pt of #AEB2B9. VColors.handle is the nearest neutral in the palette
                // that is a drawn edge rather than a text colour; three hairlines is the nearest
                // weight.
                : Border.all(color: VColors.handle, width: VControl.hairline * 3),
          ),
          child: selected
              ? const Icon(
                  Icons.check,
                  size: VControl.chevronSmall,
                  color: VColors.inkOnDark,
                )
              : null,
        ),
      );
}

/// The plainer row inside a card: a badge, a station, maybe a distance, a chevron, a hairline.
///
/// This is the list you tap through rather than the list you choose from — step 1's "Deine
/// Bahnhöfe" and "In der Nähe". Tapping one answers the question and moves the sheet on, so it
/// carries a chevron and never a tick.
///
/// It draws no surface of its own: it is a row, and the card around it is the caller's. What it
/// does own is the line under it, because a hairline after the last row is a line under nothing —
/// so [divider] is the last row's to switch off, and nobody else's.
///
/// The line starts at the title, not at the card's edge, which is what stops a list of rows from
/// reading as a form. The indent assumes a badge-sized [leading]; the mockup measures 48 pt and
/// [VControl.badgeSmall] plus the gap is 52.
class VOptionRow extends StatelessWidget {
  const VOptionRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.divider = true,
  });

  /// The icon circle. A [VIconBadge] at [VControl.badgeSmall]; the mockup draws 37 pt.
  final Widget? leading;

  /// The station name. Set at [VText.bodyL], which is the style named for exactly this.
  final String title;

  final String? subtitle;

  /// The right-hand value before the chevron: "448 m", "2,3 km", "vor 3 Tagen". It keeps its
  /// intrinsic width and the title gives way around it.
  final Widget? trailing;

  final VoidCallback? onTap;

  /// The hairline under the row. Off on the last row of a list.
  final bool divider;

  @override
  Widget build(BuildContext context) {
    Widget row = Padding(
      // Row pitch measures 47 pt with a 37 pt badge in it, so there are about 5 pt above and below.
      padding: const EdgeInsets.symmetric(vertical: VSpace.xs),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: VControl.touch),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: VSpace.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: VText.bodyL,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: VSpace.xs),
                    Text(
                      subtitle!,
                      style: VText.bodyS,
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
            const SizedBox(width: VSpace.s),
            const VChevron(),
          ],
        ),
      ),
    );

    if (onTap != null) {
      row = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashColor: VColors.pressedOverlay,
          highlightColor: VColors.pressedOverlay,
          child: row,
        ),
      );
    }

    if (!divider) return row;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row,
        VDivider(indent: leading == null ? 0 : VControl.badgeSmall + VSpace.md),
      ],
    );
  }
}
