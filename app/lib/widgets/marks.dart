import 'package:flutter/material.dart';

import '../theme/tokens.dart';

// ---------------------------------------------------------------------------
// The marks
// ---------------------------------------------------------------------------
//
// Everything in this file is small, identifying, and never interactive: a pill, a line badge, a
// delay, a tinted icon circle, an operator avatar, the heart, the app's own tile. A mark labels
// something that is already on the screen — it is never the thing itself. So none of them takes
// an onTap, none of them sets a margin, and none of them decides its own place: the row or card
// around it does. That is also why they are all as small as they are allowed to be. Where a mark
// has to become a control, the control wraps it and brings the 44 pt of touch area with it.
//
// No railway livery is drawn anywhere in here. See [VOperatorMark] for why.

/// The glyph inside a tinted circle: [VControl.badgeIcon] in a [VControl.badge], which is 44 %.
/// The ratio is what is fixed, not the size, so a 40 pt badge gets a proportionally smaller glyph
/// instead of the same glyph in more air.
/// How much of a badge the glyph fills.
///
/// Not one ratio: Material sizes an icon by its *box*, and the drawn ink inside that box is
/// roughly five sixths of it, so the token ratio alone lands every glyph visibly smaller than the
/// mockups draw it. The small badge takes proportionally more, because a 40 pt circle with a
/// 17 pt glyph in it reads as an empty ring.
double _glyphRatio(double size) => size <= VControl.badgeSmall ? 0.60 : 0.50;

// ---------------------------------------------------------------------------
// Pills
// ---------------------------------------------------------------------------

/// What a pill means, and on what ground it sits.
enum VPillTone {
  /// A quiet tag on a white surface: what a stop is, what kind of thing a row is.
  neutral,

  /// A delay, a rejection, anything the railway did to you.
  red,

  /// Ready, on time, done. The only two meanings green is allowed to carry.
  green,

  /// The one pill on the screen that is the point of the screen — inverted, so it reads before
  /// the quiet ones beside it.
  ink,

  /// A pill standing on a board rather than on paper.
  onDark,
}

/// Stadium or flat-sided.
enum VPillShape {
  /// Fully rounded. A status, a line, a figure — anything that reads as a value.
  stadium,

  /// A 6 pt corner. A word that classifies the row it is in ("Zustieg", "Umstieg"). The flat side
  /// is the whole difference between a label and a value, and it is worth keeping.
  flat,
}

/// The small filled badge that carries one short label, and at most one glyph in front of it.
///
/// One widget covers every pill in the app because the differences between them are two enums
/// wide: a tint and a corner. Splitting them into separate widgets would mean a separate place to
/// get the padding wrong each time.
///
/// The height follows the content rather than the caller: a pill carrying a glyph, and any
/// flat-sided tag, stands at [VControl.pillTall]; a bare stadium pill stands at [VControl.pill].
/// Both are measured off the mockups, and neither is a decision a call site should be making.
class VPill extends StatelessWidget {
  const VPill(
    this.label, {
    super.key,
    this.icon,
    this.tone = VPillTone.neutral,
    this.shape = VPillShape.stadium,
    this.tabular = false,
  });

  final String label;

  /// Set only where the glyph says something the word does not: a clock on "Bereit", an envelope
  /// on "Eingereicht". A decorative glyph in a 22 pt pill is just noise at 22 pt.
  final IconData? icon;

  final VPillTone tone;
  final VPillShape shape;

  /// On for a label that is mostly figures, so a column of pills lines up. Off for words, where
  /// tabular figures leave holes around a "4,50 €".
  final bool tabular;

  Color get _fill => switch (tone) {
        VPillTone.neutral => VColors.greyPill,
        VPillTone.red => VColors.redTint,
        VPillTone.green => VColors.greenTint,
        // One step off ink, not ink: the dark tag in the ride sheet measures #1C2230 exactly,
        // while the dark line badge beside it is true ink. Two dark tones, both on purpose.
        VPillTone.ink => VColors.surfaceDarkAlt,
        // The only translucent white in the palette. It is named for the progress track it was
        // cut for, but it is the veil that works on the dark board and on the red one alike.
        VPillTone.onDark => VColors.trackOnRed,
      };

  Color get _ink => switch (tone) {
        VPillTone.neutral => VColors.ink,
        VPillTone.red => VColors.red,
        VPillTone.green => VColors.green,
        VPillTone.ink => VColors.inkOnDark,
        VPillTone.onDark => VColors.inkOnDark,
      };

