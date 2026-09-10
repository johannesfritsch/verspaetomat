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
import 'package:verspaetomat/screens/ride/welcher_zug_screen.dart';
import 'package:verspaetomat/screens/ride/wohin_screen.dart';
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
    http.Response r;
    try {
      r = await http.post(Uri.parse('$base$path'), headers: _h, body: jsonEncode(body ?? {}));
    } on http.ClientException catch (e) {
      // The debug backend occasionally resets the connection although it applied the request.
      // One retry; a 4xx on the retry then means the first attempt already went through.
      // ignore: avoid_print
      print('POST $path: ${e.message}; retrying once');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      r = await http.post(Uri.parse('$base$path'), headers: _h, body: jsonEncode(body ?? {}));
      if (r.statusCode >= 400 && r.statusCode < 500) {
        // ignore: avoid_print
        print('retry POST $path → ${r.statusCode}: assuming the first attempt was applied');
        return null;
      }
    }
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
  /// Confirms the proposed next leg of the customer's journey, as the phone would (docs/17).
  Future<dynamic> confirm(String id) => _post('/admin/customers/$id/confirm');
  Future<dynamic> journey(String id) => _get('/admin/customers/$id/journey');

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

/// Destination first (docs/17): a predicted destination if the account has one,
/// otherwise the search. Then the itinerary list; [connecting] picks one with a transfer.
/// Returns the picked itinerary, or null when [connecting] found none.
/// [search] goes into the station search; [match] is the substring of the station name to tap
/// (the backend spells "Düsseldorf Hauptbahnhof", the predicted button keeps that name).
Future<ApiItinerary?> chooseJourney(WidgetTester tester, String search, {required String match, bool connecting = false}) async {
  // Bahnsteig, idle. A leftover arrival card from an earlier run is dismissed first.
  await pumpUntilFound(tester, find.byWidgetPredicate((w) => w is Text && (w.data == 'EINCHECKEN' || w.data == 'ANGEKOMMEN')), timeout: const Duration(seconds: 40));
  if (find.text('ANGEKOMMEN').evaluate().isNotEmpty) {
    await tapText(tester, 'Fertig');
  }
  await pumpUntilFound(tester, find.text('EINCHECKEN'), timeout: const Duration(seconds: 40));
  // At a station: the card with the destination buttons and "Anderes Ziel …" / "Wohin? Ziel wählen …".
  await pumpUntilFound(tester, find.byType(OutlinedButton), timeout: const Duration(seconds: 40));
  expect(find.textContaining('Köln', findRichText: true), findsWidgets);
  await settle(tester, 600);
  final predicted = find.byWidgetPredicate((w) => w is DestinationButton && w.destination.stationName.contains(match));
  if (predicted.evaluate().isNotEmpty) {
    // ignore: avoid_print
    print('destination $match: predicted');
    await tester.ensureVisible(predicted.first);
    await tester.tap(predicted.first, warnIfMissed: false);
    await settle(tester);
  } else {
    final other = find.byType(OutlinedButton);
    await tester.ensureVisible(other.first);
    await tester.tap(other.first, warnIfMissed: false);
    await settle(tester);
    // Wohin?: search.
    await pumpUntilFound(tester, find.text('Wohin?'), timeout: const Duration(seconds: 20));
    await tapText(tester, 'Bahnhof suchen');
    await pumpUntilFound(tester, find.byType(TextField), timeout: const Duration(seconds: 20));
    await tester.enterText(find.byType(TextField).first, search);
    // A Text widget only: find.text would also hit the search field's own contents.
    final hit = find.byWidgetPredicate((w) => w is Text && (w.data ?? '').contains(match));
    await pumpUntilFound(tester, hit, timeout: const Duration(seconds: 40));
    await tester.tap(hit.first, warnIfMissed: false);
    await settle(tester);
  }
  // Welcher Zug?: the itineraries.
  await pumpUntilFound(tester, find.text('Welcher Zug?'), timeout: const Duration(seconds: 20));
  await pumpUntilFound(tester, find.byType(ItineraryRow), timeout: const Duration(seconds: 60));
  await settle(tester, 800);
  final rows = find.byType(ItineraryRow);
  Finder? pick;
  for (var i = 0; i < rows.evaluate().length; i++) {
    final it = tester.widget<ItineraryRow>(rows.at(i)).itinerary;
    final ok = connecting ? it.transfers >= 1 : it.direct;
    if (ok && !it.first.cancelled) {
      pick = rows.at(i);
      break;
    }
  }
  if (pick == null) {
    if (connecting) return null;
    pick = rows.first;
  }
  final picked = tester.widget<ItineraryRow>(pick).itinerary;
  // ignore: avoid_print
  print('journey → $match: ${picked.legs.map((l) => l.line).join(' + ')} (${picked.transfers} transfers)');
  await tester.ensureVisible(pick);
  await tester.tap(pick, warnIfMissed: false);
  await settle(tester);
  return picked;
}

