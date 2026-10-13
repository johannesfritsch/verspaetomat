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
//   --dart-define=ADMIN_TOKEN=stellwerk --dart-define=PUZZLES=on|off|register|complete
//
// `register` only boots the app and prints its customer and token, so the Stellwerk can prepare
// the account (docs/51 §9c): `flags puzzles on --for <who>`, and
// `pieces <who> fill bahnhofsmission --leave 1 --leave-tier hour --next` on a picture with a video.
// `complete` then rides 70 minutes: the hour piece finishes the picture, the film downloads and
// plays, the finished picture opens from the Puzzles page, and an owned piece of a started picture
// goes into the hand.
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
import 'package:verspaetomat/screens/puzzles/puzzle_widgets.dart' show ArrivalPieceCard;
import 'package:verspaetomat/state/demo_state.dart';
import 'package:verspaetomat/widgets/puzzle.dart' show PuzzleTapArea;

import 'workflow_test.dart'
    show Stellwerk, chooseJourney, homeIdle, homeOrRide, pumpUntilFound, pumpUntilGone, reopenSheetFromBar, settle, tapIcon, tapInSheet, visibleTexts;

const mode = String.fromEnvironment('PUZZLES', defaultValue: 'on');
const puzzlesExpected = mode != 'off';

Future<void> shot(WidgetTester tester, String name) async {
  // ignore: avoid_print
  print('SHOT $name');
  await settle(tester, 6000);
}

/// The app on its own keychain slot: a customer of its own, apart from the workflow test's.
Future<Session> boot(WidgetTester tester) async {
  final prefs = await SharedPreferences.getInstance();
  final demo = DemoState();
  final session = Session(demo: demo, prefs: prefs, apiUrl: apiUrl, tokens: TokenStore(namespace: 'e2e-puzzle.'));
  session.init();
  await tester.pumpWidget(VerspaetomatApp(state: demo, session: session));
  await settle(tester, 1500);
  await pumpUntilFound(tester, homeOrRide, timeout: const Duration(seconds: 40));
  return session;
}

/// Check in at Köln Hbf, 70 minutes late, fast-forward: the arrival, counted up.
Future<void> rideSeventy(WidgetTester tester, Stellwerk sw, String customer) async {
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
}