  @override
  Widget build(BuildContext context) {
    final style = vPillLabel(_ink, tabular: tabular);
    final tall = shape == VPillShape.flat || icon != null;

    return Container(
      height: tall ? VControl.pillTall : VControl.pill,
      // Measured 6.9–7.8 pt on the stadium pills and 8.8–10 pt on the flat tags. The flat one
      // keeps the wider gutter: it is a word, and it needs the room to stop looking clipped.
      padding: EdgeInsets.symmetric(
        horizontal: shape == VPillShape.stadium ? VSpace.s : VSpace.md,
      ),
      decoration: BoxDecoration(
        color: _fill,
        borderRadius: BorderRadius.circular(
          shape == VPillShape.stadium ? VRadius.full : VRadius.sm,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            // One line box of the label's own type. The glyph then matches the word beside it at
            // every tone instead of being a number someone picked once.
            Icon(icon, size: _lineBox(style), color: _ink),
            const SizedBox(width: VSpace.s),
          ],
          Flexible(
            child: Text(label, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// The label style every pill in this file shares. [VText.pill] is tabular by default, so the
/// proportional case is the one that has to be asked for.
TextStyle vPillLabel(Color color, {bool tabular = false}) => tabular
    ? VText.pill.copyWith(color: color)
    : VText.pill.copyWith(
        color: color,
        fontFeatures: const [FontFeature.proportionalFigures()],
      );

double _lineBox(TextStyle style) => (style.fontSize ?? VControl.chevronSmall) * (style.height ?? 1);

// ---------------------------------------------------------------------------
// Lines
// ---------------------------------------------------------------------------

/// The product class a line belongs to. It decides the badge's colour, and it is the one place in
/// the app where a colour is not an app state: RE 7 is not more urgent than S 6, it is a different
/// kind of train. Red and green are fixed by the mockups; the rest take identity hues, the same
/// ones an operator gets, because that is what a product class is.
enum VLineClass { regional, sBahn, longDistance, bus, tram, unknown }

/// A line number, set the way a departure board sets it.
///
/// Two looks, and the difference between them is the point. The tinted one names a line in a list
/// of past rides: small, quiet, colour-coded by class. The dark one names the train you are
/// actually on, so it is inverted, set in [VText.badge] rather than [VText.pill], and it does not
/// take a class tint at all — there is only one of it on the screen and it does not need to be
/// told apart from anything.
/// Which class a line number belongs to, read off the number itself.
///
/// The backend sends a line as a string and nothing else, so the class has to be inferred. The
/// prefixes are the German ones and they are unambiguous in practice: an S is an S-Bahn, an RE or
/// an RB is regional, IC/ICE/EC/TGV/NJ are long distance. SEV is a rail replacement bus, which the
/// product cares about specifically (docs/28) — it runs under a train's line number and has to
/// keep looking like the bus it is.
VLineClass vLineClassOf(String line) {
  final l = line.trim().toUpperCase();
  if (l.isEmpty) return VLineClass.unknown;
  if (l.startsWith('SEV') || l.startsWith('BUS')) return VLineClass.bus;
  if (l.startsWith('ICE') || l.startsWith('IC') || l.startsWith('EC') ||
      l.startsWith('TGV') || l.startsWith('NJ') || l.startsWith('RJ')) {
    return VLineClass.longDistance;
  }
  if (l.startsWith('S')) return VLineClass.sBahn;
  if (l.startsWith('RE') || l.startsWith('RB') || l.startsWith('MEX')) return VLineClass.regional;
  if (l.startsWith('U') || l.startsWith('T') || l.startsWith('STR')) return VLineClass.tram;
  return VLineClass.unknown;
}

/// How loud a line badge is.
///
/// Three, because the mockups use three and each one means something different. The colour is the
/// line's class in all of them: colour on a line badge is identity, and a cancelled S-Bahn is
/// still an S-Bahn.
enum VLineBadgeLook {
  /// The class colour at a tint, with the class colour as ink. A line in a list.
  tint,

  /// The class colour filled, with white ink. The train a card is *about* — the share card's own
  /// journey. One per card, or it stops meaning "this one".
  solid,

  /// Ink filled, white ink, and a size larger. The train in hand, which on a screen full of
  /// tinted pills is the one thing that reads as now.
  dark,
}

class VLineBadge extends StatelessWidget {
  const VLineBadge(
    this.line, {
    super.key,
    this.cls = VLineClass.regional,
    this.look = VLineBadgeLook.tint,
  });

  final String line;
  final VLineClass cls;
  final VLineBadgeLook look;

  Color get _fill => switch (cls) {
        VLineClass.regional => VColors.redTint,
        VLineClass.sBahn => VColors.greenTint,
        VLineClass.longDistance => VColors.blueDeepTint,
        VLineClass.bus => VColors.tealTint,
        VLineClass.tram => VColors.blueTint,
        VLineClass.unknown => VColors.greyPill,
      };

  Color get _ink => switch (cls) {
        VLineClass.regional => VColors.red,
        VLineClass.sBahn => VColors.green,
        VLineClass.longDistance => VColors.blueDeep,
        VLineClass.bus => VColors.teal,
        VLineClass.tram => VColors.blue,
        VLineClass.unknown => VColors.ink2,
      };

  @override
  Widget build(BuildContext context) {
    if (look == VLineBadgeLook.dark) {
      return Container(
        // Measured 26.3 pt tall, which no control token carries. The padding makes the height
        // instead, so the badge grows with its own type rather than clipping it.
        padding: const EdgeInsets.symmetric(horizontal: VSpace.md, vertical: VSpace.xs),
        decoration: BoxDecoration(
          color: VColors.ink,
          borderRadius: BorderRadius.circular(VRadius.sm),
        ),
        child: Text(
          line,
          style: VText.badge.copyWith(color: VColors.inkOnDark),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    final solid = look == VLineBadgeLook.solid;
    return Container(
      height: VControl.pill,
      padding: const EdgeInsets.symmetric(horizontal: VSpace.s),
      decoration: BoxDecoration(
        color: solid ? _ink : _fill,
        // The solid one is a block with a name cut out of it, so it takes the card corner rather
        // than the pill's stadium — a filled stadium at this size reads as a button.
        borderRadius: BorderRadius.circular(solid ? VRadius.sm : VRadius.full),
      ),
      // Center with a width factor, not `alignment:` on the Container. A Container that is given
      // an alignment and no width takes every point it is offered, and the badge came out as wide
      // as the row it sat in.
      child: Center(
        widthFactor: 1,
        child: Text(
          line,
          style: vPillLabel(solid ? VColors.inkOnDark : _ink, tabular: true),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// The delay, with its unit, as a red pill on the right of a ride row.
///
/// The whole label is red, not just the sign: at 11 pt a two-colour label reads as a mistake. The
/// figures are tabular so that a column of these lines up on the digits, which is the only reason
/// the pill exists rather than a line of text.
class VDelayPill extends StatelessWidget {
  const VDelayPill(this.minutes, {super.key, this.unit = true, this.cancelled = false});

  final int minutes;

  /// Off where the column header already says "min".
  final bool unit;

  /// A cancelled train has no delay — a figure would be a lie, so the figure goes.
  final bool cancelled;

  @override
  Widget build(BuildContext context) {
    final label = cancelled
        ? 'Ausfall'
        : '${minutes < 0 ? '−' : '+'}${minutes.abs()}${unit ? ' min' : ''}';
    // The mockup drops "Ausfall" into a grey note under the route instead of into the pill. Here
    // it keeps the red, because wherever this widget is used the pill slot is the delay slot.
    return VPill(label, tone: VPillTone.red, tabular: !cancelled);
  }
}

// ---------------------------------------------------------------------------
// Badges and avatars
// ---------------------------------------------------------------------------

/// The tint an icon circle carries. Red and green mean something; the rest are identity — an
/// operator, a partner NGO — and they never stand for an app state.
enum VBadgeTone { red, green, teal, blue, blueDeep, greenBright, neutral }

/// A tinted circle with a filled glyph in it.
///
/// This is the device the redesign uses instead of a rule across the page: a block does not get a
/// heading with a line under it, it gets a mark at its left edge and the eye finds the block by
/// the colour. It is the most repeated object in the app, which is why the glyph ratio is baked in
/// rather than passed: two badges of different sizes still have to look like the same thing.
class VIconBadge extends StatelessWidget {
  const VIconBadge({
    super.key,
    required this.icon,
    this.tone = VBadgeTone.red,
    this.size = VControl.badge,
    this.iconSize,
  });

  final IconData icon;
  final VBadgeTone tone;

  /// [VControl.badge] heads a block; [VControl.badgeSmall] heads a row in a list.
  final double size;

  /// Only for a glyph whose drawn ink sits far off its box — most Material icons do not.
  final double? iconSize;

  Color get _fill => switch (tone) {
        VBadgeTone.red => VColors.redTint,
        VBadgeTone.green => VColors.greenTint,
        VBadgeTone.teal => VColors.tealTint,
        VBadgeTone.blue => VColors.blueTint,
        VBadgeTone.blueDeep => VColors.blueDeepTint,
        VBadgeTone.greenBright => VColors.greenBrightTint,
        VBadgeTone.neutral => VColors.greyCircle,
      };

  Color get _ink => switch (tone) {
        VBadgeTone.red => VColors.red,
        VBadgeTone.green => VColors.green,
        VBadgeTone.teal => VColors.teal,
        VBadgeTone.blue => VColors.blue,
        VBadgeTone.blueDeep => VColors.blueDeep,
        VBadgeTone.greenBright => VColors.greenBright,
        VBadgeTone.neutral => VColors.ink2,
      };

  @override
  Widget build(BuildContext context) => _disc(
        fill: _fill,
        size: size,
        child: Icon(icon, size: iconSize ?? size * _glyphRatio(size), color: _ink),
      );
}

Widget _disc({required Color fill, required double size, required Widget child}) => Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      child: child,
    );

/// The avatar on a claim card: which railway the case is against.
///
/// It ships no railway artwork, and that is a decision rather than an omission. The DB mark is a
/// registered trademark, and this app files claims *against* railways — an avatar in an operator's
/// livery would say the operator has something to do with the app, which is untrue, and it would
/// say it on the one screen where the reader is deciding whether to trust us. So an operator gets
/// a tone and a glyph, both derived from its name, and nothing that could be mistaken for a logo.
///
/// [logo] is the hook for the day a mark arrives as managed data with a licence attached, exactly
/// the way `NgoLogo` in widgets/ticket.dart already takes a data URI from the server. Nothing in
/// the app passes it today.
class VOperatorMark extends StatelessWidget {
  const VOperatorMark(this.operatorName, {super.key, this.size = VControl.badgeSmall, this.logo});

  final String operatorName;
  final double size;

  /// Artwork from managed data, drawn inside the circle in place of the glyph.
  final Widget? logo;

  /// The tone and glyph for a name. Unknown operators fall to a neutral circle with a train in it,
  /// which is true of every railway and flattering to none.
  static (VBadgeTone, IconData) look(String operatorName) {
    final n = operatorName.toLowerCase();
    if (n.contains('nordwestbahn')) return (VBadgeTone.teal, Icons.train);
    if (n.contains('transdev')) return (VBadgeTone.blueDeep, Icons.waves);
    // Not a company at all but a shared desk several railways answer through.
    if (n.contains('servicecenter') || n.contains('fahrgastrechte')) {
      return (VBadgeTone.neutral, Icons.support_agent);
    }
    return (VBadgeTone.neutral, Icons.train);
  }

  @override
  Widget build(BuildContext context) {
    final (tone, icon) = look(operatorName);
    if (logo == null) return VIconBadge(icon: icon, tone: tone, size: size);
    return _disc(
      fill: VColors.greyCircle,
      size: size,
      // Wider than a glyph: a wordmark is horizontal and needs the width a pictogram does not.
      child: SizedBox(width: size * 0.62, height: size * 0.62, child: Center(child: logo)),
    );
  }
}

/// The tiny mark under a station name in the ride timeline: who runs the train calling here.
///
/// The mockup draws the DB lozenge here — red outline, red letters, the real trade dress. This
/// draws a neutral outlined tag with a short code in it instead, for the reason set out on
/// [VOperatorMark]: the shape and the colour together are the trademark, and a claim app must not
/// wear one. The code is derived, never stored, so an operator nobody has heard of still gets a
/// mark rather than a blank.
class VOperatorTag extends StatelessWidget {
  const VOperatorTag(this.operatorName, {super.key});

  final String operatorName;

  /// "Deutsche Bahn" → DB, "NordWestBahn" → NWB, "Abellio" → ABE. Four characters at most: the tag
  /// is 18 pt wide and a fifth one would set it wider than the station name it hangs under.
  static String shortCode(String operatorName) {
    final name = operatorName.trim();
    if (name.isEmpty) return '–';
    final words = name.split(RegExp(r'[\s\-.]+')).where((w) => w.isNotEmpty).toList();
    // A name of nothing but separators passes the isEmpty guard above and then leaves no words at
    // all. "—" is the same fallback the empty branch uses.
    if (words.isEmpty) return '–';
    if (words.length > 1) {
      return _clip(words.map((w) => w.substring(0, 1)).join().toUpperCase());
    }
    final word = words.first;
    final caps = RegExp(r'[A-ZÄÖÜ]').allMatches(word).map((m) => m[0]!).join();
    if (caps.length >= 2) return _clip(caps);
    return _clip(word.toUpperCase(), max: 3);
  }

  static String _clip(String s, {int max = 4}) => s.length <= max ? s : s.substring(0, max);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: VSpace.xs),
        decoration: BoxDecoration(
          // Measured at 1.4 pt in the mockup, where no token lives. Twice the hairline is the
          // nearest the token set has, and it holds at this size.
          border: Border.all(color: VColors.ink3, width: VControl.hairline * 2),
          borderRadius: BorderRadius.circular(VRadius.bar),
        ),
        child: Text(
          shortCode(operatorName),
          // The smallest label in the app. VText.micro is 9 pt against a measured 8 pt: below
          // this the code stops being readable at arm's length.
          style: VText.micro.copyWith(color: VColors.ink2, fontWeight: FontWeight.w700),
          maxLines: 1,
        ),
      );
}

// ---------------------------------------------------------------------------
// The two drawn marks
// ---------------------------------------------------------------------------

/// The heart.
///
/// Drawn as a path, not set as an emoji and not borrowed from Icons.favorite: the app's heart has
/// a longer point than Material's, it appears at four sizes and four tints across two screens, and
/// an emoji would render as somebody else's artwork on every platform.
///
/// The default is [VColors.redBright]. The mockups tint it three ways (#ED6066 in the Wir header,
/// #FB6264 on the board, #FDBBBF on the footer card) and not one of those is a token; callers that
/// need the pale one pass it rather than the palette growing three near-reds.
class VHeartMark extends StatelessWidget {
  const VHeartMark({super.key, this.size = VControl.badgeIcon, this.color = VColors.redBright});

  /// The width. The heart is drawn a little wider than it is tall, which is what makes it read as
  /// a heart rather than as a spade.
  final double size;

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size * 0.88,
        child: CustomPaint(painter: _HeartPainter(color)),
      );
}

class _HeartPainter extends CustomPainter {
  const _HeartPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    double x(double u) => u * w;
    double y(double v) => v * h;

    final path = Path()
      ..moveTo(x(0.5), y(1))
      ..cubicTo(x(0.18), y(0.78), x(0), y(0.55), x(0), y(0.33))
      ..cubicTo(x(0), y(0.12), x(0.15), y(0), x(0.29), y(0))
      ..cubicTo(x(0.40), y(0), x(0.47), y(0.06), x(0.5), y(0.14))
      ..cubicTo(x(0.53), y(0.06), x(0.60), y(0), x(0.71), y(0))
      ..cubicTo(x(0.85), y(0), x(1), y(0.12), x(1), y(0.33))
      ..cubicTo(x(1), y(0.55), x(0.82), y(0.78), x(0.5), y(1))
      ..close();

    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_HeartPainter old) => old.color != color;
}

/// The app's own tile, drawn rather than shipped as an image.
///
/// It appears in the masthead, on the share card and in sheet headers, at sizes that do not agree,
/// and an asset would either be resampled or arrive in three copies. Drawn, it also follows the
/// tokens: when the red moves, the mark moves with it.
///
/// [VRadius.sm] is the corner at the default size and it scales with the tile, so a 72 pt mark is
/// twice the mark and not a differently-shaped one. The corner is a plain circular arc, not an iOS
/// continuous superellipse — this is the app *inside* the app, not the icon on the home screen.
class VAppMark extends StatelessWidget {
  const VAppMark({super.key, this.size = _base, this.mono = false});

  static const double _base = 36;

  final double size;

  /// The ink tile, for a sheet header or anywhere the red would compete with a nearby action.
  final bool mono;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // redBright, not red: this is the "*this one*" red, and the mark is what it was named
          // for. Measured #F72123 in the mockup.
          color: mono ? VColors.ink : VColors.redBright,
          borderRadius: BorderRadius.circular(VRadius.sm * size / _base),
        ),
        child: Icon(Icons.train, size: size * 0.58, color: VColors.inkOnDark),
      );
}
