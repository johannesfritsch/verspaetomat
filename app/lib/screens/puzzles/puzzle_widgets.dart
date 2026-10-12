import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'piece_in_hand.dart';
import 'puzzle_video.dart';

/// The cut of a picture off the wire.
PuzzleCut cutOf(ApiPuzzle p) => PuzzleCut(imageId: p.imageId, rows: p.rows, cols: p.cols);

/// „7 von 12": progress is only ever per picture (docs/51 §4, docs/47 — no second number).
String puzzleProgress(ApiPuzzle p) => '${p.owned.length} von ${p.pieces}';

/// A short last word kept with the one before it, so „Nachtschicht am Gleis 1" never leaves its
/// „1" alone on a line.
String keepLastWord(String s) {
  final i = s.lastIndexOf(' ');
  if (i < 0 || s.length - i - 1 > 4) return s;
  return '${s.substring(0, i)}\u00A0${s.substring(i + 1)}';
}

/// What a piece of a tier is called (docs/51 §2a).
String tierPieceName(PieceTier t) => switch (t) {
      PieceTier.minute => 'Minuten-Teil',
      PieceTier.quarter => 'Viertelstunden-Teil',
      PieceTier.hour => 'Stunden-Teil',
    };

/// „Fehlt noch: das Stunden-Teil." — for a picture that waits only for pieces an ordinary ride
/// does not bring (docs/51 §2a). Null while a minute would still do.
String? stillMissing(ApiPuzzle p) {
  final missing = p.missing.map(p.tierOf).toList();
  if (missing.isEmpty || missing.contains(PieceTier.minute)) return null;
  const words = ['', 'ein', 'zwei', 'drei', 'vier', 'fünf', 'sechs', 'sieben', 'acht', 'neun', 'zehn', 'elf', 'zwölf'];
  final parts = [
    for (final t in const [PieceTier.hour, PieceTier.quarter])
      if (missing.where((x) => x == t).length case final n when n > 0)
        n == 1 ? 'das ${tierPieceName(t)}' : '${n < words.length ? words[n] : '$n'} ${tierPieceName(t)}e',
  ];
  return 'Fehlt noch: ${parts.join(' und ')}.';
}

/// A picture as a board, its pixels from wherever the repository keeps them.
class PuzzleBoardOf extends StatelessWidget {
  const PuzzleBoardOf(this.puzzle, {super.key, this.complete, this.inHand = false});
  final ApiPuzzle puzzle;

  /// Defaults to the puzzle's own.
  final bool? complete;

  /// A tap on an owned piece lifts it into the hand (docs/51 §9a).
  final bool inHand;

  @override
  Widget build(BuildContext context) => PuzzleBoard(
        semanticLabel: (complete ?? puzzle.complete) ? 'Puzzle ${puzzle.title}, fertig' : 'Puzzle ${puzzle.title}, ${puzzleProgress(puzzle)} Teilen',
        cut: cutOf(puzzle),
        owned: puzzle.owned.toSet(),
        tiers: puzzle.slotTiers,
        image: RepoScope.of(context).repo.puzzleImage(puzzle),
        aspectRatio: puzzle.aspectRatio,
        complete: complete ?? puzzle.complete,
        onPieceTap: inHand ? (slot, rect) => showPieceInHand(context, puzzle, slot, from: rect) : null,
      );
}

/// What the arrival's card says to a screen reader: „Ein Stunden-Teil für Bahnhofsmission Köln,
/// 8 von 12", and the sentence under it when there is one.
String arrivalPieceLabel(ApiPuzzlePiece piece) {
  final p = piece.puzzle;
  final base = 'Ein ${tierPieceName(piece.tier)} ${piece.ownCause ? 'für' : 'von'} ${p.ngoName}, ${puzzleProgress(p)}';
  final more = p.complete ? 'Fertig: ${p.title}.${p.hasVideo ? ' Das Bild bewegt sich jetzt.' : ''}' : stillMissing(p);
  return more == null ? base : '$base. $more';
}

/// The piece an arrival brought (docs/51 §5), under the trip — or nothing, when the journey
/// brought none or the puzzles are switched off. Safe in every phase: no piece, no card.
class ArrivalPiece extends StatelessWidget {
  const ArrivalPiece({super.key, required this.piece, this.delay = const Duration(milliseconds: 1300)});
  final ApiPuzzlePiece? piece;

  /// How long the board waits before the piece comes in: until the minutes have counted up.
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final p = piece;
    if (p == null || !RepoScope.of(context).puzzlesOn) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: VSpace.s),
      child: ArrivalPieceCard(piece: p, delay: delay),
    );
  }
}

