import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:verspaetomat/api/events.dart';
import 'package:verspaetomat/api/models.dart';
import 'package:verspaetomat/mock/mock_data.dart' show TicketType;
import 'package:verspaetomat/platform/geofence_sync.dart';
import 'package:verspaetomat/repo/mock_repository.dart';
import 'package:verspaetomat/repo/repo_scope.dart';
import 'package:verspaetomat/screens/ride/ride_widgets.dart' show demoStartJourney;
import 'package:verspaetomat/state/demo_state.dart';

/// What `GeofenceSync` asks before it configures native, answered by the test: the journey and
/// the legacy ride are whatever the case needs, and nothing tells the session they changed —
/// which is how a check-in looks from here (#80).
class _Lookups extends MockRepository {
  _Lookups() : super(DemoState());

  ApiJourneyLive? journey;
  ApiRideLive? ride;

  /// Holds the next `currentJourney` answer back until completed, with the journey as it was when
  /// asked: a slow answer that is already out of date when it lands.
  Completer<void>? holdNextJourney;

  @override
  Future<ApiGeofence> geofence() async => const ApiGeofence(
        enabled: true,
        stations: [ApiGeofenceStation(id: 'vs:4711', name: 'München-Pasing', lat: 48.1497, lon: 11.4612)],
      );

  @override
  Future<ApiJourneyLive?> currentJourney() async {
    final answer = journey;
    final hold = holdNextJourney;
    if (hold != null) {
      holdNextJourney = null;
      await hold.future;
    }
    return answer;
  }

  @override
  Future<ApiRideLive?> currentRide() async => ride;
}

ApiJourneyLive _journey(ApiJourneyStatus status) => ApiJourneyLive(
      journey: ApiJourney(
        id: 'j-690',
        status: status,
        originStationId: 'vs:1',
        originStationName: 'München Hbf',
        destinationStationId: 'vs:2',
        destinationStationName: 'Augsburg Hbf',
        createdAt: DateTime.utc(2026, 10, 2, 6, 45),
      ),
    );

ApiRideLive _legacyRide(ApiRideStatus status) => ApiRideLive(
      ride: ApiRide(
        id: 'r-1',
        tripId: 't-1',
        line: 'RE 4',
        operator: 'DB Regio',
        fromStationId: 'vs:1',
        fromStationName: 'München Hbf',
        exitStationId: 'vs:2',
        exitStationName: 'Augsburg Hbf',
        ticket: TicketType.deutschlandticket,
        checkedInAt: DateTime.utc(2026, 10, 2, 6, 45),
        status: status,
        date: DateTime.utc(2026, 10, 2),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('de.verspaetomat/geofence');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late _Lookups lookups;
  late StreamController<AppEvent> events;
  late Session session;
  late GeofenceSync sync;

  /// What native was told about riding, one entry per `configure`.
  List<bool> riding() => [for (final c in calls.where((c) => c.method == 'configure')) (c.arguments as Map)['riding'] as bool];

  Future<void> boot(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    session = Session(demo: DemoState(), prefs: prefs, apiUrl: '');
    session.me = await session.repo.getMe();
    session.healthy = true;
    sync = GeofenceSync(session: session, onNudge: (_) {}, events: events.stream, repo: lookups)..start();
    // The first sync after launch is debounced like every other.
    await tester.pump(const Duration(seconds: 2));
  }

  setUp(() {
    calls = [];
    lookups = _Lookups();
    events = StreamController<AppEvent>.broadcast();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'configure' => {'registered': 1},
        'status' => {'permission': 'always', 'notifications': true, 'registered': 1},
        _ => null,
      };
    });
  });

  tearDown(() async {
    sync.dispose();
    await events.close();
    session.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('#80: native hears that a ride is running', () {
    testWidgets('a journey event reconfigures native with riding: true', (tester) async {
      await boot(tester);
      expect(riding(), [false]);

      // The check-in happened; the server says so on the event stream and nowhere else.
      lookups.journey = _journey(ApiJourneyStatus.riding);
      events.add(const AppEvent('journey', {'status': 'riding'}));
      await tester.pump(const Duration(seconds: 2));

      expect(riding(), [false, true]);
    });

    testWidgets('a journey waiting at a change counts as riding', (tester) async {
      // Between two legs no leg is riding, so `rides/current` says nothing — and the change
      // station would nudge (docs/48: a nudge only while no journey is open).
      lookups.journey = _journey(ApiJourneyStatus.transfer);
      await boot(tester);
      expect(riding(), [true]);
    });

    testWidgets('a ride from before journeys still counts, and an arrived journey does not', (tester) async {
      lookups.ride = _legacyRide(ApiRideStatus.riding);
      await boot(tester);
      expect(riding(), [true], reason: 'no journey: the legacy ride decides');

      lookups.ride = null;
      lookups.journey = _journey(ApiJourneyStatus.arrived);
      events.add(const AppEvent('journey', {'arrived': true}));
      await tester.pump(const Duration(seconds: 2));
      expect(riding(), [true, false]);
    });

    testWidgets('a check-in through the app configures at once, not two seconds later', (tester) async {
      await boot(tester);
      expect(riding(), [false]);

      // The app goes to the background seconds after a check-in (eight in the log of #80); a
      // debounced sync can be lost to the suspension.
      lookups.journey = _journey(ApiJourneyStatus.riding);
      await demoStartJourney(session.repo);
      await tester.pump(const Duration(milliseconds: 100));

      expect(riding(), [false, true]);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('going to the background runs a pending sync before the app is suspended', (tester) async {
      await boot(tester);
      expect(riding(), [false]);

      lookups.journey = _journey(ApiJourneyStatus.riding);
      await session.refresh(); // a session change: debounced
      sync.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump();

      expect(riding(), [false, true], reason: 'configured on the way out, not after the suspension');
    });

    testWidgets('a slow answer that is already out of date does not have the last word', (tester) async {
      // The first sync asks while no journey runs, and its answer is slow.
      final hold = Completer<void>();
      lookups.holdNextJourney = hold;
      await boot(tester);
      expect(riding(), isEmpty, reason: 'the first sync is still waiting for its answer');

      // While it waits, the passenger checks in, and the sync that follows sees the journey.
      lookups.journey = _journey(ApiJourneyStatus.riding);
      await demoStartJourney(session.repo);
      await tester.pump(const Duration(milliseconds: 100));

      // Then the old answer lands.
      hold.complete();
      await tester.pump(const Duration(milliseconds: 100));

      expect(riding().last, isTrue, reason: 'native must end up knowing the ride runs');
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
