import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import '../../widgets/ticket.dart' show NgoLogo;
import 'setup_step.dart';

/// Schritt 1 von 3: who the money goes to (#43).
///
/// First, before either permission question. It is the one thing the setup asks that is about
/// the product rather than about the phone, it costs a tap and no system dialog, and somebody who
/// has just chosen a Verein has a reason to say yes to the two that follow.
///
/// The ticket used to be asked beside it and is not any more: it decides what a delay is worth,
/// so it belongs where a delay is, and it is already asked on the check-in step („Ticket wählen",
/// `welcher_zug_screen.dart`) and in Einstellungen.
///
/// „Später entscheiden" is a real answer. `ngo_id` defaults to `bahnhofsmission` in migration
/// 0002, nothing is owed to anybody yet, and the choice is asked again where it matters — on the
/// claim, where the payee is filled in.
class ZweckScreen extends StatefulWidget {
  const ZweckScreen({super.key});

  @override
  State<ZweckScreen> createState() => _ZweckScreenState();
}

class _ZweckScreenState extends State<ZweckScreen> {
  String? _picked;
  bool _busy = false;

  Future<void> _next() async {
    final session = RepoScope.read(context);
    final id = _picked;
    setState(() => _busy = true);
    if (id != null) await session.updateSettings(MePatch(ngoId: id));
    if (mounted) context.go(Routes.permissions);
  }

  @override
  Widget build(BuildContext context) {
    final session = RepoScope.of(context);
    final ngos = session.ngos;
    // Whoever is in the table, in the order it sends them. The list is managed data (docs/05),
    // never a list in the bundle, so this screen has no opinion about how many there are.
    final selected = _picked ?? session.me?.settings.ngoId;
    return SetupStep(
      step: 1,
      total: 3,
      asset: 'assets/onboarding/setup-zweck.webp',
      imageHeight: 170,
      title: 'Wähle einen Verein',
      busy: _busy,
      body: [
        const SetupText('Deine Entschädigung geht direkt dorthin. Von der Bahn, nicht über uns.'),
        if (ngos.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: VSpace.m),
            child: Text(
              session.busy ? 'Vereine werden geladen …' : (session.error ?? 'Keine Vereine geladen.'),
              style: VText.caption,
            ),
          )
        else
          for (final n in ngos)
            _NgoRow(
              ngo: n,
              selected: selected == n.id,
              onTap: () => setState(() => _picked = n.id),
            ),
      ],
      primary: 'Weiter',
      onPrimary: _busy ? null : _next,
      secondary: 'Später entscheiden',
      onSecondary: _busy ? null : () => context.go(Routes.permissions),
      footnote: 'Du kannst deinen Zweck später jederzeit ändern.',
    );
  }
}

class _NgoRow extends StatelessWidget {
  const _NgoRow({required this.ngo, required this.selected, required this.onTap});
  final ApiNgo ngo;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: VSpace.s),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VRadius.md),
        child: Container(
          padding: const EdgeInsets.all(VSpace.md),
          decoration: BoxDecoration(
            color: selected ? VColors.redTint : VColors.paperElevated,
            border: Border.all(color: selected ? VColors.red : VColors.hairline, width: selected ? 1.5 : 1),
            borderRadius: BorderRadius.circular(VRadius.md),
          ),
          child: Row(
            children: [
              // The partner's own mark when it has sent one, otherwise a glyph — the same rule
              // the claim card follows. „Bild folgt" in a grey box, which is what this list used
              // to show, reads as unfinished at the moment somebody is choosing who gets money.
              VIconBadge(
                icon: Icons.volunteer_activism_outlined,
                tone: VBadgeTone.green,
                size: VControl.badgeSmall,
                child: NgoLogo.decode(ngo.logo) == null
                    ? null
                    : NgoLogo(dataUri: ngo.logo, height: VControl.badgeSmall * 0.56),
              ),
              const SizedBox(width: VSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ngo.name, style: VText.title),
                    Text(ngo.tagline, style: VText.bodyS, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: VSpace.s),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? VColors.red : Colors.transparent,
                  border: Border.all(color: selected ? VColors.red : VColors.rule, width: 1.5),
                ),
                child: selected ? const Icon(Icons.check, size: 15, color: VColors.paper) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
