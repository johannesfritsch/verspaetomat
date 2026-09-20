import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/stations/station_extract.dart';
import 'package:verspaetomat/stations/station_index.dart';

import 'support/vst_fixture.dart';

/// The mirror of `backend/src/stations/mod.rs`'s own tests, over an extract built by hand.
///
/// Each one names the Rust test it answers, because the point is not that the Dart is
/// self-consistent but that it gives the same answer as the server for the same table.
StationIndex indexOf(List<VstStation> stations) => StationIndex(StationExtract.decode(buildVst(stations)));

void main() {
  group('nearby', () {
    test('the Hauptbahnhof wins its own forecourt (mod.rs:571)', () {
      // docs/23 §1: both are inside 300 m, so rank decides and the tram stop sixty metres away
      // does not become the station the passenger is told they are at.
      final ix = indexOf(const [
        VstStation(1, 'München Hbf', 48.1402, 11.5600, 3),
        VstStation(2, 'München, Hauptbahnhof Nord', 48.1407, 11.5602, 1),
      ]);
      final near = ix.nearby(lat: 48.1404, lon: 11.5601);
      expect(near.stations.first.name, 'München Hbf');
      expect(near.complete, isTrue);
      expect(near.source, 'gps');
    });

    test('nothing is nearby from far enough away (mod.rs:585)', () {
      // The Rust's own one-station index: Paris has no business seeing Köln. (Over the *shipped*
      // table Paris is populated — see station_parity_test.dart, which uses the Alps instead.)
      final ix = indexOf(const [VstStation(1, 'Köln Hbf', 50.9430, 6.9586, 3)]);
      final near = ix.nearby(lat: 48.8566, lon: 2.3522);
      expect(near.stations, isEmpty);
      expect(near.complete, isFalse, reason: 'an empty answer is never complete');
      expect(near.searchRadiusM, 0);
    });

    test('the radius is the last station returned (mod.rs:596)', () {
      final ix = indexOf(const [
        VstStation(1, 'Kißlegg', 47.7914, 9.8921, 2),
        VstStation(2, 'Wangen im Allgäu', 47.6874, 9.8255, 2),
      ]);
      final near = ix.nearby(lat: 47.7914, lon: 9.8921, limit: 2);
      expect(near.stations.length, 2);
      expect(near.searchRadiusM, greaterThan(10000));
      expect(near.searchRadiusM, lessThan(15000));
    });

    test('the radius is taken after the cut, so it is what the answer reaches', () {
      final ix = indexOf(const [
        VstStation(1, 'Nah', 50.0000, 8.0000, 2),
        VstStation(2, 'Mittel', 50.0100, 8.0000, 2),
        VstStation(3, 'Weit', 50.1000, 8.0000, 2),
      ]);
      final one = ix.nearby(lat: 50.0000, lon: 8.0000, limit: 1);
      expect(one.stations.length, 1);
      expect(one.searchRadiusM, 0, reason: 'the nearest station is the query point itself');
      final two = ix.nearby(lat: 50.0000, lon: 8.0000, limit: 2);
      expect(two.searchRadiusM, greaterThan(1000));
      expect(two.searchRadiusM, lessThan(1200));
      // The third is inside 50 km and deliberately not counted: the radius says how far this
      // answer reaches, not how far the scan looked.
      expect(ix.nearby(lat: 50.0000, lon: 8.0000, limit: 3).searchRadiusM, greaterThan(11000));
    });

    test('nothing within fifty kilometres is an empty answer, not the nearest one in the country', () {
      final ix = indexOf(const [VstStation(1, 'Köln Hbf', 50.9430, 6.9586, 3)]);
      // Just inside and just outside 50 km, due north of Köln.
      expect(ix.nearby(lat: 51.3400, lon: 6.9586).stations, hasLength(1));
      expect(ix.nearby(lat: 51.4500, lon: 6.9586).stations, isEmpty);
    });

    test('a full tie comes back in ascending id order', () {
      // Rust's sorts are stable and its input is in id order; Dart's `List.sort` is not, so the
      // id has to be the last tiebreaker or the top-1 can flip between runs.
      final ix = indexOf(const [
        VstStation(41, 'Doppel A', 50.0000, 8.0000, 2),
        VstStation(42, 'Doppel B', 50.0000, 8.0000, 2),
        VstStation(43, 'Doppel C', 50.0000, 8.0000, 2),
      ]);
      for (var i = 0; i < 20; i++) {
        expect(ix.nearby(lat: 50.0000, lon: 8.0000).stations.map((s) => s.id).toList(),
            ['vs:41', 'vs:42', 'vs:43']);
      }
    });

    test('the answer carries the ids, ranks and distances the server puts on it', () {
      final ix = indexOf(const [VstStation(4711, 'Köln Hbf', 50.9430, 6.9586, 3)]);
      final s = ix.nearby(lat: 50.9430, lon: 6.9586).stations.single;
      expect(s.id, 'vs:4711');
      expect(s.name, 'Köln Hbf');
      expect(s.railRank, 3);
      expect(s.distanceM, 0);
      expect(s.lat, closeTo(50.9430, 5e-7));
    });

    test('a Stellwerk override is named as one', () {
      final ix = indexOf(const [VstStation(1, 'Köln Hbf', 50.9430, 6.9586, 3)]);
      final near = ix.nearby(lat: 50.9430, lon: 6.9586, source: 'stellwerk', label: 'Köln Hbf');
      expect(near.source, 'stellwerk');
      expect(near.label, 'Köln Hbf');
      expect(near.simulated, isTrue);
      expect(near.independentOfFix, isTrue);
    });
  });

  group('search', () {
    test('a search prefers the name that starts with what was typed (mod.rs:625)', () {
      final ix = indexOf(const [
        VstStation(1, 'Bergisch Gladbach, Kölner Straße', 50.99, 7.13, 1),
        VstStation(2, 'Köln Süd', 50.9230, 6.9430, 2),
        VstStation(3, 'Köln Hbf', 50.9430, 6.9586, 3),
      ]);
      final hits = ix.search('köln', limit: 5);
      expect(hits.map((s) => s.name).toList(),
          ['Köln Hbf', 'Köln Süd', 'Bergisch Gladbach, Kölner Straße']);
      expect(hits.first.railRank, isNull, reason: 'a searched station is not a ranking');
      expect(hits.first.distanceM, isNull);
    });

    test('a Hauptbahnhof beats a stop that merely sorts earlier (mod.rs:640)', () {
      final ix = indexOf(const [
        VstStation(1, 'Köln Ehrenfeld Bf Ehrenfeld', 50.9500, 6.9200, 3),
        VstStation(2, 'Köln Hbf', 50.9430, 6.9586, 3),
      ]);
      expect(ix.search('köln', limit: 5).first.name, 'Köln Hbf');
    });

    test('a half-typed Hauptbahnhof still finds it (mod.rs:651)', () {
      final berlin = indexOf(const [VstStation(1, 'Berlin Hauptbahnhof', 52.5251, 13.3694, 3)]);
      for (final q in ['Berlin', 'Berlin Haupt', 'Berlin Hauptbahnhof', 'berlin hbf', 'Berlin Hbf']) {
        expect(berlin.search(q, limit: 5).length, 1, reason: '$q found nothing');
      }
      final koeln = indexOf(const [VstStation(1, 'Köln Hbf', 50.9430, 6.9586, 3)]);
      for (final q in ['Köln Hbf', 'Köln Hauptbahnhof', 'köln h']) {
        expect(koeln.search(q, limit: 5).length, 1, reason: '$q found nothing');
      }
    });

    test('an empty query is an empty answer, not the whole table', () {
      final ix = indexOf(kSampleStations);
      expect(ix.search(''), isEmpty);
      expect(ix.search('   '), isEmpty);
    });

    test('the limit is the server default and it cuts', () {
      final ix = indexOf(plausibleTable(count: 60));
      expect(ix.search('Musterstadt').length, 12);
      expect(ix.search('Musterstadt', limit: 3).length, 3);
    });

    test('equal hits come back in ascending id order', () {
      final ix = indexOf(const [
        VstStation(7, 'Gleichstadt', 50.0, 8.0, 2),
        VstStation(8, 'Gleichstadt', 51.0, 9.0, 2),
      ]);
      expect(ix.search('gleich').map((s) => s.id).toList(), ['vs:7', 'vs:8']);
    });
  });
}
