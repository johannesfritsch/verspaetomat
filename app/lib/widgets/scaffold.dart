import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'header_scene.dart';
import 'marks.dart';

// ---------------------------------------------------------------------------
// The page frame
// ---------------------------------------------------------------------------
//
// A tab is three things stacked in one Stack: a painted band at the very top, a scrolling column
// over it, and a bar laid across the bottom. Only the middle one moves. That is the whole idea —
// the landscape belongs to the phone, not to the content, so it stays put while the cards travel
// over it, and the title that sets over it never drags a picture along behind it.
//
// The bar is an overlay, never a bottom inset. The design mockups let the last card run under it
// on purpose, and reserving a gap instead would put a strip of empty paper under every screen.
// What the scaffold owes the caller is room to scroll the last card clear of the bar, which is
// bottom padding, not a hole.

/// How loud a tinted button is.
enum VTintTone {
  /// Red type on a red tint, and it carries its own red glow. The second action of a screen —
  /// loud enough to be found, quiet enough that the primary still wins.
  red,

  /// Ink on grey. No glow. A neutral action with no opinion about itself.
  neutral,
}

/// A filled tinted button: a block of colour with the label cut out of it.
///
/// It sits between the primary button and a bare text link, and it exists because the design has
/// two actions that are neither. "Teilen" on Wir is the screen's second voice and a ghost button
/// disappeared next to the hero board; "In Karten anzeigen" in the ride sheet is a handoff to
/// another app and must not look like an app action at all.
///
/// The red one glows. That is not decoration: every red surface in this design spills light
/// downward, and a red button that did not would read as disabled.
///
/// The mockup draws the neutral one at 38 pt. It is built at 44 anyway — a control you can see is
/// a control someone will aim at, and the drawn height is the designer's, the hit target is iOS's.
class VTintButton extends StatelessWidget {
  const VTintButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.tone = VTintTone.red,
    this.expanded = true,
    this.size,
  });

  final String label;

  /// Null disables the button, which is the only disabled state it has.
  final VoidCallback? onTap;

  final IconData? icon;
  final VTintTone tone;

  /// Whether the button takes the full content width. Wir's "Teilen" does not — it keeps the left
  /// two thirds and leaves the rest of the paper to the handwritten note beside it.
  final bool expanded;

  /// The drawn height. Never allowed below [VControl.touch], whatever is asked for.
  final double? size;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final height = math.max(size ?? VControl.button, VControl.touch);
    final shape = BorderRadius.circular(VRadius.button);

    final Color fill;
    final Color ink;
    if (!enabled) {
      fill = VColors.disabledFill;
      ink = VColors.disabledInk;
    } else if (tone == VTintTone.red) {
      fill = VColors.redTintStrong;
      ink = VColors.red;
    } else {
      fill = VColors.greyFill;
      ink = VColors.ink;
    }

    final text = Text(
      label,
      style: VText.button.copyWith(color: ink),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    return Container(
      width: expanded ? double.infinity : null,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: shape,
        boxShadow:
            enabled && tone == VTintTone.red ? VShadow.glowButton : const <BoxShadow>[],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashColor: VColors.pressedOverlay,
          highlightColor: VColors.pressedOverlay,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: VSpace.m),
            child: Row(
              mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  // Both mockups draw a 20 pt icon box. There is no icon-size token at 20 except
                  // the chevron's, which is exactly that size.
                  Icon(icon, size: VControl.chevron, color: ink),
                  // The two mockups disagree — 13.8 pt on Wir, 8.3 pt in the sheet — and one
                  // button gets one gap. md (12) sits between them.
                  const SizedBox(width: VSpace.md),
                ],
                if (expanded) Flexible(child: text) else text,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A round filled button with one glyph in it: the ride sheet's collapse chevron.
///
/// It is drawn at 34 pt because that is what the sheet header has room for beside a 25 pt title,
/// and it is *built* inside a 44 pt box because a thumb aiming at a 34 pt circle misses. The grey
/// fill does the whole job of saying "control"; there is no border and no shadow, since the sheet
/// it sits on is already the raised surface.
class VCircleIconButton extends StatelessWidget {
  const VCircleIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = VControl.circleButton,
    this.fill,
  });

  final IconData icon;
  final VoidCallback onTap;

  /// The drawn diameter. The touch area around it is always at least [VControl.touch].
  final double size;

  /// Overrides the neutral fill, for the rare circle that has to carry a tint.
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final box = math.max(size, VControl.touch);
    // The glyph keeps the mockup's ratio to the circle (20 pt in 34) at any diameter.
    final glyph = VControl.chevron * (size / VControl.circleButton);
    return SizedBox(
      width: box,
      height: box,
      child: Center(
        child: SizedBox(
          width: size,
          height: size,
          child: Material(
            color: fill ?? VColors.greyFill,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              splashColor: VColors.pressedOverlay,
              highlightColor: VColors.pressedOverlay,
              child: Center(child: Icon(icon, size: glyph, color: VColors.ink)),
            ),
          ),
        ),
      ),
    );
  }
}

