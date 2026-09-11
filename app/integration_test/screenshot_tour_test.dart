// Screenshot tour: visits every screen in Demo mode and prints a marker per screen.
// A host-side loop takes a simulator screenshot at each marker (see tools/tour.sh).
//
//   flutter test integration_test/screenshot_tour_test.dart -d <sim> --dart-define=NO_LOCATION=1

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
import 'package:verspaetomat/screens/ride/wohin_screen.dart' show DestinationButton;
import 'package:verspaetomat/widgets/kit.dart' show VGhostButton, VListRow, VOutlineButton, VPrimaryButton;

const tour = <(String, String)>[
  ('showcase', Routes.showcase),
  ('welcome', Routes.welcome),
  ('permissions', Routes.permissions),
  ('setup', Routes.setup),
  ('bahnsteig', Routes.bahnsteig),
  ('checkin', '${Routes.checkin}?station=koeln-hbf'),
  ('exit-stop', '${Routes.exitStop}?departure=re7-0747&station=koeln-hbf&name=K%C3%B6ln%20Hbf'),
  ('wohin', '${Routes.wohin}?station=koeln-hbf&name=K%C3%B6ln%20Hbf'),
  ('wohin-zug', '${Routes.wohin}?station=koeln-hbf&name=K%C3%B6ln%20Hbf&departure=re7-0747&line=RE%207'),
  ('welcher-zug', '${Routes.welcherZug}?from=koeln-hbf&fromName=K%C3%B6ln%20Hbf&to=mock%3Ad-sseldorf-hbf&toName=D%C3%BCsseldorf%20Hbf'),
  ('unterwegs', Routes.unterwegs),
  ('angekommen-68', '${Routes.angekommen}?variant=68'),
  ('angekommen-14', '${Routes.angekommen}?variant=14'),
  ('angekommen-ausfall', '${Routes.angekommen}?variant=ausfall'),
  ('angekommen-nodata', '${Routes.angekommen}?variant=nodata'),
  ('antraege', Routes.antraege),
  ('antrag', '${Routes.antrag}?desk=Servicecenter%20Fahrgastrechte'),
  ('antrag-unbekannt', '${Routes.antrag}?desk=Unbekannt'),
  ('antwort-ok', '${Routes.antwort}?mail=m-0718-in'),
  ('antwort-frage', '${Routes.antwort}?demo=question'),
  ('antwort-nein', '${Routes.antwort}?demo=rejected'),
  ('nachtrag', Routes.nachtrag),
  ('wir', Routes.wir),
  ('zweck', '${Routes.zweck}?id=bahnhofsmission'),
  ('ich', Routes.ich),
  ('historie', Routes.historie),
  ('einstellungen', Routes.einstellungen),
  ('daten', Routes.datenherkunft),
  ('impressum', '/rechtliches/impressum'),
  ('datenschutz', '/rechtliches/datenschutz'),
  ('bote', '/rechtliches/bote'),
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
      await wait(tester, 1500);
    }
    /// Closes the topmost bottom sheet the way a thumb does, above its top edge.
    Future<void> dismissSheet(WidgetTester tester) async {
      await tester.tapAt(const Offset(200, 60));
      await wait(tester, 700);
    }
    RideMonitor monitor() => RideScope.read(tester.element(find.byType(Scaffold).first))!;
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.wir);
    await wait(tester, 600);
    demo.reset(); // an arrival left over from the Angekommen routes would hide the idle state
    demo.awayFromStation = true;
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.bahnsteig);
    await shot('bahnsteig-away');
    demo.awayFromStation = false;
    final dep = Mock.departuresKoelnHbf.firstWhere((d) => !d.cancelled);
    demo.checkIn(departure: dep, exitStop: dep.stops.last, fromStation: 'Köln Hbf');
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.wir);
    await wait(tester, 600);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.bahnsteig);
    // The ride under way (docs/19, docs/20): the ride card and the bar on Home, the bar and
    // the disabled square on another tab, the sheet full and half.
    await shot('bar-home');
    await shot('home-riding-card');
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.antraege);
    await shot('bar-antraege');
    await shot('nav-disabled');
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.bahnsteig);
    await wait(tester, 600);
    monitor().openSheet();
    await shot('sheet-riding');
    // Not awaited: frames come from the test pumps, so the future would wait forever.
    monitor().sheetController.animateTo(0.5, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    await shot('sheet-half');
    // "Abbrechen" asks why, and "Ich gebe auf" explains the Art. 18 right (docs/21 §1).
    monitor().sheetController.animateTo(0.92, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    await wait(tester, 800);
    final abbrechen = find.widgetWithText(VGhostButton, 'Abbrechen').first;
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
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.wir);
    await wait(tester, 600);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.bahnsteig);
    await shot('bahnsteig-arrived');
    demo.reset();
    Future<void> home(String name) async {
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.wir);
      await wait(tester, 600);
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.bahnsteig);
      await shot(name);
    }
    demo.awayFromStation = true;
    await home('bahnsteig-away-wir'); // the away box and the Wir block above the fold
    demo.awayFromStation = false;
    // docs/23 §1: no fix yet, so the card says so instead of naming the last station.
    demo.locatingStation = true;
    await home('bahnsteig-locating');
    demo.locatingStation = false;
    demo.reset();
    // docs/24 §1: the check-in is three sheets, and the source is a question. Home's card
    // carries the Von row that opens the first of them.
    await home('bahnsteig-von-nach');
    await tester.tap(find.byKey(const Key('von-row')));
    await wait(tester, 900);
    await shot('einchecken-von');
    // Sheets are dismissed by tapping their barrier: these are modal routes on the shell's own
    // navigator, and popping that directly trips go_router's "no pages left" assertion.
    await dismissSheet(tester);
    // The square runs all three; the itineraries are a sheet now, one swipe from the choice above.
    await tester.tap(find.byIcon(Icons.train).first);
    await wait(tester, 1200);
    await shot('einchecken-von-square');
    await tester.tap(find.byKey(const Key('von-detected')));
    await wait(tester, 1400);
    await shot('einchecken-wohin-sheet');
    await tester.tap(find.byType(DestinationButton).last);
    await wait(tester, 1800);
    await shot('einchecken-zug-sheet');
    await dismissSheet(tester);
    demo.reset();
    // docs/24 §3: the pause, and the one line on Home that says it is running.
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.einstellungen);
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
    // from the phone. The Entwicklung row is present because the tour runs a debug build.
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.einstellungen);
    await shot('einstellungen-entwicklung');
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.entwicklung);
    await shot('debug-status');
    await tester.dragUntilVisible(
      find.byKey(const Key('diagnose-log')),
      find.byType(SingleChildScrollView).first,
      const Offset(0, -220),
    );
    await shot('debug-log');
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.bahnsteig);
    await wait(tester, 600);
    // "Ich fahre weiter" (docs/21 §2): the passenger gives up on this train at Hagen and
    // picks the next one onward; only the delay up to that earliest train counts.
    DemoLeg tourLeg(String tripId, String from, String to) {
      final d = Mock.allDepartures.firstWhere((x) => x.id == tripId);
      return DemoLeg(departure: d, from: from, exit: d.stops.firstWhere((x) => x.name == to));
    }
    demo.startJourney(origin: 'Köln Hbf', destination: 'Lüdenscheid', legs: [tourLeg('re7-0747', 'Köln Hbf', 'Hagen Hbf'), tourLeg('rb52-0855', 'Hagen Hbf', 'Lüdenscheid')]);
    await wait(tester, 600);
    demo.liveDelay = 74;
    demo.replanJourney();
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.bahnsteig);
    await wait(tester, 600);
    monitor().openSheet();
    await shot('weiterfahrt-sheet');
    monitor().closeSheet();
    await wait(tester, 400);
    demo.reset();
    // Anträge (docs/18): the cards. Collecting only, then sent + question + accepted.
    Future<void> tab(String route, String name) async {
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.wir);
      await wait(tester, 600);
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go(route);
      await shot(name);
    }
    demo.incidents.removeWhere((i) => i.status == IncidentStatus.eingereicht);
    demo.mails.clear();
    await tab(Routes.antraege, 'antraege-collecting');
    demo.reset();
    demo.receiveReply(outcome: MailOutcome.question);
    demo.receiveReply(outcome: MailOutcome.accepted);
    await tab(Routes.antraege, 'antraege-mixed');
    demo.incidents.removeWhere((i) => i.isOpen); // only the claim cards, so they sit above the fold
    await tab(Routes.antraege, 'antraege-claims-only');
    demo.reset();
    // A case taken out of the bundle, shown in the list (docs/21 §4).
    demo.incidents.removeWhere((i) => i.status == IncidentStatus.eingereicht);
    demo.mails.clear();
    demo.discardIncident(demo.openIncidents.first.id, 'nicht_gefahren');
    await tab(Routes.antraege, 'antraege-discarded');
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
    await tab(Routes.antraege, 'antraege-empty');
    demo.reset();
    // The Einchecken card without any journey history: only the Wohin? field.
    demo.noHistory = true;
    await tab(Routes.bahnsteig, 'bahnsteig-no-history');
    demo.noHistory = false;
    demo.reset();
    // The reply composer (docs/18): Ticketkopie toggle, Foto hinzufügen, chips.
    final question = demo.receiveReply(outcome: MailOutcome.question)!;
    await tab('${Routes.antwort}?mail=${question.id}', 'antwort-rueckfrage');
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
    go(Routes.unterwegs);
    await shot('unterwegs-journey');
    demo.simulateArrival(minutes: 5); // in time for the RB 52
    go(Routes.wir);
    await wait(tester, 600);
    go(Routes.unterwegs);
    await shot('unterwegs-transfer');
    monitor().closeSheet();
    await shot('bar-transfer');
    go(Routes.bahnsteig);
    await shot('home-transfer-card');
    demo.confirmLeg(Mock.allDepartures.firstWhere((x) => x.id == 'rb52-0855'));
    demo.simulateArrival(minutes: 12);
    go(Routes.angekommen);
    await shot('angekommen-journey');
    demo.reset();
    demo.startJourney(origin: 'Köln Hbf', destination: 'Lüdenscheid', legs: [leg('re7-0747', 'Köln Hbf', 'Hagen Hbf'), leg('rb52-0855', 'Hagen Hbf', 'Lüdenscheid')]);
    demo.simulateArrival(minutes: 68); // the RB 52 is gone: missed connection, next one proposed
    go(Routes.unterwegs);
    await shot('unterwegs-verpasst');
    demo.confirmLeg(Mock.allDepartures.firstWhere((x) => x.id == 'rb52-0955'));
    demo.simulateArrival(minutes: 0);
    go(Routes.angekommen);
    await shot('angekommen-verpasst');
    go(Routes.historie);
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
    go(Routes.antraege);
    await shot('bar-stale');
    demo.staleRide = false;
    demo.reset();

    // One pushed sub-screen, so the header with the back arrow is in the set too.
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.wir);
    await wait(tester, 800);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('${Routes.zweck}?id=bahnhofsmission');
    await wait(tester, 1800);
    // ignore: avoid_print
    print('SHOT zweck-pushed');
    await wait(tester, 1500);
  });
}
