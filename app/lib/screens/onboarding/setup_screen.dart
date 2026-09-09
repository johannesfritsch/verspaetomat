import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../mock/mock_data.dart' show TicketType, TicketTypeX;
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../state/demo_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';

/// Ticket type and default cause. Personal details are asked at the first claim.
class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = RepoScope.of(context);
    final demo = DemoScope.of(context);
    final ticket = session.me?.settings.ticket ?? demo.ticket;
    final ngoId = session.me?.settings.ngoId ?? demo.ngoId;
    final ngos = session.ngos;
    return VScreen(
      eyebrow: 'Schritt 2 von 2',
      title: 'Dein Ticket, dein Zweck',
      bottom: VPrimaryButton(
        label: 'Fertig',
        onTap: () async {
          await session.completeOnboarding();
          if (context.mounted) context.go(Routes.bahnsteig);
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
              selected: ticket == t,
              onTap: () => session.updateSettings(MePatch(ticket: t)),
            ),
            const VGap.s(),
          ],
          Text('Lässt sich pro Fahrt und im Profil ändern.', style: VText.caption),
          const VGap.xl(),
          const VSection('Zweck'),
          const VGap.m(),
          Text('Dorthin geht die Entschädigung. Direkt von der Bahn, nicht über uns.', style: VText.bodyS.copyWith(color: VColors.ink2)),
          const VGap.m(),
          if (ngos.isEmpty)
            Text(session.busy ? 'Vereine werden geladen …' : (session.error ?? 'Keine Vereine geladen.'), style: VText.caption)
          else
            for (final n in ngos) ...[
              _NgoCard(ngo: n, selected: ngoId == n.id, onTap: () => session.updateSettings(MePatch(ngoId: n.id))),
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
  final ApiNgo ngo;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: VColors.paperElevated,
                    border: Border.all(color: VColors.rule),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text('Bild\nfolgt', textAlign: TextAlign.center, style: VText.caption.copyWith(fontSize: 11)),
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
            const SizedBox(height: 10),
            Text('Bestätigt über Verspätomat: ${fmtEuroWhole(ngo.confirmedTotalCents / 100)}', style: VText.caption),
          ],
        ),
      ),
    );
  }
}
