import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../repo/repo_scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import '../claims/claims_widgets.dart';
import 'community_widgets.dart';

/// One team: combined minutes and euros, members.
class TeamScreen extends StatelessWidget {
  const TeamScreen({super.key, required this.teamId});
  final String teamId;

  @override
  Widget build(BuildContext context) {
    final session = RepoScope.of(context);
    return Loader<List<ApiTeam>>(
      load: (repo) => repo.teams(),
      builder: (context, teams, refresh) {
        final team = teams.where((t) => t.id == teamId).firstOrNull ?? teams.firstOrNull;
        if (team == null) {
          return VScreen(eyebrow: 'TEAM', title: 'Team', child: Text('Kein Team gefunden.', style: VText.body));
        }
        final me = session.me?.nickname;
        final link = 'verspaetomat.de/t/${team.inviteToken ?? team.id}';

        return VScreen(
          eyebrow: 'TEAM',
          title: team.name,
          trailing: VIconButton(icon: Icons.ios_share, onTap: () => showSnack(context, 'Link kopiert: $link')),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const VGap.m(),
              Text('${team.members.length} Mitglieder', style: VText.caption),
              const VGap.l(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: BigFigure(value: fmtInt(team.minutes), label: 'Minuten zusammen', style: VText.number.copyWith(fontSize: 44, letterSpacing: -1.5))),
                  Expanded(child: BigFigure(value: fmtEuroWhole(team.eurosCents / 100), label: 'Euro bestätigt')),
                ],
              ),
              const VGap.l(),
              const VRule.red(),
              const VGap.l(),
              const VSection('Diesen Monat'),
              if (team.topMember != null)
                VListRow(
                  title: team.topMember == me ? 'Du' : team.topMember!,
                  subtitle: 'Geduldigstes Mitglied',
                  trailing: Container(width: 8, height: 8, decoration: const BoxDecoration(color: VColors.red, shape: BoxShape.circle)),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: VSpace.m),
                  child: Text('Noch keine Fahrten in diesem Monat.', style: VText.caption),
                ),
              const VGap.l(),
              const VSection('Mitglieder'),
              for (final m in team.members)
                VListRow(
                  title: m == me ? 'Du' : m,
                  leading: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: m == me ? VColors.red : VColors.rule, shape: BoxShape.circle),
                  ),
                ),
              const VGap.l(),
              if (team.inviteToken != null) ...[
                Container(
                  padding: const EdgeInsets.all(VSpace.m),
                  decoration: BoxDecoration(border: Border.all(color: VColors.rule), borderRadius: BorderRadius.circular(4)),
                  child: Row(
                    children: [
                      Expanded(child: Text(link, style: VText.mono)),
                      const Icon(Icons.link, size: 20, color: VColors.ink2),
                    ],
                  ),
                ),
                const VGap.s(),
              ],
              VGhostButton(label: 'Link teilen', icon: Icons.ios_share, onTap: () => showSnack(context, 'Link kopiert: $link')),
            ],
          ),
        );
      },
    );
  }
}
