import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../mock/mock_data.dart' show Mock;
import '../../repo/repo_scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'claims_widgets.dart';

/// Zweck: one NGO, its story, its account, what has reached it.
class ZweckScreen extends StatelessWidget {
  const ZweckScreen({super.key, required this.ngoId});
  final String ngoId;

  @override
  Widget build(BuildContext context) {
    final session = RepoScope.of(context);
    return Loader<List<ApiNgo>>(
      load: (repo) => repo.ngos(),
      builder: (context, ngos, refresh) {
        final ngo = ngos.where((n) => n.id == ngoId).firstOrNull ?? ngos.firstOrNull;
        if (ngo == null) {
          return VScreen(title: 'Zweck', child: Text('Kein Verein gefunden.', style: VText.body));
        }
        final isDefault = session.me?.settings.ngoId == ngo.id;

        return VScreen(
          eyebrow: 'Zweck',
          title: ngo.name,
          bottom: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              VPrimaryButton(
                label: isDefault ? 'Dein Standard' : 'Als Standard wählen',
                icon: isDefault ? Icons.check : null,
                onTap: isDefault
                    ? null
                    : () async {
                        await session.updateSettings(MePatch(ngoId: ngo.id));
                        if (!context.mounted) return;
                        final msg = session.error == null ? '${ngo.name} ist jetzt dein Zweck.' : 'Nicht gespeichert: ${session.error}';
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                      },
              ),
              const VGap.xs(),
              VGhostButton(label: 'Trotzdem spenden', icon: Icons.open_in_new, onTap: () => _trotzdem(context, ngo)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: VColors.paperElevated,
                  border: Border.all(color: VColors.rule),
                  borderRadius: BorderRadius.circular(4),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Center(
                      child: Text(ngo.name.isNotEmpty ? ngo.name.substring(0, 1) : '?', style: VText.display.copyWith(color: VColors.ruleSoft)),
                    ),
                    Positioned(right: 12, bottom: 10, child: Text('Bild folgt', style: VText.caption.copyWith(color: VColors.ink3))),
                  ],
                ),
              ),
              const VGap.m(),
              Text(ngo.tagline, style: VText.h2),
              const VGap.m(),
              for (final p in ngo.story)
                Padding(
                  padding: const EdgeInsets.only(bottom: VSpace.m),
                  child: Text(p, style: VText.body),
                ),
              const VGap.s(),
              const VSection('Transparenz'),
              VKeyValue('Kontoinhaber', ngo.accountHolder, strong: true),
              const VRule(),
              VKeyValue('IBAN', ngo.iban, valueStyle: VText.mono),
              const VRule(),
              VKeyValue('Bestätigt über Verspätomat', fmtEuroWhole(ngo.confirmedTotalCents / 100), strong: true),
              const VRule(),
              VKeyValue('Eingereicht, unterwegs', fmtEuroWhole(ngo.submittedTotalCents / 100)),
              const VRule(),
              VKeyValue('Letzte Meldung', ngo.lastReport != null ? Mock.longDate(ngo.lastReport!) : '–'),
              const VGap.s(),
              Text(
                'Die Entschädigung überweist die Bahn direkt auf dieses Konto. Wir sehen kein Geld, nur die Antwort.',
                style: VText.caption,
              ),
              const VGap.xl(),
            ],
          ),
        );
      },
    );
  }

  Future<void> _trotzdem(BuildContext context, ApiNgo ngo) {
    return showVSheet(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(VSpace.page, 0, VSpace.page, VSpace.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const VSheetHeader(title: 'Trotzdem spenden'),
            Text('Das läuft nicht über uns. Du landest direkt bei ${ngo.name}.', style: VText.body),
            const VGap.s(),
            Text(ngo.donationUrl, style: VText.mono.copyWith(color: VColors.ink2)),
            const VGap.l(),
            VPrimaryButton(
              label: 'Weiter zur Spendenseite',
              icon: Icons.open_in_new,
              onTap: () {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Öffnet im Browser: ${ngo.donationUrl}')));
              },
            ),
            const VGap.xs(),
            VGhostButton(label: 'Doch nicht', onTap: () => Navigator.of(ctx).pop()),
          ],
        ),
      ),
    );
  }
}
