import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/platform/diagnose_log.dart';
import 'package:verspaetomat/platform/geofence.dart';
import 'package:verspaetomat/platform/geofence_replay.dart';

/// #29: "a map of the state at different times".
///
/// The history is a join, not a recording: the log says *when* and names a station, the region set
/// says *where* that station is. The rule this pins is what happens when the join fails — a line
/// about a station that is no longer registered has no position anywhere on the phone, and the
/// only honest answer is to count it and leave it off the map rather than place it somewhere
/// plausible.
void main() {
  GeofenceRegion region(String id, String name, {double lat = 50.94, double lon = 6.96}) =>
      GeofenceRegion(id: id, name: name, lat: lat, lon: lon, radiusM: 300);

  LogLine line(String source, String text, {int minute = 0}) =>
      LogLine(at: DateTime(2026, 9, 18, 8, minute), source: source, text: text);

  const koeln = 'Köln Hbf';

  test('the real lines native writes all find their station', () {
    final regions = [region('station:koeln', koeln), region('station:bonn', 'Bonn Hbf', lat: 50.73, lon: 7.09)];
    final log = [
      line('geofence', 'enter $koeln', minute: 1),
      line('geofence', 'watching for 50 m at $koeln', minute: 2),
      line('geofence', '37 m from $koeln', minute: 3),
      line('geofence', 'nudge scheduled $koeln in 180 s', minute: 4),
      line('geofence', 'cancelled Bonn Hbf: left the region', minute: 5),
    ];

    final replay = GeofenceReplay.place(regions, log);
    expect(replay.events, hasLength(5));
    expect(replay.unplaceable, 0);
    expect(replay.events.first.stationName, koeln);
    expect(replay.events.first.regionId, 'station:koeln');
    expect(replay.events.last.regionId, 'station:bonn');
    // Oldest first: a replay is walked forwards.
    expect(replay.events.first.at.isBefore(replay.events.last.at), isTrue);
  });

  test('a line about a station that is no longer registered is counted, not placed', () {
    final replay = GeofenceReplay.place(
      [region('station:koeln', koeln)],
      [
        line('geofence', 'enter $koeln'),
        line('geofence', 'enter Memmingen', minute: 5),
        line('geofence', 'cancelled Memmingen: left the region', minute: 9),
      ],
    );

    expect(replay.events, hasLength(1), reason: 'Memmingen is gone from the set, so we do not know where it was');
    expect(replay.unplaceable, 2);
    expect(replay.events.single.stationName, koeln);
  });

  test('lines that name no station at all still count as unplaceable', () {
    final replay = GeofenceReplay.place(
      [region('station:koeln', koeln)],
      [
        line('geofence', 'configure: 8 stations, enabled=true, riding=false, auth=always'),
        line('geofence', 'significant-location monitoring on', minute: 1),
        line('geofence', 'umbrella exit', minute: 2),
      ],
    );
    expect(replay.events, isEmpty);
    expect(replay.unplaceable, 3);
    expect(replay.isEmpty, isTrue);
  });

  test('only geofence lines are placed, and other sources are not counted against us', () {
    final replay = GeofenceReplay.place(
      [region('station:koeln', koeln)],
      [
        line('http', 'GET /v1/stations/nearby → 200 · 84 ms'),
        line('app', 'resumed', minute: 1),
        line('push', 'tapped station · $koeln', minute: 2),
        line('geofence', 'enter $koeln', minute: 3),
      ],
    );
    expect(replay.events, hasLength(1));
    expect(replay.unplaceable, 0, reason: 'an http line is not a geofence event that went missing');
  });

  test('the longer station name wins when one contains the other', () {
    // Both are real German stations and one name contains the other; matching the short one first
    // would put every "Köln Hbf Tief" event at the wrong circle.
    final regions = [
      region('station:koeln', koeln),
      region('station:tief', 'Köln Hbf Tief', lat: 50.9431, lon: 6.9590),
    ];
    final replay = GeofenceReplay.place(regions, [line('geofence', 'enter Köln Hbf Tief')]);
    expect(replay.events.single.regionId, 'station:tief');
  });

  test('the umbrella is never a replay target', () {
    final replay = GeofenceReplay.place(
      [GeofenceRegion(id: 'umbrella', name: 'umbrella', lat: 50.94, lon: 6.96, radiusM: 8000)],
      [line('geofence', 'umbrella exit')],
    );
    expect(replay.events, isEmpty);
    expect(replay.unplaceable, 1);
  });

  test('a region without coordinates cannot host an event either', () {
    final replay = GeofenceReplay.place(
      [const GeofenceRegion(id: 'station:koeln', name: koeln, radiusM: 300)],
      [line('geofence', 'enter $koeln')],
    );
    expect(replay.events, isEmpty, reason: 'we know the station, but not where it is');
    expect(replay.unplaceable, 1);
  });

  test('an empty set and an empty log are both simply empty', () {
    expect(GeofenceReplay.place(const [], const []).events, isEmpty);
    expect(GeofenceReplay.place(const [], const []).unplaceable, 0);
    expect(GeofenceReplay.place([region('a', 'A')], const []).isEmpty, isTrue);
  });
}
