import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'marks.dart';
import 'surfaces.dart';

// ---------------------------------------------------------------------------
// The connection picker
// ---------------------------------------------------------------------------
//
// Check-in step 3: a list of trains, one of which you are sitting in. Everything here exists to
// make four of these readable in one glance, so the card is built as a departure board rather
// than as a list row — two times at the edges, the journey drawn between them, and the reasons
// to pick this one on a line underneath.
//
// Two things the mockup draws are deliberately absent. There is no arrival platform, because the
// app only ever knows the platform you got on at; the arrival column carries the station and
// stops there. And there is no occupancy tag: "Hohe Auslastung" is drawn in the mockup and the
// app has no such data, so the widget has no way to say it.

/// One connection, and whether it is the chosen one.
///
/// The three columns are a picture of the journey: departure at the left edge, arrival at the
/// right, and the time it takes drawn across the gap. The rule between the two end dots is what
/// makes it a journey rather than two unrelated times, and the line badge hangs on that rule
/// because the train is a property of the leg, not of either end.
///
/// The two end columns take the same flex and the same styles, so a departure and an arrival line
/// up on both the time and the station even though only the departure has a platform under it.
/// That is the whole reason the platform is the last line rather than the middle one.
///
/// Selected is a tinted surface with a red edge and a filled tick; unselected is a white card with
/// a hollow ring. Both are the same shape and the same size, so choosing one does not make the
/// list jump.
class VConnectionCard extends StatelessWidget {
  const VConnectionCard({
    super.key,
    required this.departTime,
    required this.departStation,
    this.departPlatform,
    required this.arriveTime,
    required this.arriveStation,
    required this.duration,
    required this.line,
    required this.cls,
    required this.tags,
    required this.selected,
    required this.onTap,
  });

  /// "05:25". German clock, no seconds.
  final String departTime;

  final String departStation;

  /// "Gl. 8". Null where the timetable does not say, which is most regional traffic.
  final String? departPlatform;

  final String arriveTime;
  final String arriveStation;

  /// "2 h 08 min", already formatted. The card never does arithmetic on a duration.
  final String duration;

  /// The line number as the backend sends it: "ICE 911".
  final String line;

  /// Pass `vLineClassOf(line)` unless the caller knows better.
  final VLineClass cls;

  /// [VConnectionTag]s. They wrap, so there is no cap on how many.
  final List<Widget> tags;

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _VConnectionSurface(
        selected: selected,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 4 : 7 : 4 is the mockup's own proportion — the ends measure 69 and 80 pt and
                // the middle 135 pt. The ends get the same flex anyway: they hold the same two
                // lines, and an arrival that was allowed to be wider than its departure would
                // pull the whole list off its axis.
                Expanded(
                  flex: 4,
                  child: _VEnd(
                    time: departTime,
                    station: departStation,
                    platform: departPlatform,
                  ),
                ),
                const SizedBox(width: VSpace.s),
                Expanded(flex: 7, child: _VLeg(duration: duration, line: line, cls: cls)),
                const SizedBox(width: VSpace.s),
                Expanded(
                  flex: 4,
                  // The mockup sets the arrival flush left like the departure rather than
                  // mirroring it, and that is what keeps the two times on one baseline grid.
                  child: _VEnd(time: arriveTime, station: arriveStation),
                ),
                const SizedBox(width: VSpace.s),
                _VSelectMark(selected: selected),
              ],
            ),
            if (tags.isNotEmpty) ...[
              // Measured 9.7 pt; [VSpace.s] is the nearest token.
              const SizedBox(height: VSpace.s),
              Wrap(spacing: VSpace.s, runSpacing: VSpace.s, children: tags),
            ],
          ],
        ),
      );
}

/// One end of a connection: the time, the station, and on the departure side the platform.
///
/// Every line is capped at one and ellipsizes. "Weingarten (Berg) Bahnhof" is a real station and
/// it is wider than the column will ever be, so the only question is whether it truncates or
/// breaks the layout.
class _VEnd extends StatelessWidget {
  const _VEnd({required this.time, required this.station, this.platform});

