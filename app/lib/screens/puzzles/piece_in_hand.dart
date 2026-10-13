import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/models.dart';
import '../../mock/mock_data.dart' show Mock;
import '../../repo/repo_scope.dart';
import '../../state/puzzle_video_store.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'puzzle_video.dart';
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
class PieceInHand extends StatefulWidget {
  const PieceInHand({super.key, required this.puzzle, required this.slot, required this.animation, this.from});
  final ApiPuzzle puzzle;
  final int slot;
  final Rect? from;
  final Animation<double> animation;

  @override
  State<PieceInHand> createState() => _PieceInHandState();
}

class _PieceInHandState extends State<PieceInHand> {
  late final CurvedAnimation _flight = CurvedAnimation(parent: widget.animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
  late final CurvedAnimation _words = CurvedAnimation(parent: widget.animation, curve: const Interval(0.5, 1));

  /// The side it rests on: it rises front up, the switch at the bottom turns it over, and so does
  /// a swipe across it.
  final _back = ValueNotifier(false);

  @override
  void dispose() {
    _flight.dispose();
    _words.dispose();
    _back.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.puzzle;
    final slot = widget.slot;
    final from = widget.from;
    final animation = widget.animation;
    final tier = p.tierOf(slot);
    final screen = MediaQuery.sizeOf(context);
    final board = boardFor(p);
    final cut = cutOf(p);
    final cell = Size(board.width / cut.cols, board.height / cut.rows);
    final bounds = cut.piece(slot, cell).getBounds();
    // Sized and placed by its body, not by the box its knobs span: every piece's body is 55 % of the
    // screen wide — knobs on both sides then still clear the margins — and stands in the middle. Measured by the box, a knob
    // on one side only pushed the piece the other way, and knobs on both sides made it smaller.
    // It stands as low as a piece with knobs above and below would, so none rises above the line.
    final body = cut.cellRect(slot, cell);
    final scale = screen.width * 0.55 / body.width;
    final width = bounds.width * scale;
    final height = bounds.height * scale;
    final middle = Offset(screen.width / 2, screen.height * 0.16 + (cell.height / 2 + cell.shortestSide * PuzzleCut.knobReach) * scale);
    final target = (bounds.topLeft - body.center) * scale + middle & Size(width, height);
    final start = from ?? Rect.fromCenter(center: target.center, width: width * 0.4, height: height * 0.4);
    final flight = _flight;
    final words = _words;
    void close() => Navigator.of(context).maybePop();
    final label = 'Ein ${tierPieceName(tier)} von ${p.ngoName}, Platz ${slot + 1} von ${p.pieces}';

    final page = Semantics(
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
                      body: shape.body,
                      tier: tier,
                      width: width,
                      side: _back,
                      back: (context) => PieceBack(
                        tier: tier,
                        ngoName: p.ngoName,
                        title: p.title,
                        place: 'Platz ${slot + 1} von ${p.pieces}',
                        ride: p.rides[slot],
                        body: pieceBackBody(cut, slot, board),
                      ),
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
                      if (p.awardedAt[slot] case final at?) ...[
                        const SizedBox(height: 2),
                        Text('Bekommen am ${finishedOn(at)}', style: VText.caption.copyWith(color: VColors.inkOnDark3), textAlign: TextAlign.center),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            // Front or back, without having to find the swipe that turns it over.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: VSpace.l),
                  child: FadeTransition(
                    opacity: words,
                    child: Center(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _back,
                        builder: (context, back, _) => VSegmented<bool>(
                          key: const Key('piece-side'),
                          onDark: true,
                          segments: const [(false, 'Vorderseite'), (true, 'Rückseite')],
                          value: back,
                          onChanged: (v) => _back.value = v,
                        ),
                      ),
                    ),
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
    // Light status bar icons while the room goes dark under the piece; the route underneath sets its own back when this one
    // closes. On iOS this is the status bar's text, on Android its icons.
    return AnnotatedRegion<SystemUiOverlayStyle>(value: SystemUiOverlayStyle.light, child: page);
  }
}

/// The body of a piece, clear of its knobs and of the holes cut into it, as fractions of the box
/// its outline spans — mirrored left to right, because the back is seen from behind.
Rect pieceBackBody(PuzzleCut cut, int slot, Size board) {
  final cell = Size(board.width / cut.cols, board.height / cut.rows);
  final bounds = cut.piece(slot, cell).getBounds();
  final r = cut.cellRect(slot, cell);
  // A hole reaches about a third of a cell into the body; a knob or a flat side needs only a margin.
  double inset(PieceSide side) => cell.shortestSide * (cut.tab(slot, side) < 0 ? 0.33 : 0.1);
  final body = Rect.fromLTRB(r.left + inset(PieceSide.left), r.top + inset(PieceSide.top), r.right - inset(PieceSide.right), r.bottom - inset(PieceSide.bottom));
  return Rect.fromLTRB(
    (bounds.right - body.right) / bounds.width,
    (body.top - bounds.top) / bounds.height,
    (bounds.right - body.left) / bounds.width,
    (body.bottom - bounds.top) / bounds.height,
  );
}

/// The ride on the back of a piece, one short thing to a line, so that it fits the column a body
/// with holes on both sides leaves: „RE 1", „12. Okt.", „Köln Hbf", „→ Düsseldorf Hbf",
/// „68 Minuten" (or „pünktlich").
List<String> pieceRideLines(ApiPieceRide r) {
  final d = r.date;
  return [
    r.lines.join(', '),
    if (d != null) Mock.monthDate(d),
    r.from,
    '→ ${r.to}',
    r.minutes > 0 ? '${r.minutes} ${r.minutes == 1 ? 'Minute' : 'Minuten'}' : 'pünktlich',
  ].where((l) => l.isNotEmpty).toList();
}

/// The back of a piece: the card it is printed on, its tier's clock and name, whose it is, of
/// what, where it goes, and the ride that brought it.
class PieceBack extends StatelessWidget {
  const PieceBack({super.key, required this.tier, required this.ngoName, required this.title, this.place, this.ride, this.body});
  final PieceTier tier;
  final String ngoName;
  final String title;

  /// „Platz 5 von 12".
  final String? place;

  /// The ride that brought it. Null: a piece that names none, or a server before rides.
  final ApiPieceRide? ride;

  /// Where the words may go, from [pieceBackBody]. Without it, a margin all round.
  final Rect? body;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final size = c.biggest;
        final b = body;
        final area = b == null
            ? (Offset.zero & size).deflate(size.shortestSide * 0.24)
            : Rect.fromLTRB(b.left * size.width, b.top * size.height, b.right * size.width, b.bottom * size.height);
        return ColoredBox(
          color: VColors.track,
          child: Stack(
            children: [
              Positioned.fromRect(
                rect: area,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      // A ride's lines are short enough for the body's own width; set wider, the
                      // whole back would be scaled down to fit and the clock with it.
                      width: b == null ? size.width * 0.52 : math.max(area.width, ride != null ? 64 : 96),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TierClock(tier, size: math.min(size.width * 0.2, area.shortestSide * 0.42)),
                          // Words only where they can be read: a small piece shows its clock alone.
                          // With a ride, the clock and the ride: what it is, whose and where it goes
                          // stand on the page under the piece, and a body cut in on two sides has
                          // room for three short lines, not seven. Without one, as before — a body
                          // cut in on every side what the piece is and where it goes, the Verein
                          // and the picture under it as well.
                          if (size.width >= 160 && ride != null) ...[
                            const VGap.s(),
                            for (final (i, line) in pieceRideLines(ride!).indexed)
                              Text(line, style: i == 0 ? VText.bodySStrong : VText.caption, textAlign: TextAlign.center),
                          ] else if (size.width >= 160) ...[
                            const VGap.s(),
                            Text(tierPieceName(tier), style: VText.bodySStrong, textAlign: TextAlign.center),
                            if (area.width >= 120) ...[
                              const VGap.s(),
                              Text(ngoName, style: VText.bodySStrong, textAlign: TextAlign.center),
                              const SizedBox(height: 2),
                              Text(keepLastWord(title), style: VText.caption.copyWith(color: VColors.ink2), textAlign: TextAlign.center),
                            ],
                            if (place != null) ...[
                              const SizedBox(height: 2),
                              Text(place!, style: VText.caption, textAlign: TextAlign.center),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The back of a finished picture, set like the back of a printed card: whose it is, what it
/// shows, the Verein's sentence, the day it was finished, and that it moves.
class PictureBack extends StatelessWidget {
  const PictureBack({super.key, required this.puzzle});
  final ApiPuzzle puzzle;

  @override
  Widget build(BuildContext context) {
    final p = puzzle;
    final done = p.completedAt;
    return ColoredBox(
      color: VColors.track,
      child: Padding(
        padding: const EdgeInsets.all(VSpace.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VEyebrow(p.ngoName),
            const VGap.s(),
            Text(keepLastWord(p.title), style: VText.h3),
            if (p.caption.isNotEmpty) ...[
              const VGap.s(),
              Text(p.caption, style: VText.bodyS),
            ],
            const Spacer(),
            Row(
              children: [
                if (done != null) Expanded(child: Text('Fertig am ${finishedOn(done)}', style: VText.caption)) else const Spacer(),
                if (p.hasVideo) const Icon(Icons.play_circle_outline, size: VControl.chevron, color: VColors.ink2),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A finished picture as a thing in the hand: a print on board with an edge, that turns (§9a), and
/// with its film's button on it when it has one (§9b). A tap plays the film once it is here.
class PictureTile extends StatefulWidget {
  const PictureTile({super.key, required this.puzzle, required this.width, this.tilt});
  final ApiPuzzle puzzle;
  final double width;
  final TileTilt? tilt;

  @override
  State<PictureTile> createState() => _PictureTileState();
}

class _PictureTileState extends State<PictureTile> {
  final _button = GlobalKey<_FilmButtonState>();
  bool _asked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked) return;
    _asked = true;
    // A finished picture whose film is not on the phone yet: fetch it now (§9b).
    final p = widget.puzzle;
    if (p.complete && p.video != null) RepoScope.read(context).videos.ensure(p);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.puzzle;
    final board = boardFor(p);
    final outline = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & board, Radius.circular(board.width * VRadius.md / 300)));
    final session = RepoScope.of(context);
    final film = p.video != null && p.complete ? session.videos : null;
    final button = film == null ? null : _FilmButton(key: _button, puzzle: p, store: film);
    return PuzzlePicture(
      image: session.repo.puzzleImage(p),
      builder: (context, img) => Tile3D(
        key: const Key('picture-tile'),
        cacheKey: '${p.imageId}/picture',
        outline: outline,
        image: img,
        source: pictureSource(img == null ? board : Size(img.width.toDouble(), img.height.toDouble()), board, Offset.zero & board),
        width: widget.width,
        depth: 0.018,
        tilt: widget.tilt,
        overlay: button == null ? null : Align(alignment: Alignment.bottomCenter, child: Padding(padding: const EdgeInsets.only(bottom: VSpace.l), child: button)),
        onTap: button == null ? null : () => _button.currentState?.press(),
        back: (context) => PictureBack(puzzle: p),
      ),
    );
  }
}

/// The round button on a finished picture with a film: play when it is here, a ring while it
/// comes, a way to try again when it did not.
class _FilmButton extends StatefulWidget {
  const _FilmButton({super.key, required this.puzzle, required this.store});
  final ApiPuzzle puzzle;
  final PuzzleVideoStore store;

  @override
  State<_FilmButton> createState() => _FilmButtonState();
}

class _FilmButtonState extends State<_FilmButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 360));

  /// Play when it is here; while it comes, the ring answers with a pulse; after a failure, again.
  void press() {
    final state = widget.store.stateOf(widget.puzzle);
    switch (state.phase) {
      case VideoPhase.ready:
        showPuzzleVideo(context, widget.puzzle, state);
      case VideoPhase.failed:
        widget.store.retry(widget.puzzle);
      case VideoPhase.none:
        widget.store.ensure(widget.puzzle);
        _pulse.forward(from: 0);
      case VideoPhase.queued || VideoPhase.downloading:
        _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PuzzleVideoState>(
      valueListenable: widget.store.watch(widget.puzzle),
      builder: (context, state, _) {
        final loading = state.phase == VideoPhase.queued || state.phase == VideoPhase.downloading || state.phase == VideoPhase.none;
        final label = switch (state.phase) {
          VideoPhase.ready => 'Video abspielen',
          VideoPhase.failed => 'Video nicht geladen, noch einmal versuchen',
          _ => 'Video lädt',
        };
        return Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          onTap: press,
          child: GestureDetector(
            key: const Key('film-button'),
            behavior: HitTestBehavior.opaque,
            onTap: press,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) => Transform.scale(scale: 1 + 0.12 * math.sin(math.pi * _pulse.value), child: child),
              child: SizedBox.square(
                dimension: VControl.badge,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: VControl.badge,
                      height: VControl.badge,
                      decoration: BoxDecoration(color: VColors.ink.withValues(alpha: 0.7), shape: BoxShape.circle),
                      child: Icon(
                        state.phase == VideoPhase.failed ? Icons.refresh : Icons.play_arrow_rounded,
                        color: VColors.inkOnDark.withValues(alpha: state.ready || state.phase == VideoPhase.failed ? 1 : 0.55),
                        size: state.phase == VideoPhase.failed ? VControl.badgeIcon : 30,
                      ),
                    ),
                    if (loading)
                      SizedBox.square(
                        dimension: VControl.badge - 4,
                        child: CircularProgressIndicator(
                          key: const Key('film-progress'),
                          value: state.phase == VideoPhase.downloading ? state.progress : null,
                          strokeWidth: 2.5,
                          color: VColors.inkOnDark,
                          backgroundColor: VColors.trackOnDark,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
