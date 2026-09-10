// End-to-end walk of the core workflows against the local backend.
//
// The world (delays, arrivals, the railway's reply) is driven through the
// backend's Stellwerk admin API, exactly as a person would with the CLI.
// The app itself carries no simulate buttons in local mode.
//
// flutter test integration_test/workflow_test.dart -d <simulator udid> \
//   --dart-define=API_URL=http://127.0.0.1:8081 --dart-define=BACKEND=local \
//   --dart-define=NO_LOCATION=1 --dart-define=E2E=true --dart-define=INITIAL_ROUTE=/bahnsteig \
//   --dart-define=ADMIN_TOKEN=stellwerk
//
// Needs real departures at Köln Hbf, so it only passes while trains run.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:verspaetomat/api/models.dart';
import 'package:verspaetomat/main.dart';
import 'package:verspaetomat/api/token_store.dart';
import 'package:verspaetomat/repo/repo_scope.dart';
import 'package:verspaetomat/screens/claims/claims_widgets.dart';
import 'package:verspaetomat/screens/ride/ride_widgets.dart';
import 'package:verspaetomat/state/demo_state.dart';

const adminToken = String.fromEnvironment('ADMIN_TOKEN', defaultValue: 'stellwerk');

// ---------------------------------------------------------------------------
// Stellwerk: the admin API, as the CLI uses it.
// ---------------------------------------------------------------------------

class Stellwerk {
  Stellwerk(this.base);
  final String base;

  Map<String, String> get _h => {'x-admin-token': adminToken, 'content-type': 'application/json'};

  Future<dynamic> _get(String path) async {
    final r = await http.get(Uri.parse('$base$path'), headers: _h);
    if (r.statusCode >= 300) throw StateError('GET $path → ${r.statusCode} ${r.body}');
    return jsonDecode(r.body);
  }

  Future<dynamic> _post(String path, [Map<String, dynamic>? body]) async {
    final r = await http.post(Uri.parse('$base$path'), headers: _h, body: jsonEncode(body ?? {}));
    if (r.statusCode >= 300) throw StateError('POST $path → ${r.statusCode} ${r.body}');
    return r.body.isEmpty ? null : jsonDecode(r.body);
  }

  Future<List<Map<String, dynamic>>> customers() async => (await _get('/admin/customers') as List).cast<Map<String, dynamic>>();

  Future<void> delay(String id, int minutes) => _post('/admin/customers/$id/delay', {'minutes': minutes});
  Future<dynamic> fastForward(String id) => _post('/admin/customers/$id/ff');
  Future<void> poll() => _post('/admin/poll');
  Future<void> reply(String id, String outcome) => _post('/admin/customers/$id/reply', {'outcome': outcome});
  Future<void> reset(String id) => _post('/admin/customers/$id/reset');
  Future<void> locate(String id, String station) => _post('/admin/customers/$id/locate', {'station': station});

  /// The customer that is riding `line` right now. Polls for up to [timeout].
  Future<String> ridingCustomer({String? line, Set<String> exclude = const {}, Duration timeout = const Duration(seconds: 30)}) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      final list = await customers();
      final riding = list.where((c) => c['riding'] == true && !exclude.contains(c['id'])).toList();
      final hit = riding.where((c) => line == null || (c['ride']?['line'] ?? '') == line).firstOrNull ?? riding.firstOrNull;
      if (hit != null) return hit['id'] as String;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw StateError('no riding customer within $timeout (line: $line)');
  }
}

// ---------------------------------------------------------------------------
// Pumping helpers. The app never "settles" (animated clock, polling timers).
// ---------------------------------------------------------------------------

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

Future<void> tapIcon(WidgetTester tester, IconData icon) async {
  final f = find.byIcon(icon);
  await pumpUntilFound(tester, f, timeout: const Duration(seconds: 20));
  await tester.tap(f.first, warnIfMissed: false);
  await settle(tester, 800);
}

// ---------------------------------------------------------------------------
// One ride: check in through the UI, then let the Stellwerk run the world.
// ---------------------------------------------------------------------------

