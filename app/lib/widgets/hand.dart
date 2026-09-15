import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

// ---------------------------------------------------------------------------
// The app's own hand
// ---------------------------------------------------------------------------
//
// Everything else in the app is Archivo: a station name, a figure, a button. This file is the one
// place it writes rather than sets type. That privilege is worth exactly four sentences —
// "Mehr Bahn. Mehr Gutes." and "Aus Verspätung wird Gutes." beside the two hero boards,
// "Zeig, was wir gemeinsam schaffen!" beside the Teilen button, "Gemeinsam wirken." on the footer
// card — plus the little arrow that points from a note back at the thing it is about. A second
// voice that says five things is a voice; one that says fifty is a theme.
//
// Both parts here are ornament. Neither is ever the only way to reach something, neither carries
// state, and neither is a control: nothing in this file has a hit target, because nothing in it
// can be pressed.
//
// Screen readers see them differently, though, and on purpose. The arrow is pure drawing — it has
// no name, and "Grafik" announced between a button and its label is noise — so it is wrapped in
// [ExcludeSemantics] and disappears. The note is not drawing: it is a real German sentence, and a
// reader who cannot see it would otherwise miss a line the sighted user reads. So the note keeps a
// voice, but exactly one: its four drawn lines are replaced by a single label with the line breaks
// flattened to spaces, so VoiceOver says "Aus Verspätung wird Gutes." rather than four fragments.
// A caller that has already said the same thing in the surrounding surface's own label wraps the
// note in [ExcludeSemantics] itself.

/// A handwritten margin note.
///
/// It is set in [VText.hand] — the app's only non-Archivo face — and it is deliberately quiet:
/// never the red, never a heading, never load-bearing copy. It is an aside written next to the
/// interface, not part of it.
///
/// **Rotation and layout.** [Transform.rotate] paints outside its own layout box: the parent is
/// still told the *unrotated* size, so a tilted two-line note would silently paint into whatever
/// sits under it. Measured on the real string, the overhang is large enough to matter —
/// "Zeig, was wir gemeinsam schaffen!" is about 72 × 34 pt unrotated, and at −8° its painted
/// bounds are 76.0 × 43.7 pt, so it would reach about 4.8 pt above and 4.8 pt below the space it
/// claimed, which is a third of the gap under the Teilen button. So this widget does not hand the
/// rotation to the parent as a surprise. It measures the text with a [TextPainter], computes the
/// rotated bounds (`w·|cos| + h·|sin|` by `w·|sin| + h·|cos|`) and reports *those* as its size,
/// with the note centred inside. It therefore occupies exactly what it paints, and a [Column]
/// above or below it keeps its gap. If the rotated width would not fit the incoming constraints
/// the text is re-wrapped narrower rather than clipped — a hand note wraps, it never ellipsises.
///
/// **What the mockups measure.** Two different tilts live in those files and only one of them is
/// rotation. Every line of every note rises to the right — baseline fits give −8.1° ("Gutes." on
/// Home), −9.5° ("Mehr"), −11.9° ("gemeinsam schaffen!"), −12.6° ("Gemeinsam") and −14.5°
/// ("Verspätung" on the Wir board) — but on the two board notes all four lines still start at the
/// same left edge, so those blocks are upright and the rise belongs to the mockups' script face,
/// not to a transform. Caveat sets on a flat baseline and nothing reproduces that quirk, so the
/// board notes take `angle: 0` and lose it. What is real rotation is the block tilt of the two
/// notes on paper: the footer note's second line starts 2 px right of its first over a 34 px line
/// pitch, which is −3.4° before the side bearings of "G" against "w" are argued about, and the
/// anatomy pass read the same two blocks at −7° and −8°. [tilt] takes the upper end, because the
/// note has to look pinned on rather than merely crooked.
class VHandNote extends StatelessWidget {
  const VHandNote(
    this.text, {
    super.key,
    this.angle = 0,
    this.align = TextAlign.left,
    this.color,
    this.size,
  });

  /// The note. Newlines are the line breaks the designer drew; they are honoured as written,
  /// because where a handwritten line ends is part of how it looks.
  final String text;

