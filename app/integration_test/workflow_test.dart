// End-to-end walk of the core workflows against the local backend.
//
// flutter test integration_test/workflow_test.dart -d <simulator udid> \
//   --dart-define=API_URL=http://127.0.0.1:8081 --dart-define=BACKEND=local \
//   --dart-define=NO_LOCATION=1 --dart-define=E2E=true --dart-define=INITIAL_ROUTE=/bahnsteig
//
// Needs real departures at Köln Hbf, so it only passes while trains run.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:verspaetomat/api/models.dart';
import 'package:verspaetomat/main.dart';
import 'package:verspaetomat/repo/repo_scope.dart';
import 'package:verspaetomat/screens/claims/claims_widgets.dart';
import 'package:verspaetomat/screens/ride/ride_widgets.dart';
import 'package:verspaetomat/state/demo_state.dart';

/// The app never "settles" (animated clock, polling timers), so we pump in steps.
Future<void> pumpUntilFound(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('not found within $timeout: $finder\nvisible: ${visibleTexts()}');
}

/// Every Text on screen, for failure messages.
String visibleTexts() {
  final texts = find.byType(Text).evaluate().map((e) => (e.widget as Text).data ?? '').where((t) => t.isNotEmpty).toList();
  return texts.take(40).join(' | ');
}

Future<void> pumpUntilGone(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isEmpty) return;
  }
  throw TestFailure('still present after $timeout: $finder');
}

Future<void> settle(WidgetTester tester, [int ms = 600]) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapText(WidgetTester tester, String text, {Duration timeout = const Duration(seconds: 30), bool rich = false}) async {
  final f = rich ? find.textContaining(text, findRichText: true) : find.text(text);
  await pumpUntilFound(tester, f, timeout: timeout);
  await tester.ensureVisible(f.first);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(f.first, warnIfMissed: false);
  await settle(tester);
}

