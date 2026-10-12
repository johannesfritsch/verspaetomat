import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../api/models.dart' show PieceTier;
import '../theme/tokens.dart';

// ---------------------------------------------------------------------------
// Puzzles (docs/51 §7)
// ---------------------------------------------------------------------------
//
// The server sends a whole picture and says which pieces of it a passenger has. The phone cuts it:
// real pieces with knobs and holes, not tiles, because the shape is what reads as a puzzle at a
// glance. The cut is fixed per picture — derived from its id alone — so the same picture looks the
// same on every phone.

/// FNV-1a, 32 bits. Not `String.hashCode`, which is free to differ between runs and builds: the
/// cut of a picture has to come out the same on every phone, every time.
int puzzleHash(String s) {
  var h = 0x811c9dc5;
  for (final b in utf8.encode(s)) {
    h ^= b;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

enum PieceSide { top, right, bottom, left }

/// How one picture is cut: which way each knob points and how it sits. Pieces count row by row
/// from the top left (`row * cols + col`), as on the wire.
@immutable
class PuzzleCut {
  const PuzzleCut({required this.imageId, required this.rows, required this.cols});
  final String imageId;
  final int rows;
  final int cols;

  int get pieces => rows * cols;

  /// The knob on the edge under row [r] at column [c]: 1 when it belongs to the upper piece and
  /// points down, -1 when it points up.
  int _down(int r, int c) => puzzleHash('$imageId/h/$r/$c') & 1 == 0 ? 1 : -1;

  /// The knob on the edge right of column [c] in row [r]: 1 when it points right.
  int _right(int r, int c) => puzzleHash('$imageId/v/$r/$c') & 1 == 0 ? 1 : -1;

  /// What a piece has on one side: 0 flat (the border of the picture), 1 a knob, -1 a hole.
  int tab(int index, PieceSide side) {
    final r = index ~/ cols, c = index % cols;
    return switch (side) {
      PieceSide.top => r == 0 ? 0 : -_down(r - 1, c),
      PieceSide.bottom => r == rows - 1 ? 0 : _down(r, c),
      PieceSide.left => c == 0 ? 0 : -_right(r, c - 1),
      PieceSide.right => c == cols - 1 ? 0 : _right(r, c),
    };
  }

  /// One side of a piece, in the direction its outline runs (clockwise from the top left corner).
  /// A flat side is two points; a cut one is the ten points of three cubic Béziers. The side two
  /// neighbours share is the same points, reversed.
  List<Offset> edge(int index, PieceSide side, Size cell) {
    final r = index ~/ cols, c = index % cols;
    final x0 = c * cell.width, x1 = x0 + cell.width;
    final y0 = r * cell.height, y1 = y0 + cell.height;
    return switch (side) {
      PieceSide.top => r == 0 ? [Offset(x0, y0), Offset(x1, y0)] : _below(r - 1, c, cell),
      PieceSide.right => c == cols - 1 ? [Offset(x1, y0), Offset(x1, y1)] : _beside(r, c, cell),
      PieceSide.bottom => r == rows - 1 ? [Offset(x1, y1), Offset(x0, y1)] : _below(r, c, cell).reversed.toList(),
      PieceSide.left => c == 0 ? [Offset(x0, y1), Offset(x0, y0)] : _beside(r, c - 1, cell).reversed.toList(),
    };
  }

  /// The edge under row [r], left to right.
  List<Offset> _below(int r, int c, Size cell) {
    final y = (r + 1) * cell.height;
    return _knob(Offset(c * cell.width, y), Offset((c + 1) * cell.width, y), Offset(0, _down(r, c).toDouble()), cell.shortestSide, puzzleHash('$imageId/hj/$r/$c'));
  }

  /// The edge right of column [c], top to bottom.
  List<Offset> _beside(int r, int c, Size cell) {
    final x = (c + 1) * cell.width;
    return _knob(Offset(x, r * cell.height), Offset(x, (r + 1) * cell.height), Offset(_right(r, c).toDouble(), 0), cell.shortestSide, puzzleHash('$imageId/vj/$r/$c'));
  }

  /// The classic knob, after Draradech's jigsaw generator: the edge dips a little the wrong way at
  /// the shoulders, narrows into a neck and swells into a round head a quarter of a piece high.
  /// [seed] moves the head along the edge and tilts it a little, so no two knobs are the same.
  static List<Offset> _knob(Offset a, Offset b, Offset normal, double depth, int seed) {
    double j(int shift, double range) => (((seed >> shift) & 0x3f) / 63 - 0.5) * 2 * range;
    const t = 0.1;
    final sa = j(1, 0.02), sb = j(7, 0.04), sc = j(13, 0.02), sd = j(19, 0.02), se = j(25, 0.02);
    final along = b - a;
    Offset p(double u, double v) => a + along * u + normal * (v * depth);
    return [
      p(0, 0),
      p(0.2, sa),
      p(0.5 + sb + sd, -t + sc),
      p(0.5 - t + sb, t + sc),
      p(0.5 - 2 * t + sb - sd, 3 * t + sc),
      p(0.5 + 2 * t + sb - sd, 3 * t + sc),
      p(0.5 + t + sb, t + sc),
      p(0.5 + sb + sd, -t + sc),
      p(0.8, se),
      p(1, 0),
    ];
  }

  /// The outline of one piece, in board coordinates for a board of [cell]-sized cells.
  Path piece(int index, Size cell) {
    final path = Path();
    for (final side in PieceSide.values) {
      final pts = edge(index, side, cell);
      if (side == PieceSide.top) path.moveTo(pts.first.dx, pts.first.dy);
      if (pts.length == 2) {
        path.lineTo(pts[1].dx, pts[1].dy);
      } else {
        for (var i = 1; i < pts.length; i += 3) {
          path.cubicTo(pts[i].dx, pts[i].dy, pts[i + 1].dx, pts[i + 1].dy, pts[i + 2].dx, pts[i + 2].dy);
        }
      }
    }
    return path..close();
  }

  /// One piece on its own, in its slot's coordinates: the cell's top left corner at the origin,
  /// the knobs reaching a quarter of a cell past it on their sides. For drawing a piece away from
  /// its board — the piece in the hand (docs/51 §9a) extrudes this outline.
  Path slotPath(int row, int col, Size cell) {
    final index = row * cols + col;
    return piece(index, cell).shift(-cellRect(index, cell).topLeft);
  }

  Rect cellRect(int index, Size cell) => Rect.fromLTWH((index % cols) * cell.width, (index ~/ cols) * cell.height, cell.width, cell.height);

  @override
  bool operator ==(Object other) => other is PuzzleCut && other.imageId == imageId && other.rows == rows && other.cols == cols;

  @override
  int get hashCode => Object.hash(imageId, rows, cols);
}

/// Resolves a picture to pixels and hands them to [builder], null until they are there. The
/// board draws its empty ground meanwhile, which is also what a picture that will not load shows.
class PuzzlePicture extends StatefulWidget {
  const PuzzlePicture({super.key, required this.image, required this.builder});
  final ImageProvider? image;
  final Widget Function(BuildContext context, ui.Image? image) builder;

  @override
  State<PuzzlePicture> createState() => _PuzzlePictureState();
}

class _PuzzlePictureState extends State<PuzzlePicture> {
  ImageStream? _stream;
  ImageInfo? _info;
  late final _listener = ImageStreamListener(
    (info, _) {
      if (!mounted) return;
      setState(() {
        _info?.dispose();
        _info = info;
      });
    },
    onError: (_, __) {},
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(PuzzlePicture old) {
    super.didUpdateWidget(old);
    if (old.image != widget.image) _resolve();
  }

  void _resolve() {
    final stream = widget.image?.resolve(createLocalImageConfiguration(context));
    if (stream?.key != null && stream?.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    // Another picture, or none: the old one's pixels must not stand in while it loads.
    if (_info != null) {
      _info!.dispose();
      _info = null;
    }
    _stream = stream;
    stream?.addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _info?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _info?.image);
}

/// A picture cut into pieces (docs/51 §7). The pieces in [owned] show the picture; the others
/// are pale outlines on `track` — grey says *nothing here yet*, as it does under an empty bar.
/// [complete] draws the finished picture without its seams.
///
/// With [tiers], every rare slot shows what it is (docs/51 §2a), owned or not: a little station
/// clock in its corner and a rim — fine ink for a quarter of an hour, red for an hour. A minute
/// shows nothing.
class PuzzleBoard extends StatelessWidget {
  const PuzzleBoard({
    super.key,
    required this.cut,
    this.owned = const {},
    this.tiers,
    this.image,
    this.aspectRatio,
    this.complete = false,
    this.semanticLabel,
    this.onPieceTap,
  });

  final PuzzleCut cut;
  final Set<int> owned;

  /// A tap on an owned piece: its slot and where it is on the screen (docs/51 §9a). Taps elsewhere
  /// on the board fall through.
  final void Function(int slot, Rect global)? onPieceTap;

  /// What a screen reader says for the picture: „Puzzle Nachtschicht am Gleis 1, 8 von 12
  /// Teilen". Without one the board is decoration and says nothing.
  final String? semanticLabel;

  /// Every slot's tier, row by row. Null draws no marks at all.
  final List<PieceTier>? tiers;
  final ImageProvider? image;

  /// Width over height of the picture. The grid's own when null.
  final double? aspectRatio;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final board = AspectRatio(
      aspectRatio: aspectRatio ?? cut.cols / cut.rows,
      child: PuzzlePicture(
        image: image,
        builder: (context, img) => CustomPaint(
          painter: PuzzleBoardPainter(
            cut: cut,
            owned: complete ? {for (var i = 0; i < cut.pieces; i++) i} : owned,
            tiers: tiers,
            image: img,
            seams: complete ? 0 : 1,
          ),
        ),
      ),
    );
    final tap = onPieceTap;
    final tappable = tap == null ? board : PuzzleTapArea(cut: cut, owned: complete ? {for (var i = 0; i < cut.pieces; i++) i} : owned, onPieceTap: tap, child: board);
    final label = semanticLabel;
    return label == null ? tappable : Semantics(image: true, label: label, child: tappable);
  }
}

/// Draws a board: the ground, the owned pieces' picture, the outlines, the rims and the marks.
class PuzzleBoardPainter extends CustomPainter {
  PuzzleBoardPainter({required this.cut, required this.owned, required this.image, this.tiers, this.seams = 1});
  final PuzzleCut cut;
  final Set<int> owned;
  final List<PieceTier>? tiers;
  final ui.Image? image;

  /// How strongly the seams between owned pieces show, 1 to 0. The finish fades them out, and
  /// the rims and marks of the owned pieces with them: a finished picture is one picture.
  final double seams;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = Size(size.width / cut.cols, size.height / cut.rows);
    final line = _line(cell);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.width < 96 ? VRadius.sm : VRadius.md)));
    canvas.drawRect(Offset.zero & size, Paint()..color = VColors.track);
    final img = image;
    if (img != null && owned.isNotEmpty) {
      if (owned.length >= cut.pieces) {
        _drawPicture(canvas, img, size);
      } else {
        final clip = Path();
        for (final i in owned) {
          clip.addPath(cut.piece(i, cell), Offset.zero);
        }
        canvas.save();
        canvas.clipPath(clip);
        _drawPicture(canvas, img, size);
        canvas.restore();
      }
    }
    final pale = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = line
      ..color = VColors.paperElevated;
    for (var i = 0; i < cut.pieces; i++) {
      if (!owned.contains(i)) canvas.drawPath(cut.piece(i, cell), pale);
    }
    if (seams > 0) {
      // A dark cut with a hair of light beside it, so a seam reads on a night sky as well as on a
      // white one.
      final light = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = line
        ..color = VColors.paperElevated.withValues(alpha: 0.35 * seams);
      final seam = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = line
        ..color = VColors.ink.withValues(alpha: 0.3 * seams);
      for (final i in owned) {
        final path = cut.piece(i, cell);
        canvas.drawPath(path.shift(Offset(line, line)), light);
        canvas.drawPath(path, seam);
      }
    }
    final t = tiers;
    // Not on a thumbnail: at a few points a cell, a clock and a rim are only noise.
    if (t != null && cell.shortestSide >= _markMinCell) {
      // What the picture still waits for first, quieter; what it has on top.
      for (final have in [false, true]) {
        for (var i = 0; i < cut.pieces && i < t.length; i++) {
          if (owned.contains(i) != have) continue;
          final alpha = have ? seams : 0.6;
          if (alpha <= 0) continue;
          _drawRim(canvas, cut.piece(i, cell), t[i], cell, alpha);
          _drawMark(canvas, t[i], cut.cellRect(i, cell), cell, alpha);
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(PuzzleBoardPainter old) =>
      old.cut != cut ||
      old.image != image ||
      old.seams != seams ||
      old.tiers != tiers ||
      old.owned.length != owned.length ||
      !old.owned.containsAll(owned);
}

/// The width of a seam: a hair on a thumbnail, never more than a point on a large board.
double _line(Size cell) => (cell.shortestSide * 0.012).clamp(0.5, 1.2);

/// The rim of a rare piece (docs/51 §2a): ink for a quarter of an hour, red for an hour — red is
/// money in this app, and an hour's delay is the one that becomes a claim. A minute has none.
/// The quarter's is the finer of the two — a fine edge on a dark picture, not an outline.
void _drawRim(Canvas canvas, Path path, PieceTier tier, Size cell, double alpha) {
  final (color, weight) = switch (tier) {
    PieceTier.minute => (null, 0.0),
    PieceTier.quarter => (VColors.ink.withValues(alpha: 0.65), 0.6),
    PieceTier.hour => (VColors.red, 1.0),
  };
  if (color == null) return;
  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _line(cell) * 2.2 * weight
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: color.a * alpha),
  );
}

/// Below this a cell is a thumbnail's, and a clock in it would be a dot.
const double _markMinCell = 22;

/// The tier mark: a small station clock in the top left corner of a piece's body, where no knob
/// ever is — a quarter of an hour with the quarter from twelve to three filled in, an hour with
/// the whole face in red. A minute has none: no mark means common, and twelve clocks on one board
/// would only be noise (docs/51 §2a).
void _drawMark(Canvas canvas, PieceTier tier, Rect slot, Size cell, double alpha) {
  if (tier == PieceTier.minute || cell.shortestSide < _markMinCell) return;
  final r = (cell.shortestSide * 0.1).clamp(3.5, 7.0);
  final inset = math.max(r + 2.5, cell.shortestSide * 0.17);
  paintTierClock(canvas, tier, slot.topLeft + Offset(inset, inset), r, alpha: alpha);
}

/// The station clock of a tier at [c], radius [r]: a quarter filled in ink, or the whole face red.
/// [hand] draws a minute's clock too — its one hand at twelve — where a minute must show something,
/// as on the back of a piece in the hand.
void paintTierClock(Canvas canvas, PieceTier tier, Offset c, double r, {double alpha = 1, bool hand = false}) {
  final ink = VColors.ink.withValues(alpha: alpha);
  final rim = (tier == PieceTier.hour ? VColors.red : VColors.ink).withValues(alpha: alpha);
  canvas.drawCircle(c, r, Paint()..color = VColors.paperElevated.withValues(alpha: alpha));
  switch (tier) {
    case PieceTier.minute:
      if (hand) {
        canvas.drawLine(
          c,
          c - Offset(0, r * 0.72),
          Paint()
            ..color = ink
            ..strokeWidth = math.max(1.0, r * 0.12)
            ..strokeCap = StrokeCap.round,
        );
      }
    case PieceTier.quarter:
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, math.pi / 2, true, Paint()..color = ink);
    case PieceTier.hour:
      canvas.drawCircle(c, r, Paint()..color = rim);
  }
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, r * 0.18)
      ..color = rim,
  );
}

