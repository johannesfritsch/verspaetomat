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
import '../../widgets/ticket.dart';
import '../share/share_lines.dart';
import '../share/share_sheet.dart';

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
        return VTabScaffold(
          sceneHeart: true,
          onRefresh: () async => refresh(),
          header: VTabHeader(
            title: 'Wir',
            subtitle: '${fmtInt(c.users)} Fahrgäste',
            tagline: 'Gemeinsam mehr bewegen.',
            narrow: true,
            onSettings: () => context.push(Routes.einstellungen).then((_) => refresh()),
          ),
          children: [
            // The community's big number first (docs/18); no community euro totals here. Wir takes
            // the red board and Home the dark one, so the two copies of the same figure read as
            // two looks of one object rather than as two different claims (docs/43).
            VBoard(
              look: VBoardLook.red,
              onTap: () => showSourceSheet(
                context,
                title: 'Minuten zusammen gewartet',
                origin: 'Die Summe aller endgültigen Verspätungen aller Fahrgäste, Minute für Minute.',
                freshness: 'Live',
              ),
              aside: const Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  VHandNote(
                    'Aus\nVerspätung\nwird\nGutes.',
                    angle: -0.09,
                    align: TextAlign.right,
                    color: VColors.inkOnDark2,
                  ),
                  VGap.s(),
                  VHeartMark(),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const VBoardLabel('Zusammen gewartet', icon: Icons.groups_outlined),
                  const VGap.s(),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      fmtInt(c.minutes + _extraMinutes),
                      style: VText.number.copyWith(color: VColors.inkOnDark),
                    ),
                  ),
                  const VGap.md(),
                  const VBoardCaption('Minuten, von uns allen zusammen'),
                ],
              ),
            ),

            // docs/27 §2: the collective number, which nobody's own ego is in — which is exactly
            // why it is the one people pass on.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 3,
                  child: VTintButton(
                    label: 'Teilen',
                    icon: Icons.ios_share,
                    onTap: () => showShareSheet(
                      context,
                      lines: ShareLines.wir(minutes: c.minutes + _extraMinutes),
                      build: ({fahrgast, strecke, date, line}) => TicketData.wir(
                        minutes: c.minutes + _extraMinutes,
                        people: c.users,
                        line: line,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: VSpace.s),
                const Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      VHandArrow(),
                      SizedBox(width: VSpace.xs),
                      Flexible(
                        child: VHandNote('Zeig, was wir\ngemeinsam schaffen!', angle: -0.06),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Every block on this screen stands on a card (issue #13, docs/37). Each Verein is its
            // own card now rather than a row in a shared one: three cards read as three partners,
            // where three rules read as a table of them.
            VSectionHeader(
              'Vereine',
              wide: true,
              onCard: false,
              linkLabel: 'Mehr erfahren',
              onLink: () => context.push(Routes.zweck),
            ),
            for (final n in c.ngos) _NgoCard(ngo: n),

            VCard(
              tone: VCardTone.sunken,
              padding: const EdgeInsets.all(VSpace.cardTight),
              child: Row(
                children: [
                  const VIconBadge(
                    icon: Icons.groups,
                    tone: VBadgeTone.neutral,
                    size: VControl.badgeSmall,
                  ),
                  const SizedBox(width: VSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${fmtInt(c.users)} Menschen machen mit.', style: VText.bodyStrong),
                        Text('Danke, dass du Teil davon bist.', style: VText.bodyS),
                      ],
                    ),
                  ),
                  const SizedBox(width: VSpace.s),
                  const VHeartMark(size: 20, color: VColors.redTint),
                  const SizedBox(width: VSpace.xs),
                  const VHandNote('Gemeinsam\nwirken.', angle: -0.12),
                ],
              ),
            ),

            // No mockup covers the boards. They keep the structure they had and take the new card.
            VSectionHeader('Ranglisten', wide: true, onCard: false),
            VCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (st.board != null) ...[
                    _RankLine(board: st.board!),
                    const VGap.m(),
                  ],
                  SegmentTabs(
                    labels: const ['Meine Linie', 'Meine Stadt', 'Deutschland'],
                    index: _board,
                    onChanged: (i) => setState(() => _board = i),
                  ),
                  const VGap.s(),
                  Text(
                    switch (_board) {
                      0 => 'Deine häufigste Linie',
                      1 => session.me?.homeStation.isNotEmpty == true
                          ? session.me!.homeStation
                          : 'Deine Stadt',
                      _ => 'Alle Fahrgäste',
                    },
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
                    (session.me?.settings.showOnBoards ?? true)
                        ? 'Nur verifizierte Fahrten zählen.'
                        : 'Nur verifizierte Fahrten zählen. Du bist in den Ranglisten verborgen.',
                    style: VText.caption,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One Verein, on its own card.
///
/// The circle carries the partner's identity, and identity is the one job colour has in this app.
/// The glyph and the tint are guessed from the name here, which is a stand-in: they belong in the
/// managed NGO data next to the logo, so a new partner does not need an app release (docs/43 §5).
class _NgoCard extends StatelessWidget {
  const _NgoCard({required this.ngo});
  final ApiNgoTotal ngo;

  /// Keyword first, so the three partners we ship with look drawn rather than generated; then a
  /// stable fallback off the id, so a fourth partner is at least consistent with itself.
  (IconData, VBadgeTone) get _mark {
    final n = ngo.name.toLowerCase();
    if (n.contains('wald') || n.contains('baum') || n.contains('natur')) {
      return (Icons.forest, VBadgeTone.greenBright);
    }
    if (n.contains('hospiz') || n.contains('kinder')) {
      return (Icons.house, VBadgeTone.blue);
    }
    if (n.contains('bahnhofsmission') || n.contains('mission')) {
      return (Icons.volunteer_activism, VBadgeTone.red);
    }
    const rest = [VBadgeTone.teal, VBadgeTone.blueDeep, VBadgeTone.green, VBadgeTone.red];
    final id = ngo.id.isEmpty ? ngo.name : ngo.id;
    return (Icons.volunteer_activism, rest[id.codeUnits.fold(0, (a, b) => a + b) % rest.length]);
  }

  @override
  Widget build(BuildContext context) {
    final (icon, tone) = _mark;
    return VListCard(
      leading: VIconBadge(icon: icon, tone: tone, size: VControl.badgeSmall),
      title: ngo.name,
      subtitle: 'Geschichte und Zweck',
      trailing: Text(fmtEuroWhole(ngo.confirmedCents / 100), style: VText.numberS),
      onTap: () => context.push('${Routes.zweck}?id=${ngo.id}'),
    );
  }
}

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
