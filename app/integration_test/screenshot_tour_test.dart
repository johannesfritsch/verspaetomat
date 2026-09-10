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
import 'package:verspaetomat/widgets/kit.dart' show VPrimaryButton;

const tour = <(String, String)>[
  ('showcase', Routes.showcase),
  ('welcome', Routes.welcome),
  ('permissions', Routes.permissions),
  ('setup', Routes.setup),
  ('bahnsteig', Routes.bahnsteig),
  ('checkin', '${Routes.checkin}?station=koeln-hbf'),
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
    // The ride under way (docs/19): the bar on Home and on another tab, the sheet full and half.
    await shot('bar-home');
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.antraege);
    await shot('bar-antraege');
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.bahnsteig);
    await wait(tester, 600);
    monitor().openSheet();
    await shot('sheet-riding');
    // Not awaited: frames come from the test pumps, so the future would wait forever.
    monitor().sheetController.animateTo(0.5, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    await shot('sheet-half');
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
