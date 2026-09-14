import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'marks.dart';
import 'surfaces.dart';

// ---------------------------------------------------------------------------
// The ride sheet's timeline and its neighbours
// ---------------------------------------------------------------------------
//
// The sheet you see while the train is moving is the densest screen in the app: a spine of stops,
// a time and a signed delay per stop, and — under DANACH — the same object again, told quietly,
// for the train you have not boarded yet. Everything here is built so those two tellings are one
// widget with two tones rather than two widgets that drift apart.
//
// The one number that carries meaning in this file is the signed delay. It is signed on every row,
// including the on-time one: a column where some rows say "+3" and others say nothing is a column
// you have to read twice, and "+0" is the cheapest way to say "we checked".

/// Geometry of the gutter that holds the spine. Not tokens, because no token describes "a column
/// wide enough for a 13 pt ring with its halo around it"; every other measure in this file is one.
const double _gutterWidth = 28;
const double _dotSize = 13;
const double _spineWidth = 2.2;

/// How loud the line is.
enum VTimelineTone {
  /// The train you are on. Red spine, red rings, haloes on the stops that matter.
  live,

  /// The train you have not boarded yet, under DANACH. The same line with the volume down.
  quiet,
}

/// Which surface colour shows through a hollow ring. Both timelines sit on white — the sheet and
/// the card — so there is one answer, and it is named rather than repeated.
const Color _ringInterior = VColors.paperElevated;

/// One stop on a timeline.
///
/// A value class, not a widget: [VStopTimeline] has to know about its neighbours to decide where
/// the spine starts and stops, and a list of widgets cannot be asked that.
class VStop {
  const VStop({
    required this.station,
    required this.time,
    this.delta,
    this.tag,
    this.bold = false,
    this.halo = false,
    this.mark,
  });

  /// The station, as the railway writes it. Long ones ellipsize; they never wrap.
  final String station;

  /// The time this stop is called at, already formatted ("10:41").
  final String time;

  /// Minutes off the plan. Null means unknown, which is not the same as zero — an unknown delay
  /// prints no second line, a zero prints "+0".
  final int? delta;

  /// What this stop is to the passenger: "Zustieg", "Umstieg", "Ziel".
  final String? tag;

  /// The stop the screen is about — where you get off. It sets the name, the time and the tag
  /// heavier, and it is what makes the dot the current one.
  final bool bold;

  /// A soft disc behind the dot. Reserved for the two stops a passenger actually has to act at:
  /// where they boarded and where they change. It is ignored on the quiet tone, which has no
  /// tinting anywhere.
  final bool halo;

  /// The operator's mark, set under the station name. The timeline does not know what a railway
  /// looks like, so the caller hands it one.
  final Widget? mark;
}

/// The stops of one train as a single vertical line.
///
/// The spine runs between the first and the last dot centre and no further. A line that overshoots
/// the last stop promises a stop that is not there, which on a timeline is a lie rather than a
/// flourish — so each row draws only its own half-segments and the ends simply have none.
class VStopTimeline extends StatelessWidget {
  const VStopTimeline({super.key, required this.stops, this.tone = VTimelineTone.live});

  final List<VStop> stops;
  final VTimelineTone tone;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < stops.length; i++)
            _StopRow(
              stop: stops[i],
              tone: tone,
              first: i == 0,
              last: i == stops.length - 1,
            ),
        ],
      );
}

/// The height of a station-name line, derived from the token rather than guessed, because the dot
/// has to sit on that line's centre and not on the row's.
double get _nameLineHeight => VText.bodyL.fontSize! * VText.bodyL.height!;

class _StopRow extends StatelessWidget {
  const _StopRow({
    required this.stop,
    required this.tone,
    required this.first,
    required this.last,
  });

