// Screenshot tour: visits every screen in Demo mode and prints a marker per screen.
// A host-side loop takes a simulator screenshot at each marker (see tools/tour.sh).
//
//   flutter test integration_test/screenshot_tour_test.dart -d <sim> --dart-define=NO_LOCATION=1

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:verspaetomat/main.dart';
import 'package:verspaetomat/mock/mock_data.dart';
import 'package:verspaetomat/repo/repo_scope.dart';
import 'package:verspaetomat/router.dart';
import 'package:verspaetomat/state/demo_state.dart';
import 'package:verspaetomat/state/ride_monitor.dart';
import 'package:verspaetomat/screens/claims/claims_widgets.dart' show IncidentRow;
import 'package:verspaetomat/screens/claims/signature_board.dart';
import 'package:verspaetomat/screens/community/community_widgets.dart' show BadgeIcon, SwitchRow;
import 'package:verspaetomat/screens/share/share_moments.dart' show showConfirmedSheet;
import 'package:verspaetomat/widgets/ticket.dart' show Ticket;
import 'package:verspaetomat/widgets/kit.dart' show VCard, VDropzone, VGhostButton, VListRow, VOutlineButton, VPrimaryButton, VSelectCard;

// docs/29: there is one check-in and it is the sheets in `checkin_flow.dart`. The screens that
// used to be listed here — the departures board, "Wo steigst du aus?", the Wohin? and
// Welcher Zug? pages — are gone, and the flow's own shots (`einchecken-*`) cover what is left.
const tour = <(String, String)>[
  ('showcase', Routes.showcase),
  ('setup-zweck', Routes.chooseCause),
  ('setup-mitteilungen', Routes.permissions),
  ('setup-standort', Routes.location),
  ('setup-immer', Routes.locationAlways),
  ('setup-fertig', Routes.ready),
  ('bahnsteig', Routes.home),
  ('unterwegs', Routes.ride),
  ('angekommen-68', '${Routes.arrived}?variant=68'),
  ('angekommen-14', '${Routes.arrived}?variant=14'),
  ('angekommen-ausfall', '${Routes.arrived}?variant=cancelled'),
  ('angekommen-nodata', '${Routes.arrived}?variant=nodata'),
  ('antraege', Routes.claims),
  ('antrag', '${Routes.claim}?desk=Servicecenter%20Fahrgastrechte'),
  ('antrag-unbekannt', '${Routes.claim}?desk=Unbekannt'),
  ('antwort-ok', '${Routes.reply}?mail=m-0718-in'),
  ('antwort-frage', '${Routes.reply}?demo=question'),
  ('antwort-nein', '${Routes.reply}?demo=rejected'),
  ('nachtrag', Routes.addRide),
  ('wir', Routes.community),
  ('zweck', '${Routes.cause}?id=bahnhofsmission'),
  ('ich', Routes.me),
  ('historie', Routes.history),
  ('einstellungen', Routes.settings),
  ('daten', Routes.dataSources),
  ('stoerung', Routes.outage),
  ('impressum', '/legal/impressum'),
  ('datenschutz', '/legal/datenschutz'),
  ('bote', '/legal/bote'),
];

