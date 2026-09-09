import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../mock/mock_data.dart';
import '../../router.dart';
import '../../state/demo_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';

/// Ticket type and default cause. Personal details are asked at the first claim.
class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = DemoScope.of(context);
    return VScreen(
      eyebrow: 'Schritt 2 von 2',
      title: 'Dein Ticket, dein Zweck',
      bottom: VPrimaryButton(
        label: 'Fertig',
        onTap: () {
          state.completeOnboarding();
          context.go(Routes.bahnsteig);
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VGap.m(),
          const VSection('Ticket'),
          const VGap.m(),
          for (final t in TicketType.values) ...[
            VChoiceCard(
              title: t.label,
              subtitle: t.rule,
              selected: state.ticket == t,
              onTap: () => state.setTicket(t),
            ),
            const VGap.s(),
          ],
          Text('Lässt sich pro Fahrt und im Profil ändern.', style: VText.caption),
          const VGap.xl(),
          const VSection('Zweck'),
          const VGap.m(),
          Text('Dorthin geht die Entschädigung. Direkt von der Bahn, nicht über uns.', style: VText.bodyS.copyWith(color: VColors.ink2)),
          const VGap.m(),
          for (final n in Mock.ngos) ...[
            _NgoCard(ngo: n, selected: state.ngoId == n.id, onTap: () => state.setNgo(n.id)),
            const VGap.s(),
          ],
          const VGap.s(),
          Text('Name, Adresse und Ticketnummer fragen wir erst, wenn dein erster Antrag bereit ist.', style: VText.caption),
        ],
      ),
    );
  }
}

class _NgoCard extends StatelessWidget {
  const _NgoCard({required this.ngo, required this.selected, required this.onTap});
  final Ngo ngo;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = (ngo.campaignConfirmed / ngo.campaignGoal).clamp(0.0, 1.0);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.all(VSpace.m),
        decoration: BoxDecoration(
          color: selected ? VColors.paperElevated : Colors.transparent,
          border: Border.all(color: selected ? VColors.ink : VColors.rule, width: selected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: VColors.ink, borderRadius: BorderRadius.circular(3)),
                  child: Text(ngo.name.substring(0, 1), style: VText.h2.copyWith(color: VColors.paper)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ngo.name, style: VText.title),
                      Text(ngo.tagline, style: VText.caption),
                    ],
                  ),
                ),
                VIconButton(icon: Icons.info_outline, color: VColors.ink2, onTap: () => context.push('${Routes.zweck}?id=${ngo.id}')),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? VColors.red : Colors.transparent,
                    border: Border.all(color: selected ? VColors.red : VColors.rule, width: 1.5),
                  ),
                  child: selected ? const Icon(Icons.check, size: 14, color: VColors.paper) : null,
                ),
              ],
            ),
            const SizedBox(height: 12),
            VProgress(confirmed: progress, submitted: (ngo.campaignSubmitted / ngo.campaignGoal).clamp(0.0, 1.0)),
            const SizedBox(height: 6),
            Text('${fmtEuro(ngo.campaignConfirmed)} von ${fmtEuro(ngo.campaignGoal)} ${ngo.campaignDeadline}', style: VText.caption),
          ],
        ),
      ),
    );
  }
}
