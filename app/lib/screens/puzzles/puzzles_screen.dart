import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../repo/repo_scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import '../claims/claims_widgets.dart' show Loader;
import 'piece_in_hand.dart' show showFinishedPicture;
import 'puzzle_sheet.dart';
import 'puzzle_widgets.dart';

/// „Deine Puzzles" (docs/51 §6): the pictures under way, then the finished ones.
///
/// Pictures nobody has started are not here — the surprise belongs to the arrival — and there is
/// no count across pictures, only „7 von 12" on each.
class PuzzlesScreen extends StatelessWidget {
  const PuzzlesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Loader<ApiPuzzles>(
      placeholder: (_) => const VScreen(eyebrow: 'Sammlung', title: 'Deine Puzzles', child: Column(children: [VSkeletonCard(), VGap.md(), VSkeletonCard()])),
      load: (repo) => repo.puzzles(),
      builder: (context, data, refresh) {
        // The films of finished pictures that are not on the phone yet (§9b).
        final videos = RepoScope.of(context).videos;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (final p in data.puzzles) {
            videos.ensure(p);
          }
        });
        return VScreen(
          eyebrow: 'Sammlung',
          title: 'Deine Puzzles',
          child: PuzzlesBody(puzzles: data),
        );
      },
    );
  }
}

/// The page under the header, on its own so every state can be pumped without a repository.
class PuzzlesBody extends StatelessWidget {
  const PuzzlesBody({super.key, required this.puzzles});
  final ApiPuzzles puzzles;

  @override
  Widget build(BuildContext context) {
    // The one most recently added to first, the newest finished first (§6).
    final ordered = puzzlesInOrder(puzzles);
    final started = ordered.where((p) => !p.complete).toList();
    final done = ordered.where((p) => p.complete).toList();

    if (started.isEmpty && done.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: VSpace.s),
        child: VCard(
          child: Row(
            children: [
              const SizedBox(width: 72, child: PuzzleBoard(cut: PuzzleCut(imageId: 'leer', rows: 4, cols: 3))),
              const SizedBox(width: VSpace.m),
              Expanded(
                child: Text(
                  puzzles.moreWaiting ? 'Deine erste Fahrt bringt das erste Teil.' : 'Noch keine Bilder. Sie kommen, wenn die Vereine welche schicken.',
                  style: VText.bodyStrong,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (started.isEmpty && !puzzles.moreWaiting) ...[
          const VGap.s(),
          Text('Alle Bilder sind fertig. Neue kommen, wenn die Vereine welche schicken.', style: VText.body),
        ],
        if (started.isNotEmpty) ...[
          const VSectionHeader('Angefangen', onCard: false),
          const VGap.s(),
          for (final p in started) ...[
            _StartedCard(key: ValueKey(p.imageId), puzzle: p),
            const VGap.md(),
          ],
        ],
        if (done.isNotEmpty) ...[
          const VSectionHeader('Fertig', onCard: false),
          const VGap.s(),
          // Two columns; a short row keeps its own height rather than stretching to the long one.
          for (var i = 0; i < done.length; i += 2) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _DoneTile(key: ValueKey(done[i].imageId), puzzle: done[i])),
                const SizedBox(width: VSpace.md),
                Expanded(child: i + 1 < done.length ? _DoneTile(key: ValueKey(done[i + 1].imageId), puzzle: done[i + 1]) : const SizedBox.shrink()),
              ],
            ),
            const VGap.md(),
          ],
        ],
      ],
    );
  }
}

class _StartedCard extends StatelessWidget {
  const _StartedCard({super.key, required this.puzzle});
  final ApiPuzzle puzzle;

  @override
  Widget build(BuildContext context) {
    final p = puzzle;
    // One node per picture for a screen reader: the board's label, the title, the Verein, the count.
    // A tap opens the picture whole, with its holes, or its pieces laid apart (docs/51 §6).
    return MergeSemantics(
      child: VCard(
        onTap: () => showPuzzle(context, p),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 112, child: PuzzleBoardOf(p)),
            const SizedBox(width: VSpace.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(keepLastWord(p.title), style: VText.title),
                  const VGap.xs(),
                  Text(p.ngoName, style: VText.bodyS),
                  const VGap.m(),
                  Text(puzzleProgress(p), style: VText.title),
                  if (stillMissing(p) case final missing?) ...[
                    const VGap.xs(),
                    Text(missing, style: VText.bodyS),
                  ],
                  // docs/51 §4, §9b: the picture becomes a film once it is finished. Said now, quietly.
                  if (p.hasVideo && !p.complete) ...[
                    const VGap.xs(),
                    Text('Bewegt sich, wenn es fertig ist.', style: VText.caption.copyWith(color: VColors.ink2)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoneTile extends StatelessWidget {
  const _DoneTile({super.key, required this.puzzle});
  final ApiPuzzle puzzle;

  @override
  Widget build(BuildContext context) {
    final p = puzzle;
    return MergeSemantics(
      child: VCard(
        padding: const EdgeInsets.all(VSpace.cardTight),
        onTap: () => showFinishedPicture(context, p),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A picture that moves says so in its corner (§9b).
            Stack(
              children: [
                PuzzleBoardOf(p, complete: true),
                if (p.hasVideo)
                  Positioned(
                    right: VSpace.s,
                    bottom: VSpace.s,
                    child: Container(
                      key: const Key('film-badge'),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(color: VColors.ink.withValues(alpha: 0.7), shape: BoxShape.circle),
                      child: const Icon(Icons.play_arrow_rounded, size: 16, color: VColors.inkOnDark),
                    ),
                  ),
              ],
            ),
            const VGap.s(),
            Text(keepLastWord(p.title), style: VText.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(p.ngoName, style: VText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
