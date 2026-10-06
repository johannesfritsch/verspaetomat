import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:verspaetomat/api/events.dart';
import 'package:verspaetomat/api/models.dart';
import 'package:verspaetomat/mock/mock_data.dart' show TicketType;
import 'package:verspaetomat/platform/geofence.dart';
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

  /// What native holds for a nudge tapped while no engine was listening; `status` hands it out once.
  Map<String, String>? pendingNudge;

  /// What reached `onNudge`.
  late List<GeofenceNudge> tapped;

  /// What native was told about riding, one entry per `configure`.
  List<bool> riding() => [for (final c in calls.where((c) => c.method == 'configure')) (c.arguments as Map)['riding'] as bool];

  /// [signedIn] false: `/v1/me` has not answered yet. A unit test draws no frames, so the first
  /// frame is whatever [firstFrame] says, and already there unless a case holds it back.
  Future<void> boot(WidgetTester tester, {bool signedIn = true, Future<void> Function()? firstFrame}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    session = Session(demo: DemoState(), prefs: prefs, apiUrl: '');
    if (signedIn) {
      session.me = await session.repo.getMe();
      session.healthy = true;
    }
    sync = GeofenceSync(
      session: session,
      onNudge: tapped.add,
      events: events.stream,
      repo: lookups,
      firstFrame: firstFrame ?? () async {},
    )..start();
    // The first sync after launch is debounced like every other.
    await tester.pump(const Duration(seconds: 2));
  }

  /// The native side calling into Dart, as `GeofenceChannel.swift` does for a tap.
  Future<void> fromNative(String method, Map<String, Object?> args) =>
      messenger.handlePlatformMessage(channel.name, const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)), (_) {});

  setUp(() {
    calls = [];
    tapped = [];
    pendingNudge = null;
    lookups = _Lookups();
    events = StreamController<AppEvent>.broadcast();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      final pending = pendingNudge;
      if (call.method == 'status') pendingNudge = null;
      return switch (call.method) {
        'configure' => {'registered': 1},
        'status' => {
            'permission': 'always',
            'notifications': true,
            'registered': 1,
            if (pending != null) 'pendingNudge': pending,
          },
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

  group('#86: a check-in answers the nudges of its station', () {
    List<Object?> cleared() => [for (final c in calls.where((c) => c.method == 'clearIgnored')) (c.arguments as Map)['stationId']];

    testWidgets('a check-in clears the ignored tally of the station it starts from', (tester) async {
      await boot(tester);
      // docs/25 §4: „no check-in within 30 minutes" is what makes a nudge ignored. Three nudges
      // at a station somebody then checked in at must not mute it for a month.
      final from = (await session.repo.nearbyStations()).stations.first;
      await demoStartJourney(session.repo);
      await tester.pump(const Duration(milliseconds: 100));

      expect(cleared(), [from.id]);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('a check-in that failed clears nothing', (tester) async {
      await boot(tester);
      await expectLater(
        session.repo.startJourney(const StartJourneyRequest(fromStationId: 'koeln-hbf', fromStationName: 'Köln Hbf', toStationId: 'x', toStationName: 'X', legs: [])),
        throwsA(anything),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(cleared(), isEmpty);
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('#87: a tapped nudge waits until the app stands', () {
    const pasing = {'kind': 'station', 'stationId': 'vs:4711', 'stationName': 'München, Pasing'};

    testWidgets('a nudge tapped before launch is handed over once the account has loaded', (tester) async {
      // The cold start: iOS launched the app for the tap, and native kept it in `pendingNudge`.
      pendingNudge = pasing;
      await boot(tester, signedIn: false);
      expect(tapped, isEmpty, reason: 'no account yet: the check-in it opens has nothing to ask with');

      await session.refresh(); // `/v1/me` answers
      await tester.pump();
      expect(tapped.map((n) => n.stationId), ['vs:4711']);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('a tap from a running engine waits for the first frame', (tester) async {
      final frame = Completer<void>();
      await boot(tester, firstFrame: () => frame.future);

      await fromNative('nudgeTapped', pasing);
      await tester.pump();
      expect(tapped, isEmpty, reason: 'nothing drawn yet: there is no shell to open a sheet in');

      frame.complete();
      await tester.pump();
      expect(tapped.map((n) => n.stationId), ['vs:4711']);
    });

    testWidgets('an app that is up hands a tap over at once', (tester) async {
      await boot(tester);
      await fromNative('nudgeTapped', pasing);
      await tester.pump();
      expect(tapped.map((n) => n.stationId), ['vs:4711']);
    });
  });
}
