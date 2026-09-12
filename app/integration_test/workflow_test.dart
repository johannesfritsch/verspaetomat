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
import 'package:verspaetomat/mock/mock_data.dart' show Mock;
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
    // The debug backend occasionally resets the connection on the response although it applied
    // the request (the server log shows the work done, no panic). So: retry a few times, and a
    // 4xx after such a reset means the first attempt already went through.
    http.Response? r;
    var reset = false;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        r = await http.post(Uri.parse('$base$path'), headers: _h, body: jsonEncode(body ?? {}));
        break;
      } on http.ClientException catch (e) {
        reset = true;
        // ignore: avoid_print
        print('POST $path: ${e.message} (attempt $attempt of 3)');
        if (attempt == 3) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
    if (reset && r!.statusCode >= 400 && r.statusCode < 500) {
      // ignore: avoid_print
      print('retry POST $path → ${r.statusCode}: the reset attempt had already been applied');
      return null;
    }
    if (r!.statusCode >= 300) throw StateError('POST $path → ${r.statusCode} ${r.body}');
    return r.body.isEmpty ? null : jsonDecode(r.body);
  }

  Future<List<Map<String, dynamic>>> customers() async => (await _get('/admin/customers') as List).cast<Map<String, dynamic>>();

  Future<void> delay(String id, int minutes) => _post('/admin/customers/$id/delay', {'minutes': minutes});
  Future<dynamic> fastForward(String id) => _post('/admin/customers/$id/ff');
  Future<void> poll() => _post('/admin/poll');
  Future<void> reply(String id, String outcome) => _post('/admin/customers/$id/reply', {'outcome': outcome});
  Future<void> reset(String id) => _post('/admin/customers/$id/reset');
  /// Every ride of a run uses the same trip; the shift a fast-forward leaves on it would make
  /// the next check-in arrive on the spot. Cleared before each check-in.
  Future<void> clearOverrides() async {
    final r = await http.delete(Uri.parse('$base/admin/overrides'), headers: _h);
    if (r.statusCode >= 300) throw StateError('DELETE /admin/overrides → ${r.statusCode} ${r.body}');
  }
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

/// Home in one of its idle states: the check-in card ('EINCHECKEN'), the arrival card
/// ('ANGEKOMMEN'); or the ride under way as the bar above the nav (docs/19).
final Finder homeOrRide = find.byWidgetPredicate(
  (w) => (w is Text && (w.data == 'EINCHECKEN' || w.data == 'ANGEKOMMEN')) || w.key == const Key('ride-bar'),
);

/// Home idle: one section, one card, one button — with or without a position (docs/30).
final Finder homeIdle = find.byWidgetPredicate((w) => w is Text && w.data == 'EINCHECKEN');

final Finder rideBar = find.byKey(const Key('ride-bar'));
final Finder rideSheet = find.byKey(const Key('ride-sheet-handle'));

