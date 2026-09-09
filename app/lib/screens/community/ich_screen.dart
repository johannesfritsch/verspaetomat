import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../mock/mock_data.dart';
import '../../router.dart';
import '../../state/demo_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'community_widgets.dart';

/// Ich: level, badges, statistics, teams.
class IchScreen extends StatelessWidget {
  const IchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = DemoScope.of(context);
    final rides = state.rides;
    final delayed = rides.where((r) => r.delay > 0).toList();
    final avg = delayed.isEmpty ? 0 : (delayed.fold(0, (s, r) => s + r.delay) / delayed.length).round();
    final longest = rides.fold(0, (m, r) => r.delay > m ? r.delay : m);
    final byLine = <String, int>{};
    for (final r in rides) {
      byLine[r.line] = (byLine[r.line] ?? 0) + r.delay;
    }
    final patientLine = byLine.entries.fold<MapEntry<String, int>?>(null, (m, e) => m == null || e.value > m.value ? e : m)?.key ?? 'RE 7';
    const minutesThisYear = 1372;
    final progress = (Mock.pointsTotal / Mock.nextLevelAt).clamp(0.0, 1.0);
    final earned = Mock.badges.where((b) => b.earned).length;

    return VScreen(
      showBack: false,
      padding: const EdgeInsets.fromLTRB(VSpace.page, VSpace.l, VSpace.page, VSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TabHeader(
            title: Mock.userName,
            caption: Mock.levelName,
            trailing: VIconButton(icon: Icons.settings_outlined, onTap: () => context.push(Routes.einstellungen)),
          ),
          const VGap.xl(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(fmtInt(Mock.pointsTotal), style: VText.number),
              const SizedBox(width: 10),
              Text('Geduldspunkte', style: VText.title.copyWith(color: VColors.ink2)),
            ],
          ),
          const VGap.m(),
          VProgress(confirmed: progress),
          const SizedBox(height: 8),
          Text('${fmtInt(Mock.nextLevelAt - Mock.pointsTotal)} bis „${Mock.nextLevelName}“', style: VText.caption),
          const VGap.l(),
          const VRule.red(),
          const VGap.m(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: BigFigure(value: '+${Mock.pointsThisWeek + state.bonusPoints}', label: 'Diese Woche')),
              Expanded(child: BigFigure(value: '${rides.length}', label: 'Fahrten, letzte 14 Tage')),
            ],
          ),
          const VGap.xl(),
          VSection('Abzeichen', trailing: Text('$earned von ${Mock.badges.length}', style: VText.caption)),
          const VGap.s(),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 0.92,
            children: [
              for (final b in Mock.badges) BadgeTile(badge: b, onTap: () => _showBadge(context, b)),
            ],
          ),
          const VGap.xl(),
          const VSection('Meine Statistik'),
          VKeyValue('Durchschnittliche Verspätung', '$avg Minuten', strong: true),
          const VRule.soft(),
          VKeyValue('Geduldigste Linie', patientLine, strong: true),
          const VRule.soft(),
          VKeyValue('Längste Wartezeit', '$longest Minuten', strong: true),
          const VRule.soft(),
          VKeyValue('Minuten dieses Jahr', fmtInt(minutesThisYear), strong: true),
          const VRule.soft(),
          VKeyValue('Fahrten dieses Jahr', '214', strong: true),
          const VGap.xl(),
          const VSection('Teams'),
          for (final t in Mock.teams)
            VListRow(
              title: t.name,
              subtitle: '${t.members} Mitglieder',
              chevron: true,
              onTap: () => context.push('${Routes.team}?id=${t.id}'),
            ),
          const VGap.xl(),
          const VSection('Mehr'),
          VListRow(title: 'Alle Fahrten', subtitle: '${rides.length} zuletzt', chevron: true, onTap: () => context.push(Routes.historie)),
          VListRow(title: 'Einstellungen', subtitle: 'Ticket, Zweck, Standort, Datenschutz', chevron: true, onTap: () => context.push(Routes.einstellungen)),
        ],
      ),
    );
  }

  void _showBadge(BuildContext context, VBadge b) {
    showVSheet(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(bottom: VSpace.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VSheetHeader(title: b.name, subtitle: b.earned ? 'Verdient am ${b.earnedOn}' : 'Noch nicht verdient'),
            Padding(
              padding: const EdgeInsets.fromLTRB(VSpace.page, VSpace.s, VSpace.page, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b.rule, style: VText.body),
                  if (b.earned) ...[
                    const VGap.m(),
                    VGhostButton(
                      label: 'Als Karte teilen',
                      icon: Icons.ios_share,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        showSnack(context, 'Karte erstellt. Teilen öffnet sich in der echten App.');
                      },
                    ),
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
