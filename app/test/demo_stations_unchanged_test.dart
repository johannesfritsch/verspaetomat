import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/api/models.dart';
import 'package:verspaetomat/repo/mock_repository.dart';
import 'package:verspaetomat/state/demo_state.dart';

/// Demo mode is untouched by issue #39, and this is the check that says so.
///
/// The station extract belongs to `HttpRepository`; `MockRepository` never sees it. The one way
/// this change could have reached Demo is through the two fields added to [ApiNearby] — so those
/// are what this file pins down.
void main() {
  test('the demo still answers with its three Köln stations', () async {
    final repo = MockRepository(DemoState());
    final near = await repo.nearbyStations();
    expect(near.source, 'demo');
    expect(near.stations, hasLength(3));
    expect(near.stations.first.name, contains('Köln'));
    expect(near.stations.map((s) => s.railRank).toList(), [3, 2, 1]);
    expect(near.independentOfFix, isTrue, reason: 'the demo list needs no fix to be believed');
    expect(near.checking, isFalse);
  });

  test('the demo search still finds a station by name', () async {
    final repo = MockRepository(DemoState());
    expect(await repo.searchStations('köln'), isNotEmpty);
    expect(await repo.searchStations('zzz'), isEmpty);
  });

  test('the two new fields default to what an answer without them meant', () async {
    // `mock_repository.dart` builds `ApiNearby` without them, so the defaults are what Demo gets.
    // `complete: false` is the fail-closed value the native umbrella sizing wants
    // (app/ios/Runner/Geofence.swift:108) and `searchRadiusM: 0` is „this answer does not say".
    final near = await MockRepository(DemoState()).nearbyStations();
    expect(near.complete, isFalse);
    expect(near.searchRadiusM, 0);
    // And nothing in the app treats an incomplete answer as no answer.
    expect(near.stations, isNotEmpty);
  });

  test('a server answer still carries the server’s own numbers', () {
    final near = ApiNearby.fromJson({
      'stations': [
        {'id': 'vs:2049', 'name': 'Köln Hbf', 'lat': 50.943, 'lon': 6.9586, 'distance_m': 10, 'rail_rank': 3},
      ],
      'source': 'gps',
      'label': null,
      'search_radius_m': 1093,
      'complete': true,
    });
    expect(near.searchRadiusM, 1093);
    expect(near.complete, isTrue);
    expect(near.stations.single.id, 'vs:2049');

    // An older server that sends neither field still parses, and lands on the fail-closed values.
    final old = ApiNearby.fromJson({'stations': [], 'source': 'none', 'label': null});
    expect(old.searchRadiusM, 0);
    expect(old.complete, isFalse);
  });
}