  /// Radians, clockwise-positive like the rest of Flutter. Negative lifts the right-hand end.
  final double angle;

  final TextAlign align;

  /// Defaults to [VText.hand]'s own ink. The mockups use three tints: near-white on the red board
  /// (measured #F6ECEB — nearest token [VColors.inkOnDark2]), grey-white on the dark board
  /// (measured #B9B9BA — nearest token [VColors.inkOnDark3]), and slate on paper (measured #7C858D
  /// and #65727E — nearest token [VColors.ink2], which is the style's default and why paper notes
  /// pass nothing).
  final Color? color;

  /// Overrides the face's own size. Null means [VText.hand], which is where the size belongs.
  final double? size;

  /// The tilt of a note pinned to paper, in radians: −8°. The share note and the footer note use
  /// it; the two notes on a hero board do not. See the class doc for the forensics.
  static const double tilt = -0.14;

  @override
  Widget build(BuildContext context) {
    var style = VText.hand;
    if (color != null) style = style.copyWith(color: color);
    if (size != null) style = style.copyWith(fontSize: size);

    return LayoutBuilder(
      builder: (context, constraints) {
        final span = TextSpan(text: text, style: style);
        final direction = Directionality.of(context);
        final scaler = MediaQuery.textScalerOf(context);
        final painter = TextPainter(
          textWidthBasis: TextWidthBasis.longestLine,
          // A margin note breaks where it was written to break and nowhere else. Left to wrap, a
          // narrow column split „Verspätung" into „Verspätun" and „g", which is not handwriting,
          // it is a fault.
          maxLines: null,
          text: span,
          textAlign: align,
          textDirection: direction,
          textScaler: scaler,
        );

        // Measured unwrapped: the width the note asks for is the width of its longest
        // authored line, and the caller gives it that or the note overhangs — which on a board is
        // fine, because the board is wider than the column the note sits in.
        final ceiling = double.infinity;
        painter.layout(maxWidth: ceiling);
        var width = painter.width;
        var height = painter.height + _inkSlack(span, direction, scaler, ceiling);

        final sin = math.sin(angle).abs();
        final cos = math.cos(angle).abs();

        // Re-wrap if the rotated block would not fit. The height is what the rotation borrows
        // from the width, so subtract it and lay the text out again.
        if (sin > 0 && ceiling.isFinite && width * cos + height * sin > ceiling) {
          painter.layout(maxWidth: math.max(0, ceiling - height * sin));
          width = painter.width;
          height = painter.height + _inkSlack(span, direction, scaler, ceiling);
        }

        final rotated = Size(width * cos + height * sin, width * sin + height * cos);
        painter.dispose();

        return Semantics(
          label: text.replaceAll('\n', ' '),
          child: ExcludeSemantics(
            child: SizedBox(
              width: rotated.width,
              height: rotated.height,
              child: Center(
                child: Transform.rotate(
                  angle: angle,
                  // The child is given the painter's own width so it breaks exactly where the
                  // measurement said it would; the rotation then pivots about that box's centre,
                  // which is the centre of the SizedBox, so the painted bounds fill it exactly.
                  child: SizedBox(
                    width: width,
                    child: Text(text, style: style, textAlign: align, softWrap: false),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// How far the handwriting's ink reaches outside its own line boxes.
///
/// [VText.hand] sets a line height of 1.0, which is the tight spacing the design draws and which
/// a grotesk can live with. Caveat cannot: its ascenders and descenders run well past a box that
/// tall, so a block measured by its line boxes is shorter than the writing in it and the last
/// line's descenders get sliced off — „schaffen!" lost the tails of both its f's.
///
/// Rather than loosen the spacing, the block is measured a second time at the font's own line
/// height and the difference is added as slack. The text still sets tight; the box around it is
/// simply big enough to hold what is drawn.
double _inkSlack(TextSpan span, TextDirection direction, TextScaler scaler, double ceiling) {
  final style = span.style;
  if (style == null || style.height == null) return 0;
  final natural = TextPainter(
    textWidthBasis: TextWidthBasis.longestLine,
    text: TextSpan(text: span.text, style: style.copyWith(height: null)),
    textDirection: direction,
    textScaler: scaler,
  )..layout(maxWidth: ceiling);
  final slack = natural.height - (style.height! * (style.fontSize ?? 0) * natural.computeLineMetrics().length);
  natural.dispose();
  return slack > 0 ? slack : 0;
}

/// The little curved arrow that points from a note back at the thing the note is about.
///
/// It is drawn rather than set, because no icon in Material bends like this: the head is at the
/// top and the tail sweeps down and away, the way you would flick a biro. One quadratic curve, two
/// short strokes for the head, round caps, no fill.
///
/// **Measured.** On `wir.png` the ink runs x 551.5–606, y 779.5–810 px at the mockup's 2.167×, so
/// the arrow is drawn at about 25 × 14 pt. The curve starts at the tip (553.5, 781.3), bottoms out
/// at (587, 808) and ends at (603.75, 799.4); the two head strokes are about 6.5 pt long and reach
/// (566.9, 785.3) and (554.75, 795.6). Every one of those points is below, expressed as a fraction
/// of the box, so the drawing is the same shape at any size. The default box is 45 × 26 pt, which
/// is the design spec's size rather than the mockup's — the aspect is the same (1.73 against the
/// measured 1.78), so the arrow only comes out bigger, never distorted. Pass `width: 26,
/// height: 15` for the mockup's own scale.
///
/// [mirrored] flips it left-to-right for a note sitting on the other side of what it points at.
/// Mirroring is a canvas flip, not a second set of coordinates, so the two versions cannot drift.
class VHandArrow extends StatelessWidget {
  const VHandArrow({
    super.key,
    this.width = 45,
    this.height = 26,
    this.mirrored = false,
    this.color,
  });

  final double width;
  final double height;

  /// False: the head is at the top *left* and the arrow points up and to the left, which is the
  /// instance in the mockups. True: the head is at the top right.
  final bool mirrored;

  /// Measured #7C858D, the same slate as the note it belongs to. Nearest token is [VColors.ink2];
  /// there is no token for this exact grey and it does not deserve one.
  final Color? color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox(
          width: width,
          height: height,
          child: CustomPaint(
            painter: _VHandArrowPainter(color: color ?? VColors.ink2, mirrored: mirrored),
          ),
        ),
      );
}

class _VHandArrowPainter extends CustomPainter {
  const _VHandArrowPainter({required this.color, required this.mirrored});

  final Color color;
  final bool mirrored;

  /// The nib. Measured 4 px = 1.8 pt on a drawing 25 pt wide; the brief asks for ~1.5. It is a
  /// constant rather than a fraction of the box because a pen has one nib — a bigger arrow is a
  /// bigger gesture, not a fatter line.
  static const double _nib = 1.6;

  // The drawing, as fractions of the box. See the doc comment on VHandArrow for where they were
  // measured. The control point sits below the box on purpose: a quadratic reaches only about
  // 60 % of the way to its control, and it is what puts the low point of the sweep on the floor.
  static const Offset _tip = Offset(0, 0);
  static const Offset _control = Offset(0.554, 1.566);
  static const Offset _tail = Offset(1, 0.679);
  static const Offset _barbUpper = Offset(0.265, 0.143);
  static const Offset _barbLower = Offset(0.025, 0.532);

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _nib
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Inset by half the nib so the stroke stays inside the box instead of straddling its edge.
    final inset = _nib / 2;
    final w = math.max(0.0, size.width - _nib);
    final h = math.max(0.0, size.height - _nib);
    Offset at(Offset f) => Offset(inset + f.dx * w, inset + f.dy * h);

    final tip = at(_tip);
    final control = at(_control);
    final tail = at(_tail);

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..quadraticBezierTo(control.dx, control.dy, tail.dx, tail.dy)
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(at(_barbUpper).dx, at(_barbUpper).dy)
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(at(_barbLower).dx, at(_barbLower).dy);

    if (mirrored) {
      canvas.save();
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
      canvas.drawPath(path, pen);
      canvas.restore();
    } else {
      canvas.drawPath(path, pen);
    }
  }

  @override
  bool shouldRepaint(_VHandArrowPainter old) =>
      old.color != color || old.mirrored != mirrored;
}