/// A tier's clock on its own, as large as it is laid out — the back of a piece in the hand.
class TierClock extends StatelessWidget {
  const TierClock(this.tier, {super.key, this.size = 48});
  final PieceTier tier;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(dimension: size, child: CustomPaint(painter: _TierClockPainter(tier)));
}

class _TierClockPainter extends CustomPainter {
  _TierClockPainter(this.tier);
  final PieceTier tier;

  @override
  void paint(Canvas canvas, Size size) => paintTierClock(canvas, tier, size.center(Offset.zero), size.shortestSide / 2 - 1, hand: true);

  @override
  bool shouldRepaint(_TierClockPainter old) => old.tier != tier;
}

/// Taps on the owned pieces of a board, and nowhere else: a tap on a missing piece or on the
/// empty ground falls through to whatever is under the board — the card it stands on.
class PuzzleTapArea extends StatelessWidget {
  const PuzzleTapArea({super.key, required this.cut, required this.owned, required this.onPieceTap, required this.child});
  final PuzzleCut cut;
  final Set<int> owned;

  /// The piece's slot, and its rect on the screen — the cell with its knobs.
  final void Function(int slot, Rect global) onPieceTap;
  final Widget child;

  /// The owned piece under [local] on a board of [size], or null.
  static int? pieceAt(PuzzleCut cut, Set<int> owned, Size size, Offset local) {
    final cell = Size(size.width / cut.cols, size.height / cut.rows);
    for (final i in owned) {
      if (cut.piece(i, cell).contains(local)) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return _HitOnly(
      hit: (local, size) => pieceAt(cut, owned, size, local) != null,
      child: Builder(
        builder: (context) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final box = context.findRenderObject() as RenderBox?;
            if (box == null) return;
            final slot = pieceAt(cut, owned, box.size, d.localPosition);
            if (slot == null) return;
            final cell = Size(box.size.width / cut.cols, box.size.height / cut.rows);
            final bounds = cut.piece(slot, cell).getBounds();
            onPieceTap(slot, box.localToGlobal(bounds.topLeft) & bounds.size);
          },
          child: child,
        ),
      ),
    );
  }
}

