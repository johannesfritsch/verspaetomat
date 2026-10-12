// One ride against the local backend with the puzzles flag on or off (docs/51): a 70-minute
// delay brings an hour piece on the arrival, and Ich leads to the Puzzles page — or, with the
// flag off, none of it shows.
//
// Before it, on the backend it runs against (the stations imported, as for workflow_test):
//   stellwerk ngo image add bahnhofsmission bild.jpg --title "…" --caption "…" --yes
//   stellwerk flags puzzles on --yes        (or off, with PUZZLES=off below)
//
// flutter test integration_test/puzzle_e2e_test.dart -d <simulator udid> \
//   --dart-define=API_URL=http://127.0.0.1:8080 --dart-define=BACKEND=local \
//   --dart-define=NO_LOCATION=1 --dart-define=E2E=true --dart-define=INITIAL_ROUTE=/home \
//   --dart-define=ADMIN_TOKEN=stellwerk --dart-define=PUZZLES=on|off
//
// Needs real departures from Köln Hbf to Düsseldorf Hbf, so it only passes while trains run.
//
// Prints `SHOT <name>` and holds the screen for a while at each moment worth a screenshot, so a
// script watching the output can take it with `xcrun simctl io <udid> screenshot`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:verspaetomat/api/token_store.dart';
import 'package:verspaetomat/main.dart';
import 'package:verspaetomat/repo/repo_scope.dart';
import 'package:verspaetomat/state/demo_state.dart';

import 'workflow_test.dart'
    show Stellwerk, chooseJourney, homeIdle, homeOrRide, pumpUntilFound, reopenSheetFromBar, settle, tapIcon, tapInSheet, visibleTexts;

const puzzlesExpected = String.fromEnvironment('PUZZLES', defaultValue: 'on') == 'on';

Future<void> shot(WidgetTester tester, String name) async {
  // ignore: avoid_print
  print('SHOT $name');
  await settle(tester, 6000);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('one ride, puzzles ${puzzlesExpected ? 'on' : 'off'}', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final demo = DemoState();
    // Own keychain slot: a customer of its own, apart from the workflow test's.
    final session = Session(demo: demo, prefs: prefs, apiUrl: apiUrl, tokens: TokenStore(namespace: 'e2e-puzzle.'));
    session.init();
    await tester.pumpWidget(VerspaetomatApp(state: demo, session: session));
    await settle(tester, 1500);

    final sw = Stellwerk(apiUrl);
    await pumpUntilFound(tester, homeOrRide, timeout: const Duration(seconds: 40));
    final customer = (await sw.customers()).first['id'] as String;
    // ignore: avoid_print
    print('customer $customer, puzzlesOn=${session.puzzlesOn}');
    expect(session.puzzlesOn, puzzlesExpected);
    await sw.locate(customer, 'Köln Hbf');
    await pumpUntilFound(tester, homeIdle, timeout: const Duration(seconds: 40));

    await sw.clearOverrides();
    final picked = (await chooseJourney(tester, 'Düsseldorf Hbf', match: 'Düsseldorf H', viaSquare: true))!;
    await pumpUntilFound(tester, find.textContaining(picked.first.line, findRichText: true), timeout: const Duration(seconds: 40));
    await reopenSheetFromBar(tester);
    final riding = await sw.ridingCustomer(line: picked.first.line);
    expect(riding, customer);
    await sw.delay(customer, 70);
    await sw.fastForward(customer);

    await pumpUntilFound(tester, find.byWidgetPredicate((w) => w is Text && (w.data == 'Fertig' || w.data == 'ANGEKOMMEN')), timeout: const Duration(seconds: 60));
    if (find.text('ANGEKOMMEN').evaluate().isNotEmpty && find.text('Fertig').evaluate().isEmpty) {
      await tester.tap(find.text('Ansehen').first, warnIfMissed: false);
      await settle(tester);
    }
    await pumpUntilFound(tester, find.textContaining(RegExp(r'^\d+ Minuten')), timeout: const Duration(seconds: 20));
    // The piece waits for the count-up, then comes in.
    await settle(tester, 4000);

    final sheet = find.byKey(const Key('ride-sheet'));
    final card = find.byKey(const Key('arrival-piece'));
    if (puzzlesExpected) {
      await pumpUntilFound(tester, card, timeout: const Duration(seconds: 20));
      final scrollable = find.descendant(of: sheet, matching: find.byType(Scrollable)).first;
      await tester.scrollUntilVisible(card, 200, scrollable: scrollable);
      await settle(tester, 2500);
      // ignore: avoid_print
      print('arrival card: ${find.descendant(of: card, matching: find.byType(Text)).evaluate().map((e) => (e.widget as Text).data).join(' | ')}');
      expect(find.descendant(of: card, matching: find.text('Ein Stunden-Teil.')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.textContaining(RegExp(r'^EIN TEIL (FÜR|VON) '))), findsOneWidget);
      await shot(tester, 'arrival');
    } else {
      await settle(tester, 2000);
      expect(card, findsNothing, reason: visibleTexts());
      expect(find.textContaining('-Teil'), findsNothing);
      await shot(tester, 'arrival-off');
    }
    await tapInSheet(tester, 'Fertig');
    await pumpUntilFound(tester, homeIdle, timeout: const Duration(seconds: 40));

    // Ich: the Puzzles row, and through it the page.
    await tapIcon(tester, Icons.person_outline);
    await pumpUntilFound(tester, find.textContaining('Meine Statistik'), timeout: const Duration(seconds: 40));
    await settle(tester, 1500);
    final row = find.byKey(const Key('ich-puzzles'));
    if (puzzlesExpected) {
      await pumpUntilFound(tester, row, timeout: const Duration(seconds: 20));
      await tester.ensureVisible(row);
      await settle(tester, 800);
      await tester.tap(row, warnIfMissed: false);
      await pumpUntilFound(tester, find.text('Deine Puzzles'), timeout: const Duration(seconds: 20));
      await pumpUntilFound(tester, find.textContaining(RegExp(r'^\d+ von 12$')), timeout: const Duration(seconds: 20));
      await settle(tester, 2500);
      // ignore: avoid_print
      print('puzzles page: ${visibleTexts()}');
      await shot(tester, 'puzzles');
    } else {
      await tester.scrollUntilVisible(find.textContaining('Meine Statistik'), 200, scrollable: find.byType(Scrollable).first);
      await settle(tester, 800);
      expect(row, findsNothing);
      expect(find.text('Puzzles'), findsNothing);
      await shot(tester, 'ich-off');
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