Future<String> rideOnce(WidgetTester tester, Stellwerk sw, int n, {String? knownCustomer}) async {
  // Bahnsteig, idle. A leftover arrival card from an earlier run is dismissed first.
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
  // Prefer a train whose operator files at the Servicecenter, so three rides bundle at one desk.
  for (final requireDesk in [true, false]) {
    for (var i = 0; i < rows.evaluate().length; i++) {
      final d = tester.widget<DepartureRow>(rows.at(i)).departure;
      final regional = d.category == ApiCategory.re || d.category == ApiCategory.rb || d.category == ApiCategory.s;
      final deskOk = !requireDesk || d.desk == 'Servicecenter Fahrgastrechte';
      if (!d.cancelled && regional && deskOk) {
        pick = rows.at(i);
        break;
      }
    }
    if (pick != null) break;
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

  // Unterwegs shows the line; no simulate buttons in local mode.
  await pumpUntilFound(tester, find.textContaining(picked.line, findRichText: true), timeout: const Duration(seconds: 40));
  expect(find.textContaining('Demo:'), findsNothing);

  // Stellwerk: who is riding? Then +68 and fast-forward to the exit stop.
  final customer = knownCustomer ?? await sw.ridingCustomer(line: picked.line);
  await sw.delay(customer, 68);
  await sw.fastForward(customer);

  // The app polls every 20 s and routes to the reveal on its own.
  await pumpUntilFound(
    tester,
    find.byWidgetPredicate((w) => w is Text && (w.data == 'Fertig' || w.data == 'ANGEKOMMEN')),
    timeout: const Duration(seconds: 60),
  );
  if (find.text('ANGEKOMMEN').evaluate().isNotEmpty && find.text('Fertig').evaluate().isEmpty) {
    await tapText(tester, 'Ansehen');
  }
  // The reveal shows the final delay: the live delay the train already had plus our 68.
  final minutesLine = find.byWidgetPredicate((w) {
    if (w is! Text || w.data == null) return false;
    final m = RegExp(r'^(\d+) Minuten').firstMatch(w.data!);
    return m != null && int.parse(m.group(1)!) >= 68;
  });
  await pumpUntilFound(tester, minutesLine, timeout: const Duration(seconds: 20));
  await tapText(tester, 'Fertig');
  await pumpUntilFound(tester, find.text('Kein Zug. Gut so.'), timeout: const Duration(seconds: 40));
  return customer;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('check-in x3 via Stellwerk, claim, send, reply', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final demo = DemoState();
    // Own keychain slot: the test gets its own customer and never resets the one a person uses on this device.
    final session = Session(demo: demo, prefs: prefs, apiUrl: apiUrl, tokens: TokenStore(namespace: 'e2e.'));
    session.init();
    await tester.pumpWidget(VerspaetomatApp(state: demo, session: session));
    await settle(tester, 1500);

    final sw = Stellwerk(apiUrl);
    String? customer;
    try {
      // 0. The app has booted and called /v1/me, so its customer is the most recently seen one.
      //    Start from a clean slate: earlier runs may have left claims (5 sends per day) and rides.
      await pumpUntilFound(tester, find.byWidgetPredicate((w) => w is Text && (w.data == 'Kein Zug. Gut so.' || w.data == 'ANGEKOMMEN' || w.data == 'UNTERWEGS')), timeout: const Duration(seconds: 40));
      customer = (await sw.customers()).first['id'] as String;
      await sw.reset(customer);
      // The reset arrives over the event stream; the platform is empty again.
      await pumpUntilFound(tester, find.text('Kein Zug. Gut so.'), timeout: const Duration(seconds: 20));
      // The test phone has no GPS (NO_LOCATION): Stellwerk puts the customer at Köln Hbf.
      await sw.locate(customer, 'Köln Hbf');
      // ignore: avoid_print
      print('customer $customer reset');

      // 1–2. Three rides so the Servicecenter bundle reaches 4,50 €.
      for (var n = 1; n <= 3; n++) {
        customer = await rideOnce(tester, sw, n, knownCustomer: customer);
      }

      // 3. Konto → Antrag.
      await tapIcon(tester, Icons.receipt_long_outlined);
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
      await tester.ensureVisible(pad);
      await tester.pump(const Duration(milliseconds: 300));
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

      // 4. eingereicht → the railway answers (Stellwerk) → bestätigt → Wir.
      // Rows no longer carry a status chip; the section label does (uppercased by VSection).
      await pumpUntilFound(tester, find.text('EINGEREICHT'), timeout: const Duration(seconds: 40));
      expect(find.textContaining('Demo:'), findsNothing);
      await sw.reply(customer!, 'accepted');

      // Refresh the ledger: the refresh icon if there is one, else leave and come back.
      if (find.byIcon(Icons.refresh).evaluate().isNotEmpty) {
        await tapIcon(tester, Icons.refresh);
      } else {
        await tapIcon(tester, Icons.groups_outlined);
        await tapIcon(tester, Icons.receipt_long_outlined);
      }
      await pumpUntilFound(tester, find.text('BESTÄTIGT'), timeout: const Duration(seconds: 40));

      await tapIcon(tester, Icons.groups_outlined);
      await pumpUntilFound(tester, find.text('Bestätigt'), timeout: const Duration(seconds: 40));
    } finally {
      // Leave the customer clean for the next run.
      if (customer != null) {
        try {
          await sw.reset(customer);
        } catch (_) {}
      }
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
