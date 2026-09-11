import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../mock/mock_data.dart';
import '../router.dart';
import '../state/demo_state.dart';
import '../theme/tokens.dart';
import '../widgets/kit.dart';

/// The index of every screen. This is where a demo starts.
class ShowcaseScreen extends StatelessWidget {
  const ShowcaseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = DemoScope.of(context);
    final phaseLabel = switch (state.phase) {
      TripPhase.idle => 'Kein Zug',
      TripPhase.riding => 'Unterwegs mit ${state.trip?.departure.line}',
      TripPhase.arrived => 'Angekommen, +${state.finalDelay}',
    };

    return VScreen(
      showBack: false,
      padding: const EdgeInsets.fromLTRB(VSpace.page, VSpace.l, VSpace.page, VSpace.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const VStationClock(size: 48, animated: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Verspätomat', style: VText.h1),
                    Text('Showcase · alle Screens', style: VText.caption),
                  ],
                ),
              ),
            ],
          ),
          const VGap.l(),
          Container(
            padding: const EdgeInsets.all(VSpace.m),
            decoration: BoxDecoration(border: Border.all(color: VColors.rule), borderRadius: BorderRadius.circular(4)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ZUSTAND', style: VText.eyebrow),
                const SizedBox(height: 6),
                Text(phaseLabel, style: VText.bodyStrong),
                Text('${state.ticket.label} · ${state.ngo.name}', style: VText.caption),
                const SizedBox(height: 12),
                VDemoControl(label: 'Alles zurücksetzen', icon: Icons.restart_alt, onTap: state.reset),
              ],
            ),
          ),
          const VGap.xl(),
          _group(context, 'Der Weg eines Fahrgasts', [
            ('Willkommen', 'drei Karten', Routes.welcome),
            ('Berechtigungen', 'Mitteilungen, Standort', Routes.permissions),
            ('Dein Ticket, dein Zweck', 'Setup', Routes.setup),
            ('Bahnsteig', 'Home', Routes.bahnsteig),
            ('Unterwegs', 'die Fahrt', Routes.unterwegs),
            ('Angekommen +68', 'Anspruch, Bündel bereit', '${Routes.angekommen}?variant=68'),
            ('Angekommen +14', 'kein Anspruch, Punkte', '${Routes.angekommen}?variant=14'),
            ('Angekommen +59', 'um eine Minute', '${Routes.angekommen}?variant=59'),
            ('Angekommen, Ausfall', 'Reise nicht angetreten', '${Routes.angekommen}?variant=ausfall'),
            ('Angekommen, keine Daten', 'selbst eingetragen', '${Routes.angekommen}?variant=nodata'),
          ]),
          const VGap.l(),
          _group(context, 'Konto und Antrag', [
            ('Anträge', 'Sammeln, unterwegs, beantwortet', Routes.antraege),
            ('Antrag', 'fünf Schritte, Servicecenter', '${Routes.antrag}?desk=Servicecenter%20Fahrgastrechte'),
            ('Antrag, unbekannter Betreiber', 'Adresse fehlt', '${Routes.antrag}?desk=Unbekannt'),
            ('Antwort: angenommen', 'Post vom Servicecenter', '${Routes.antwort}?mail=m-0718-in'),
            ('Antwort: Rückfrage', 'Ticketkopie nachreichen', '${Routes.antwort}?demo=question'),
            ('Antwort: abgelehnt', 'außergewöhnliche Umstände', '${Routes.antwort}?demo=rejected'),
            ('Nachtrag', 'gestern vergessen', Routes.nachtrag),
          ]),
          const VGap.l(),
          _group(context, 'Wir und Ich', [
            ('Wir', 'Community, Vereine, Ranglisten', Routes.wir),
            ('Zweck', 'Bahnhofsmission Köln', '${Routes.zweck}?id=bahnhofsmission'),
            ('Ich', 'Profil, Abzeichen', Routes.ich),
            ('Alle Fahrten', 'Historie', Routes.historie),
            ('Einstellungen', 'und Datenschutz', Routes.einstellungen),
            ('Woher kommen die Daten?', 'die Tabelle', Routes.datenherkunft),
          ]),
          const VGap.xl(),
          Text('Alle Daten sind erfunden. Bahnhöfe, Züge, Beträge und Vereine dienen nur der Vorführung.', style: VText.caption),
          const VGap.s(),
          Text('Stand: ${Mock.longDate(Mock.today)}', style: VText.caption),
        ],
      ),
    );
  }

  Widget _group(BuildContext context, String title, List<(String, String, String)> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VSection(title),
        for (final (label, sub, route) in items)
          VListRow(title: label, subtitle: sub, chevron: true, onTap: () => context.push(route)),
      ],
    );
  }
}
