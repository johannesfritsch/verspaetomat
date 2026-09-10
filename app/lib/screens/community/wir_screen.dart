import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../api/events.dart';
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import '../claims/claims_widgets.dart';
import 'community_widgets.dart';

class _WirData {
  const _WirData(this.community);
  final ApiCommunity community;
}

/// Wir: the community. Minutes waited together, euros submitted and
/// confirmed, NGOs, boards.
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

  String get _scope => switch (_board) { 0 => 'line', 1 => 'city', _ => 'germany' };

  @override
  Widget build(BuildContext context) {
    final session = RepoScope.of(context);
    return Loader<_WirData>(
      controller: _loader,
      load: (repo) async {
        final c = await repo.community();
        return _WirData(c);
      },
      builder: (context, data, refresh) {
        final c = data.community;
        return VScreen(
          showBack: false,
          padding: const EdgeInsets.fromLTRB(VSpace.page, VSpace.l, VSpace.page, VSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TabHeader(title: 'Wir', caption: '${fmtInt(c.users)} Fahrgäste'),
              const VGap.xl(),
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
              const VGap.m(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: BigFigure(
                      value: fmtEuroWhole(c.submittedCents / 100),
                      label: 'Eingereicht',
                      onTap: () => showSourceSheet(
                        context,
                        title: 'Eingereichte Euro',
                        origin: 'Die Summe aller Anträge, die Fahrgäste über ihre Verspätomat-Adresse abgeschickt haben und die noch keine Antwort haben.',
                        freshness: 'Live',
                        fallback: 'Ein Antrag ohne Antwort bleibt hier, bis die Bahn schreibt.',
                      ),
                    ),
                  ),
                  Expanded(
                    child: BigFigure(
                      value: fmtEuroWhole(c.confirmedCents / 100),
                      label: 'Bestätigt',
                      onTap: () => showSourceSheet(
                        context,
                        title: 'Bestätigte Euro',
                        origin: 'Nur Geld, für das eine Antwort der Bahn oder eine Monatsmeldung des Vereins vorliegt. Wir raten nie.',
                        freshness: 'Antworten sofort, Vereinsmeldungen monatlich',
                        fallback: 'Bleibt bei „eingereicht“, bis ein Beleg da ist.',
                      ),
                    ),
                  ),
                ],
              ),
              const VGap.xl(),
              const VSection('Vereine'),
              for (final n in c.ngos) _ngoRow(context, n),
              const VGap.xl(),
              VSection('Ranglisten', trailing: Text('7 Tage', style: VText.caption)),
              const VGap.m(),
              SegmentTabs(labels: const ['Meine Linie', 'Meine Stadt', 'Deutschland'], index: _board, onChanged: (i) => setState(() => _board = i)),
              const VGap.s(),
              Text(
                switch (_board) { 0 => 'Deine häufigste Linie', 1 => session.me?.homeStation.isNotEmpty == true ? session.me!.homeStation : 'Deine Stadt', _ => 'Alle Fahrgäste' },
                style: VText.caption,
              ),
              const VGap.s(),
              _Board(scope: _scope),
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
                      Text('eingereicht: ${fmtEuroWhole(ngo.submittedCents / 100)}', style: VText.caption),
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

/// The board for one scope, loaded on its own so tab switches are cheap.
class _Board extends StatelessWidget {
  const _Board({required this.scope});
  final String scope;

  @override
  Widget build(BuildContext context) {
    return Loader<List<ApiBoardEntry>>(
      key: ValueKey(scope),
      load: (repo) => repo.boards(scope),
      builder: (context, entries, _) {
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
      },
    );
  }
}