/// Hit-tests its child only where [hit] says so.
class _HitOnly extends SingleChildRenderObjectWidget {
  const _HitOnly({required this.hit, super.child});
  final bool Function(Offset local, Size size) hit;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHitOnly(hit);

  @override
  void updateRenderObject(BuildContext context, _RenderHitOnly renderObject) => renderObject.hit = hit;
}

class _RenderHitOnly extends RenderProxyBox {
  _RenderHitOnly(this.hit);
  bool Function(Offset local, Size size) hit;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) => size.contains(position) && hit(position, size) && super.hitTest(result, position: position);
}

/// One piece lifted off its board (docs/51 §9a): its outline on a board of [board] size, and the
/// part of a picture of [image] pixels that lies under it, as the board draws it (cover, centred).
({Path outline, Rect source}) pieceShape(PuzzleCut cut, int slot, Size board, Size image) {
  final cell = Size(board.width / cut.cols, board.height / cut.rows);
  final outline = cut.piece(slot, cell);
  return (outline: outline, source: pictureSource(image, board, outline.getBounds()));
}

/// The part of a picture of [image] pixels under [part] of a board of [board] size that shows
/// the picture cropped to cover it, centred.
Rect pictureSource(Size image, Size board, Rect part) {
  final fit = applyBoxFit(BoxFit.cover, image, board);
  final shown = Alignment.center.inscribe(fit.source, Offset.zero & image);
  final k = shown.width / board.width;
  return Rect.fromLTWH(shown.left + part.left * k, shown.top + part.top * k, part.width * k, part.height * k);
}