  final VStop stop;
  final VTimelineTone tone;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final line = _nameLineHeight;
    final dotCentre = VSpace.md + line / 2;
    final nameStyle =
        stop.bold ? VText.bodyL.copyWith(fontWeight: FontWeight.w700) : VText.bodyL;

    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: _gutterWidth,
          child: _StopGutter(
            dotCentre: dotCentre,
            tone: tone,
            current: stop.bold,
            halo: stop.halo && tone == VTimelineTone.live,
            first: first,
            last: last,
          ),
        ),
        Padding(
          // The operator mark eats into the row's own bottom padding instead of adding to it;
          // otherwise a mark row stands a third taller than its neighbours and the pitch breaks.
          padding: EdgeInsets.only(
            left: _gutterWidth + VSpace.md,
            top: VSpace.md,
            bottom: stop.mark == null ? VSpace.md : VSpace.xs,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: line,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          stop.station,
                          style: nameStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (stop.mark != null)
                      Padding(padding: const EdgeInsets.only(top: VSpace.xs), child: stop.mark!),
                  ],
                ),
              ),
              if (stop.tag != null) ...[
                const SizedBox(width: VSpace.s),
                SizedBox(
                  height: line,
                  child: Center(child: _StopTag(stop.tag!, dark: stop.bold)),
                ),
              ],
              const SizedBox(width: VSpace.md),
              VStopTime(time: stop.time, delta: stop.delta, bold: stop.bold),
            ],
          ),
        ),
      ],
    );
  }
}

class _StopGutter extends StatelessWidget {
  const _StopGutter({
    required this.dotCentre,
    required this.tone,
    required this.current,
    required this.halo,
    required this.first,
    required this.last,
  });

  final double dotCentre;
  final VTimelineTone tone;
  final bool current;
  final bool halo;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final spine = Center(
      child: Container(width: _spineWidth, color: _toneColor(tone)),
    );
    return Stack(
      children: [
        if (halo)
          Positioned(
            left: 0,
            top: dotCentre - _gutterWidth / 2,
            width: _gutterWidth,
            height: _gutterWidth,
            child: const VStopHalo(size: _gutterWidth),
          ),
        Column(
          children: [
            SizedBox(
              height: dotCentre - _dotSize / 2,
              child: first ? null : spine,
            ),
            VStopDot(current: current, tone: tone),
            Expanded(child: last ? const SizedBox.shrink() : spine),
          ],
        ),
      ],
    );
  }
}

/// The spine's colour. The quiet leg is ink, not grey: it is the journey you have not started
/// yet, not a disabled one, and at ink3 it read as switched off.
Color _toneColor(VTimelineTone tone) =>
    tone == VTimelineTone.live ? VColors.red : VColors.surfaceDark;

/// One stop on the spine: a ring with the surface showing through it.
///
/// Hollow is the default because a timeline is a plan, not a record — a filled dot would say "this
/// one has happened" about every stop at once. The current stop gets a heavier ring and a centre,
/// which is the only difference the eye needs to find where it gets off.
class VStopDot extends StatelessWidget {
  const VStopDot({super.key, this.current = false, this.tone = VTimelineTone.live});

  final bool current;
  final VTimelineTone tone;

  @override
  Widget build(BuildContext context) {
    final color = _toneColor(tone);
    // 3 / 2.2 pt strokes and a 4 pt centre: ring weights, which no token describes.
    final stroke = current ? 3.0 : 2.2;
    return Container(
      width: _dotSize,
      height: _dotSize,
      decoration: BoxDecoration(
        color: _ringInterior,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: stroke),
      ),
      child: current
          ? Center(
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            )
          : null,
    );
  }
}

/// The soft disc behind a dot.
///
/// It marks the two stops a passenger has to do something at, and it does it without a border, a
/// pill or a second colour — the tint fades out rather than ending, so it reads as attention on
/// the dot rather than as another object beside it.
class VStopHalo extends StatelessWidget {
  const VStopHalo({super.key, this.size = _gutterWidth});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                VColors.redTintSoft,
                VColors.redTintSoft,
                // The same tint at zero alpha, so the disc fades out instead of ending on a ring.
                VColors.redTintSoft.withAlpha(0),
              ],
              stops: const [0, 0.6, 1],
            ),
          ),
        ),
      );
}

