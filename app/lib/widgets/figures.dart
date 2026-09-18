import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'surfaces.dart';

// ---------------------------------------------------------------------------
// The drawn figures
// ---------------------------------------------------------------------------
//
// Three things in the app draw a number instead of setting it: the week chart, the delay tile and
// the progress bar. They live together because they share one habit — the shape carries the
// reading and the type only confirms it. None of them is interactive, none of them animates yet,
// and all three have to survive the states that make a chart lie: an empty week, a cancelled
// train, a bar at zero.

/// The ground a progress bar stands on.
///
/// The bar is not one object recoloured. Each ground carries its own fill *and* its own track,
/// because a track that reads as empty on paper disappears on the dark board and a fill that
/// reads as red on paper is muddy on the red one.
enum VProgressGround {
  /// On paper, or on a white card.
  light,

  /// On the dark hero board.
  dark,

  /// On the red hero board.
  red,
}

/// The rounded bar with full caps: how far along something is.
///
/// Two segments, not one. [value] is what is settled and it is drawn in the ground's full fill;
/// [submitted] is the part that is under way but not yet counted, drawn behind it in a pale red so
/// the eye reads "this much more is already moving" without reading it as done. The caps are fully
/// round at both ends of both segments, so a bar at 3 % is still a shape rather than a sliver.
///
/// It never labels itself: [label] is the caller's own string, because the number beside a bar is
/// sometimes a percentage and sometimes an amount. [pct] builds the German percentage for the
/// common case.
class VProgressBar extends StatelessWidget {
  const VProgressBar({
    super.key,
    required this.value,
    this.submitted = 0,
    this.ground = VProgressGround.light,
    this.label,
    this.height = VControl.progress,
  });

  /// The settled part, 0..1.
  final double value;

  /// The part that is under way, 0..1, drawn behind [value] and measured from where it ends.
  final double submitted;

  final VProgressGround ground;

  /// The trailing figure. Null means no figure at all — most bars on a board carry none.
  final String? label;

  final double height;

  /// A percentage the German way: a space before the sign, and the space does not break.
  static String pct(double value) =>
      '${(value.clamp(0, 1) * 100).round()} %';

  Color get _fill => switch (ground) {
        VProgressGround.light => VColors.red,
        VProgressGround.dark => VColors.progressOnDark,
        VProgressGround.red => VColors.progressOnRed,
      };

  Color get _track => switch (ground) {
        VProgressGround.light => VColors.track,
        VProgressGround.dark => VColors.trackOnDark,
        VProgressGround.red => VColors.trackOnRed,
      };

  /// The pending segment. The spec names a colour only for the light ground, so the dark and the
  /// red one borrow the same tint rather than invent two more tokens.
  Color get _pending => VColors.redTint;

  TextStyle get _labelStyle => switch (ground) {
        VProgressGround.light => VText.pct,
        VProgressGround.dark || VProgressGround.red =>
          VText.pct.copyWith(color: VColors.inkOnDark3),
      };

  @override
  Widget build(BuildContext context) {
    final settled = value.clamp(0.0, 1.0);
    final pending = (value + submitted).clamp(0.0, 1.0);
    final text = label;

    return Semantics(
      value: text ?? pct(settled),
      // A bar has no width of its own: it is always as wide as it is given. Dropped straight into
      // a Row it would be handed an unbounded constraint and throw, which is a hard failure for a
      // decorative widget, so it takes a sensible width instead and leaves the caller to wrap it
      // in Expanded when the row should decide.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bounded = constraints.hasBoundedWidth;
          final width = bounded ? constraints.maxWidth : _unboundedWidth;
          final bar = _bar(width, settled, pending);
          if (text == null) return bounded ? bar : SizedBox(width: width, child: bar);
          return Row(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (bounded) Expanded(child: bar) else SizedBox(width: width, child: bar),
              // Measured 10.6 pt; VSpace.md is the nearest token.
              const SizedBox(width: VSpace.md),
              // Not Flexible: with a flex of its own it competed with the bar's Expanded and took
              // half the row, so a bar with a label was drawn at half the width of one without.
              Text(text, style: _labelStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          );
        },
      ),
    );
  }

  /// The bar itself, at a known width.
  ///
  /// The segments are laid out in points rather than as fractions, because a share can be tiny —
  /// 1.372 minutes of 1.208.313 is a thousandth — and a fraction of that draws nothing at all. A
  /// bar that is *some* of the way along has to look different from one that is nowhere, so a
  /// non-zero share keeps at least a round dot's worth of fill.
  Widget _bar(double width, double settled, double pending) {
    double segment(double share) {
      if (share <= 0) return 0;
      return (width * share).clamp(height, width);
    }

    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(VRadius.full),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: _track),
            // height: infinity, not a bare width. Align hands its child loose constraints, so a
            // SizedBox with only a width leaves the fill no height at all and the bar draws as an
            // empty track however far along it is.
            if (pending > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: segment(pending),
                  height: double.infinity,
                  child: ColoredBox(color: _pending),
                ),
              ),
            if (settled > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: segment(settled),
                  height: double.infinity,
                  child: ColoredBox(color: _fill),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// What a bar falls back to when nothing above it says how wide it should be. Wide enough to
  /// read as a bar, narrow enough to fit beside something on a phone.
  static const _unboundedWidth = 120.0;
}

