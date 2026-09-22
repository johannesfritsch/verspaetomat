import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../mock/mock_data.dart';
import '../repo/repo_scope.dart';
import '../router.dart';
import '../state/demo_state.dart';
import '../theme/tokens.dart';
import '../widgets/kit.dart';

/// The index of every screen. This is where a demo starts.
///
/// Since issue #28 it is also reachable from Einstellungen › Entwicklung in a **release** build,
/// where it is pushed rather than gone to — so it needs a back arrow — and where it runs against
/// the real account in local mode. That second fact is why half the list is not drawn there: the
/// entries that exist to show an invented ride either show the passenger's real data under a
/// label promising something else, or, in two cases, write to the production database. See
/// [_demoOnly].
class ShowcaseScreen extends StatelessWidget {
  const ShowcaseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = DemoScope.of(context);
    // Demo mode is the only place the invented entries mean anything. In a debug build this is
    // still the app's home screen, reached with `go`, and there is nothing to go back to.
    final isLocal = RepoScope.of(context).isLocal;
    final canPop = context.canPop();
    final phaseLabel = switch (state.phase) {
      TripPhase.idle => 'Kein Zug',
      TripPhase.riding => 'Unterwegs mit ${state.trip?.departure.line}',
      TripPhase.arrived => 'Angekommen, +${state.finalDelay}',
    };