/// The time a train calls at a stop, with how far off the plan that is.
///
/// Two lines, right-aligned to the same edge: the times line up because the column is right-aligned,
/// not because the figures are padded. The delay always carries a sign, including "+0" — the column
/// means "how late", and a blank in it would read as "unknown" rather than "on time".
class VStopTime extends StatelessWidget {
  const VStopTime({super.key, required this.time, this.delta, this.bold = false});

  final String time;

  /// Minutes off the plan; null prints no second line at all.
  final int? delta;

  final bool bold;

  @override
  Widget build(BuildContext context) {
    final d = delta;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          time,
          style: bold ? VText.mono.copyWith(fontWeight: FontWeight.w700) : VText.mono,
        ),
        if (d != null) ...[
          const SizedBox(height: VSpace.xs),
          Text(
            d >= 0 ? '+$d' : '$d',
            style: VText.delta.copyWith(color: d > 0 ? VColors.red : VColors.green),
          ),
        ],
      ],
    );
  }
}

/// What a stop is to the passenger, in one word.
///
/// Grey on an ordinary stop, dark on the one the screen is about — the same escalation the station
/// name makes, so the two read as one emphasis rather than two.
class _StopTag extends StatelessWidget {
  const _StopTag(this.label, {this.dark = false});

  final String label;
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: VSpace.s, vertical: VSpace.xs),
        decoration: BoxDecoration(
          color: dark ? VColors.surfaceDarkAlt : VColors.greyPill,
          borderRadius: BorderRadius.circular(VRadius.sm),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dark ? VText.pill.copyWith(color: VColors.inkOnDark) : VText.pill,
        ),
      );
}

// ---------------------------------------------------------------------------
// The two notes that sit beside the timeline
// ---------------------------------------------------------------------------

/// Where a callout's tail points.
enum VCalloutTail {
  /// At the thing on its left — on the ride sheet, the delay figure.
  left,

  /// Nowhere. The bubble stands on its own.
  none,
}

/// The grey bubble that says what the delay means for the next fixed point of the journey.
///
/// It is a speech bubble and not a card because it is a remark about the number beside it, not a
/// block of its own: the tail is the whole argument, and it is why this cannot be a [VPanel].
class VCallout extends StatelessWidget {
  const VCallout({
    super.key,
    required this.icon,
    required this.line1,
    this.line2,
    this.tail = VCalloutTail.left,
  });

  final IconData icon;
  final String line1;
  final String? line2;
  final VCalloutTail tail;

  @override
  Widget build(BuildContext context) {
    final bubble = Flexible(
      child: Container(
        decoration: BoxDecoration(
          color: VColors.greyFill,
          borderRadius: BorderRadius.circular(VRadius.md),
        ),
        padding: const EdgeInsets.all(VSpace.s),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: VControl.badgeIcon,
              height: VControl.badgeIcon,
              decoration: const BoxDecoration(color: VColors.red, shape: BoxShape.circle),
              child: Icon(icon, size: VControl.chevronSmall, color: VColors.inkOnDark),
            ),
            const SizedBox(width: VSpace.md),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(line1, style: VText.bodySStrong, maxLines: 2),
                  if (line2 != null) Text(line2!, style: VText.bodyS, maxLines: 2),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (tail == VCalloutTail.none) {
      return Row(mainAxisSize: MainAxisSize.min, children: [bubble]);
    }
    // The tail is a sibling of the bubble in a centre-aligned Row, so it stays on the bubble's
    // vertical middle however many lines the bubble grows to.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: _tailDepth, height: _tailHeight, child: _CalloutTail()),
        bubble,
      ],
    );
  }
}

/// Tail geometry: 8 pt deep, 13 pt tall. Shape, not spacing, so no spacing token fits.
const double _tailDepth = 8;
const double _tailHeight = 13;

class _CalloutTail extends StatelessWidget {
  const _CalloutTail();

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _CalloutTailPainter());
}

class _CalloutTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      // A half pixel of overlap into the bubble, or antialiasing leaves a seam where they meet.
      ..moveTo(size.width + 0.5, 0)
      ..lineTo(0, size.height / 2)
      ..lineTo(size.width + 0.5, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = VColors.greyFill);
  }

  @override
  bool shouldRepaint(_CalloutTailPainter oldDelegate) => false;
}