/// Geduldspunkte over time, with one column picked out.
///
/// Seven bars is the shape the design asks for — a week, Monday first, today solid. But the app
/// does not always have seven days to show. Since issue #33 the standing endpoint carries a daily
/// series and the Bahnsteig draws Mo–So, but a server without it still answers with this week and
/// last week, so the chart takes however many columns it is given and widens the bars to fill the
/// same block. Two fat bars labelled „Diese" and „Letzte" are a week history at low resolution;
/// an empty rectangle is nothing at all.
///
/// The bars stand on one baseline and are read against each other, not against an axis: there is
/// no scale, no grid and no value anywhere on the chart, so the tallest bar is simply the best
/// column and everything else is a fraction of it. The picked column is solid [VColors.redBright]
/// while the rest are [VColors.track] — but its *label* stays grey like the others, because the
/// colour already says which one it is and a second marker would only shout.
///
/// A column worth nothing still draws a stub, as long as *something* in the week did: an empty day
/// and a missing day would otherwise look the same, and the chart has to be able to say "nothing
/// happened on Tuesday". A week where nothing happened at all is the other way round — seven
/// full-height tracks, because seven stubs read as a hole in the page rather than as a week that
/// has not started (issue #33).
class VWeekBars extends StatelessWidget {
  const VWeekBars({
    super.key,
    required this.values,
    required this.todayIndex,
    required this.labels,
    this.maxHeight = VControl.weekBarMax,
    this.barWidth,
    this.emptyIsTrack = false,
  });

  /// The columns, oldest first. Any length from two upwards; one column is not a chart and the
  /// caller should show nothing instead.
  final List<int> values;

  /// Which column to pick out — today in a week, this week in a comparison. Out of range picks
  /// none, which is what a history of finished weeks wants.
  final int todayIndex;

  /// The label under each column: Mo Di Mi …, or Diese / Letzte.
  final List<String> labels;

  /// The height of the tallest column.
  final double maxHeight;

  /// Overrides the width a column works out for itself.
  final double? barWidth;

  /// Whether a week with nothing in it draws full-height tracks instead of stubs (issue #33).
  ///
  /// Only the caller knows whether all-zero means *this week was quiet* or *no numbers arrived*.
  /// A standing that failed to load is `ApiStanding.empty`, which is all zeroes too, and seven
  /// full-height bars for a page that is still loading would be the chart claiming a week it has
  /// not been told about. So the flag is off by default and the seven-day caller turns it on.
  final bool emptyIsTrack;

  /// The block the chart fills, whatever it is showing: seven narrow bars and two wide ones take
  /// up the same room, so the panel around them does not change shape with the data.
  static const _block = 7 * VControl.weekBar + 6 * VControl.weekBarGap;

  /// Past this a bar stops reading as a bar and starts reading as a block of colour. Two columns
  /// sharing the seven-bar block would be 50 pt wide each, which is a swatch, not a chart.
  static const _maxBarWidth = 16.0;

  /// The height of a column worth zero *in a week that has something in it*. There is no token
  /// for a stub; VSpace.xs is the nearest value that still reads as a bar rather than as a line.
  static const _stub = VSpace.xs;