/// The whole picture over [size], cropped to fill it as `BoxFit.cover` would.
void _drawPicture(Canvas canvas, ui.Image img, Size size) {
  final src = Size(img.width.toDouble(), img.height.toDouble());
  final fit = applyBoxFit(BoxFit.cover, src, size);
  canvas.drawImageRect(img, Alignment.center.inscribe(fit.source, Offset.zero & src), Offset.zero & size, Paint()..filterQuality = FilterQuality.medium);
}

/// The new piece of an arrival coming into its place (docs/51 §5), driven by [reveal] from 0 to 1.
///
/// It comes in from below, a little larger and turned, with the shadow of something held over
/// the board; glides to its slot, straightens and settles with a small overshoot; then the one red
/// lights along its edge for a moment — the light under what just happened. When it was the last
/// piece, [finish] then fades the seams and lets the picture breathe once.
class PieceReveal extends StatelessWidget {
  const PieceReveal({
    super.key,
    required this.cut,
    required this.owned,
    required this.piece,
    required this.reveal,
    this.finish,
    this.tiers,
    this.image,
    this.aspectRatio,
  });

  final PuzzleCut cut;

  /// Every piece owned, the new one included.
  final Set<int> owned;
  final int piece;
  final Animation<double> reveal;

  /// Every slot's tier. An hour piece keeps its red light a little longer.
  final List<PieceTier>? tiers;