/// The settings gear, in the one shape both headers want: a 20 pt glyph with 44 pt of touch
/// around it, top-aligned so it hangs off the top of the band rather than floating beside a
/// title whose height nobody controls.
class _VSettingsButton extends StatelessWidget {
  const _VSettingsButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: VControl.touch,
      height: VControl.touch,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          splashColor: VColors.pressedOverlay,
          highlightColor: VColors.pressedOverlay,
          child: const Center(
            // The gear measures 19.8–20.3 pt; VControl.chevron is the only 20 in the set.
            child: Icon(Icons.settings_outlined, size: VControl.chevron, color: VColors.ink),
          ),
        ),
      ),
    );
  }
}

/// Home's masthead: the one place in the app where the product says its own name.
///
/// Every other screen is about the user's minutes; this row is about whose minutes they are being
/// counted by. It appears on Home and nowhere else, which is why the wordmark and the tagline are
/// written into the widget rather than passed in — there is no second masthead to configure.
///
/// The [caption] is the line the running app needs and the design mockups do not show: which
/// Stellwerk the build is talking to, or that the location is simulated. It sits under the tagline
/// rather than beside it, because it is a note about the build and must never crowd the name.
class VAppMasthead extends StatelessWidget {
  const VAppMasthead({super.key, this.onSettings, this.caption});

  final VoidCallback? onSettings;

  /// A development or diagnostics line: the Stellwerk the app is pointed at, a simulated location.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const VAppMark(),
        // Measured 13.8 pt; md (12) is the nearest token.
        const SizedBox(width: VSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Verspätomat',
                style: VText.wordmark,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'Verspätung sammeln. Gutes tun.',
                style: VText.tagline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (caption != null) ...[
                const SizedBox(height: VSpace.xs),
                Text(
                  caption!,
                  style: VText.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        if (onSettings != null) ...[
          const SizedBox(width: VSpace.s),
          _VSettingsButton(onTap: onSettings),
        ],
      ],
    );
  }
}

/// A tab's title block: the big word and the quiet lines under it.
///
/// Sub-screens announce themselves with a small-caps eyebrow over a title; a tab does the
/// opposite, because a tab is a place you chose to be and does not need to justify itself. So the
/// title comes first and everything else is a footnote to it.
///
/// There are two footnote slots and they are not the same thing. [subtitle] is a fact — "18.420
/// Fahrgäste", "4 Fälle gesammelt" — and when a [tagline] follows it, it keeps full ink, because
/// the number is what the reader came for. [tagline] is the promise under the fact and stays
/// quiet. A header with only a subtitle has no number to protect, so that single line is quiet
/// too.
///
/// The gear is top-aligned rather than centred on the title: the title is 30 pt and wraps, and a
/// gear that moved when a word wrapped would look broken.
class VTabHeader extends StatelessWidget {
  const VTabHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.tagline,
    this.trailing,
    this.onSettings,
    this.narrow = false,
  });

  final String title;

  /// The line directly under the title. Full ink when a [tagline] follows it.
  final String? subtitle;

  /// A second, quieter line. Wir is the only screen that uses both.
  final String? tagline;

  /// Something of the caller's between the text and the gear: a badge, a spinner while a standing
  /// reload runs.
  final Widget? trailing;

  final VoidCallback? onSettings;

  /// Keeps the text column to the left of the page. On a tab with the illustrated band behind it
  /// the right third belongs to the landscape, and a subtitle running the full width sets straight
  /// across the train.
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final hasTagline = tagline != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: narrow ? _narrowFlex : _fullFlex,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: VText.h1, maxLines: 2, overflow: TextOverflow.ellipsis),
              if (subtitle != null) ...[
                const SizedBox(height: VSpace.xs),
                Text(
                  subtitle!,
                  style: hasTagline ? VText.bodyL : VText.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (hasTagline) ...[
                const SizedBox(height: VSpace.xs),
                Text(
                  tagline!,
                  style: VText.body,
                  maxLines: 2,
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
        // The rest of the row belongs to the landscape, and nothing is drawn into it.
        if (narrow) const Spacer(flex: _fullFlex - _narrowFlex),
        if (onSettings != null) ...[
          const SizedBox(width: VSpace.s),
          _VSettingsButton(onTap: onSettings),
        ],
      ],
    );
  }

  static const _fullFlex = 100;
  static const _narrowFlex = 66;
}