  final String time;
  final String station;
  final String? platform;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The time measures 18.2 pt in the mockup. VText.numberS at 20 is the nearest token and
          // the right register besides: a departure time is a figure, and it is tabular so that
          // four of these stack into a column that reads down the digits.
          Text(
            time,
            style: VText.numberS,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // No gap between the three lines: the mockup stacks them on their line boxes alone,
          // measured baseline to baseline at 16 and 13 pt.
          Text(
            station,
            // Measured 11.5 pt in full ink — VText.bodyS is the nearest size but carries the
            // secondary ink, and the station name is the content of the column, not a footnote.
            style: VText.bodyS.copyWith(color: VColors.ink),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (platform != null)
            Text(
              platform!,
              // Measured #6E7588, which is VColors.ink2 to within a level.
              style: VText.caption.copyWith(color: VColors.ink2),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      );
}

/// The middle of a connection: how long it takes, the rule it takes it along, and the train.
///
/// The rule is ink2 rather than a hairline, because it is not a divider — it is the leg of the
/// journey, and it has to carry the two dots and the badge without going faint between them.
class _VLeg extends StatelessWidget {
  const _VLeg({required this.duration, required this.line, required this.cls});

  final String duration;
  final String line;
  final VLineClass cls;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            duration,
            // Measured 10.1 pt in ink2. VText.caption is the nearest size; the height is flattened
            // to 1.0 so the rule under it lands on the departure time's baseline, which is where
            // the mockup puts it. Tabular, because a column of durations is a column of figures.
            style: VText.caption.copyWith(
              color: VColors.ink2,
              height: 1.0,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: VSpace.xs),
          SizedBox(
            // The dot's diameter. Measured 8.3 pt, and no control token carries a mark this
            // small, so the spacing step of the same value stands in for it.
            height: VSpace.s,
            child: Row(
              children: [
                const _VLegDot(),
                Expanded(
                  child: Container(
                    // Measured 1.06 pt. Twice the hairline is the nearest the token set has.
                    height: VControl.hairline * 2,
                    color: VColors.ink2,
                  ),
                ),
                const _VLegDot(),
              ],
            ),
          ),
          const SizedBox(height: VSpace.xs),
          VLineBadge(line, cls: cls),
        ],
      );
}

/// The open circle at each end of the leg. Hollow, so the card's own ground shows through it and
/// the same dot works on the white card and on the tinted one.
class _VLegDot extends StatelessWidget {
  const _VLegDot();

  @override
  Widget build(BuildContext context) => Container(
        width: VSpace.s,
        height: VSpace.s,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // Measured 1.6 pt; three hairlines is the nearest the token set reaches.
          border: Border.all(color: VColors.ink2, width: VControl.hairline * 3),
        ),
      );
}

/// Whether this is the train you are on: a filled red tick, or an empty ring waiting for one.
///
/// It is a mark and not a control — the whole card is the tap target, so this never has to carry
/// 44 pt of its own. Both states are the same 22 pt circle so the row does not shift when the
/// selection moves.
class _VSelectMark extends StatelessWidget {
  const _VSelectMark({required this.selected});

  final bool selected;

  /// Measured 22.6 pt filled and 21.4 pt hollow. [VControl.badgeIcon] is the app's glyph size and
  /// the nearest token to both.
  static const double _size = VControl.badgeIcon;

  @override
  Widget build(BuildContext context) {
    if (!selected) {
      return Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // Measured #A2A7B3. VColors.disabledInk is the nearest token by a wide margin and it is
          // used here for its value, not its name: an unchosen connection is not disabled.
          border: Border.all(color: VColors.disabledInk, width: VControl.hairline * 3),
        ),
      );
    }
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: VColors.red),
      child: const Icon(
        Icons.check,
        // Measured 12.5 pt of drawn ink, which is a 16 pt icon box.
        size: VControl.chevronSmall,
        color: VColors.inkOnDark,
      ),
    );
  }
}

