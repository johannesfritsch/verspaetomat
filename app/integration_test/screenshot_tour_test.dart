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

const tour = <(String, String)>[
  ('showcase', Routes.showcase),
  ('welcome', Routes.welcome),
  ('permissions', Routes.permissions),
  ('setup', Routes.setup),
  ('bahnsteig', Routes.bahnsteig),
  ('checkin', '${Routes.checkin}?station=koeln-hbf'),
  ('exit', '${Routes.exitStop}?departure=re7-0747'),
  ('unterwegs', Routes.unterwegs),
  ('angekommen-68', '${Routes.angekommen}?variant=68'),
  ('angekommen-14', '${Routes.angekommen}?variant=14'),
  ('angekommen-ausfall', '${Routes.angekommen}?variant=ausfall'),
  ('angekommen-nodata', '${Routes.angekommen}?variant=nodata'),
  ('konto', Routes.konto),
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
    // The Bahnsteig in its other three states (docs/16): away from a station, riding, arrived.
    Future<void> shot(String name) async {
      await wait(tester, 1800);
      // ignore: avoid_print
      print('SHOT $name');
      await wait(tester, 1500);
    }
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
    await shot('bahnsteig-riding');
    demo.simulateArrival(minutes: 68);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.wir);
    await wait(tester, 600);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(Routes.bahnsteig);
    await shot('bahnsteig-arrived');
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