/// Taps [text] inside the open ride sheet (Home behind it may show the same word, e.g. the
/// arrival card's "Fertig"); scrolls the sheet until the widget is on screen first.
Future<void> tapInSheet(WidgetTester tester, String text) async {
  final sheet = find.byKey(const Key('ride-sheet'));
  final f = find.descendant(of: sheet, matching: find.text(text));
  await pumpUntilFound(tester, f, timeout: const Duration(seconds: 30));
  final scrollable = find.descendant(of: sheet, matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(f.first, 200, scrollable: scrollable);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(f.first, warnIfMissed: false);
  await settle(tester);
}

/// Pulls the ride sheet down (the header's chevron) so the bar shows, then taps the bar to
/// open it again: the docs/19 path the test exercises after every check-in.
Future<void> reopenSheetFromBar(WidgetTester tester) async {
  await pumpUntilFound(tester, rideSheet, timeout: const Duration(seconds: 20));
  await tapIcon(tester, Icons.expand_more);
  await pumpUntilFound(tester, rideBar, timeout: const Duration(seconds: 20));
  await pumpUntilFound(tester, find.textContaining('nach '), timeout: const Duration(seconds: 20));
  await tester.tap(rideBar);
  await pumpUntilFound(tester, rideSheet, timeout: const Duration(seconds: 20));
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

/// The whole check-in, through the three sheets it always runs now (docs/24 §1, docs/30):
/// Von wo? · Wohin? · Welcher Zug?. Home proposes no stations any more — it is one button —
/// so both entry points land on the same first sheet, and [viaSquare] only decides which
/// button the test presses.
///
/// The destination is a predicted one if the account has any, otherwise the search.
/// [search] goes into the station search; [match] is the substring of the station name to tap
/// (the backend spells "Düsseldorf Hauptbahnhof", the predicted button keeps that name).
/// [connecting] picks an itinerary with a transfer; the return value is the picked itinerary,
/// or null when [connecting] found none.
Future<ApiItinerary?> chooseJourney(WidgetTester tester, String search, {required String match, bool connecting = false, bool viaSquare = false}) async {
  // Bahnsteig, idle. A leftover arrival card from an earlier run is dismissed first.
  await pumpUntilFound(tester, find.byWidgetPredicate((w) => w is Text && (w.data == 'EINCHECKEN' || w.data == 'ANGEKOMMEN')), timeout: const Duration(seconds: 40));
  if (find.text('ANGEKOMMEN').evaluate().isNotEmpty) {
    await tapText(tester, 'Fertig');
  }
  await pumpUntilFound(tester, find.text('EINCHECKEN'), timeout: const Duration(seconds: 40));

  // Step 1: the square in the nav, or the button on Home. Both open "Von wo?", which asks
  // with the detected station preselected. One tap moves on.
  await tester.tap(find.byKey(Key(viaSquare ? 'nav-checkin' : 'einchecken-cta')), warnIfMissed: false);
  await pumpUntilFound(tester, find.text('Von wo?'), timeout: const Duration(seconds: 30));
  await pumpUntilFound(tester, find.byKey(const Key('von-detected')), timeout: const Duration(seconds: 30));
  await tester.tap(find.byKey(const Key('von-detected')), warnIfMissed: false);

  // Step 2: the destinations from history, or the search behind "Bahnhof suchen".
  await pumpUntilFound(tester, find.text('Wohin?'), timeout: const Duration(seconds: 30));
  await settle(tester, 600);
  final predicted = find.byWidgetPredicate((w) => w is DestinationButton && w.destination.stationName.contains(match));
  if (predicted.evaluate().isNotEmpty) {
    // ignore: avoid_print
    print('destination $match: from history');
    await tester.ensureVisible(predicted.last);
    await tester.tap(predicted.last, warnIfMissed: false);
    await settle(tester);
  } else {
    // No history yet (a fresh E2E customer): the search sheet's own field, found by its hint
    // so the finder cannot wander off to another TextField in the tree.
    final searchField = find.byWidgetPredicate(
      (w) => w is TextField && (w.decoration?.hintText ?? '').startsWith('Köln Hbf'),
    );
    await tapText(tester, 'Bahnhof suchen');
    await pumpUntilFound(tester, searchField, timeout: const Duration(seconds: 30));
    await tester.ensureVisible(searchField.last);
    await tester.enterText(searchField.last, search);
    // A Text widget only: find.text would also hit the field's own contents.
    final hit = find.byWidgetPredicate((w) => w is Text && (w.data ?? '').contains(match));
    await pumpUntilFound(tester, hit, timeout: const Duration(seconds: 40));
    await tester.ensureVisible(hit.last);
    await tester.tap(hit.last, warnIfMissed: false);
    await settle(tester);
  }
  // Welcher Zug?: the itineraries.
  await pumpUntilFound(tester, find.text('Welcher Zug?'), timeout: const Duration(seconds: 20));
  await pumpUntilFound(tester, find.byType(ItineraryRow), timeout: const Duration(seconds: 60));
  await settle(tester, 800);
  final rows = find.byType(ItineraryRow);
  Finder? pick;
  // Prefer trains whose operator the claims directory knows: an unknown operator becomes its
  // own desk ("Unbekannt") whose claim flow has no ticket step, which the test relies on.
  // A connecting journey with exactly one transfer first: the scenario confirms one leg and
  // expects the arrival after the next; late at night Transitous sometimes only offers two.
  // The list holds the last half hour as well now (issue #9), and a train that already left is a
  // real check-in but a poor test subject: the scenario fast-forwards to the exit stop from the
  // entry stop. So a departure still to come is preferred, and a past one is only a last resort.
  bool stillToCome(ApiItinerary it) {
    final d = it.first.liveDeparture ?? it.plannedDeparture;
    return d == null || d.isAfter(DateTime.now());
  }

  for (final (knownOnly, oneTransfer, futureOnly) in [
    (true, true, true),
    (false, true, true),
    (true, false, true),
    (false, false, true),
    (true, false, false),
    (false, false, false),
  ]) {
    for (var i = 0; i < rows.evaluate().length && pick == null; i++) {
      final it = tester.widget<ItineraryRow>(rows.at(i)).itinerary;
      final ok = connecting ? (oneTransfer ? it.transfers == 1 : it.transfers >= 1) : it.direct;
      final known = it.legs.every((l) => Mock.desks.containsKey(l.operator) || l.operator.startsWith('DB '));
      if (ok && !it.first.cancelled && (known || !knownOnly) && (stillToCome(it) || !futureOnly)) pick = rows.at(i);
    }
    if (pick != null) break;
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
  await sw.clearOverrides();
  final picked = (await chooseJourney(tester, 'Düsseldorf Hbf', match: 'Düsseldorf H', viaSquare: true))!;
  final line = picked.first.line;

  // The check-in opens the ride sheet on Home (docs/19); it shows the line, no simulate
  // buttons in local mode. Pull it down, find the bar, tap the bar: the sheet is back.
  await pumpUntilFound(tester, find.textContaining(line, findRichText: true), timeout: const Duration(seconds: 40));
  expect(find.textContaining('Demo:'), findsNothing);
  await reopenSheetFromBar(tester);

  // Stellwerk: who is riding? Then +68 and fast-forward to the exit stop.
  final customer = knownCustomer ?? await sw.ridingCustomer(line: line);
  await sw.delay(customer, 68);
  await sw.fastForward(customer);

  // The app polls every 20 s; the open sheet switches to the reveal on its own.
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
  await tapInSheet(tester, 'Fertig');
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
      await pumpUntilFound(tester, homeOrRide, timeout: const Duration(seconds: 40));
      customer = (await sw.customers()).first['id'] as String;
      await sw.reset(customer);
      // The reset arrives over the event stream; the platform is empty again.
      await pumpUntilFound(tester, homeIdle, timeout: const Duration(seconds: 20));
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
      await pumpUntilFound(tester, find.textContaining('Bereit ·'), timeout: const Duration(seconds: 40));
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
      // The claim card says its status in words (docs/18).
      await pumpUntilFound(tester, find.textContaining('Eingereicht ·'), timeout: const Duration(seconds: 40));
      expect(find.textContaining('Demo:'), findsNothing);
      await sw.reply(customer!, 'accepted');

      // Refresh the ledger: the refresh icon if there is one, else leave and come back.
      if (find.byIcon(Icons.refresh).evaluate().isNotEmpty) {
        await tapIcon(tester, Icons.refresh);
      } else {
        await tapIcon(tester, Icons.groups_outlined);
        await tapIcon(tester, Icons.receipt_long_outlined);
      }
      await pumpUntilFound(tester, find.textContaining('Bestätigt ·'), timeout: const Duration(seconds: 40));

      // The confirmed euros belong to Ich (docs/20 §5).
      await tapIcon(tester, Icons.person_outline);
      await pumpUntilFound(tester, find.textContaining('Bestätigt, durch dich'), timeout: const Duration(seconds: 40));
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
      await pumpUntilFound(tester, homeOrRide, timeout: const Duration(seconds: 40));
      customer = (await sw.customers()).first['id'] as String;
      await sw.reset(customer);
      await pumpUntilFound(tester, homeIdle, timeout: const Duration(seconds: 20));
      await sw.locate(customer, 'Köln Hbf');
      await sw.clearOverrides();

      // Köln → Arnsberg always needs a change (Dortmund or Schwerte). No connecting itinerary right now: nothing to test.
      final picked = await chooseJourney(tester, 'Arnsberg', match: 'Arnsberg, Bahnhof', connecting: true);
      if (picked == null) {
        // ignore: avoid_print
        print('no connecting itinerary offered right now; connection scenario skipped');
        return;
      }
      final leg1 = picked.legs.first.line;
      await pumpUntilFound(tester, find.textContaining(leg1, findRichText: true), timeout: const Duration(seconds: 40));
      // The sheet opened with the check-in; pull it down so the bar carries the ride (docs/19).
      await pumpUntilFound(tester, rideSheet, timeout: const Duration(seconds: 20));
      await tapIcon(tester, Icons.expand_more);
      await pumpUntilFound(tester, rideBar, timeout: const Duration(seconds: 20));

      // Leg 1 ends: the journey goes into transfer; the bar (or the sheet's card) offers "Ich bin drin".
      await sw.fastForward(customer);
      await pumpUntilFound(tester, find.text('Ich bin drin'), timeout: const Duration(seconds: 60));
      final j1 = await sw.journey(customer);
      expect(j1['status'] ?? j1['journey']?['status'], 'transfer');

      // Confirm through the app, whichever "Ich bin drin" is on screen; the journey rides again.
      await tapText(tester, 'Ich bin drin');
      await pumpUntilGone(tester, find.text('Ich bin drin'), timeout: const Duration(seconds: 30));
      await pumpUntilFound(tester, find.textContaining('nach '), timeout: const Duration(seconds: 60));
      final j1b = await sw.journey(customer);
      expect(j1b['status'] ?? j1b['journey']?['status'], 'riding');
      // Open the sheet from the bar: the riding view with its "Stand" line.
      await tester.tap(rideBar);
      await pumpUntilFound(tester, find.byWidgetPredicate((w) => w is Text && (w.data ?? '').startsWith('Stand ')), timeout: const Duration(seconds: 30));

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
      await tapInSheet(tester, 'Fertig');
      await pumpUntilFound(tester, homeIdle, timeout: const Duration(seconds: 40));
    } finally {
      if (customer != null) {
        try {
          await sw.reset(customer);
        } catch (_) {}
      }
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