/// Ich, then „Alle ansehen" beside its Puzzles heading: the page.
Future<void> openPuzzles(WidgetTester tester) async {
  await tapIcon(tester, Icons.person_outline);
  await pumpUntilFound(tester, find.textContaining('Meine Statistik'), timeout: const Duration(seconds: 40));
  await settle(tester, 1500);
  final row = find.byKey(const Key('ich-puzzles'));
  await pumpUntilFound(tester, row, timeout: const Duration(seconds: 20));
  await tester.ensureVisible(row);
  await settle(tester, 800);
  await tester.tap(find.descendant(of: row, matching: find.text('Alle ansehen')), warnIfMissed: false);
  await pumpUntilFound(tester, find.text('Deine Puzzles'), timeout: const Duration(seconds: 20));
  await settle(tester, 2500);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('one ride, puzzles ${puzzlesExpected ? 'on' : 'off'}', (tester) async {
    final session = await boot(tester);
    final sw = Stellwerk(apiUrl);
    final customer = (await sw.customers()).first['id'] as String;
    // ignore: avoid_print
    print('customer $customer, puzzlesOn=${session.puzzlesOn}');
    expect(session.puzzlesOn, puzzlesExpected);
    await rideSeventy(tester, sw, customer);

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

    // Home: the picture under way where „Deine Woche" stood — or the week, with the flag off.
    final homeCard = find.byKey(const Key('home-puzzles'));
    if (puzzlesExpected) {
      await pumpUntilFound(tester, homeCard, timeout: const Duration(seconds: 20));
      await tester.ensureVisible(homeCard);
      await settle(tester, 1500);
      expect(find.text('DEINE WOCHE'), findsNothing);
      expect(find.descendant(of: homeCard, matching: find.textContaining(RegExp(r'^(\d+ von 12|Fertig)$'))), findsOneWidget);
      await shot(tester, 'home');
    } else {
      final week = find.text('DEINE WOCHE');
      await pumpUntilFound(tester, week, timeout: const Duration(seconds: 20));
      await tester.ensureVisible(week);
      await settle(tester, 1500);
      expect(homeCard, findsNothing);
      await shot(tester, 'home-off');
    }

    // Ich: the Puzzles row, and through it the page.
    if (puzzlesExpected) {
      await openPuzzles(tester);
      await pumpUntilFound(tester, find.textContaining(RegExp(r'^\d+ von 12$')), timeout: const Duration(seconds: 20));
      await settle(tester, 2500);
      // ignore: avoid_print
      print('puzzles page: ${visibleTexts()}');
      await shot(tester, 'puzzles');
    } else {
      await tapIcon(tester, Icons.person_outline);
      await pumpUntilFound(tester, find.textContaining('Meine Statistik'), timeout: const Duration(seconds: 40));
      await settle(tester, 1500);
      final row = find.byKey(const Key('ich-puzzles'));
      await tester.scrollUntilVisible(find.textContaining('Meine Statistik'), 200, scrollable: find.byType(Scrollable).first);
      await settle(tester, 800);
      expect(row, findsNothing);
      expect(find.text('Puzzles'), findsNothing);
      await shot(tester, 'ich-off');
    }
  }, timeout: const Timeout(Duration(minutes: 10)), skip: mode == 'register' || mode == 'complete');

  testWidgets('register: the customer and its token, for the Stellwerk', (tester) async {
    final session = await boot(tester);
    for (var i = 0; i < 40 && session.me == null; i++) {
      await settle(tester, 250);
    }
    // ignore: avoid_print
    print('CUSTOMER ${session.me?.id} TOKEN ${await session.tokens.token()}');
  }, skip: mode != 'register');

  testWidgets('complete: the hour piece finishes the picture, the film plays, a piece in the hand', (tester) async {
    final session = await boot(tester);
    final sw = Stellwerk(apiUrl);
    for (var i = 0; i < 40 && session.me == null; i++) {
      await settle(tester, 250);
    }
    final customer = session.me!.id;
    expect(session.puzzlesOn, isTrue, reason: 'flags puzzles on --for $customer');
    await rideSeventy(tester, sw, customer);

    final card = find.byKey(const Key('arrival-piece'));
    await pumpUntilFound(tester, card, timeout: const Duration(seconds: 20));
    final scrollable = find.descendant(of: find.byKey(const Key('ride-sheet')), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(card, 200, scrollable: scrollable);
    await pumpUntilFound(tester, find.descendant(of: card, matching: find.text('Das Bild bewegt sich jetzt.')), timeout: const Duration(seconds: 20));
    await tester.scrollUntilVisible(find.byKey(const Key('arrival-watch')), 200, scrollable: scrollable);
    await settle(tester, 1000);
    // ignore: avoid_print
    print('arrival card: ${find.descendant(of: card, matching: find.byType(Text)).evaluate().map((e) => (e.widget as Text).data).join(' | ')}');
    expect(find.descendant(of: card, matching: find.text('Ein Stunden-Teil.')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('12 von 12.')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.textContaining('Fertig: Nachtschicht am Gleis')), findsOneWidget);
    await shot(tester, 'arrival-complete');

    // The film comes once the last piece is there; „Ansehen" plays it.
    final puzzle = tester.widget<ArrivalPieceCard>(find.byType(ArrivalPieceCard)).piece.puzzle;
    for (var i = 0; i < 120 && !session.videos.stateOf(puzzle).ready; i++) {
      await settle(tester, 500);
    }
    // ignore: avoid_print
    print('film: ${session.videos.stateOf(puzzle).phase}');
    expect(session.videos.stateOf(puzzle).ready, isTrue);
    await tester.tap(find.byKey(const Key('arrival-watch')), warnIfMissed: false);
    await pumpUntilFound(tester, find.byKey(const Key('puzzle-video')), timeout: const Duration(seconds: 10));
    await settle(tester, 3000);
    await shot(tester, 'player');
    // Twenty seconds of film, then the picture again.
    await pumpUntilGone(tester, find.byKey(const Key('puzzle-video')), timeout: const Duration(seconds: 40));
    await tapInSheet(tester, 'Fertig');
    await pumpUntilFound(tester, homeIdle, timeout: const Duration(seconds: 40));

    // Home: the picture under way where „Deine Woche" stood — or the week, with the flag off.
    final homeCard = find.byKey(const Key('home-puzzles'));
    if (puzzlesExpected) {
      await pumpUntilFound(tester, homeCard, timeout: const Duration(seconds: 20));
      await tester.ensureVisible(homeCard);
      await settle(tester, 1500);
      expect(find.text('DEINE WOCHE'), findsNothing);
      expect(find.descendant(of: homeCard, matching: find.textContaining(RegExp(r'^(\d+ von 12|Fertig)$'))), findsOneWidget);
      await shot(tester, 'home');
    } else {
      final week = find.text('DEINE WOCHE');
      await pumpUntilFound(tester, week, timeout: const Duration(seconds: 20));
      await tester.ensureVisible(week);
      await settle(tester, 1500);
      expect(homeCard, findsNothing);
      await shot(tester, 'home-off');
    }

    // The finished picture from the Puzzles page, with its film's button.
    await openPuzzles(tester);
    // ignore: avoid_print
    print('puzzles page: ${visibleTexts()}');
    final badge = find.byKey(const Key('film-badge'));
    await pumpUntilFound(tester, badge, timeout: const Duration(seconds: 20));
    await tester.ensureVisible(badge);
    await settle(tester, 500);
    await tester.tap(badge, warnIfMissed: false);
    await pumpUntilFound(tester, find.byKey(const Key('film-button')), timeout: const Duration(seconds: 20));
    await settle(tester, 1500);
    await shot(tester, 'finished-sheet');
    Navigator.of(tester.element(find.byKey(const Key('film-button')))).pop();
    await pumpUntilGone(tester, find.byKey(const Key('film-button')), timeout: const Duration(seconds: 10));

    // A piece of a started picture into the hand (§9a): the middle of an owned cell.
    final started = find.byWidgetPredicate((w) => w is PuzzleTapArea && w.owned.isNotEmpty && w.owned.length < w.cut.pieces);
    await pumpUntilFound(tester, started, timeout: const Duration(seconds: 20));
    await tester.ensureVisible(started.first);
    await settle(tester, 500);
    final area = tester.widget<PuzzleTapArea>(started.first);
    final box = tester.renderObject<RenderBox>(started.first);
    final slot = area.owned.first;
    final cell = Size(box.size.width / area.cut.cols, box.size.height / area.cut.rows);
    await tester.tapAt(box.localToGlobal(Offset((slot % area.cut.cols + 0.5) * cell.width, (slot ~/ area.cut.cols + 0.5) * cell.height)));
    await pumpUntilFound(tester, find.byKey(const Key('piece-in-hand')), timeout: const Duration(seconds: 10));
    await settle(tester, 1500);
    await shot(tester, 'piece-in-hand');
    await tester.tap(find.byKey(const Key('piece-in-hand-close')), warnIfMissed: false);
    await pumpUntilGone(tester, find.byKey(const Key('piece-in-hand')), timeout: const Duration(seconds: 10));
  }, timeout: const Timeout(Duration(minutes: 10)), skip: mode != 'complete');
}