/// How loud a note inside a card is.
enum VNoteTone {
  /// A promise the app is making. Red tint, and deliberately not red text.
  red,

  /// A fact. Grey tint.
  neutral,
}

/// One promise, set apart inside a card: "Am Umstieg fragen wir einmal: bist du drin?".
///
/// The red tone tints the block but darkens the ink to [VColors.redInk]. Red type on a red tint
/// fails contrast at this size, and a promise you cannot read is worse than no promise — this is
/// the case that token exists for.
class VNoteBanner extends StatelessWidget {
  const VNoteBanner({
    super.key,
    required this.icon,
    required this.text,
    this.tone = VNoteTone.red,
  });

  final IconData icon;
  final String text;
  final VNoteTone tone;

  @override
  Widget build(BuildContext context) {
    final red = tone == VNoteTone.red;
    return VPanel(
      tone: red ? VPanelTone.red : VPanelTone.neutral,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Measured at 18 pt; VControl.chevron (20) is the nearest token.
          Icon(icon, size: VControl.chevron, color: red ? VColors.red : VColors.ink2),
          const SizedBox(width: VSpace.md),
          Expanded(
            child: Text(
              text,
              style: red ? VText.bodyS.copyWith(color: VColors.redInk) : VText.bodyS,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The onward leg
// ---------------------------------------------------------------------------

/// What kind of vehicle a leg is.
enum VTransportKind { train, regional, sBahn, bus, tram, ferry, walk }

/// The vehicle glyph in front of a leg.
///
/// It says what you are looking for on the platform before you have read a word of the row — which
/// is the whole reason a line badge alone was not enough.
class VTransportIcon extends StatelessWidget {
  const VTransportIcon(this.kind, {super.key, this.size = 24, this.color});

  final VTransportKind kind;

  /// No icon-size token fits; 24 is the box the mockup draws.
  final double size;

  final Color? color;

  IconData get _icon => switch (kind) {
        VTransportKind.train => Icons.train,
        VTransportKind.regional => Icons.directions_railway,
        VTransportKind.sBahn => Icons.directions_transit,
        VTransportKind.bus => Icons.directions_bus,
        VTransportKind.tram => Icons.tram,
        VTransportKind.ferry => Icons.directions_boat,
        VTransportKind.walk => Icons.directions_walk,
      };

  @override
  Widget build(BuildContext context) =>
      Icon(_icon, size: size, color: color ?? VColors.ink);
}

/// The header of the onward leg: which train you take next, from where and when.
///
/// It is tappable, which the old DANACH row was not. A row that names a specific train and then
/// refuses to show it is a dead end, and the chevron is there to promise it is not one.
class VLegRow extends StatelessWidget {
  const VLegRow({
    super.key,
    required this.line,
    required this.cls,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  /// The line as the railway prints it: "RB 52".
  final String line;

  final VLineClass cls;

  /// Where it goes: "nach Lüdenscheid".
  final String title;

  /// Where and when it leaves: "ab Hagen Hbf 10:55 · Gl. 6".
  final String subtitle;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: VControl.touch),
      child: Row(
        children: [
          VTransportIcon(_kindOf(cls)),
          const SizedBox(width: VSpace.s),
          VLineBadge(line, cls: cls, dark: true),
          // The mockup sets 28 pt here; VSpace.l is the nearest token and it also gives a long
          // destination more room to breathe before the chevron.
          const SizedBox(width: VSpace.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: VText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(subtitle, style: VText.bodyS, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: VSpace.s),
          const VChevron(),
        ],
      ),
    );

    if (onTap == null) return row;
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

/// The glyph a product class travels under. Regional trains and long distance are both trains; the
/// S-Bahn is the one class a passenger looks for by a different sign.
VTransportKind _kindOf(VLineClass cls) => switch (cls) {
      VLineClass.sBahn => VTransportKind.sBahn,
      VLineClass.longDistance => VTransportKind.train,
      VLineClass.regional => VTransportKind.regional,
      VLineClass.bus => VTransportKind.bus,
      VLineClass.tram => VTransportKind.tram,
      VLineClass.unknown => VTransportKind.train,
    };
