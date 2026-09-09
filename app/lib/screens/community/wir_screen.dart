import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../mock/mock_data.dart';
import '../../router.dart';
import '../../state/demo_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'community_widgets.dart';

/// Wir: the community. Minutes waited together, euros submitted and
/// confirmed, campaigns, boards, teams.
class WirScreen extends StatefulWidget {
  const WirScreen({super.key});

  @override
  State<WirScreen> createState() => _WirScreenState();
}

class _WirScreenState extends State<WirScreen> {
  int _minutes = Mock.communityMinutes;
  int _board = 0;
  Timer? _timer;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _tick++;
      setState(() => _minutes += 1 + (_tick * 7) % 3);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  List<BoardEntry> get _entries => switch (_board) {
        0 => Mock.boardLine,
        1 => Mock.boardCity,
        _ => Mock.boardGermany,
      };

  @override
  Widget build(BuildContext context) {
    final state = DemoScope.of(context);
    final entries = _entries;
    final top = entries.where((e) => e.rank <= 10).toList();
    final me = entries.where((e) => e.isMe && e.rank > 10).toList();

    return VScreen(
      showBack: false,
      padding: const EdgeInsets.fromLTRB(VSpace.page, VSpace.l, VSpace.page, VSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TabHeader(title: 'Wir', caption: '${fmtInt(Mock.communityUsers)} Fahrgäste'),
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
                  Text(fmtInt(_minutes), style: VText.number),
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
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: BigFigure(
                  value: '${fmtInt(Mock.communitySubmitted.round())} €',
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
                  value: '${fmtInt((Mock.communityConfirmed + state.confirmedTotal - Mock.incidents.where((i) => i.status == IncidentStatus.bestaetigt).fold(0.0, (s, i) => s + i.amount)).round())} €',
                  label: 'Bestätigt',
                  style: VText.number.copyWith(fontSize: 40, letterSpacing: -1.2),
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
          const VSection('Kampagnen'),
          for (final ngo in Mock.ngos) _campaignRow(context, ngo),
          const VGap.xl(),
          VSection('Ranglisten', trailing: Text('7 Tage', style: VText.caption)),
          const VGap.m(),
          SegmentTabs(labels: const ['Meine Linie', 'Meine Stadt', 'Deutschland'], index: _board, onChanged: (i) => setState(() => _board = i)),
          const VGap.s(),
          Text(
            switch (_board) { 0 => 'RE 7 Köln – Rheine', 1 => 'Köln', _ => 'Alle Fahrgäste' },
            style: VText.caption,
          ),
          const VGap.s(),
          for (final e in top) BoardRow(entry: e),
          if (me.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('· · ·', style: VText.caption.copyWith(letterSpacing: 4)),
            ),
            for (final e in me) BoardRow(entry: e),
          ],
          const VGap.s(),
          Text(
            state.showOnBoards ? 'Nur verifizierte Fahrten zählen.' : 'Nur verifizierte Fahrten zählen. Du bist in den Ranglisten verborgen.',
            style: VText.caption,
          ),
          const VGap.xl(),
          const VSection('Teams'),
          for (final t in Mock.teams)
            VListRow(
              title: t.name,
              subtitle: '${t.members} Mitglieder · ${fmtInt(t.minutes)} Minuten · ${fmtEuro(t.euros)}',
              chevron: true,
              onTap: () => context.push('${Routes.team}?id=${t.id}'),
            ),
          const VGap.s(),
          VGhostButton(label: 'Team gründen', icon: Icons.add, onTap: () => _foundTeam(context)),
        ],
      ),
    );
  }

  Widget _campaignRow(BuildContext context, Ngo ngo) {
    final confirmed = (ngo.campaignConfirmed / ngo.campaignGoal).clamp(0.0, 1.0);
    final submitted = (ngo.campaignSubmitted / ngo.campaignGoal).clamp(0.0, 1.0);
    return InkWell(
      onTap: () => context.push('${Routes.zweck}?id=${ngo.id}'),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(ngo.name, style: VText.bodyStrong)),
                    const Icon(Icons.chevron_right, size: 20, color: VColors.ink3),
                  ],
                ),
                const SizedBox(height: 10),
                VProgress(confirmed: confirmed, submitted: submitted),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${fmtEuro(ngo.campaignConfirmed)} von ${fmtEuro(ngo.campaignGoal)}',
                        style: VText.caption.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                    ),
                    Text(ngo.campaignDeadline, style: VText.caption),
                  ],
                ),
              ],
            ),
          ),
          const VRule(),
        ],
      ),
    );
  }

  void _foundTeam(BuildContext context) {
    final ctrl = TextEditingController();
    showVSheet(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(bottom: VSpace.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const VSheetHeader(title: 'Team gründen', subtitle: 'Ein Name, ein Link. Fertig.'),
            Padding(
              padding: const EdgeInsets.fromLTRB(VSpace.page, VSpace.s, VSpace.page, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'z. B. Büro Nord'), style: VText.body),
                  const VGap.m(),
                  Container(
                    padding: const EdgeInsets.all(VSpace.m),
                    decoration: BoxDecoration(border: Border.all(color: VColors.rule), borderRadius: BorderRadius.circular(4)),
                    child: Row(
                      children: [
                        Expanded(child: Text('verspaetomat.de/t/8f2k1', style: VText.mono)),
                        const Icon(Icons.link, size: 20, color: VColors.ink2),
                      ],
                    ),
                  ),
                  const VGap.m(),
                  VPrimaryButton(
                    label: 'Link teilen',
                    icon: Icons.ios_share,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      showSnack(context, 'Link kopiert. Wer ihn öffnet, ist im Team.');
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
