import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/platform/geofence.dart';

/// #29: the shape native answers with, pinned on this side.
///
/// `status` and `countersHistory` are hand-built dictionaries in Swift and hand-parsed maps in
/// Dart, with no generated code in between, so the two can drift silently — a renamed key or an
/// Int where a Double was expected shows up as a missing circle on a map rather than as an error.
/// These fakes send exactly what `Geofence.swift` and `GeofenceChannel.swift` send.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('de.verspaetomat/geofence');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void answer(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async => handler(call));
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('status', () {
    test('a region keeps the coordinates native has always sent', () async {
      answer((_) => {
            'permission': 'always',
            'notifications': true,
            'registered': 2,
            'regions': [
              {'id': 'station:8000207', 'name': 'Köln Hbf', 'lat': 50.943, 'lon': 6.9589, 'radiusM': 300.0, 'distanceM': 120.0, 'inside': true},
              {'id': 'umbrella', 'lat': 50.943, 'lon': 6.9589, 'radiusM': 8000.0},
            ],
            'discLat': 50.943,
            'discLon': 6.9589,
            'discRadiusM': 50000.0,
            'counters': {'requests': 3, 'nearby': 1},
          });

      final s = await Geofence.instance.status();
      expect(s.regions, hasLength(2));

      final koeln = s.regions.first;
      expect(koeln.name, 'Köln Hbf');
      expect(koeln.lat, 50.943);
      expect(koeln.lon, 6.9589);
      expect(koeln.hasPosition, isTrue);
      expect(koeln.inside, isTrue);
      expect(koeln.radiusM, 300.0);

      final umbrella = s.regions.last;
      expect(umbrella.isUmbrella, isTrue);
      // No name in the payload: it falls back to the identifier rather than to an empty row.
      expect(umbrella.name, 'umbrella');
      expect(umbrella.distanceM, isNull, reason: 'native omits distance when it has no fix to measure from');
      expect(s.disc, isNotNull);
      expect(s.disc!.radiusM, 50000.0);
    });

    test('a region native could not place is kept, not dropped', () async {
      answer((_) => {
            'permission': 'always',
            'registered': 1,
            'regions': [
              {'id': 'station:1', 'name': 'Irgendwo', 'radiusM': 300.0},
            ],
          });

      final s = await Geofence.instance.status();
      expect(s.regions, hasLength(1), reason: 'it is registered; the map is what has to leave it out');
      expect(s.regions.single.hasPosition, isFalse);
      expect(s.regions.single.lat, isNull);
    });

    test('no native side at all is a safe empty status, not a crash', () async {
      answer((_) => throw MissingPluginException('no platform'));
      final s = await Geofence.instance.status();
      expect(s.regions, isEmpty);
      expect(s.disc, isNull);
      expect(s.permission, GeofencePermission.notDetermined);
    });
  });

  group('countersHistory', () {
    test('reads the days back, newest first, with their counters', () async {
      late MethodCall seen;
      answer((call) {
        seen = call;
        return [
          {'day': '2026-09-18', 'counters': {'requests': 4, 'nearby': 2, 'scheduled': 1}},
          {'day': '2026-09-16', 'counters': {'requests': 9, 'nearby': 3}},
        ];
      });

      final days = await Geofence.instance.countersHistory(days: 8);
      expect(seen.method, 'countersHistory');
      expect((seen.arguments as Map)['days'], 8);

      expect(days, hasLength(2));
      expect(days.first.day, '2026-09-18');
      expect(days.first.get('requests'), 4);
      // A counter that was never bumped that day reads as zero, which is what it means here.
      expect(days.first.get('cancelled'), 0);
      // 2026-09-17 is absent rather than zero: nothing bumped a counter that day — most often a
      // day that never left the coverage disc — and the table must not invent a row for it.
      expect(days.map((d) => d.day), isNot(contains('2026-09-17')));
      expect(days.last.get('requests'), 9);
    });

    test('a phone with no history answers with nothing', () async {
      answer((_) => <dynamic>[]);
      expect(await Geofence.instance.countersHistory(), isEmpty);
    });

    test('Android, which implements none of this, is empty rather than an error', () async {
      answer((_) => throw MissingPluginException('not implemented'));
      expect(await Geofence.instance.countersHistory(), isEmpty);
    });
  });

  group('the two actions', () {
    test('refreshNow reports what happened, not just whether it worked', () async {
      answer((_) => 'started');
      expect(await Geofence.instance.refreshNow(), GeofenceRefresh.started);

      answer((_) => 'off');
      expect(await Geofence.instance.refreshNow(), GeofenceRefresh.off);

      // The case that matters most: refusing because the near-watch is running is not a failure,
      // and the screen must be able to say so rather than "nothing happened".
      answer((_) => 'busy');
      expect(await Geofence.instance.refreshNow(), GeofenceRefresh.busy);

      answer((_) => 'denied');
      expect(await Geofence.instance.refreshNow(), GeofenceRefresh.denied);

      answer((_) => throw MissingPluginException('no platform'));
      expect(await Geofence.instance.refreshNow(), GeofenceRefresh.unavailable);

      // An answer nobody taught it must not read as success.
      answer((_) => 'something new');
      expect(await Geofence.instance.refreshNow(), GeofenceRefresh.unavailable);
    });

    test('testNudge asks for a delay in seconds and never calls a refusal a success', () async {
      late MethodCall seen;
      answer((call) {
        seen = call;
        return true;
      });

      expect(await Geofence.instance.testNudge(), isTrue);
      expect(seen.method, 'testNudge');
      expect((seen.arguments as Map)['delay'], 10.0);

      await Geofence.instance.testNudge(delay: const Duration(seconds: 30));
      expect((seen.arguments as Map)['delay'], 30.0);

      // Notifications denied: UNUserNotificationCenter refuses the request, and the whole point
      // of the button is that this is reported rather than swallowed.
      answer((_) => false);
      expect(await Geofence.instance.testNudge(), isFalse);

      answer((_) => throw MissingPluginException('no platform'));
      expect(await Geofence.instance.testNudge(), isFalse);
    });
  });
}