    return VScreen(
      showBack: canPop,
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
          // Demo bookkeeping. In local mode it describes nothing that is on screen — it would
          // print „Kein Zug · Deutschlandticket · Bahnhofsmission Köln" beside a real account
          // with a real ride — and its reset button is a confident label on a no-op.
          if (!isLocal) ...[
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
          ] else ...[
            const VNoteBanner(
              icon: Icons.info_outline,
              tone: VNoteTone.neutral,
              text: 'Dies ist dein echtes Konto, keine Vorführung. Schirme, die eine erfundene '
                  'Fahrt brauchen, fehlen deshalb hier: sie würden entweder deine echten Daten '
                  'unter einem falschen Namen zeigen oder einen angefangenen Antrag '
                  'überschreiben. Vollständig ist die Liste nur im Vorführungs-Modus.',
            ),
            const VGap.xl(),
          ],
          _group(context, 'Der Weg eines Fahrgasts', isLocal: isLocal, [
            // The three onboarding screens write the ticket, the NGO and the onboarding flag, and
            // raise the OS prompts. Not from an index.
            const _Entry('Willkommen', 'drei Karten', Routes.welcome, demoOnly: true),
            const _Entry('Wähle einen Verein', 'Setup 1 · Zweck', Routes.chooseCause, demoOnly: true),
            const _Entry('Sollen wir uns melden?', 'Setup 2 · Mitteilungen', Routes.permissions, demoOnly: true),
            const _Entry('Am Bahnsteig erinnern?', 'Setup 3 · Standort', Routes.location, demoOnly: true),
            const _Entry('Fast geschafft', 'Setup 3 · „Immer"', Routes.locationAlways, demoOnly: true),
            const _Entry("Los geht's!", 'Setup · Ende', Routes.ready, demoOnly: true),
            const _Entry('Bahnsteig', 'Home', Routes.home),
            const _Entry('Unterwegs', 'die Fahrt', Routes.ride),
            _Entry('Angekommen +68', 'Anspruch, Bündel bereit', '${Routes.arrived}?variant=68', demoOnly: true),
            _Entry('Angekommen +14', 'kein Anspruch, Punkte', '${Routes.arrived}?variant=14', demoOnly: true),
            _Entry('Angekommen +59', 'um eine Minute', '${Routes.arrived}?variant=59', demoOnly: true),
            _Entry('Angekommen, Ausfall', 'Reise nicht angetreten', '${Routes.arrived}?variant=cancelled', demoOnly: true),
            _Entry('Angekommen, keine Daten', 'selbst eingetragen', '${Routes.arrived}?variant=nodata', demoOnly: true),
          ]),
          const VGap.l(),
          _group(context, 'Konto und Antrag', isLocal: isLocal, [
            const _Entry('Anträge', 'Sammeln, unterwegs, beantwortet', Routes.claims),
            // These two POST a draft, which can delete one that already holds a ticket photo and
            // a signature. The Vorführung below shows the same five steps and touches nothing.
            _Entry('Antrag', 'fünf Schritte, Servicecenter', '${Routes.claim}?desk=Servicecenter%20Fahrgastrechte', demoOnly: true),
            _Entry('Antrag, unbekannter Betreiber', 'Adresse fehlt', '${Routes.claim}?desk=Unbekannt', demoOnly: true),
            _Entry('Antwort: angenommen', 'Post vom Servicecenter', '${Routes.reply}?mail=m-0718-in', demoOnly: true),
            _Entry('Antwort: Rückfrage', 'Ticketkopie nachreichen', '${Routes.reply}?demo=question', demoOnly: true),
            _Entry('Antwort: abgelehnt', 'außergewöhnliche Umstände', '${Routes.reply}?demo=rejected', demoOnly: true),
            const _Entry('Nachtrag', 'gestern vergessen', Routes.addRide),
            // The walkthrough is safe everywhere: its session is a throwaway on the mock
            // repository, which has no HTTP client at all (issue #25).
            const _Entry('Vorführung', 'der ganze Antrag, ohne zu senden', Routes.demoClaim),
          ]),
          const VGap.l(),
          _group(context, 'Wir und Ich', isLocal: isLocal, [
            const _Entry('Wir', 'Community, Vereine, Ranglisten', Routes.community),
            _Entry('Zweck', 'Bahnhofsmission Köln', '${Routes.cause}?id=bahnhofsmission'),
            const _Entry('Ich', 'Profil, Abzeichen', Routes.me),
            const _Entry('Alle Fahrten', 'Historie', Routes.history),
            const _Entry('Einstellungen', 'und Datenschutz', Routes.settings),
            const _Entry('Woher kommen die Daten?', 'die Tabelle', Routes.dataSources),
            const _Entry('Störung', 'wenn der Server nicht erreichbar ist', Routes.outage),
            const _Entry('Zaunkarte', 'wie die Zäune stehen', Routes.fenceMap),
          ]),
          const VGap.xl(),
          if (!isLocal) ...[
            Text('Alle Daten sind erfunden. Bahnhöfe, Züge, Beträge und Vereine dienen nur der Vorführung.', style: VText.caption),
            const VGap.s(),
            // `Mock.today` is a fixed date in the demo fixture; printing it beside a real account
            // would date the app to a day that has nothing to do with anything.
            Text('Stand: ${Mock.longDate(Mock.today)}', style: VText.caption),
          ],
        ],
      ),
    );
  }

  /// One group of the index. `demoOnly` entries are left out in local mode (issue #28).
  ///
  /// A group whose entries are all demo-only disappears with them rather than leaving a heading
  /// over nothing.
  Widget _group(BuildContext context, String title, List<_Entry> items, {required bool isLocal}) {
    final shown = items.where((e) => !(isLocal && e.demoOnly)).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VSection(title),
        for (final e in shown)
          VListRow(title: e.label, subtitle: e.sub, chevron: true, onTap: () => context.push(e.route)),
      ],
    );
  }
}

/// One row of the Showcase.
///
/// [demoOnly] marks an entry that is only truthful against the mock repository (issue #28). Two
/// kinds qualify, and both matter now that the Showcase is reachable from a release build:
///
/// - **It would show real data under an invented label.** The five `Angekommen` variants apply
///   their delay only when `!session.isLocal` (`angekommen_screen.dart`), so in a release build a
///   row reading „+68 · Anspruch, Bündel bereit" opens the passenger's real last arrival, or an
///   empty page. The two demo `Antwort` rows already neutralise themselves the same way.
/// - **It would write to the real account.** `Antrag` POSTs `/v1/claims/draft`, which deletes an
///   existing draft — with its uploaded ticket photo and its signature — when the cases it holds
///   are no longer all open. `Willkommen`/`Berechtigungen`/`Setup` write the ticket, the NGO and
///   the onboarding flag, raise the iOS location and notification prompts (which cannot be raised
///   again in-app once dismissed) and then `go`, wiping the stack. None of that belongs behind a
///   row in a screen index.
class _Entry {
  const _Entry(this.label, this.sub, this.route, {this.demoOnly = false});
  final String label;
  final String sub;
  final String route;
  final bool demoOnly;
}
