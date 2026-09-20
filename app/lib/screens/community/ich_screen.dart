import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../mock/mock_data.dart' show Mock;
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import '../../widgets/ticket.dart';
import '../share/share_lines.dart';
import '../share/share_sheet.dart';
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
      placeholder: (context) => VTabScaffold(
        art: VHeaderSceneArt.landscapeIch,
        header: VTabHeader(
          title: RepoScope.read(context).me?.nickname ?? 'Ich',
          subtitle: 'Gemeinsam für pünktlichere Züge',
          narrow: true,
          onSettings: () => context.push(Routes.einstellungen),
        ),
        children: const [VSkeletonBoard(look: VBoardLook.red), VSkeletonCard(), VSkeletonList()],
      ),
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
        // An abandoned ride was not a trip: neither "aufgegeben" nor "nicht gefahren" counts (docs/21 §3).
        final recent = rides.where((r) => r.status != ApiRideStatus.abandoned && DateTime.now().difference(r.date).inDays <= 14).length;
        final name = displayName(me) ?? 'Fahrgast';
        final lvl = data.standing.level;
        final my = data.standing.community;
        final confirmedCents = my?.myConfirmedCents ?? data.ledger?.summary.confirmedCents ?? 0;
        final submittedCents = data.ledger?.summary.submittedCents ?? 0;
        final session = RepoScope.of(context);
        final ngoId = me.settings.ngoId;
        final ngoName = session.ngos.where((n) => n.id == ngoId).map((n) => n.name).firstOrNull;

        return VTabScaffold(
          art: VHeaderSceneArt.landscapeIch,
          onRefresh: () async => refresh(),
          header: VTabHeader(
            title: name,
            // The mockup ends this line on a heart emoji. The words are the app's and the heart is
            // on the board below, where it has something to sit beside; floating between the name
            // and the gear it read as a stray mark rather than as a sign-off.
            subtitle: 'Gemeinsam für pünktlichere Züge',
            narrow: true,
            onSettings: () => context.push(Routes.einstellungen).then((_) => refresh()),
          ),
          children: [
            // The red board, like Wir: the two screens that are about people take it, and Home
            // keeps the dark one (docs/43 §8).
            VBoard(
              look: VBoardLook.red,
              // The mockup puts a handwritten note here as well as on Wir. It is not built: at
              // Ich's share of the board the note cannot set „Verspätung" without being cut by
              // the card's own edge, and a margin note that is trimmed reads as a rendering fault
              // rather than as a hand. Wir keeps its note, which fits; the heart carries this one.
              aside: const Align(
                alignment: Alignment.topRight,
                child: VHeartMark(color: VColors.inkOnDark2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const VBoardLabel('Geduldspunkte', icon: Icons.workspace_premium_outlined),
                  const VGap.s(),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      fmtInt(me.pointsTotal),
                      style: VText.number.copyWith(color: VColors.inkOnDark),
                    ),
                  ),
                  if (lvl != null) ...[
                    const VGap.md(),
                    VProgressBar(value: lvl.progress, ground: VProgressGround.red),
                    const VGap.s(),
                    VBoardCaption(
                      lvl.pointsToNext > 0
                          ? '${fmtInt(lvl.pointsToNext)} bis „${lvl.nextName}“'
                          : '${lvl.name} · höchste Stufe erreicht',
                      maxLines: 1,
                    ),
                  ],
                ],
              ),
            ),

            // The four figures as one block rather than two rows of two: a quadrant reads as one
            // statement about the account, which is what it is.
            VCard(
              child: VStatQuad(
                stats: [
                  VStat(
                    icon: Icons.train,
                    value: fmtEuro(confirmedCents / 100),
                    label: 'Bestätigt, durch dich gespendet',
                  ),
                  VStat(
                    icon: Icons.mail_outline,
                    value: fmtEuro(submittedCents / 100),
                    label: 'Eingereicht, unterwegs',
                  ),
                  VStat(
                    icon: Icons.bar_chart,
                    value: '+${fmtInt(me.pointsThisWeek)}',
                    label: 'Diese Woche',
                  ),
                  VStat(
                    icon: Icons.route_outlined,
                    value: '$recent',
                    label: 'Fahrten, letzte 14 Tage',
                  ),
                ],
              ),
            ),

            VSectionHeader(
              'Abzeichen',
              heading: true,
              onCard: false,
              linkLabel: 'Alle ansehen',
              onLink: () => _showAllBadges(context, data.badges),
            ),
            VCard(
              padding: const EdgeInsets.symmetric(
                horizontal: VSpace.cardTight,
                vertical: VSpace.card,
              ),
              child: VAchievementStrip(
                items: [
                  for (final b in data.badges)
                    VAchievement(
                      label: b.name,
                      art: BadgeIcon(badge: b, size: 40),
                      earned: b.earned,
                      onTap: () => _showBadge(context, b),
                    ),
                ],
              ),
            ),

            const VSectionHeader('Meine Statistik', heading: true, onCard: false),
            VCard(
              child: Column(
                children: [
                  VKeyValue('Durchschnittliche Verspätung', '$avg Minuten', strong: true),
                  const VDivider(),
                  VKeyValue('Geduldigste Linie', patientLine, strong: true),
                  const VDivider(),
                  VKeyValue('Längste Wartezeit', '$longest Minuten', strong: true),
                  const VDivider(),
                  VKeyValue('Minuten dieses Jahr', fmtInt(minutesThisYear), strong: true),
                  const VDivider(),
                  VKeyValue('Fahrten dieses Jahr', fmtInt(thisYear.length), strong: true),
                ],
              ),
            ),

            // The mockup's menu names three screens that do not exist — Profil bearbeiten, Meine
            // Spenden, Statistiken. These are the three that do.
            VMenuCard(
              rows: [
                VMenuRow(
                  icon: Icons.favorite_outline,
                  label: 'Dein Zweck · ${ngoName ?? 'noch nicht gewählt'}',
                  onTap: () => pickNgo(context, session, ngoId.isEmpty ? null : ngoId),
                ),
                VMenuRow(
                  icon: Icons.route_outlined,
                  label: 'Alle Fahrten',
                  onTap: () => context.push(Routes.historie),
                ),
                VMenuRow(
                  icon: Icons.settings_outlined,
                  label: 'Einstellungen',
                  onTap: () => context.push(Routes.einstellungen).then((_) => refresh()),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// Every badge, when four on the strip are not enough. The strip is the glance; this is the shelf.
  void _showAllBadges(BuildContext context, List<ApiBadge> badges) {
    showVSheet<void>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(bottom: VSpace.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VSheetHeader(
              title: 'Abzeichen',
              subtitle: '${badges.where((b) => b.earned).length} von ${badges.length} verdient',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: VSpace.sheet),
              child: GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: VSpace.s,
                crossAxisSpacing: VSpace.s,
                childAspectRatio: 0.80,
                children: [
                  for (final b in badges)
                    BadgeTile(badge: b, onTap: () => _showBadge(context, b)),
                ],
              ),
            ),
          ],
        ),
      ),
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
                  Center(child: BadgeIcon(badge: b, size: 140)),
                  const VGap.m(),
                  Text(b.rule, style: VText.body),
                  if (b.earned) ...[
                    const VGap.m(),
                    VGhostButton(
                      label: 'Als Karte teilen',
                      icon: Icons.ios_share,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        // docs/27 §1: the badge card leads with the fact that earned it, because
                        // a badge name alone is readable only by people who have the app.
                        showShareSheet(
                          context,
                          date: DateTime.now(),
                          lines: ShareLines.abzeichen(name: b.name),
                          build: ({fahrgast, strecke, date, line}) => TicketData.abzeichen(
                            name: b.name,
                            rule: b.rule,
                            asset: BadgeIcon.assetFor(b.id, earned: true),
                            fahrgast: fahrgast,
                            date: date,
                            line: line,
                          ),
                        );
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