/// One ride: pick a departure at Köln Hbf, confirm the exit stop, simulate +68, finish.
Future<void> rideOnce(WidgetTester tester, int n) async {
  // Bahnsteig: a leftover arrival card from an earlier run is dismissed first.
  await pumpUntilFound(tester, find.byWidgetPredicate((w) => w is Text && (w.data == 'Kein Zug. Gut so.' || w.data == 'ANGEKOMMEN')), timeout: const Duration(seconds: 40));
  if (find.text('ANGEKOMMEN').evaluate().isNotEmpty) {
    await tapText(tester, 'Fertig');
  }
  await pumpUntilFound(tester, find.text('Kein Zug. Gut so.'), timeout: const Duration(seconds: 40));
  final chip = find.byType(ActionChip);
  await pumpUntilFound(tester, chip, timeout: const Duration(seconds: 40));
  expect(find.textContaining('Köln', findRichText: true), findsWidgets);
  await tester.ensureVisible(chip.first);
  await tester.tap(chip.first, warnIfMissed: false);
  await settle(tester);

  // Einchecken: wait for departures, pick the first non-cancelled regional one.
  await pumpUntilFound(tester, find.byType(DepartureRow), timeout: const Duration(seconds: 40));
  await settle(tester, 800);
  final rows = find.byType(DepartureRow);
  Finder? pick;
  for (var i = 0; i < rows.evaluate().length; i++) {
    final w = tester.widget<DepartureRow>(rows.at(i));
    final d = w.departure;
    final regional = d.category == ApiCategory.re || d.category == ApiCategory.rb || d.category == ApiCategory.s;
    if (!d.cancelled && regional) {
      pick = rows.at(i);
      break;
    }
  }
  pick ??= rows.first; // no regional train right now: any rail departure will do
  final picked = tester.widget<DepartureRow>(pick).departure;
  // ignore: avoid_print
  print('ride $n: ${picked.line} → ${picked.destination} (${picked.category})');
  await tester.ensureVisible(pick);
  await tester.tap(pick, warnIfMissed: false);
  await settle(tester);

  // Ausstieg: the usual stop is preselected; confirm.
  await pumpUntilFound(tester, find.byType(StopLine), timeout: const Duration(seconds: 40));
  await tapText(tester, 'Einchecken');

  // Unterwegs: simulate the arrival.
  await tapText(tester, 'Demo: Ankunft +68', timeout: const Duration(seconds: 40));

  // Angekommen: +68 and Fertig.
  await pumpUntilFound(tester, find.textContaining('68', findRichText: true), timeout: const Duration(seconds: 40));
  await tapText(tester, 'Fertig');
  await pumpUntilFound(tester, find.text('Kein Zug. Gut so.'), timeout: const Duration(seconds: 40));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('check-in x3, claim, send, reply', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final demo = DemoState();
    final session = Session(demo: demo, prefs: prefs, apiUrl: apiUrl);
    session.init();
    await tester.pumpWidget(VerspaetomatApp(state: demo, session: session));
    await settle(tester, 1500);

    // 1–2. Three rides so the Servicecenter bundle reaches 4,50 €.
    for (var n = 1; n <= 3; n++) {
      await rideOnce(tester, n);
    }

    // 3. Konto → Antrag.
    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await settle(tester, 800);
    await pumpUntilFound(tester, find.text('bereit'), timeout: const Duration(seconds: 40));
    await tapText(tester, 'Antrag vorbereiten');

    // Step 1: personal data and the recovery code appear on the first claim only.
    await pumpUntilFound(tester, find.byWidgetPredicate((w) => w is TextField || (w is Text && (w.data ?? '').contains('@verspaetomat.de'))), timeout: const Duration(seconds: 40));
    if (find.byType(TextField).evaluate().length >= 4) {
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Johannes Test');
      await tester.enterText(fields.at(1), 'Venloer Straße 123, 50823 Köln');
      await tester.enterText(fields.at(2), 'johannes@example.de');
      await tester.enterText(fields.at(3), 'D-2026-0904-771-2201');
      await tester.pump(const Duration(milliseconds: 200));
      await tapText(tester, 'Speichern');
      try {
        await tapText(tester, 'Ich habe es notiert', timeout: const Duration(seconds: 15));
      } on TestFailure {
        // no recovery code sheet this time
      }
    }
    await pumpUntilFound(tester, find.textContaining('@verspaetomat.de'), timeout: const Duration(seconds: 20));
    await tapText(tester, 'Weiter');

    // Step 2: one ticket image per month covered.
    await pumpUntilFound(tester, find.text('Aus Fotos'), timeout: const Duration(seconds: 20));
    while (find.text('Aus Fotos').evaluate().isNotEmpty) {
      await tapText(tester, 'Aus Fotos');
      await pumpUntilGone(tester, find.text('Lädt hoch …'), timeout: const Duration(seconds: 40));
      await settle(tester, 800);
    }
    await tapText(tester, 'Weiter');

    // Step 3: Zweck.
    await settle(tester, 800);
    await tapText(tester, 'Weiter');

    // Step 4: sign.
    await pumpUntilFound(tester, find.byType(SignaturePad), timeout: const Duration(seconds: 20));
    final pad = find.byType(SignaturePad);
    await tester.drag(pad, const Offset(120, 30));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.drag(pad, const Offset(-60, 40));
    await tester.pump(const Duration(milliseconds: 200));
    await tapText(tester, 'Bestätigen');
    await pumpUntilGone(tester, find.text('Speichert …'), timeout: const Duration(seconds: 40));
    await tapText(tester, 'Weiter');

    // Step 5: send from the relay address with a copy to the private inbox.
    await pumpUntilFound(tester, find.textContaining('BCC'), timeout: const Duration(seconds: 20));
    expect(find.textContaining('@verspaetomat.de'), findsWidgets);
    await tapText(tester, 'Absenden');
    await pumpUntilFound(tester, find.text('Abgeschickt.'), timeout: const Duration(seconds: 40));
    await tapText(tester, 'Zurück zum Konto');

    // 4. eingereicht → simulated reply → bestätigt → Wir.
    await pumpUntilFound(tester, find.text('eingereicht'), timeout: const Duration(seconds: 40));
    await tapText(tester, 'Demo: Antwort der Bahn simulieren');
    await settle(tester, 1500);
    // ignore: avoid_print
    print('after reply: ${visibleTexts()}');
    await pumpUntilFound(tester, find.text('Antwort'), timeout: const Duration(seconds: 40));
    await pumpUntilFound(tester, find.text('bestätigt'), timeout: const Duration(seconds: 40));
    await tester.tap(find.byIcon(Icons.arrow_back).first);
    await settle(tester, 1500);
    // ignore: avoid_print
    print('back on konto: ${visibleTexts()}');
    await pumpUntilFound(tester, find.text('bestätigt'), timeout: const Duration(seconds: 40));

    await tester.tap(find.byIcon(Icons.groups_outlined));
    await settle(tester, 800);
    await pumpUntilFound(tester, find.text('Bestätigt'), timeout: const Duration(seconds: 40));
  }, timeout: const Timeout(Duration(minutes: 15)));
}
