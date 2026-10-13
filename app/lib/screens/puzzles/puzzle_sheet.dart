import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../repo/repo_scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'piece_in_hand.dart';
import 'puzzle_widgets.dart';

/// The two ways of looking at a picture under way.
enum PuzzleView { puzzle, pieces }

/// A picture under way, large (docs/51 §6): the board as it stands, in 3D, with a hole for every
/// piece still missing — or its pieces laid apart, each a tap away from the hand (§9a).
Future<void> showPuzzle(BuildContext context, ApiPuzzle p) => showVSheet<void>(context, builder: (_) => PuzzleSheet(puzzle: p));

class PuzzleSheet extends StatefulWidget {
  const PuzzleSheet({super.key, required this.puzzle, this.view = PuzzleView.puzzle});
  final ApiPuzzle puzzle;

  /// Where it opens.
  final PuzzleView view;

  @override
  State<PuzzleSheet> createState() => _PuzzleSheetState();
}

class _PuzzleSheetState extends State<PuzzleSheet> {
  late PuzzleView _view = widget.view;

  @override
  Widget build(BuildContext context) {
    final p = widget.puzzle;
    final missing = stillMissing(p);
    final pieces = _view == PuzzleView.pieces;
    return Padding(
      padding: const EdgeInsets.only(bottom: VSpace.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VSheetHeader(title: keepLastWord(p.title), subtitle: p.ngoName),
          Padding(
            padding: const EdgeInsets.fromLTRB(VSpace.sheet, VSpace.s, VSpace.sheet, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // One stage for both views, so the switch does not move under the finger.
                LayoutBuilder(
                  builder: (context, c) {
                    final stage = Size(c.maxWidth, MediaQuery.sizeOf(context).height * 0.46);
                    // A little smaller than the stage, so its edge has room when it turns.
                    final width = (stage.width < stage.height * p.aspectRatio ? stage.width : stage.height * p.aspectRatio) * 0.86;
                    return SizedBox.fromSize(
                      size: stage,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: pieces
                            ? Padding(
                                key: const ValueKey('pieces'),
                                padding: const EdgeInsets.symmetric(vertical: VSpace.s),
                                child: PuzzleSpread(
                                  cut: cutOf(p),
                                  owned: p.owned.toSet(),
                                  tiers: p.slotTiers,
                                  image: RepoScope.of(context).repo.puzzleImage(p),
                                  aspectRatio: p.aspectRatio,
                                  pieceLabel: (slot) => '${tierPieceName(p.tierOf(slot))}, Platz ${slot + 1} von ${p.pieces}',
                                  onPieceTap: (slot, rect) => showPieceInHand(context, p, slot, from: rect),
                                ),
                              )
                            : Center(
                                key: const ValueKey('puzzle'),
                                child: Semantics(
                                  image: true,
                                  label: 'Puzzle ${p.title}, ${puzzleProgress(p)} Teilen. Zum Drehen ziehen.',
                                  child: PuzzleTile(puzzle: p, width: width),
                                ),
                              ),
                      ),
                    );
                  },
                ),
                const VGap.m(),
                Text(puzzleProgress(p), style: VText.title),
                if (missing != null) ...[
                  const VGap.xs(),
                  Text(missing, style: VText.bodyS),
                ],
                const VGap.xs(),
                Text(
                  pieces ? 'Tipp ein Teil an, dann kannst du es drehen und umdrehen.' : 'Zum Drehen ziehen.',
                  style: VText.caption,
                ),
                const VGap.l(),
                Center(
                  child: VSegmented<PuzzleView>(
                    key: const Key('puzzle-view'),
                    segments: const [(PuzzleView.puzzle, 'Puzzle'), (PuzzleView.pieces, 'Teile')],
                    value: _view,
                    onChanged: (v) => setState(() => _view = v),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A picture under way as a thing in the hand (§9a): the board with an edge, a hole where each
/// missing piece belongs, the seams and the rare pieces' rims on its face, and its card on the back.
class PuzzleTile extends StatelessWidget {
  const PuzzleTile({super.key, required this.puzzle, required this.width, this.tilt});
  final ApiPuzzle puzzle;

  /// How wide the whole board would be: a missing outer row or column makes the tile narrower.
  final double width;
  final TileTilt? tilt;

  @override
  Widget build(BuildContext context) {
    final p = puzzle;
    final owned = p.owned.toSet();
    // Nothing to hold yet: the flat board, grey all over.
    if (owned.isEmpty) return SizedBox(width: width, child: PuzzleBoardOf(p));
    final board = boardFor(p);
    final cut = cutOf(p);
    final outline = boardOutline(cut, owned, board, radius: board.width * VRadius.md / 300);
    final bounds = outline.getBounds();
    return PuzzlePicture(
      image: RepoScope.of(context).repo.puzzleImage(p),
      builder: (context, img) => Tile3D(
        key: const Key('puzzle-tile'),
        cacheKey: '${p.imageId}/board/${(p.owned.toList()..sort()).join(',')}',
        outline: outline,
        image: img,
        source: pictureSource(img == null ? board : Size(img.width.toDouble(), img.height.toDouble()), board, bounds),
        width: width * bounds.width / board.width,
        depth: 0.018,
        tilt: tilt,
        overlay: IgnorePointer(
          child: CustomPaint(painter: PuzzleMarksPainter(cut: cut, owned: owned, board: board, bounds: bounds, outline: outline, tiers: p.slotTiers)),
        ),
        back: (context) => PuzzleBack(puzzle: p, board: board, bounds: bounds),
      ),
    );
  }
}

/// The back of a picture under way: grey card, the seams between its pieces, and each piece's
/// clock where it sits — as the back of a puzzle on the table looks, gaps and all. Seen from
/// behind, so left is right. What it is and how far it has come stand on the sheet around it.
class PuzzleBack extends StatelessWidget {
  const PuzzleBack({super.key, required this.puzzle, required this.board, required this.bounds});
  final ApiPuzzle puzzle;
  final Size board;
  final Rect bounds;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: VColors.track,
      child: CustomPaint(
        size: Size.infinite,
        painter: _PuzzleBackPainter(cut: cutOf(puzzle), owned: puzzle.owned.toSet(), tiers: puzzle.slotTiers, board: board, bounds: bounds),
      ),
    );
  }
}

class _PuzzleBackPainter extends CustomPainter {
  _PuzzleBackPainter({required this.cut, required this.owned, required this.tiers, required this.board, required this.bounds});
  final PuzzleCut cut;
  final Set<int> owned;
  final List<PieceTier> tiers;
  final Size board;
  final Rect bounds;

  @override
  void paint(Canvas canvas, Size size) {
    if (bounds.isEmpty) return;
    final s = size.width / bounds.width;
    final cell = Size(board.width / cut.cols, board.height / cut.rows);
    // From the board to the back: scaled, and mirrored left to right.
    Offset at(Offset p) => Offset(size.width - (p.dx - bounds.left) * s, (p.dy - bounds.top) * s);
    canvas.save();
    canvas.translate(size.width, 0);
    canvas.scale(-s, s);
    canvas.translate(-bounds.left, -bounds.top);
    final seam = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 / s
      ..color = VColors.ink.withValues(alpha: 0.12);
    for (final i in owned) {
      canvas.drawPath(cut.piece(i, cell), seam);
    }
    canvas.restore();
    // The clocks the right way round, each in the middle of its piece's body.
    final r = (cell.shortestSide * s * 0.16).clamp(4.0, 16.0);
    for (final i in owned) {
      paintTierClock(canvas, i < tiers.length ? tiers[i] : PieceTier.minute, at(cut.cellRect(i, cell).center), r, alpha: 0.85, hand: true);
    }
  }

  @override
  bool shouldRepaint(_PuzzleBackPainter old) => old.cut != cut || old.board != board || old.bounds != bounds || old.owned.length != owned.length || !old.owned.containsAll(owned);
}