/// One direct journey: check in through the UI, then let the Stellwerk run the world.
Future<String> rideOnce(WidgetTester tester, Stellwerk sw, int n, {String? knownCustomer}) async {
  final picked = (await chooseJourney(tester, 'Düsseldorf Hbf', match: 'Düsseldorf H'))!;
  final line = picked.first.line;

  // Unterwegs shows the line; no simulate buttons in local mode.
  await pumpUntilFound(tester, find.textContaining(line, findRichText: true), timeout: const Duration(seconds: 40));
  expect(find.textContaining('Demo:'), findsNothing);

  // Stellwerk: who is riding? Then +68 and fast-forward to the exit stop.
  final customer = knownCustomer ?? await sw.ridingCustomer(line: line);
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
  // The reveal shows the journey delay: the live delay the train already had plus our 68.
  final minutesLine = find.byWidgetPredicate((w) {
    if (w is! Text || w.data == null) return false;
    final m = RegExp(r'^(\d+) Minuten').firstMatch(w.data!);
    return m != null && int.parse(m.group(1)!) >= 68;
  });
  await pumpUntilFound(tester, minutesLine, timeout: const Duration(seconds: 20));
  await tapText(tester, 'Fertig');
  await pumpUntilFound(tester, find.text('EINCHECKEN'), timeout: const Duration(seconds: 40));
  return customer;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('journey x3 (destination first) via Stellwerk, claim, send, reply', (tester) async {
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
      await pumpUntilFound(tester, find.byWidgetPredicate((w) => w is Text && (w.data == 'EINCHECKEN' || w.data == 'ANGEKOMMEN' || w.data == 'UNTERWEGS')), timeout: const Duration(seconds: 40));
      customer = (await sw.customers()).first['id'] as String;
      await sw.reset(customer);
      // The reset arrives over the event stream; the platform is empty again.
      await pumpUntilFound(tester, find.text('EINCHECKEN'), timeout: const Duration(seconds: 20));
      // The test phone has no GPS (NO_LOCATION): Stellwerk puts the customer at Köln Hbf.
      await sw.locate(customer, 'Köln Hbf');
      // ignore: avoid_print
      print('customer $customer reset');

      // 1–2. Three rides so the Servicecenter bundle reaches 4,50 €.
      for (var n = 1; n <= 3; n++) {
        customer = await rideOnce(tester, sw, n, knownCustomer: customer);
      }

      // 3. Anträge → Antrag (the receipt icon is the Anträge tab).
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
      await tapText(tester, 'Zu den Anträgen');

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

  testWidgets('journey with a connection: transfer, confirm, arrive', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final demo = DemoState();
    final session = Session(demo: demo, prefs: prefs, apiUrl: apiUrl, tokens: TokenStore(namespace: 'e2e.'));
    session.init();
    await tester.pumpWidget(VerspaetomatApp(state: demo, session: session));
    await settle(tester, 1500);

    final sw = Stellwerk(apiUrl);
    String? customer;
    try {
      await pumpUntilFound(tester, find.byWidgetPredicate((w) => w is Text && (w.data == 'EINCHECKEN' || w.data == 'ANGEKOMMEN' || w.data == 'UNTERWEGS')), timeout: const Duration(seconds: 40));
      customer = (await sw.customers()).first['id'] as String;
      await sw.reset(customer);
      await pumpUntilFound(tester, find.text('EINCHECKEN'), timeout: const Duration(seconds: 20));
      await sw.locate(customer, 'Köln Hbf');

      // Köln → Arnsberg always needs a change (Dortmund or Schwerte). No connecting itinerary right now: nothing to test.
      final picked = await chooseJourney(tester, 'Arnsberg', match: 'Arnsberg, Bahnhof', connecting: true);
      if (picked == null) {
        // ignore: avoid_print
        print('no connecting itinerary offered right now; connection scenario skipped');
        return;
      }
      final leg1 = picked.legs.first.line;
      await pumpUntilFound(tester, find.textContaining(leg1, findRichText: true), timeout: const Duration(seconds: 40));

      // Leg 1 ends: the journey goes into transfer, the confirmation card appears.
      await sw.fastForward(customer);
      await pumpUntilFound(tester, find.text('Ich bin drin'), timeout: const Duration(seconds: 60));
      final j1 = await sw.journey(customer);
      expect(j1['status'] ?? j1['journey']?['status'], 'transfer');

      // Stellwerk confirms the proposed next leg as the phone would; the app follows.
      await sw.confirm(customer);
      await pumpUntilFound(tester, find.byWidgetPredicate((w) => w is Text && (w.data == 'UNTERWEGS' || (w.data ?? '').startsWith('Stand '))), timeout: const Duration(seconds: 60));
      await pumpUntilGone(tester, find.text('Ich bin drin'), timeout: const Duration(seconds: 30));

      // Leg 2 ends at the destination: the arrival with the journey delay.
      await sw.delay(customer, 68);
      await sw.fastForward(customer);
      await pumpUntilFound(tester, find.byWidgetPredicate((w) => w is Text && (w.data == 'Fertig' || w.data == 'ANGEKOMMEN')), timeout: const Duration(seconds: 60));
      if (find.text('ANGEKOMMEN').evaluate().isNotEmpty && find.text('Fertig').evaluate().isEmpty) {
        await tapText(tester, 'Ansehen');
      }
      await pumpUntilFound(tester, find.textContaining('Arnsberg'), timeout: const Duration(seconds: 20));
      final minutesLine = find.byWidgetPredicate((w) => w is Text && RegExp(r'^\d+ Minuten').hasMatch(w.data ?? ''));
      await pumpUntilFound(tester, minutesLine, timeout: const Duration(seconds: 20));
      final j2 = await sw.journey(customer);
      final status = j2['status'] ?? j2['journey']?['status'];
      expect(status, 'arrived');
      await tapText(tester, 'Fertig');
    } finally {
      if (customer != null) {
        try {
          await sw.reset(customer);
        } catch (_) {}
      }
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
