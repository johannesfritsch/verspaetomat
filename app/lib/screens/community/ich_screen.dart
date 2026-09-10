import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../mock/mock_data.dart' show Mock;
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import '../claims/claims_widgets.dart';
import 'community_widgets.dart';

class _IchData {
  const _IchData(this.me, this.badges, this.rides, this.standing, this.ledger);
  final ApiCustomer me;
  final List<ApiBadge> badges;
  final List<ApiRide> rides;
  final ApiStanding standing;
  final ApiIncidents? ledger;
}

/// Ich: level, badges, statistics.
class IchScreen extends StatelessWidget {
  const IchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Loader<_IchData>(
      load: (repo) async {
        final me = await repo.getMe();
        final badges = await repo.badges();
        List<ApiRide> rides = const [];
        try {
          rides = await repo.rides();
        } catch (_) {}
        final standing = await repo.standing().catchError((_) => ApiStanding.empty);
        ApiIncidents? ledger;
        try {
          ledger = await repo.incidents();
        } catch (_) {}
        return _IchData(me, badges, rides, standing, ledger);
      },
      builder: (context, data, refresh) {
        final me = data.me;
        final rides = data.rides;
        final arrived = rides.where((r) => r.finalDelayMinutes != null).toList();
        final delayed = arrived.where((r) => (r.finalDelayMinutes ?? 0) > 0).toList();
        final avg = delayed.isEmpty ? 0 : (delayed.fold(0, (s, r) => s + (r.finalDelayMinutes ?? 0)) / delayed.length).round();
        final longest = arrived.fold(0, (m, r) => (r.finalDelayMinutes ?? 0) > m ? (r.finalDelayMinutes ?? 0) : m);
        final byLine = <String, int>{};
        for (final r in arrived) {
          byLine[r.line] = (byLine[r.line] ?? 0) + (r.finalDelayMinutes ?? 0);
        }
        final patientLine = byLine.entries.fold<MapEntry<String, int>?>(null, (m, e) => m == null || e.value > m.value ? e : m)?.key ?? '–';
        final year = DateTime.now().year;
        final thisYear = arrived.where((r) => r.date.year == year).toList();
        final minutesThisYear = thisYear.fold(0, (s, r) => s + (r.finalDelayMinutes ?? 0));
        final recent = rides.where((r) => DateTime.now().difference(r.date).inDays <= 14).length;
        final earned = data.badges.where((b) => b.earned).length;
        final name = displayName(me) ?? 'Fahrgast';
        final lvl = data.standing.level;
        final my = data.standing.community;
        final confirmedCents = my?.myConfirmedCents ?? data.ledger?.summary.confirmedCents ?? 0;
        final submittedCents = data.ledger?.summary.submittedCents ?? 0;
        final session = RepoScope.of(context);
        final ngoId = me.settings.ngoId;
        final ngoName = session.ngos.where((n) => n.id == ngoId).map((n) => n.name).firstOrNull;

        return VScreen(
          showBack: false,
          padding: const EdgeInsets.fromLTRB(VSpace.page, VSpace.l, VSpace.page, VSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TabHeader(
                title: name,
                caption: me.levelName,
                onSettings: () => context.push(Routes.einstellungen).then((_) => refresh()),
              ),
              const VGap.xl(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(fmtInt(me.pointsTotal), style: VText.number),
                  const SizedBox(width: 10),
                  Text('Geduldspunkte', style: VText.title.copyWith(color: VColors.ink2)),
                ],
              ),
              const VGap.m(),
              const VRule.red(),
              // The level (docs/20 §5): the same line Home shows under "Deine Woche".
              if (lvl != null) ...[
                const VGap.m(),
                VProgress(confirmed: lvl.progress),
                const SizedBox(height: 6),
                Text(
                  lvl.pointsToNext > 0 ? '${lvl.name} · ${fmtInt(lvl.pointsToNext)} bis „${lvl.nextName}“' : '${lvl.name} · höchste Stufe erreicht',
                  style: VText.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const VGap.m(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: BigFigure(
                      value: fmtEuro(confirmedCents / 100),
                      label: 'Bestätigt, durch dich',
                      onTap: () => context.go(Routes.antraege),
                    ),
                  ),
                  Expanded(child: BigFigure(value: fmtEuro(submittedCents / 100), label: 'Eingereicht, unterwegs')),
                ],
              ),
              const VGap.m(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: BigFigure(value: '+${me.pointsThisWeek}', label: 'Diese Woche')),
                  Expanded(child: BigFigure(value: '$recent', label: 'Fahrten, letzte 14 Tage')),
                ],
              ),
              const VGap.xl(),
              VSection('Abzeichen', trailing: Text('$earned von ${data.badges.length}', style: VText.caption)),
              const VGap.s(),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 0.92,
                children: [
                  for (final b in data.badges) BadgeTile(badge: b, onTap: () => _showBadge(context, b)),
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
              VKeyValue('Fahrten dieses Jahr', fmtInt(thisYear.length), strong: true),
              const VGap.xl(),
              const VSection('Mehr'),
              VListRow(
                title: 'Dein Zweck',
                subtitle: ngoName ?? 'Noch nicht gewählt',
                chevron: true,
                onTap: ngoId.isEmpty ? () => pickNgo(context, session, null) : () => context.push('${Routes.zweck}?id=$ngoId'),
              ),
              const VRule.soft(),
              VListRow(title: 'Alle Fahrten', subtitle: '${rides.length} zuletzt', chevron: true, onTap: () => context.push(Routes.historie)),
            ],
          ),
        );
      },
    );
  }

  void _showBadge(BuildContext context, ApiBadge b) {
    showVSheet(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(bottom: VSpace.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VSheetHeader(title: b.name, subtitle: b.earned ? 'Verdient am ${Mock.longDate(b.earnedOn!)}' : 'Noch nicht verdient'),
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
