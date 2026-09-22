import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';

/// What happens after the Antrag is gone — the part of this product nobody can be shown.
///
/// The five steps take two minutes. Everything after them takes four to six weeks and then arrives
/// on its own, so a person deciding whether to install this cannot see it, and an App Store
/// reviewer certainly cannot wait for it. This screen is the rest of the story, and each card opens
/// the screen that will really be shown when that day comes — the same widgets, with example data.
///
/// The three outcomes are the three the backend actually distinguishes for a claim that arrives:
/// paid, asked about, refused. There is no fourth happy ending invented here.
class DemoWeiterScreen extends StatelessWidget {
  const DemoWeiterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return VScreen(
      eyebrow: 'Vorführung',
      title: 'Und dann?',
      scroll: true,
      art: VHeaderSceneArt.antragSenden,
      bottom: VGhostButton(
        label: 'Vorführung beenden',
        onTap: () => context.canPop() ? context.pop() : context.go(Routes.claims),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VGap.s(),
          Text('Der Antrag ist raus. Ab hier wartest du.', style: VText.h2),
          const VGap.s(),
          Text(
            'Das Eisenbahnunternehmen hat einen Monat Zeit, in der Praxis werden es vier bis sechs '
            'Wochen. Die Antwort kommt per Mail an deine private E-Mail-Adresse und gleichzeitig hier in der App. Du '
            'musst nichts nachhalten und nichts erinnern.',
            style: VText.caption,
          ),
          const VGap.l(),
          const VSectionHeader('Drei Antworten sind möglich', onCard: false),
          const VGap.s(),
          _Outcome(
            icon: Icons.euro_symbol,
            tone: VBadgeTone.green,
            title: 'Die Bahn zahlt',
            text: 'Das Geld geht direkt an den Verein, nie über uns. In der App siehst du den Betrag '
                'und dass er angekommen ist.',
            onTap: () => context.push('${Routes.reply}?demo=accepted'),
          ),
          const VGap.s(),
          _Outcome(
            icon: Icons.help_outline,
            tone: VBadgeTone.blue,
            title: 'Die Bahn fragt nach',
            text: 'Meistens fehlt eine Ticketkopie oder eine Zugnummer. Die App hat Vorlagen; du '
                'antwortest mit zwei Tipps, von deiner eigenen Adresse.',
            onTap: () => context.push('${Routes.reply}?demo=question'),
          ),
          const VGap.s(),
          _Outcome(
            icon: Icons.block_outlined,
            tone: VBadgeTone.red,
            title: 'Die Bahn lehnt ab',
            text: 'Du siehst die Begründung im Klartext. Hältst du sie für falsch, ist die '
                'Schlichtungsstelle söp kostenlos zuständig — zwischen dir und der Bahn, ohne uns.',
            onTap: () => context.push('${Routes.reply}?demo=rejected'),
          ),
          const VGap.l(),
          const VDivider(strong: true),
          const VGap.m(),
          const VNoteBanner(
            tone: VNoteTone.plain,
            icon: Icons.verified_user_outlined,
            text: 'In allen drei Fällen bleibt der Antrag deiner. Wir haben ihn ausgefüllt und '
                'überbracht; geantwortet wird dir, und das Geld fließt ohne uns.',
          ),
          const VGap.xl(),
        ],
      ),
    );
  }
}

/// One possible answer, as a card that opens the screen it would really be shown on.
class _Outcome extends StatelessWidget {
  const _Outcome({required this.icon, required this.tone, required this.title, required this.text, required this.onTap});

  final IconData icon;
  final VBadgeTone tone;
  final String title;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return VCard(
      padding: const EdgeInsets.all(VSpace.cardTight),
      onTap: onTap,
      child: Row(
        children: [
          VIconBadge(icon: icon, tone: tone, size: VControl.badgeSmall),
          const SizedBox(width: VSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: VText.title),
                const SizedBox(height: 2),
                Text(text, style: VText.bodyS.copyWith(color: VColors.ink2)),
                const SizedBox(height: 4),
                Text('Ansehen', style: VText.link),
              ],
            ),
          ),
          const SizedBox(width: VSpace.s),
          const VChevron(),
        ],
      ),
    );
  }
}
