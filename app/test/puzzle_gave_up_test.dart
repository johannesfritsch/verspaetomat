import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:verspaetomat/mock/mock_data.dart';
import 'package:verspaetomat/repo/mock_repository.dart';
import 'package:verspaetomat/repo/repo_scope.dart';
import 'package:verspaetomat/screens/ride/unterwegs_screen.dart' show showGaveUpSheet;
import 'package:verspaetomat/state/demo_state.dart';

/// docs/51 §3: giving up earns a piece, because the waiting happened — and a piece nobody sees
/// was not given. The „Aufgegeben" sheet shows it the way an arrival does.
void main() {
  testWidgets('a given-up journey brings its piece onto the sheet', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final demo = DemoState();
    final session = Session(demo: demo, prefs: await SharedPreferences.getInstance(), apiUrl: '');
    final repo = MockRepository(demo);
    final d = Mock.allDepartures.first;
    demo.checkIn(departure: d, exitStop: d.stops.last, fromStation: d.stops.first.name);
    final done = await repo.finishJourney(demo.journey!.id, arrived: false, reason: 'aufgegeben');
    expect(done.piece, isNotNull, reason: 'Demo awards on aufgegeben, as the server does');

    await tester.binding.setSurfaceSize(const Size(393, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(RepoScope(
      session: session,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => showGaveUpSheet(context, TicketType.deutschlandticket, done.countedMinutes, done.piece), child: const Text('go')),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Aufgegeben'), findsOneWidget);
    expect(find.byKey(const Key('arrival-piece')), findsOneWidget);
    expect(find.textContaining('-Teil.'), findsOneWidget);
  });

  testWidgets('never having boarded brings nothing', (tester) async {
    final demo = DemoState();
    final repo = MockRepository(demo);
    final d = Mock.allDepartures.first;
    demo.checkIn(departure: d, exitStop: d.stops.last, fromStation: d.stops.first.name);
    final done = await repo.finishJourney(demo.journey!.id, arrived: false, reason: 'nicht_gefahren');
    expect(done.piece, isNull);
  });
}