/// The card a connection stands on.
///
/// Unselected is a plain [VCard]. Selected is not, because no card tone carries both a tint and a
/// border, and the chosen train needs both: the tint says *this one* at a glance down the list and
/// the red edge says it again when the list is scrolled and only half a card is showing. So the
/// selected state is a [VPanel] in the same red tint, with the border and the lit shadow on a box
/// around it. It is the one place in this file that draws its own rectangle.
class _VConnectionSurface extends StatelessWidget {
  const _VConnectionSurface({
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Measured 7.4 pt as a circular arc, which is what a 10 pt continuous corner draws as. These
    // are list-row cards and VListCard is at the same radius.
    final shape = BorderRadius.circular(VRadius.md);

    if (!selected) {
      return VCard(
        radius: VRadius.md,
        padding: const EdgeInsets.all(VSpace.cardTight),
        onTap: onTap,
        child: child,
      );
    }

    final box = Container(
      decoration: BoxDecoration(
        borderRadius: shape,
        // Measured 0.85 pt. Twice the hairline is the nearest token, and the deep red rather than
        // the bright one: this is a chosen state, not the app's own mark.
        border: Border.all(color: VColors.red, width: VControl.hairline * 2),
        boxShadow: VShadow.cardCta,
      ),
      child: VPanel(
        radius: VRadius.md,
        padding: const EdgeInsets.all(VSpace.cardTight),
        child: child,
      ),
    );

    // Same clipping as VCard: without it the splash squares off at the corner.
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
                borderRadius: shape,
                splashColor: VColors.pressedOverlay,
                highlightColor: VColors.pressedOverlay,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What a tag under a connection says about it.
enum VConnectionTone {
  /// A reason to pick this train: it is direct, it is running on time. Green, and green only ever
  /// means that.
  good,

  /// A fact about the train that is neither good nor bad, and is usually long: where you change.
  neutral,
}

/// The small pills under a connection: "Direkt", "Pünktlich", "1× umsteigen in Mannheim Hbf".
///
/// A [VPill] with the tone decided by meaning rather than by the call site, which is the whole
/// reason this wrapper exists — three screens picking `VPillTone.green` by hand would eventually
/// pick it for something that is not good news. The glyph is optional because a transfer label is
/// already a sentence and does not need one.
///
/// It ellipsizes rather than pushing the row wide: the transfer label carries a station name and
/// station names are unbounded.
class VConnectionTag extends StatelessWidget {
  const VConnectionTag(this.label, {super.key, this.icon, this.tone = VConnectionTone.neutral});

  final String label;

  /// A leaf on "Direkt", a clock on "Pünktlich". Only where the glyph says something the word
  /// does not.
  final IconData? icon;

  final VConnectionTone tone;

  @override
  Widget build(BuildContext context) => VPill(
        label,
        icon: icon,
        tone: switch (tone) {
          VConnectionTone.good => VPillTone.green,
          VConnectionTone.neutral => VPillTone.neutral,
        },
      );
}

/// The row at the foot of the list: there are more trains than these four.
///
/// A card rather than a link, because it is the last item in a list of cards and a link at the end
/// of a stack of surfaces reads as a footnote to the last one rather than as the way onward. The
/// chevron is what makes it a door.
class VMoreRow extends StatelessWidget {
  const VMoreRow({
    super.key,
    required this.label,
    required this.onTap,
    this.icon = Icons.tune,
  });

  /// "Weitere Verbindungen".
  final String label;

  final VoidCallback onTap;

  /// The glyph at the left edge. A filter dial by default, because what is behind this row is the
  /// full timetable rather than a longer version of this list.
  final IconData icon;

  @override
  Widget build(BuildContext context) => VCard(
        radius: VRadius.md,
        // The same inner padding as a connection card, so the whole list has one left edge. The
        // row is drawn 43 pt tall and built at [VControl.touch].
        padding: const EdgeInsets.symmetric(
          horizontal: VSpace.cardTight,
          vertical: VSpace.s,
        ),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: VControl.touch),
          child: Row(
            children: [
              // Measured 19.4 pt of icon box; badgeIcon is the app's glyph size and the nearest
              // token that is about a glyph.
              Icon(icon, size: VControl.badgeIcon, color: VColors.ink),
              const SizedBox(width: VSpace.md),
              Expanded(
                child: Text(
                  label,
                  // Measured 12.1 pt in full ink, set plain: this is a destination, not a heading.
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
      );
}
