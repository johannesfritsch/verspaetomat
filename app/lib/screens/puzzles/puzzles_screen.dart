import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import '../claims/claims_widgets.dart' show Loader;
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
      builder: (context, data, refresh) => VScreen(
        eyebrow: 'Sammlung',
        title: 'Deine Puzzles',
        child: PuzzlesBody(puzzles: data),
      ),
    );
  }
}

/// The page under the header, on its own so every state can be pumped without a repository.
class PuzzlesBody extends StatelessWidget {
  const PuzzlesBody({super.key, required this.puzzles});
  final ApiPuzzles puzzles;

  @override
  Widget build(BuildContext context) {
    final started = puzzles.puzzles.where((p) => !p.complete).toList();
    final done = puzzles.puzzles.where((p) => p.complete).toList();

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
            _StartedCard(puzzle: p),
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
                Expanded(child: _DoneTile(puzzle: done[i])),
                const SizedBox(width: VSpace.md),
                Expanded(child: i + 1 < done.length ? _DoneTile(puzzle: done[i + 1]) : const SizedBox.shrink()),
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
  const _StartedCard({required this.puzzle});
  final ApiPuzzle puzzle;

  @override
  Widget build(BuildContext context) {
    final p = puzzle;
    return VCard(
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DoneTile extends StatelessWidget {
  const _DoneTile({required this.puzzle});
  final ApiPuzzle puzzle;

  @override
  Widget build(BuildContext context) {
    final p = puzzle;
    return VCard(
      padding: const EdgeInsets.all(VSpace.cardTight),
      onTap: () => _show(context, p),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PuzzleBoardOf(p, complete: true),
          const VGap.s(),
          Text(keepLastWord(p.title), style: VText.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(p.ngoName, style: VText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  /// The picture large, with the Verein's sentence and the day the last piece came.
  void _show(BuildContext context, ApiPuzzle p) {
    showVSheet<void>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(bottom: VSpace.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VSheetHeader(title: p.title, subtitle: p.ngoName),
            Padding(
              padding: const EdgeInsets.fromLTRB(VSpace.sheet, VSpace.s, VSpace.sheet, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: ConstrainedBox(
                      // The whole picture on a phone, without pushing the sentence off the sheet.
                      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.5),
                      child: PuzzleBoardOf(p, complete: true),
                    ),
                  ),
                  if (p.caption.isNotEmpty) ...[
                    const VGap.m(),
                    Text(p.caption, style: VText.bodyL),
                  ],
                  if (p.completedAt != null) ...[
                    const VGap.s(),
                    Text('Fertig am ${finishedOn(p.completedAt!)}', style: VText.caption),
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

/// „3. Oktober", and the year only when it is not this one.
String finishedOn(DateTime at, {DateTime? now}) {
  const months = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];
  final d = at.toLocal();
  final year = (now ?? DateTime.now()).year == d.year ? '' : ' ${d.year}';
  return '${d.day}. ${months[d.month - 1]}$year';
}