  @override
  Widget build(BuildContext context) {
    final count = values.length;
    if (count < 2) return const SizedBox.shrink();
    final week = [for (final v in values) v > 0 ? v : 0];
    // A short label list is padded rather than thrown: a chart with a nameless column is worth
    // more than a crash, and the caller's mistake should not reach the passenger.
    final days = [for (var i = 0; i < count; i++) i < labels.length ? labels[i] : ''];
    // The block is divided into equal slots and the bar is centred in its slot. Sizing the bar
    // first and the slot after it left „Letzte" and „Diese" touching, because a two-column chart
    // has wide labels under narrow bars.
    final slot = (_block + VControl.weekBarGap) / count;
    final width = barWidth ?? (slot - VControl.weekBarGap).clamp(VControl.weekBar, _maxBarWidth);

    // The week can be all zeroes — a quiet week is a real week, not a division by zero.
    var peak = 0;
    for (final v in week) {
      if (v > peak) peak = v;
    }

    // One slot per day, a bar centred in it. The slot is a bar plus a gap wide, which puts exactly
    // VControl.weekBarGap between two bars and leaves the labels room to be wider than the bars
    // they sit under.
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < count; i++)
          SizedBox(
            width: slot,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: width,
                  // A week with nothing in it draws full-height tracks rather than seven stubs
                  // (issue #33): the stubs read as a hole in the page, and a track reads as a
                  // place where something will go. The big 0 beside them is what says there is
                  // no data — the bars are uniform and unlit, so they cannot be read as values.
                  height: peak == 0 ? (emptyIsTrack ? maxHeight : _stub) : _barHeight(week[i], peak),
                  decoration: BoxDecoration(
                    // Nothing is picked out of a week where nothing happened: one column lit red
                    // would read as a little something. `redBright` is the *this one* red and
                    // earns it only where there is a value to point at.
                    // Today is lit only when today itself is worth something. Lighting a zero
                    // today draws a small red mark that reads as "you earned a little today".
                    color: i == todayIndex && week[i] > 0 ? VColors.redBright : VColors.track,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(VRadius.bar),
                    ),
                  ),
                ),
                // Measured 7 pt between the baseline and the label; VSpace.s is the nearest token.
                const SizedBox(height: VSpace.s),
                Text(
                  days[i],
                  style: VText.micro,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
      ],
    );
  }

  double _barHeight(int value, int peak) {
    final scaled = maxHeight * value / peak;
    return scaled < _stub ? _stub : scaled;
  }
}

/// The ride sheet's one number: how late the train is right now.
///
/// The plus is a separate Text, and that is the whole trick of the tile. Set at the digits' size
/// the font's own plus comes out a third of their height and reads as a smudge beside them, so it
/// is set at [_plusRatio] of the figure and sat on the same baseline — big enough to be part of the
/// number, small enough that the minutes stay the thing you read.
///
/// The figure scales down inside the tile instead of widening it. "+3", "+204" and a cancelled
/// "Ausfall" all have to sit in the same half-width block beside the callout, and a tile that
/// changed width with the delay would move the callout every time the feed updated.
///
/// Give it a bounded slot — it fills the width it is handed.
class VDelayTile extends StatelessWidget {
  const VDelayTile(this.minutes, {super.key, this.caption, this.cancelled = false});

  /// Minutes late. Always drawn signed, including "+0" — an unsigned 0 reads as "no data".
  final int minutes;

  /// The line under the figure. Null takes the line that fits the state.
  final String? caption;

  /// The train does not run at all. There is no number to show then, so the tile says the word.
  final bool cancelled;

  /// The plus against the digits. Measured 45.7 pt of plus against 70.1 pt of digit.
  static const _plusRatio = 0.65;

  /// The figure's line box, cut down to roughly its ink.
  ///
  /// A 96 pt line at height 1.0 is 96 pt tall while the digits inside it are 64 — the rest is the
  /// font's internal leading, and at this size that is thirty points of empty tile above and below
  /// the number. The design lays the tile out against the ink, so the box has to be trimmed to it.
  /// Digits have no descender, so nothing is at risk of being cut.
  static const _figureLineHeight = 0.78;

  @override
  Widget build(BuildContext context) {
    final figure = VText.display.copyWith(height: _figureLineHeight);
    final plus = figure.copyWith(
      fontSize: (figure.fontSize ?? 0) * _plusRatio,
      color: VColors.red,
    );

    final Widget number = cancelled
        ? Text('Ausfall', style: figure.copyWith(color: VColors.red), maxLines: 1)
        : Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('+', style: plus),
              // Measured 5.5 pt between the plus and the first digit.
              const SizedBox(width: VSpace.xs),
              Text(_german(minutes), style: figure),
            ],
          );

    return VPanel(
      tone: VPanelTone.red,
      radius: VRadius.md,
      padding: const EdgeInsets.all(VSpace.card),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(fit: BoxFit.scaleDown, child: number),
            const SizedBox(height: VSpace.s),
            Text(
              caption ?? (cancelled ? 'Zug fällt aus' : 'Minuten Verspätung'),
              // Measured 13 pt and on one line. bodyS is the token that fits „Minuten Verspätung"
              // across the tile without breaking it; two lines is the net for a longer caption.
              style: VText.bodyS.copyWith(color: VColors.ink),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// A whole number the German way: 1.208.313. Minutes never get this far, but the figure styles are
/// tabular for a reason and a four-digit delay must not come out looking English.
String _german(int value) {
  final digits = value.abs().toString();
  final out = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
    out.write(digits[i]);
  }
  return out.toString();
}
