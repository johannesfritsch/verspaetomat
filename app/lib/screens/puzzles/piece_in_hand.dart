import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../repo/repo_scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'puzzle_widgets.dart';

/// The board size a piece's outline is cut on: only its proportions matter.
Size boardFor(ApiPuzzle p) => Size(1000, 1000 / p.aspectRatio);

/// Lifts an owned piece off its board into the middle of the screen, to be turned in the hand
/// (docs/51 §9a). [from] is where it sits on the screen; it rises from there and goes back on close.
Future<void> showPieceInHand(BuildContext context, ApiPuzzle puzzle, int slot, {Rect? from}) {
  return Navigator.of(context, rootNavigator: true).push(_PieceRoute(puzzle: puzzle, slot: slot, from: from));
}

class _PieceRoute extends PageRoute<void> {
  _PieceRoute({required this.puzzle, required this.slot, this.from});
  final ApiPuzzle puzzle;
  final int slot;
  final Rect? from;

  @override
  bool get opaque => false;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 420);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 320);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) =>
      PieceInHand(puzzle: puzzle, slot: slot, from: from, animation: animation);
}

/// The overlay itself: the room darkened, the piece in the middle, what it is underneath.
class PieceInHand extends StatelessWidget {
  const PieceInHand({super.key, required this.puzzle, required this.slot, required this.animation, this.from});
  final ApiPuzzle puzzle;
  final int slot;
  final Rect? from;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final p = puzzle;
    final tier = p.tierOf(slot);
    final screen = MediaQuery.sizeOf(context);
    final board = boardFor(p);
    final cut = cutOf(p);
    final bounds = cut.piece(slot, Size(board.width / cut.cols, board.height / cut.rows)).getBounds();
    final width = screen.width * 0.7;
    final height = width * bounds.height / bounds.width;
    final target = Rect.fromLTWH((screen.width - width) / 2, screen.height * 0.16, width, height);
    final start = from ?? Rect.fromCenter(center: target.center, width: width * 0.4, height: height * 0.4);
    final flight = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    final words = CurvedAnimation(parent: animation, curve: const Interval(0.5, 1));
    void close() => Navigator.of(context).maybePop();
    final label = 'Ein ${tierPieceName(tier)} von ${p.ngoName}, Platz ${slot + 1} von ${p.pieces}';

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: label,
      onDismiss: close,
      // A route of its own over the app: the text below wants a Material's default style.
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // The room goes dark; a tap on it, or a swipe down, puts the piece back.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: close,
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0) > 300) close();
                },
                child: FadeTransition(opacity: animation, child: ColoredBox(color: VColors.surfaceDark.withValues(alpha: 0.9))),
              ),
            ),
            AnimatedBuilder(
              animation: flight,
              builder: (context, child) {
                final now = Rect.lerp(start, target, flight.value)!;
                return Positioned.fromRect(
                  rect: target,
                  child: Transform(
                    transform: Matrix4.identity()
                      ..translateByDouble(now.left - target.left, now.top - target.top, 0, 1)
                      ..scaleByDouble(now.width / target.width, now.height / target.height, 1, 1),
                    child: child,
                  ),
                );
              },
              child: Semantics(
                image: true,
                label: '$label. Zum Drehen ziehen.',
                child: PuzzlePicture(
                  image: RepoScope.of(context).repo.puzzleImage(p),
                  builder: (context, img) {
                    final shape = pieceShape(cut, slot, board, img == null ? board : Size(img.width.toDouble(), img.height.toDouble()));
                    return Tile3D(
                      key: const Key('piece-in-hand'),
                      cacheKey: '${p.imageId}/$slot',
                      outline: shape.outline,
                      image: img,
                      source: shape.source,
                      tier: tier,
                      width: width,
                      back: (context) => PieceBack(tier: tier, ngoName: p.ngoName, title: p.title),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              left: VSpace.l,
              right: VSpace.l,
              top: target.bottom + VSpace.xl + width * 0.12,
              child: FadeTransition(
                opacity: words,
                child: IgnorePointer(
                  child: Column(
                    children: [
                      Text('Ein ${tierPieceName(tier)}', style: VText.h3.copyWith(color: VColors.inkOnDark), textAlign: TextAlign.center),
                      const VGap.s(),
                      Text(p.ngoName, style: VText.bodyStrong.copyWith(color: VColors.inkOnDark2), textAlign: TextAlign.center),
                      const VGap.xs(),
                      Text(keepLastWord(p.title), style: VText.body.copyWith(color: VColors.inkOnDark2), textAlign: TextAlign.center),
                      const VGap.s(),
                      Text('Platz ${slot + 1} von ${p.pieces}', style: VText.caption.copyWith(color: VColors.inkOnDark3), textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: VSpace.s,
              child: SafeArea(
                child: FadeTransition(
                  opacity: words,
                  child: Semantics(
                    label: 'Schließen',
                    button: true,
                    excludeSemantics: true,
                    onTap: close,
                    child: IconButton(
                      key: const Key('piece-in-hand-close'),
                      tooltip: 'Schließen',
                      iconSize: 26,
                      constraints: const BoxConstraints.tightFor(width: VControl.touch, height: VControl.touch),
                      icon: const Icon(Icons.close, color: VColors.inkOnDark),
                      onPressed: close,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The back of a piece: the card it is printed on, its tier's clock, whose it is and of what.
class PieceBack extends StatelessWidget {
  const PieceBack({super.key, required this.tier, required this.ngoName, required this.title});
  final PieceTier tier;
  final String ngoName;
  final String title;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => ColoredBox(
        color: VColors.track,
        child: Padding(
          // Clear of the knobs and holes, on the body of the piece.
          padding: EdgeInsets.all(c.biggest.shortestSide * 0.24),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: c.biggest.width * 0.52,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TierClock(tier, size: c.biggest.width * 0.2),
                    // Words only where they can be read: a small piece shows its clock alone.
                    if (c.biggest.width >= 160) ...[
                      const VGap.s(),
                      Text(ngoName, style: VText.bodySStrong, textAlign: TextAlign.center),
                      const SizedBox(height: 2),
                      Text(keepLastWord(title), style: VText.caption.copyWith(color: VColors.ink2), textAlign: TextAlign.center),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The back of a finished picture: the board it is mounted on, and what it is.
class PictureBack extends StatelessWidget {
  const PictureBack({super.key, required this.puzzle});
  final ApiPuzzle puzzle;

  @override
  Widget build(BuildContext context) {
    final done = puzzle.completedAt;
    return ColoredBox(
      color: VColors.track,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(VSpace.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(keepLastWord(puzzle.title), style: VText.title, textAlign: TextAlign.center),
              const VGap.xs(),
              Text(puzzle.ngoName, style: VText.bodyS, textAlign: TextAlign.center),
              if (done != null) ...[
                const VGap.s(),
                Text('Fertig am ${finishedOn(done)}', style: VText.caption, textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A finished picture as a thing in the hand: a print on board with an edge, that turns (§9a, §9b).
class PictureTile extends StatelessWidget {
  const PictureTile({super.key, required this.puzzle, required this.width, this.tilt, this.overlay});
  final ApiPuzzle puzzle;
  final double width;
  final TileTilt? tilt;

  /// Laid on the picture: the play button, once a picture can have a video (§9b).
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final p = puzzle;
    final board = boardFor(p);
    final outline = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & board, Radius.circular(board.width * VRadius.md / 300)));
    return PuzzlePicture(
      image: RepoScope.of(context).repo.puzzleImage(p),
      builder: (context, img) => Tile3D(
        key: const Key('picture-tile'),
        cacheKey: '${p.imageId}/picture',
        outline: outline,
        image: img,
        source: pictureSource(img == null ? board : Size(img.width.toDouble(), img.height.toDouble()), board, Offset.zero & board),
        width: width,
        depth: 0.025,
        tilt: tilt,
        overlay: overlay,
        back: (context) => PictureBack(puzzle: p),
      ),
    );
  }
}
