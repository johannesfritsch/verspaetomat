import 'package:flutter/material.dart';

import '../../mock/mock_data.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'community_widgets.dart';

/// One team: combined minutes and euros, sponsor line, members.
class TeamScreen extends StatelessWidget {
  const TeamScreen({super.key, required this.teamId});
  final String teamId;

  static const _members = <String, List<(String, int)>>{
    'buero-nord': [('Anke W.', 412), ('Du', 96), ('Tobias R.', 88), ('Lena M.', 74), ('Karim B.', 61), ('Svenja O.', 40)],
    'wg-ehrenfeld': [('Du', 96), ('Paula', 71), ('Mehmet', 44), ('Jule', 18)],
  };

  @override
  Widget build(BuildContext context) {
    final team = Mock.teams.firstWhere((t) => t.id == teamId, orElse: () => Mock.teams.first);
    final members = _members[team.id] ?? _members.values.first;

    return VScreen(
      eyebrow: 'TEAM',
      title: team.name,
      trailing: VIconButton(icon: Icons.ios_share, onTap: () => showSnack(context, 'Link kopiert: verspaetomat.de/t/${team.id}')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VGap.m(),
          Text('${team.members} Mitglieder', style: VText.caption),
          const VGap.l(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: BigFigure(value: fmtInt(team.minutes), label: 'Minuten zusammen', style: VText.number.copyWith(fontSize: 44, letterSpacing: -1.5))),
              Expanded(child: BigFigure(value: fmtEuroWhole(team.euros), label: 'Euro bestätigt')),
            ],
          ),
          const VGap.l(),
          const VRule.red(),
          if (team.sponsorLine != null) ...[
            const VGap.m(),
            Text('SPONSOR', style: VText.eyebrow),
            const SizedBox(height: 6),
            Text(team.sponsorLine!, style: VText.body),
            const SizedBox(height: 8),
            Row(
              children: [
                const VChip('zugesagt', tone: VTone.neutral),
                const SizedBox(width: 8),
                Expanded(child: Text('Wird bestätigt, sobald der Verein den Eingang meldet.', style: VText.caption)),
              ],
            ),
            const VGap.m(),
            const VRule(),
          ],
          const VGap.l(),
          VSection('Diesen Monat', trailing: Text('Geduldspunkte', style: VText.caption)),
          if (team.topMember != null)
            VListRow(
              title: team.topMember == Mock.userName ? 'Du' : team.topMember!,
              subtitle: 'Geduldigstes Mitglied im September',
              trailing: Container(width: 8, height: 8, decoration: const BoxDecoration(color: VColors.red, shape: BoxShape.circle)),
            ),
          const VGap.l(),
          const VSection('Mitglieder'),
          for (var i = 0; i < members.length; i++)
            BoardRow(entry: BoardEntry(rank: i + 1, name: members[i].$1, points: members[i].$2, isMe: members[i].$1 == 'Du')),
          const VGap.l(),
          VGhostButton(label: 'Link teilen', icon: Icons.ios_share, onTap: () => showSnack(context, 'Link kopiert: verspaetomat.de/t/${team.id}')),
        ],
      ),
    );
  }
}
