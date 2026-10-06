import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:verspaetomat/repo/app_repository.dart';
import 'package:verspaetomat/repo/repo_scope.dart';
import 'package:verspaetomat/screens/ride/unterwegs_screen.dart' show RideSheetBody;
import 'package:verspaetomat/screens/ride/welcher_zug_screen.dart' show WelcherZugList;
import 'package:verspaetomat/state/demo_state.dart';
import 'package:verspaetomat/state/ride_monitor.dart';

/// #82: after a missed connection the sheet offered exactly one train. „Ich bin im Zug"
/// confirmed that one, „Leider verpasst" swapped it for another, and the way to pick a train
/// yourself — „Welcher Zug?" for the journey that is running — was only wired to a Weiterfahrt.
/// These pin the way in after a missed connection, that it opens the picker for *this* journey
/// rather than a new check-in, and that it is offered only where the journey has a cap: at an
/// ordinary change a later train of one's own choosing would count in full, and whether it
/// should is a rule nobody has decided yet (docs/17).
void main() {
  final now = DateTime.now().toUtc();
  String at(int minutes) => now.add(Duration(minutes: minutes)).toIso8601String();

  /// Memmingen, the RE 96 in. [missed]: the RE 75 at 09:04 is gone and the server proposes the
  /// RS 7 to Ulm, with the cap from that moment unless [cap] is false. Otherwise the RE 75 is
  /// still there: an ordinary change.
  ApiJourneyLive atMemmingen({required bool missed, bool cap = true}) {
    final next = {
      'trip_id': missed ? 'rs7' : 're75-0904',
      'line': missed ? 'RS 7' : 'RE 75',
      'headsign': 'Ulm Hbf',
      'category': 're',
      'from_station_id': 'de-DELFI_de:09764:3100:1:1',
      'from_station_name': 'Memmingen',
      'to_station_id': 'de-DELFI_de:08421:1008_G',
      'to_station_name': 'Ulm Hbf',
      'planned_departure': at(20),
      'planned_arrival': at(71),
      'platform': '51',
      'cancelled': false,
      'delay_min': 0,
      'replanned': missed && cap,
      'reason': missed ? 'verpasst' : null,
    };
    return ApiJourneyLive.fromJson({
      'journey': {
        'id': 'j-81',
        'status': 'transfer',
        'origin_station_id': 'vs:1',
        'origin_station_name': 'Lindau-Reutin',
        'destination_station_id': 'vs:3',
        'destination_station_name': 'Saarbrücken Hbf',
        'planned_departure': at(-60),
        'planned_arrival': at(230),
        'missed_connection': missed,
        'current_leg': 1,
        'legs': [
          {
            'trip_id': 're96', 'line': 'RE 96', 'leg_no': 1, 'status': 'arrived',
            'from_station_id': 'vs:1', 'from_station_name': 'Lindau-Reutin', 'to_station_id': 'vs:2', 'to_station_name': 'Memmingen',
            'planned_departure': at(-60), 'planned_arrival': at(-5),
          },
          {...next, 'leg_no': 2, 'status': 'planned'},
        ],
        'next_leg': next,
        'transfer_station_name': 'Memmingen',
        'transfer_reason': 'umstieg',
        'earliest_onward_arrival': missed && cap ? at(300) : null,
        'created_at': at(-60),
      },
      'next_leg': next,
    });
  }

  Future<RideMonitor> pump(WidgetTester tester, ApiJourneyLive live) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final session = Session(demo: DemoState(), prefs: prefs, apiUrl: 'http://127.0.0.1:9');
    final monitor = RideMonitor(session)..journey = live;
    await tester.pumpWidget(RepoScope(
      session: session,
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: RideSheetBody(monitor: monitor)))),
    ));
    return monitor;
  }

  Future<void> openAbortSheet(WidgetTester tester) async {
    final end = find.text('Anders beenden …');
    await tester.ensureVisible(end);
    await tester.tap(end);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('a missed connection offers another train, and opens the picker for this journey', (tester) async {
    await pump(tester, atMemmingen(missed: true));

    final other = find.byKey(const Key('transfer-other-train'));
    expect(other, findsOneWidget);
    expect(find.text('Anderen Zug wählen'), findsOneWidget);
    // „Leider verpasst" names the train it is about: the one on the card, not the planned one.
    expect(find.text('RS 7 verpasst'), findsOneWidget);
    expect(find.text('Leider verpasst'), findsNothing);

    await tester.ensureVisible(other);
    await tester.tap(other);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final list = tester.widget<WelcherZugList>(find.byType(WelcherZugList));
    expect(list.continueJourneyId, 'j-81', reason: 'the next leg of this journey, not a new check-in');
    expect(list.fromStationName, 'Memmingen');
    expect(list.fromStationId, 'de-DELFI_de:09764:3100:1:1', reason: 'from where the proposed train leaves');
    expect(list.toStationId, 'vs:3');
    expect(list.toStationName, 'Saarbrücken Hbf');
    // The cap from the interruption comes along, so a later train says what it costs.
    expect(list.earliestOnwardArrival, isNotNull);
    // Not „Weiterfahrt": nobody gave up on a train here.
    expect(find.text('ANSCHLUSS VERPASST'), findsOneWidget);
    expect(find.text('WEITERFAHRT'), findsNothing);
  });

  testWidgets('an ordinary change keeps its answers: no other train', (tester) async {
    await pump(tester, atMemmingen(missed: false));

    expect(find.byKey(const Key('transfer-other-train')), findsNothing);
    expect(find.text('Anderen Zug wählen'), findsNothing);
    expect(find.byKey(const Key('transfer-in-train')), findsOneWidget);
    expect(find.text('Leider verpasst'), findsOneWidget, reason: 'as before at an ordinary change');
    expect(find.byKey(const Key('transfer-end')), findsOneWidget);
  });

  testWidgets('a missed connection without a cap offers no other train either', (tester) async {
    // The server found no way on and kept the planned train: nothing caps a later one.
    await pump(tester, atMemmingen(missed: true, cap: false));

    expect(find.byKey(const Key('transfer-other-train')), findsNothing);
  });

  testWidgets('„Anders beenden" after a missed connection points to another train instead of „Ich fahre weiter"', (tester) async {
    // „Ich fahre weiter" re-plans a journey on a train; between two the server refuses it, and
    // the sheet said „Das ging nicht".
    await pump(tester, atMemmingen(missed: true));
    await openAbortSheet(tester);

    expect(find.byKey(const Key('abort-weiterfahrt')), findsNothing);
    expect(find.text('Ich fahre weiter'), findsNothing);
    final other = find.byKey(const Key('abort-anderer-zug'));
    expect(other, findsOneWidget);

    await tester.tap(other);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.widget<WelcherZugList>(find.byType(WelcherZugList)).continueJourneyId, 'j-81');
  });

  testWidgets('„Anders beenden" at an ordinary change offers neither „Ich fahre weiter" nor another train', (tester) async {
    await pump(tester, atMemmingen(missed: false));
    await openAbortSheet(tester);

    expect(find.byKey(const Key('abort-weiterfahrt')), findsNothing, reason: 'it could only fail here');
    expect(find.byKey(const Key('abort-anderer-zug')), findsNothing, reason: 'no cap at an ordinary change');
    expect(find.byKey(const Key('abort-aufgegeben')), findsOneWidget);
    expect(find.byKey(const Key('abort-nicht-gefahren')), findsOneWidget);
  });
}