Future<void> wait(WidgetTester tester, int ms) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tour', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final demo = DemoState();
    final session = Session(demo: demo, prefs: prefs, apiUrl: apiUrl);
    session.init();
    await tester.pumpWidget(VerspaetomatApp(state: demo, session: session));
    await wait(tester, 1500);
    for (final (name, route) in tour) {
      final ctx = tester.element(find.byType(Scaffold).first);
      GoRouter.of(ctx).go(route);
      await wait(tester, 1800);
      // ignore: avoid_print
      print('SHOT $name');
      await wait(tester, 1500);
    }
    // The Bahnsteig in its other states: away from a station, riding (the bar, the sheet), arrived.
    Future<void> shot(String name) async {
      await wait(tester, 1800);
      // ignore: avoid_print
      print('SHOT $name');
      // The screenshot is taken by tour.sh half a second after this line, and `simctl io
      // screenshot` is not instant: under load the captures fall behind the markers and a shot
      // lands on the next screen. Three seconds of standing still is cheap insurance — the whole
      // tour is five minutes either way.
      await wait(tester, 3000);
    }
    /// Closes the topmost bottom sheet the way a thumb does, above its top edge.
    Future<void> dismissSheet(WidgetTester tester) async {
      await tester.tapAt(const Offset(200, 60));
      await wait(tester, 700);
    }
    // Willkommen is five cards behind one route (#43), and photographing the route photographed
    // the first one. That is how the old screen's last card — the only one that grew two rows
    // under its button — went unseen: every visual pass looked at card 1. Tap „Weiter" through
    // all five, so a change to any of them shows up in the tour.
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.welcome);
    await wait(tester, 1500);
    for (final name in ['willkommen-gemeinsam', 'willkommen-einchecken', 'willkommen-warten', 'willkommen-zweck', 'willkommen-losgehts']) {
      await shot(name);
      // „Weiter" on the first four cards, „Einrichten" on the last — which is the end of the
      // walk, so the label is only tapped when there is a card after it.
      final weiter = find.widgetWithText(VPrimaryButton, 'Weiter');
      if (weiter.evaluate().isEmpty) break;
      await tester.tap(weiter);
      await wait(tester, 600);
    }

    // The boards on Wir are below the fold, so the route's own shot never showed them and the
    // ranks went unphotographed through their redesign (#24). Scroll to them.
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.community);
    await wait(tester, 1500);
    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -900));
    await shot('wir-ranglisten');

    // docs/39: behind the pre-step, the first step lists every open case of the desk with its
    // own tick. The route above stops at „So läuft das", so the tour walks one step further.
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('${Routes.claim}?desk=Servicecenter%20Fahrgastrechte');
    await wait(tester, 1800);
    await tester.tap(find.text('Los geht\'s'));
    await shot('antrag-pruefen');

    // On to the Zweck step, and then open the list of other Vereine. This is the one corner of
    // the flow the tour never reached, which is how a Row that put a full-width block button in
    // a non-flex slot got as far as TestFlight: in release the label came out one letter per
    // line and the button was centred off the screen (test/ghost_button_row_test.dart).
    // Two gates stand in the way, and both are the point of their step: „Prüfen" holds until the
    // passenger's own details are on file, and „Ticket" until a ticket hangs on the claim.
    // By the word, not by the widget: „Weiter" is the red primary once the step is finished and
    // the quiet tier while something is still missing (#21), and the tour presses it in both
    // states — the first press, on the empty form, is what puts the marks on the rows.
    Future<void> weiter() async {
      await tester.tap(find.text('Weiter').first);
      await wait(tester, 1200);
    }
    Future<void> tapIt(Finder f) async {
      await tester.ensureVisible(f);
      await wait(tester, 400);
      await tester.tap(f);
    }
    final fields = find.byType(TextField);
    if (fields.evaluate().length >= 3) {
      // Weiter first with the form empty: it has to say what is missing rather than sit grey.
      await weiter();
      await shot('antrag-angaben-fehlen');
      await wait(tester, 3500); // let the snackbar clear the button
      await tester.enterText(fields.at(0), 'Johannes Fritsch');
      await tester.enterText(fields.at(1), 'Bahnhofstraße 1, 50667 Köln');
      await tester.enterText(fields.at(2), 'johannes@example.org');
      await wait(tester, 400);
    }
    // One button: Weiter checks the details, saves them and moves on. The twelve words used to
    // interrupt here; they live in Einstellungen only since #45.
    await weiter();
    await wait(tester, 1500);
    // #52: what to upload, and why one picture per month.
    await shot('antrag-ticket');
    // This claim spans two months, and every month is its own ticket, so the step holds until
    // each one has a picture on it.
    final anhaengen = find.widgetWithText(VDropzone, 'Ticket anhängen');
    while (anhaengen.evaluate().isNotEmpty) {
      await tapIt(anhaengen.first);
      await wait(tester, 2500);
    }
    await weiter();
    await shot('antrag-zweck');
    await tapIt(find.widgetWithText(VCard, 'Anderen Zweck wählen').first);
    await wait(tester, 900);
    await shot('antrag-zweck-offen');

    // Fold the list away again, then on through the last two steps. Unterschrift will not let go
    // until the claim is signed, so the tour draws on the pad and confirms.
    // `.last`: the header's own X comes first in the tree now, and that one leaves the Antrag.
    await tapIt(find.byIcon(Icons.close).last);
    await wait(tester, 700);

    // The header X asks before it throws anything away. Answer "stay".
    await tester.tap(find.byIcon(Icons.close).first);
    await wait(tester, 900);
    await shot('antrag-verlassen');
    await tester.tap(find.widgetWithText(VPrimaryButton, 'Weiter ausfüllen').first);
    await wait(tester, 900);

    await weiter();
    await shot('antrag-unterschrift');
    final line = find.text('Hier unterschreiben');
    if (line.evaluate().isNotEmpty) {
      await tapIt(line.first);
      await wait(tester, 1200);
      await shot('antrag-unterschrift-brett');
      final board = find.byType(SignatureBoard);
      if (board.evaluate().isNotEmpty) {
        final c = tester.getCenter(board);
        await tester.dragFrom(c - const Offset(80, 10), const Offset(60, 25));
        await wait(tester, 300);
        await tester.dragFrom(c + const Offset(10, 10), const Offset(70, -30));
        await wait(tester, 600);
        await shot('antrag-unterschrift-gezeichnet');
        await tapIt(find.widgetWithText(VPrimaryButton, 'Bestätigen').first);
        await wait(tester, 2500);
      }
    }
    await shot('antrag-unterschrift-fertig');
    await weiter();
    await shot('antrag-senden');
    // The attachment is the form as signed: in Demo that PDF is composed with the ink in it.
    final pdfRow = find.text('EU-Antrag.pdf');
    if (pdfRow.evaluate().isNotEmpty) {
      await tapIt(pdfRow.first);
      await wait(tester, 3500);
      await shot('antrag-senden-pdf');
      await tester.pageBack();
      await wait(tester, 900);
    }

    RideMonitor monitor() => RideScope.read(tester.element(find.byType(Scaffold).first))!;
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.community);
    await wait(tester, 600);
    demo.reset(); // an arrival left over from the Angekommen routes would hide the idle state
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.home);
    await shot('bahnsteig-einchecken');
    final dep = Mock.departuresKoelnHbf.firstWhere((d) => !d.cancelled);
    demo.checkIn(departure: dep, exitStop: dep.stops.last, fromStation: 'Köln Hbf');
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.community);
    await wait(tester, 600);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.home);
    // The ride under way (docs/19, docs/20): the ride card and the bar on Home, the bar and
    // the disabled square on another tab, the sheet full and half.
    await shot('bar-home');
    await shot('home-riding-card');
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.claims);
    await shot('bar-antraege');
    await shot('nav-disabled');
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.home);
    await wait(tester, 600);
    monitor().openSheet();
    await shot('sheet-riding');
    // Not awaited: frames come from the test pumps, so the future would wait forever.
    monitor().sheetController.animateTo(0.5, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    await shot('sheet-half');
    // "Fahrt beenden" asks why, and "Ich gebe auf" explains the Art. 18 right (docs/21 §1).
    monitor().sheetController.animateTo(0.92, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    await wait(tester, 800);
    final abbrechen = find.byKey(const Key('ride-abort')).first;
    await tester.ensureVisible(abbrechen);
    await wait(tester, 600);
    await tester.tap(abbrechen);
    await wait(tester, 900);
    await shot('abbrechen-sheet');
    await tester.tap(find.byKey(const Key('abort-aufgegeben')));
    await wait(tester, 1200);
    await shot('abbrechen-aufgegeben');
    await tester.tap(find.widgetWithText(VOutlineButton, 'Verstanden').first);
    await wait(tester, 600);
    demo.reset();
    demo.checkIn(departure: dep, exitStop: dep.stops.last, fromStation: 'Köln Hbf');
    await wait(tester, 800);
    monitor().openSheet();
    await wait(tester, 800);
    // The arrival while the sheet is open: the reveal in place.
    demo.simulateArrival(minutes: 68);
    await shot('sheet-arrived');
    monitor().closeSheet();
    await wait(tester, 400);
    demo.reset();
    demo.checkIn(departure: dep, exitStop: dep.stops.last, fromStation: 'Köln Hbf');
    await wait(tester, 800);
    demo.simulateArrival(minutes: 68);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.community);
    await wait(tester, 600);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.home);
    await shot('bahnsteig-arrived');
    demo.reset();
    Future<void> home(String name) async {
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.community);
      await wait(tester, 600);
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.home);
      await shot(name);
    }
    // docs/30: Home is the same square of paper wherever the phone thinks it is — no station,
    // no destinations, one button. The stations are the check-in's own first question now.
    await home('bahnsteig-wir-und-einchecken');
    // docs/30: Wir is at the top now and Deine Woche wears the same box, which is below the
    // fold — so the tour scrolls to it rather than leaving the change unphotographed.
    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -420));
    await shot('bahnsteig-deine-woche');
    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, 420));
    await wait(tester, 400);
    // docs/24 §1 · docs/30: the button on Home opens the first of the three sheets, the same
    // one the square opens. It proposes the detected station, the ones nearby and the ones
    // this passenger uses most.
    await tester.tap(find.byKey(const Key('einchecken-cta')));
    await wait(tester, 1200);
    await shot('einchecken-von');
    await dismissSheet(tester);
    // The same sheet from the square in the bar. It has to look the same, bottom bar and all
    // (issue #12): the two used to open on different Navigators.
    await tester.tap(find.byKey(const Key('nav-checkin')));
    await wait(tester, 1200);
    await shot('einchecken-von-square');
    await tester.tap(find.byKey(const Key('von-detected')));
    await wait(tester, 1400);
    await shot('einchecken-wohin-sheet');
    await tester.tap(find.byType(VSelectCard).first);
    await wait(tester, 1800);
    await shot('einchecken-zug-sheet');
    await dismissSheet(tester);
    demo.reset();
    // docs/24 §3: the pause, and the one line on Home that says it is running.
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.settings);
    await shot('einstellungen-pausieren');
    await tester.tap(find.byKey(const Key('pausieren')));
    await wait(tester, 900);
    await shot('ruhe-sheet');
    await tester.tap(find.widgetWithText(VListRow, '3 Stunden').first);
    await wait(tester, 1200);
    await home('bahnsteig-stumm');
    await session.unsnoozeNudges();
    await wait(tester, 800);
    demo.reset();
    // docs/25 §5: the debug page, which exists so "why no nudge at Memmingen?" can be answered
    // from the phone. Since issue #29 the Entwicklung row is in every build, release included.
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.settings);
    await shot('einstellungen-entwicklung');
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.developer);
    await shot('debug-status');
    // Which flags this phone is on (#41). Its own segment since it stopped being a footnote under
    // „Zustand": it is the one thing here somebody changes from a laptop and then reads back on a
    // phone.
    await tester.tap(find.text('Flaggen'));
    await wait(tester, 400);
    await shot('debug-flaggen');
    // issue #32: the page is four segments now and only the open one is built, so the log has to
    // be selected rather than scrolled to. Tapping by label keeps this honest — an IndexedStack
    // would have kept the key findable and photographed the wrong segment under the right name,
    // and it is why adding a segment above did not break this.
    await tester.tap(find.text('Log'));
    await wait(tester, 400);
    await tester.dragUntilVisible(
      find.byKey(const Key('diagnose-log')),
      find.byType(SingleChildScrollView).first,
      const Offset(0, -220),
    );
    await shot('debug-log');
    // issue #29: the drawing itself. On a simulator the phone monitors nothing, so the real page
    // has nothing to draw — the Showcase entry carries an invented set so the picture can be seen.
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.fenceMap);
    await shot('zaunkarte');
    await tester.dragUntilVisible(
      find.byKey(const Key('zaunkarte-nah')),
      find.byType(SingleChildScrollView).first,
      const Offset(0, -220),
    );
    await shot('zaunkarte-nah');
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.home);
    await wait(tester, 600);
    // docs/27: the shareable Fahrkarte. The arrival card, the punctual one (which is a
    // different face, not the same card with a zero in it), and a badge.
    demo.reset();
    demo.checkIn(departure: dep, exitStop: dep.stops.last, fromStation: 'Köln Hbf');
    await wait(tester, 600);
    demo.simulateArrival(minutes: 68);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.arrived);
    await wait(tester, 1000);
    await tester.tap(find.widgetWithText(VOutlineButton, 'Teilen').first, warnIfMissed: false);
    await shot('karte-angekommen');
    await dismissSheet(tester);
    demo.reset();
    demo.checkIn(departure: dep, exitStop: dep.stops.last, fromStation: 'Köln Hbf');
    await wait(tester, 600);
    demo.simulateArrival(minutes: 0);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.arrived);
    await wait(tester, 1000);
    await tester.tap(find.widgetWithText(VOutlineButton, 'Teilen').first, warnIfMissed: false);
    await shot('karte-puenktlich');
    await dismissSheet(tester);
    demo.reset();
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.me);
    await wait(tester, 900);
    await tester.tap(find.byType(BadgeIcon).first, warnIfMissed: false);
    await wait(tester, 900);
    await tester.tap(find.widgetWithText(VGhostButton, 'Als Karte teilen').first, warnIfMissed: false);
    await shot('karte-abzeichen');
    await dismissSheet(tester);
    // #49: every card of mine, collected on Ich; one in portrait; and the railway's yes.
    final teilen = find.text('Zum Teilen');
    await tester.scrollUntilVisible(teilen, 300, scrollable: find.byType(Scrollable).first);
    await wait(tester, 600);
    await shot('ich-teilen');
    await tester.tap(find.text('Meine Minuten'), warnIfMissed: false);
    await wait(tester, 1200);
    await tester.scrollUntilVisible(find.text('Hochformat'), 200, scrollable: find.byType(Scrollable).last);
    await wait(tester, 400);
    await tester.tap(find.descendant(of: find.widgetWithText(SwitchRow, 'Hochformat'), matching: find.byType(Switch)), warnIfMissed: false);
    await wait(tester, 400);
    await tester.scrollUntilVisible(find.byType(Ticket), -300, scrollable: find.byType(Scrollable).last);
    await wait(tester, 800);
    await shot('karte-hochformat');
    await dismissSheet(tester);
    final facts = await session.repo.shareFacts();
    final ctxSheet = tester.element(find.byType(Scaffold).first);
    if (ctxSheet.mounted) unawaited(showConfirmedSheet(ctxSheet, facts.confirmedClaims.first));
    await wait(tester, 1800);
    await shot('bestaetigt');
    await dismissSheet(tester);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.home);
    await wait(tester, 600);
    // "Ich fahre weiter" (docs/21 §2): the passenger gives up on this train at Hagen and
    // picks the next one onward; only the delay up to that earliest train counts.
    DemoLeg tourLeg(String tripId, String from, String to) {
      final d = Mock.allDepartures.firstWhere((x) => x.id == tripId);
      return DemoLeg(departure: d, from: from, exit: d.stops.firstWhere((x) => x.name == to));
    }
    demo.startJourney(origin: 'Köln Hbf', destination: 'Lüdenscheid', legs: [tourLeg('re7-0747', 'Köln Hbf', 'Hagen Hbf'), tourLeg('rb52-0855', 'Hagen Hbf', 'Lüdenscheid')]);
    await wait(tester, 600);
    // #62: two trains on the sheet, the change between them.
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.home);
    await wait(tester, 600);
    monitor().openSheet();
    await shot('sheet-riding-umstieg');
    monitor().closeSheet();
    await wait(tester, 400);
    demo.liveDelay = 74;
    demo.replanJourney();
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.home);
    await wait(tester, 600);
    monitor().openSheet();
    await shot('weiterfahrt-sheet');
    monitor().closeSheet();
    await wait(tester, 400);
    demo.reset();
    // Anträge (docs/18): the cards. Collecting only, then sent + question + accepted.
    Future<void> tab(String route, String name) async {
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.community);
      await wait(tester, 600);
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go(route);
      await shot(name);
    }
    demo.incidents.removeWhere((i) => i.status == IncidentStatus.eingereicht);
    demo.mails.clear();
    await tab(Routes.claims, 'antraege-collecting');
    demo.reset();
    demo.receiveReply(outcome: MailOutcome.question);
    demo.receiveReply(outcome: MailOutcome.accepted);
    await tab(Routes.claims, 'antraege-mixed');
    demo.incidents.removeWhere((i) => i.isOpen); // only the claim cards, so they sit above the fold
    await tab(Routes.claims, 'antraege-claims-only');
    demo.reset();
    // A case taken out of the bundle, shown in the list (docs/21 §4).
    demo.incidents.removeWhere((i) => i.status == IncidentStatus.eingereicht);
    demo.mails.clear();
    demo.discardIncident(demo.openIncidents.first.id, 'nicht_gefahren');
    await tab(Routes.claims, 'antraege-discarded');
    // The row's own sheet: "Doch einreichen" and, beside it, "Fahrt löschen" (docs/23 §2).
    await tester.tap(find.text('anzeigen').first);
    await wait(tester, 800);
    // The discarded row itself, found by its reason line: `.last` would hit the next desk's card.
    final discardedRow = find.ancestor(of: find.textContaining('gar nicht mitgefahren').first, matching: find.byType(IncidentRow)).first;
    await tester.ensureVisible(discardedRow);
    await wait(tester, 400);
    await tester.tap(discardedRow);
    await shot('antraege-discarded-loeschen');
    // The sheet may already have closed itself; popping the last page would tear the router down.
    final nav = Navigator.of(tester.element(find.byType(Scaffold).last));
    if (nav.canPop()) nav.pop();
    await wait(tester, 600);
    demo.reset();
    // Nothing at all: the explainer instead of an empty box (docs/21 §5).
    demo.incidents.clear();
    demo.mails.clear();
    await tab(Routes.claims, 'antraege-empty');
    demo.reset();
    // "Wohin?" without any journey history: the line that says so, and the search (docs/18).
    demo.noHistory = true;
    await tab(Routes.home, 'bahnsteig-idle');
    await tester.tap(find.byKey(const Key('einchecken-cta')));
    await wait(tester, 1000);
    await tester.tap(find.byKey(const Key('von-detected')));
    await wait(tester, 1200);
    await shot('einchecken-wohin-leer');
    await dismissSheet(tester);
    demo.noHistory = false;
    demo.reset();
    // The reply composer (docs/18): Ticketkopie toggle, Foto hinzufügen, chips.
    final question = demo.receiveReply(outcome: MailOutcome.question)!;
    await tab('${Routes.reply}?mail=${question.id}', 'antwort-rueckfrage');
    await tester.tap(find.widgetWithText(VPrimaryButton, 'Antworten').first);
    await shot('antwort-composer');
    Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
    await wait(tester, 600);
    demo.reset();

    // Journeys with a connection (docs/17): transfer, missed connection, arrival with the journey delay.
    void go(String route) => GoRouter.of(tester.element(find.byType(Scaffold).first)).go(route);
    DemoLeg leg(String tripId, String from, String to) {
      final d = Mock.allDepartures.firstWhere((x) => x.id == tripId);
      return DemoLeg(departure: d, from: from, exit: d.stops.firstWhere((s) => s.name == to));
    }
    demo.startJourney(origin: 'Köln Hbf', destination: 'Lüdenscheid', legs: [leg('re7-0747', 'Köln Hbf', 'Hagen Hbf'), leg('rb52-0855', 'Hagen Hbf', 'Lüdenscheid')]);
    go(Routes.ride);
    await shot('unterwegs-journey');
    demo.simulateArrival(minutes: 5); // in time for the RB 52
    go(Routes.community);
    await wait(tester, 600);
    go(Routes.ride);
    await shot('unterwegs-transfer');
    monitor().closeSheet();
    await shot('bar-transfer');
    go(Routes.home);
    await shot('home-transfer-card');
    demo.confirmLeg(Mock.allDepartures.firstWhere((x) => x.id == 'rb52-0855'));
    demo.simulateArrival(minutes: 12);
    go(Routes.arrived);
    await shot('angekommen-journey');
    demo.reset();
    demo.startJourney(origin: 'Köln Hbf', destination: 'Lüdenscheid', legs: [leg('re7-0747', 'Köln Hbf', 'Hagen Hbf'), leg('rb52-0855', 'Hagen Hbf', 'Lüdenscheid')]);
    demo.simulateArrival(minutes: 68); // the RB 52 is gone: missed connection, next one proposed
    go(Routes.ride);
    await shot('unterwegs-verpasst');
    demo.confirmLeg(Mock.allDepartures.firstWhere((x) => x.id == 'rb52-0955'));
    demo.simulateArrival(minutes: 0);
    go(Routes.arrived);
    await shot('angekommen-verpasst');
    go(Routes.history);
    await shot('historie-journeys');
    // Every row opens the ride in full, with "Fahrt löschen" at the bottom (docs/23 §2).
    await tester.tap(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('journey-row-')).first);
    await shot('historie-loeschen');
    Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
    await wait(tester, 600);
    demo.reset();
    // docs/23 §3: a journey nobody closed. The bar stops reporting and asks.
    demo.startJourney(origin: 'Köln Hbf', destination: 'Rheine', legs: [leg('re7-0747', 'Köln Hbf', 'Rheine')]);
    demo.staleRide = true;
    go(Routes.claims);
    await shot('bar-stale');
    demo.staleRide = false;
    demo.reset();

    // One pushed sub-screen, so the header with the back arrow is in the set too.
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.community);
    await wait(tester, 800);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('${Routes.cause}?id=bahnhofsmission');
    await wait(tester, 1800);
    // ignore: avoid_print
    print('SHOT zweck-pushed');
    await wait(tester, 1500);
  });
}
