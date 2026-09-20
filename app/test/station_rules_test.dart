import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/screens/ride/ride_widgets.dart' show normaliseStation;
import 'package:verspaetomat/stations/station_rules.dart';

/// The ported rules, against the Rust's own answers.
///
/// Every expectation below was produced by compiling `train::normalise_station_name`,
/// `transitous::looks_like_station` and `train::haversine_m` verbatim and printing what they say
/// for these names. They are not what the Dart happens to do — which is the only way a port is
/// worth anything.
void main() {
  group('haversineM mirrors train::haversine_m', () {
    test('the assertion from backend/src/train/mod.rs:529-531', () {
      expect(haversineM(50.9430, 6.9586, 50.9410, 6.9750), greaterThan(1100));
      expect(haversineM(50.9430, 6.9586, 50.9410, 6.9750), lessThan(1300));
    });

    test('to the last digit the Rust prints', () {
      expect(haversineM(50.9430, 6.9586, 50.9410, 6.9750), closeTo(1170.383564821582, 1e-9));
      expect(haversineM(48.1404, 11.5601, 48.1402, 11.5600), closeTo(23.444207968134148, 1e-9));
      expect(haversineM(47.7914, 9.8921, 47.6874, 9.8255), closeTo(12591.090813886003, 1e-9));
    });

    test('a point is no distance from itself', () {
      expect(haversineM(50.9430, 6.9586, 50.9430, 6.9586), 0.0);
    });
  });

  group('serverStationFold mirrors train::normalise_station_name', () {
    const cases = {
      'Berlin Hauptbahnhof': 'berlin hbf',
      'Kißlegg Bahnhof': 'kißlegg',
      'Wangen (Allgäu) Zentrum': 'wangen zentrum',
      'Bad Doberan, Bahnhof': 'bad doberan',
      'Köln Hbf': 'köln hbf',
      'Münster (Westf) Hbf': 'münster hbf',
      'Köln Hbf (DE)': 'köln hbf',
      'Köln Ehrenfeld Bf Ehrenfeld': 'köln ehrenfeld ehrenfeld',
      'München, Hauptbahnhof Nord': 'münchen hbf nord',
      'Bergisch Gladbach, Kölner Straße': 'bergisch gladbach kölner straße',
      'Zoo, Bf': 'zoo',
      'Lüneburg, Bahnhof/ZOB': 'lüneburg/zob',
      'Sankt Georgen (Schwarzw)': 'sankt georgen',
      // A stray ')' saturates the depth counter at zero and is dropped with it; the '(' after it
      // still opens a span, so everything from there on goes.
      'Test )stray( brackets': 'test stray',
      'Mehrere   Leerzeichen': 'mehrere leerzeichen',
      '  Rand  ': 'rand',
      'Aachen Hbf (DE) ': 'aachen hbf',
      'Berlin Haupt': 'berlin haupt',
    };
    cases.forEach((input, want) {
      test('„$input" folds to „$want"', () => expect(serverStationFold(input), want));
    });

    test('it is not the display-side fold, and the two can never be swapped', () {
      // `normaliseStation` (ride_widgets.dart:122) keeps „bahnhof" and folds ß→ss; this one drops
      // the word and keeps the ß. Anything that used one where the other was meant would find a
      // different station.
      expect(serverStationFold('Kißlegg Bahnhof'), 'kißlegg');
      expect(normaliseStation('Kißlegg Bahnhof'), 'kisslegg bahnhof');
      expect(serverStationFold('Kißlegg Bahnhof'), isNot(normaliseStation('Kißlegg Bahnhof')));
    });
  });

  group('looksLikeStation mirrors transitous::looks_like_station', () {
    const cases = {
      'Berlin Hauptbahnhof': true,
      'Kißlegg Bahnhof': true,
      'Köln Hbf': true,
      // The trailing ')' goes first, then the trim, and only then the tests: so this one matches
      // on `contains(' Hbf')`, not on a suffix.
      'Köln Hbf (DE)': true,
      'Aachen Hbf (DE) ': true,
      'Zoo, Bf': true,
      'Wissembourg, Bahnhof': true,
      'Köln Ehrenfeld Bf Ehrenfeld': false,
      'München, Hauptbahnhof Nord': false,
      'Wangen (Allgäu) Zentrum': false,
      'Wangen im Allgäu': false,
      'Bergisch Gladbach, Kölner Straße': false,
      'Lüneburg, Bahnhof/ZOB': false,
      'Neustadt': false,
    };
    cases.forEach((input, want) {
      test('„$input" → $want', () => expect(looksLikeStation(input), want));
    });
  });

  group('compareNearbyOrder mirrors transitous::nearby_order', () {
    test('a Hauptbahnhof at 250 m beats a stop at 60 m inside one band', () {
      expect(compareNearbyOrder(250, 3, true, 60, 1, false), lessThan(0));
    });

    test('beyond the band, distance decides again', () {
      expect(compareNearbyOrder(350, 3, true, 60, 1, false), greaterThan(0));
    });

    test('inside a band and at the same rank, the name that says Bahnhof wins', () {
      expect(compareNearbyOrder(90, 3, false, 10, 3, true), greaterThan(0));
    });

    test('all else equal, the nearer one', () {
      expect(compareNearbyOrder(10, 3, true, 90, 3, true), lessThan(0));
      expect(compareNearbyOrder(90, 3, true, 90, 3, true), 0);
    });

    test('the band is the rounded metre divided, not the other way round', () {
      // 299 and 300 straddle the edge; this is why `nearby` rounds before it ranks.
      expect(299 ~/ kRankBandM, 0);
      expect(300 ~/ kRankBandM, 1);
    });
  });

  test('the constants are the ones the server uses', () {
    expect(kRankBandM, 300);
    expect(kNearbyMaxM, 50000.0);
    expect(kNearbyDefaultLimit, 3);
    expect(kNearbyLimitMax, 25);
    expect(kSearchResults, 12);
    expect(wireStationId(4711), 'vs:4711');
  });

  test('UTF-16 and UTF-8 order agree over the names this table holds', () {
    // Rust compares `String` as UTF-8 bytes and Dart as UTF-16 code units, and `search` sorts by
    // name. The two orders differ only above U+FFFF, which no German station name reaches — this
    // is that assumption written down rather than assumed.
    const names = [
      'Ärztehaus', 'Öhringen', 'Überlingen', 'Weißenfels', 'Aachen', 'Zwickau',
      'Köln Hbf', 'Kißlegg', 'Münster', 'Neustadt', 'Straße der Jugend',
    ];
    final byCodeUnits = [...names]..sort();
    final byUtf8 = [...names]..sort((a, b) {
        final x = utf8.encode(a);
        final y = utf8.encode(b);
        for (var i = 0; i < x.length && i < y.length; i++) {
          if (x[i] != y[i]) return x[i] - y[i];
        }
        return x.length - y.length;
      });
    expect(byCodeUnits, byUtf8);
  });
}