  /// Only when [piece] finished the picture.
  final Animation<double>? finish;
  final ImageProvider? image;
  final double? aspectRatio;

  /// Where in [reveal] the piece clicks into place: the haptic tick and the start of the glow.
  static const snapAt = 0.62;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([reveal, finish]),
      builder: (context, _) {
        final r = reveal.value;
        final f = finish?.value ?? 0;
        final settled = r >= 1;
        final seams = finish == null ? 1.0 : 1 - const Interval(0, 0.5).transform(f);
        final breathe = finish == null ? 0.0 : math.sin(math.pi * const Interval(0.2, 1).transform(f)) * 0.02;
        return Transform.scale(
          scale: 1 + breathe,
          child: AspectRatio(
            aspectRatio: aspectRatio ?? cut.cols / cut.rows,
            child: PuzzlePicture(
              image: image,
              builder: (context, img) => CustomPaint(
                painter: PuzzleBoardPainter(cut: cut, owned: settled ? owned : ({...owned}..remove(piece)), tiers: tiers, image: img, seams: seams),
                foregroundPainter: settled
                    ? null
                    : _PiecePainter(cut: cut, index: piece, image: img, t: r, tier: tiers != null && piece < tiers!.length ? tiers![piece] : null),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The one piece in flight, at moment [t] of the reveal.
class _PiecePainter extends CustomPainter {
  _PiecePainter({required this.cut, required this.index, required this.image, required this.t, this.tier});
  final PuzzleCut cut;
  final int index;
  final ui.Image? image;
  final double t;
  final PieceTier? tier;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = Size(size.width / cut.cols, size.height / cut.rows);
    final slot = cut.cellRect(index, cell);
    final path = cut.piece(index, cell);

    // Under the board's lower edge and a little right at first, then into the slot.
    final travel = const Interval(0, 0.55, curve: Curves.easeOutCubic).transform(t);
    final from = Offset(cell.width * 0.3, size.height - slot.top + cell.height * 0.1);
    final offset = from * (1 - travel);
    // Straightens and shrinks to size, and overshoots by a hair: the click into place.
    final settle = const Interval(0.2, PieceReveal.snapAt, curve: Curves.easeOutBack).transform(t);
    final angle = -0.14 * (1 - settle);
    final scale = 1 + 0.18 * (1 - settle);
    final lift = 1 - const Interval(0.25, PieceReveal.snapAt, curve: Curves.easeIn).transform(t);
    // The red light: a breath for most pieces; an hour piece, the one that is money, holds it a
    // moment longer before it lets go.
    final hour = tier == PieceTier.hour;
    final g = t < PieceReveal.snapAt ? 0.0 : ((t - PieceReveal.snapAt) / ((hour ? 1.0 : 0.95) - PieceReveal.snapAt)).clamp(0.0, 1.0);
    final glow = hour ? math.sin(math.pi * math.pow(g, 0.6)) : math.sin(math.pi * g);
    // Solid after the first moment: only its very first frames fade in.
    final opacity = const Interval(0, 0.06).transform(t);

    final centre = slot.center;
    canvas.saveLayer(null, Paint()..color = VColors.ink.withValues(alpha: opacity));
    canvas
      ..translate(centre.dx + offset.dx, centre.dy + offset.dy)
      ..rotate(angle)
      ..scale(scale)
      ..translate(-centre.dx, -centre.dy);

    // Held over the board: the neutral raised shadow, deeper the higher it is.
    if (lift > 0) {
      for (final s in VShadow.cardRaised) {
        canvas.drawPath(
          path.shift(s.offset * (1 + 2 * lift)),
          Paint()
            ..color = s.color.withValues(alpha: (s.color.a * (1 + 2 * lift)).clamp(0.0, 1.0))
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, Shadow.convertRadiusToSigma(s.blurRadius * (0.6 + lift))),
        );
      }
    }
    // In place: the red light under it, the same glow a primary button stands on, sized to the piece.
    if (glow > 0) {
      final k = (cell.shortestSide / VControl.button).clamp(0.5, 1.5);
      for (final g in VShadow.glowButton) {
        canvas.drawPath(
          path.shift(g.offset * k),
          Paint()
            ..color = g.color.withValues(alpha: g.color.a * glow)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, Shadow.convertRadiusToSigma(g.blurRadius * k * 0.6)),
        );
      }
    }

    canvas.save();
    canvas.clipPath(path);
    final img = image;
    if (img != null) {
      _drawPicture(canvas, img, size);
    } else {
      canvas.drawRect(slot.inflate(cell.longestSide), Paint()..color = VColors.hairlineStrong);
    }
    canvas.restore();
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _line(cell) * (1 + glow)
        ..color = Color.lerp(VColors.ink.withValues(alpha: 0.28), VColors.red, glow)!,
    );
    final tr = tier;
    if (tr != null) {
      _drawRim(canvas, path, tr, cell, 1);
      _drawMark(canvas, tr, slot, cell, 1);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PiecePainter old) => old.t != t || old.image != image || old.index != index || old.cut != cut || old.tier != tier;
}