/// The card itself: the board with the new piece coming in, whose picture it is, „7 von 12".
/// A tap while the piece is still on its way puts it in place; after that it opens the Puzzles.
class ArrivalPieceCard extends StatefulWidget {
  const ArrivalPieceCard({super.key, required this.piece, this.delay = const Duration(milliseconds: 1300)});
  final ApiPuzzlePiece piece;
  final Duration delay;

  static const _reveal = Duration(milliseconds: 1200);

  /// An hour piece takes a little longer over its red light.
  static const _revealHour = Duration(milliseconds: 1500);
  static const _finish = Duration(milliseconds: 700);

  @override
  State<ArrivalPieceCard> createState() => _ArrivalPieceCardState();
}

class _ArrivalPieceCardState extends State<ArrivalPieceCard> with SingleTickerProviderStateMixin {
  /// `--dart-define=NO_ANIM=1`: the end state at once. The screenshot tour sets it.
  static const _still = String.fromEnvironment('NO_ANIM') == '1';

  late final AnimationController _c;
  late final Animation<double> _reveal;
  Animation<double>? _finish;
  late final Animation<double> _count;
  Animation<double>? _caption;
  bool _started = false;
  bool _ticked = false;

  bool get _completes => widget.piece.puzzle.complete;

  @override
  void initState() {
    super.initState();
    final delay = widget.delay.inMilliseconds;
    final reveal = (widget.piece.tier == PieceTier.hour ? ArrivalPieceCard._revealHour : ArrivalPieceCard._reveal).inMilliseconds;
    final finish = _completes ? ArrivalPieceCard._finish.inMilliseconds : 0;
    final total = delay + reveal + finish;
    _c = AnimationController(vsync: this, duration: Duration(milliseconds: total))
      ..addListener(_tick)
      // Once the piece is in, its board takes taps: an owned piece goes into the hand.
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) setState(() {});
      });
    _reveal = CurvedAnimation(parent: _c, curve: Interval(delay / total, (delay + reveal) / total));
    _count = CurvedAnimation(parent: _reveal, curve: const Interval(0.7, 1));
    if (_completes) {
      _finish = CurvedAnimation(parent: _c, curve: Interval((delay + reveal) / total, 1));
      _caption = CurvedAnimation(parent: _finish!, curve: const Interval(0.4, 1));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // The last piece of a picture with a film: the film comes now, while the finish plays (§9b).
    final p = widget.piece.puzzle;
    if (p.complete && p.video != null) RepoScope.read(context).videos.ensure(p);
    if (_still || MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  /// One tick as the piece clicks in, and only when it was seen doing so.
  void _tick() {
    if (_ticked || !_c.isAnimating || _reveal.value < PieceReveal.snapAt) return;
    _ticked = true;
    HapticFeedback.lightImpact();
  }

  void _tap() {
    if (_c.isAnimating) {
      _c.value = 1;
      return;
    }
    context.push(Routes.puzzles);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final piece = widget.piece;
    final p = piece.puzzle;
    final missing = stillMissing(p);
    // One node for a screen reader, whole from the first frame: what the fade shows a moment
    // later is no news to someone who does not see the fade.
    final board = PieceReveal(
      cut: cutOf(p),
      owned: p.owned.toSet(),
      piece: piece.piece,
      reveal: _reveal,
      finish: _finish,
      tiers: p.slotTiers,
      image: RepoScope.of(context).repo.puzzleImage(p),
      aspectRatio: p.aspectRatio,
    );
    return Semantics(
      container: true,
      button: true,
      label: arrivalPieceLabel(piece),
      excludeSemantics: true,
      onTap: _tap,
      customSemanticsActions: {
        CustomSemanticsAction(label: 'Das Teil in die Hand nehmen'): () => showPieceInHand(context, p, piece.piece),
        if (p.complete && p.hasVideo) CustomSemanticsAction(label: 'Video ansehen'): () => _watch(context, p),
      },
      // A plain detector rather than the card's own ink: the board's piece taps sit inside it and
      // must win where they land on a piece.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _tap,
        // The arrival and the „Aufgegeben" sheet are white: like the trip and the claim around it,
        // the card sits below the sheet rather than above it, or it has no edge at all.
        child: VCard(
          key: const Key('arrival-piece'),
          tone: VCardTone.sunken,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Narrow enough that a title like „Nachtschicht am Gleis 1" keeps to one line beside it.
              SizedBox(
                width: 100,
                child: _c.isCompleted
                    ? PuzzleTapArea(
                        cut: cutOf(p),
                        owned: p.owned.toSet(),
                        onPieceTap: (slot, rect) => showPieceInHand(context, p, slot, from: rect),
                        child: board,
                      )
                    : board,
              ),
              const SizedBox(width: VSpace.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    VEyebrow(piece.ownCause ? 'Ein Teil für ${p.ngoName}' : 'Ein Teil von ${p.ngoName}', tone: VEyebrowTone.red),
                    const VGap.xs(),
                    // The finish names the picture itself, a moment later.
                    if (!_completes) Text(keepLastWord(p.title), style: VText.title),
                    if (!piece.ownCause) ...[
                      const VGap.xs(),
                      Text('Ein Verein, den andere unterstützen.', style: VText.bodyS),
                    ],
                    const VGap.m(),
                    FadeTransition(
                      opacity: _count,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // docs/51 §5.3: the tier first, then where the picture stands — each whole,
                          // on the next line when both do not fit.
                          Wrap(
                            spacing: VSpace.xs,
                            children: [
                              Text('Ein ${tierPieceName(piece.tier)}.', style: VText.bodyStrong),
                              Text('${puzzleProgress(p)}.', style: VText.bodyStrong),
                            ],
                          ),
                          if (missing != null) ...[
                            const VGap.xs(),
                            Text(missing, style: VText.bodyS),
                          ],
                        ],
                      ),
                    ),
                    if (_caption != null)
                      FadeTransition(
                        opacity: _caption!,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const VGap.s(),
                            Text(keepLastWord('Fertig: ${p.title}.'), style: VText.bodyStrong),
                            if (p.caption.isNotEmpty) ...[
                              const VGap.xs(),
                              Text(p.caption, style: VText.bodyS),
                            ],
                            if (p.hasVideo) ...[
                              const VGap.s(),
                              Text('Das Bild bewegt sich jetzt.', style: VText.bodySStrong),
                              // Not to be hit before it can be seen.
                              AnimatedBuilder(
                                animation: _caption!,
                                builder: (context, child) => IgnorePointer(ignoring: _caption!.value < 1, child: child),
                                child: _WatchLink(puzzle: p),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The film when it is on the phone, else the finished picture, whose button shows it coming.
void _watch(BuildContext context, ApiPuzzle p) {
  final film = RepoScope.read(context).videos.stateOf(p);
  if (film.ready) {
    showPuzzleVideo(context, p, film);
  } else {
    showFinishedPicture(context, p);
  }
}

/// „Ansehen": the film when it is on the phone, else the finished picture, whose button shows it
/// coming (docs/51 §9b).
class _WatchLink extends StatelessWidget {
  const _WatchLink({required this.puzzle});
  final ApiPuzzle puzzle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('arrival-watch'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _watch(context, puzzle),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: VControl.touch),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_arrow_rounded, size: VControl.chevron, color: VColors.red),
            const SizedBox(width: VSpace.xs),
            Text('Ansehen', style: VText.link),
          ],
        ),
      ),
    );
  }
}

/// Ich's door to the Puzzles (docs/51 §6), with the picture under way as its preview.
class PuzzlesRow extends StatelessWidget {
  const PuzzlesRow({super.key, required this.puzzles});
  final ApiPuzzles puzzles;

  @override
  Widget build(BuildContext context) {
    final started = puzzles.puzzles.where((p) => !p.complete).firstOrNull;
    final done = puzzles.puzzles.where((p) => p.complete).firstOrNull;
    final shown = started ?? done;
    final String subtitle;
    if (started != null) {
      subtitle = '${started.ngoName} · ${puzzleProgress(started)}';
    } else if (done != null) {
      subtitle = 'Fertig: ${done.title}';
    } else {
      subtitle = 'Deine erste Fahrt bringt das erste Teil.';
    }
    return VListCard(
      key: const Key('ich-puzzles'),
      leading: SizedBox(
        width: 33,
        child: shown == null ? const PuzzleBoard(cut: PuzzleCut(imageId: 'leer', rows: 4, cols: 3)) : PuzzleBoardOf(shown),
      ),
      title: 'Puzzles',
      subtitle: subtitle,
      onTap: () => context.push(Routes.puzzles),
    );
  }
}

/// „3. Oktober", and the year only when it is not this one.
String finishedOn(DateTime at, {DateTime? now}) {
  const months = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];
  final d = at.toLocal();
  final year = (now ?? DateTime.now()).year == d.year ? '' : ' ${d.year}';
  return '${d.day}. ${months[d.month - 1]}$year';
}