/// A whole tab page.
///
/// Three layers, and only the middle one moves:
///
///   the SCENE   [VHeaderScene], drawn behind the [header] and exactly as tall as it, bleeding
///               out past the page gutter to both screen edges. It scrolls with the header,
///               because it belongs to it. Pinned to the screen instead, it showed through every
///               gap between two cards, and a landscape flickering between cards reads as a
///               rendering fault rather than as a view out of a window.
///   the CONTENT a scrolling column: the [header] first, then the [children] with [VSpace.md]
///               between them, on the page's own ground.
///   the BOTTOM  the caller's bar, laid across the bottom. An overlay, not an inset — the design
///               lets the last card run under it, and the scaffold pays for that with bottom
///               padding deep enough to scroll that card clear.
///
/// Every tab wears a band and [art] says which drawing it is: the plain hills on Home, and one
/// apiece for Anträge, Wir and Ich. That is why a tab's title starts halfway down a hillside
/// rather than near the top of the screen.
class VTabScaffold extends StatelessWidget {
  const VTabScaffold({
    super.key,
    required this.header,
    required this.children,
    this.scene = true,
    this.art = VHeaderSceneArt.landscape,
    this.padding,
    this.bottom,
    this.onRefresh,
  });

  /// The title block. [VTabHeader], or on Home a column of masthead and header.
  final Widget header;

  /// The blocks of the page, stacked with [VSpace.md] between them.
  final List<Widget> children;

  /// Whether the illustrated band is drawn behind the header.
  final bool scene;

  /// Which drawing the band carries. Each tab has one of its own; Home keeps the plain hills.
  final VHeaderSceneArt art;

  /// The page gutter. The default is the 16 pt one every card on every tab uses.
  final EdgeInsets? padding;

  /// The bottom navigation bar, which the scaffold lays over the content but never builds.
  final Widget? bottom;

  /// Pull to reload. The spinner comes down over the scene, which is the right place for it:
  /// what reloads is the cards, and the landscape behind them never changes.
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context);
    final pad = padding ?? const EdgeInsets.fromLTRB(VSpace.page, 0, VSpace.page, VSpace.m);

    // Room to scroll the last card out from under the bar. The bar's own height plus the home
    // indicator, because the bar sits over the SafeArea rather than above it.
    final barRoom = bottom == null ? 0.0 : VControl.tabBar + inset.bottom;

    final top = inset.top + pad.top + VSpace.s;

    // The scene is laid behind the header and sized by it. The negative insets take it back out
    // to the screen edges and up under the status bar, past the gutter the content sits in.
    final headerBlock = !scene
        ? header
        : Stack(
            // Clip.none, or the Stack trims the scene back to the content width and the drawing
            // stops one page gutter short of the screen edge — a strip of bare paper down the
            // right, which is exactly the side the train runs out of.
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: -pad.left,
                right: -pad.right,
                top: -top,
                bottom: -VSpace.l,
                child: ClipRect(child: VHeaderScene(art: art)),
              ),
              // The floor is on the header, not on the scene, because the scene is sized by the
              // header: a tab whose title block is one short word would otherwise squeeze the
              // landscape into a letterbox.
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: _minHeaderHeight),
                child: header,
              ),
            ],
          );

    final blocks = <Widget>[headerBlock];
    for (final child in children) {
      blocks
        ..add(const SizedBox(height: VSpace.md))
        ..add(child);
    }

    return Scaffold(
      backgroundColor: VColors.paper,
      body: Stack(
        children: [
          Positioned.fill(
            child: _refreshable(
              context,
              SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(
                  left: pad.left,
                  right: pad.right,
                  // The header sits a little below the status bar, not against it.
                  top: top,
                  bottom: pad.bottom + barRoom,
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: blocks),
              ),
            ),
          ),
          if (bottom != null)
            Positioned(left: 0, right: 0, bottom: 0, child: bottom!),
        ],
      ),
    );
  }

  /// How tall a header with a landscape behind it has to be, whatever it holds.
  static const _minHeaderHeight = 150.0;

  Widget _refreshable(BuildContext context, Widget child) {
    final refresh = onRefresh;
    if (refresh == null) return child;
    return RefreshIndicator(
      onRefresh: refresh,
      color: VColors.red,
      backgroundColor: VColors.paperElevated,
      // Clear of the status bar and of the title, so the spinner lands on the hillside rather
      // than on top of the word it is reloading.
      edgeOffset: MediaQuery.paddingOf(context).top + VSpace.s,
      child: child,
    );
  }
}
