import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../api/events.dart';
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../screens/ride/ride_widgets.dart' show shortError;
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import '../claims/claims_widgets.dart';
import 'community_widgets.dart';

class _WirData {
  const _WirData(this.community, this.standing, this.boards);
  final ApiCommunity community;
  final ApiStanding standing;

  /// All three boards, loaded with the rest of Wir (docs/22 §2). A tab switch then only
  /// swaps rows that are already there: no loader, no height change, no scroll jump.
  final Map<String, _BoardData> boards;
}

/// One board as it came back: its rows, or why they are missing.
class _BoardData {
  const _BoardData(this.entries, this.error);
  final List<ApiBoardEntry> entries;
  final String? error;
}

const _boardScopes = ['line', 'city', 'germany'];

/// Wir: the community. Minutes waited together, the Vereine, the boards (docs/20: nothing
/// about the customer alone here; that is Ich).
class WirScreen extends StatefulWidget {
  const WirScreen({super.key});

  @override
  State<WirScreen> createState() => _WirScreenState();
}

class _WirScreenState extends State<WirScreen> {
  StreamSubscription<AppEvent>? _eventSub;
  final _loader = LoaderController();
  int _board = 0;
  int _extraMinutes = 0;
  Timer? _timer;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    _eventSub = RepoScope.read(context).events.listen((e) {
      if (mounted && e.touchesLedger) _loader.refresh();
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _tick++;
      setState(() => _extraMinutes += 1 + (_tick * 7) % 3);
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = RepoScope.of(context);
    return Loader<_WirData>(
      controller: _loader,
      load: (repo) async {
        final c = await repo.community();
        final st = await repo.standing().catchError((_) => ApiStanding.empty);
        final boards = <String, _BoardData>{};
        for (final scope in _boardScopes) {
          try {
            boards[scope] = _BoardData(await repo.boards(scope), null);
          } catch (e) {
            boards[scope] = _BoardData(const [], shortError(e));
          }
        }
        return _WirData(c, st, boards);
      },
      builder: (context, data, refresh) {
        final c = data.community;
        final st = data.standing;
        return VScreen(
          showBack: false,
          padding: const EdgeInsets.fromLTRB(VSpace.page, VSpace.l, VSpace.page, VSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TabHeader(title: 'Wir', caption: '${fmtInt(c.users)} Fahrgäste', onSettings: () => context.push(Routes.einstellungen).then((_) => refresh())),
              const VGap.xl(),

              // The community's big number first (docs/18); no community euro totals here.
              Text('ZUSAMMEN GEWARTET', style: VText.eyebrow),
              const SizedBox(height: 6),
              InkWell(
                onTap: () => showSourceSheet(
                  context,
                  title: 'Minuten zusammen gewartet',
                  origin: 'Die Summe aller endgültigen Verspätungen aller Fahrgäste, Minute für Minute.',
                  freshness: 'Live',
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(fmtInt(c.minutes + _extraMinutes), style: VText.number),
                      const SizedBox(width: 10),
                      Text('Minuten', style: VText.title.copyWith(color: VColors.ink2)),
                    ],
                  ),
                ),
              ),
              const VGap.l(),
              const VRule.red(),
              const VGap.l(),

              const VSection('Vereine'),
              for (final n in c.ngos) _ngoRow(context, n),
              const VGap.xl(),
              VSection('Ranglisten', trailing: Text('7 Tage', style: VText.caption)),
              const VGap.m(),
              if (st.board != null) ...[
                _RankLine(board: st.board!),
                const VGap.m(),
              ],
              SegmentTabs(labels: const ['Meine Linie', 'Meine Stadt', 'Deutschland'], index: _board, onChanged: (i) => setState(() => _board = i)),
              const VGap.s(),
              Text(
                switch (_board) { 0 => 'Deine häufigste Linie', 1 => session.me?.homeStation.isNotEmpty == true ? session.me!.homeStation : 'Deine Stadt', _ => 'Alle Fahrgäste' },
                style: VText.caption,
              ),
              const VGap.s(),
              IndexedStack(
                index: _board,
                alignment: Alignment.topLeft,
                sizing: StackFit.loose,
                children: [for (final scope in _boardScopes) _Board(board: data.boards[scope])],
              ),
              const VGap.s(),
              Text(
                (session.me?.settings.showOnBoards ?? true) ? 'Nur verifizierte Fahrten zählen.' : 'Nur verifizierte Fahrten zählen. Du bist in den Ranglisten verborgen.',
                style: VText.caption,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _ngoRow(BuildContext context, ApiNgoTotal ngo) {
    return InkWell(
      onTap: () => context.push('${Routes.zweck}?id=${ngo.id}'),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ngo.name, style: VText.bodyStrong),
                      const SizedBox(height: 2),
                      Text('Geschichte und Zweck', style: VText.caption),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(fmtEuroWhole(ngo.confirmedCents / 100), style: VText.numberM),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, size: 20, color: VColors.ink3),
              ],
            ),
          ),
          const VRule(),
        ],
      ),
    );
  }
}

/// One board's rows, already in hand (docs/22 §2). Switching tabs must never load, because
/// a loader is shorter than a board and the page would jump under the reader's thumb.
class _Board extends StatelessWidget {
  const _Board({required this.board});
  final _BoardData? board;

  @override
  Widget build(BuildContext context) {
    final b = board;
    if (b == null) return Text('Rangliste wird geladen …', style: VText.caption);
    if (b.error != null) return Text('Rangliste nicht erreichbar: ${b.error}', style: VText.caption.copyWith(color: VColors.red));
    final entries = b.entries;
    final top = entries.where((e) => e.rank <= 10).toList();
    final me = entries.where((e) => e.isMe && e.rank > 10).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (entries.isEmpty) Text('Noch niemand auf dieser Liste.', style: VText.caption),
        for (final e in top) BoardRow(entry: e),
        if (me.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('· · ·', style: VText.caption.copyWith(letterSpacing: 4)),
          ),
          for (final e in me) BoardRow(entry: e),
        ],
      ],
    );
  }
}

/// The customer's own place, above the boards: "Platz 5 auf der RE 7 diese Woche · 38 Punkte bis Platz 4".
class _RankLine extends StatelessWidget {
  const _RankLine({required this.board});
  final ApiStandingBoard board;

  @override
  Widget build(BuildContext context) {
    final where = board.scope == 'city' ? 'in ${board.key}' : 'auf der ${board.key}';
    final gap = board.gapToNext == null
        ? 'ganz oben'
        : '${fmtInt(board.gapToNext!)} ${board.gapToNext == 1 ? 'Punkt' : 'Punkte'} bis Platz ${board.rank - 1}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('Platz ${board.rank}', style: VText.numberM),
        const SizedBox(width: 10),
        Expanded(child: Text('$where diese Woche · $gap', style: VText.caption, maxLines: 2)),
      ],
    );
  }
}
