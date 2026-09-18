import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/platform/geofence.dart';
import 'package:verspaetomat/widgets/geofence_map.dart';

/// #29: the fence set, drawn. A diagnostics picture has one duty above being pretty — it must not
/// put anything on screen that the phone did not report. These tests pin the two ways it could:
/// by drawing a region in the wrong place, and by drawing one whose position we never had.
void main() {
  GeofenceRegion station(String id, double lat, double lon, {double radius = 300, bool inside = false}) =>
      GeofenceRegion(id: id, name: id, lat: lat, lon: lon, radiusM: radius, inside: inside);

  group('the projection', () {
    final proj = GeofenceProjection(
      centreLat: 50.9413, // Köln Hbf
      centreLon: 6.9583,
      metresPerPx: 100,
      size: const Size(200, 200),
    );

    test('the centre of the frame is the centre of the projection', () {
      final c = proj.toPx(50.9413, 6.9583);
      expect(c.dx, closeTo(100, 0.001));
      expect(c.dy, closeTo(100, 0.001));
    });

    test('north is up and east is right', () {
      expect(proj.toPx(51.0, 6.9583).dy, lessThan(100), reason: 'further north must be higher up');
      expect(proj.toPx(50.9413, 7.1).dx, greaterThan(100), reason: 'further east must be further right');
    });

    test('a degree of longitude is shorter than a degree of latitude at this latitude', () {
      // Cologne is at 51°N, so a degree east is about 63% of a degree north. Getting this wrong
      // is the classic way a map of Germany comes out stretched.
      expect(proj.metresPerDegreeLon / GeofenceProjection.metresPerDegreeLat, closeTo(math.cos(50.9413 * math.pi / 180), 0.0001));
    });

    test('a known distance lands at the right number of pixels', () {
      // 0.01° of latitude is 1113.2 m, which at 100 m/px is 11.132 px.
      expect(proj.toPx(50.9513, 6.9583).dy, closeTo(100 - 11.132, 0.01));
      expect(proj.radiusPx(1000), closeTo(10, 0.001));
    });
  });

  group('the scale bar', () {
    test('only ever says 1, 2 or 5 times a power of ten', () {
      for (final metres in [1.0, 7.0, 30.0, 123.0, 640.0, 2400.0, 51000.0, 870000.0, 99.0, 100.0, 999.0]) {
        final rounded = VGeofenceMapScale.round(metres);
        final magnitude = math.pow(10, (math.log(rounded) / math.ln10).round()).toDouble();
        final mantissa = rounded / magnitude;
        expect(
          [0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0].any((m) => (mantissa - m).abs() < 0.0001),
          isTrue,
          reason: '$metres rounded to $rounded, whose mantissa $mantissa is not a scale-bar number',
        );
        expect(rounded, lessThanOrEqualTo(metres), reason: 'the bar is drawn from this number, so it must still fit the space asked for');
      }
    });
  });

  group('the scale bar, continued', () {
    test('a bar asked for a third of the frame never comes out longer than that', () {
      // The bug this pins: rounding up turned a 33%-of-width bar into an 83%-of-width one that
      // ran across the picture and through a station.
      for (var target = 1.0; target < 2000000; target *= 1.37) {
        expect(VGeofenceMapScale.round(target), lessThanOrEqualTo(target));
      }
    });

    test('it never returns zero or a negative, whatever it is handed', () {
      for (final bad in [0.0, -5.0, 0.4]) {
        expect(VGeofenceMapScale.round(bad), greaterThan(0));
      }
    });
  });

  group('what the picture refuses to draw', () {
    testWidgets('a region without coordinates is counted, not placed', (tester) async {
      const nowhere = GeofenceRegion(id: 'ghost', name: 'Ghost', radiusM: 300);
      final map = VGeofenceMap(regions: [station('koeln', 50.9413, 6.9583), nowhere], disc: null);

      expect(map.unplaced, 1, reason: 'the page has to be able to say one region is missing');

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: map)));
      expect(find.byKey(const Key('geofence-map')), findsOneWidget);
    });

    testWidgets('nothing registered and no disc says so instead of drawing an empty box', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: VGeofenceMap(regions: []))));
      expect(find.text('Nichts registriert, nichts zu zeichnen.'), findsOneWidget);
      expect(find.byKey(const Key('geofence-map')), findsNothing);
    });

    testWidgets('regions that exist but cannot be placed say exactly that', (tester) async {
      // Not "nichts registriert": two regions ARE registered, and the count printed under the
      // map would contradict that wording. This is the Android case too, where status() returns
      // no region coordinates at all.
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: VGeofenceMap(regions: [GeofenceRegion(id: 'a', name: 'A'), GeofenceRegion(id: 'b', name: 'B')])),
      ));
      expect(find.text('Keine der 2 Regionen hat Koordinaten geliefert — nichts zu zeichnen.'), findsOneWidget);
      expect(find.text('Nichts registriert, nichts zu zeichnen.'), findsNothing);
    });
  });

  group('the picture renders', () {
    testWidgets('a real-looking set with a disc and an umbrella', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: VGeofenceMap(
            regions: [
              station('koeln', 50.9413, 6.9583, inside: true),
              station('duesseldorf', 51.2200, 6.7940),
              station('essen', 51.4514, 7.0146),
              GeofenceRegion(id: 'umbrella', name: 'umbrella', lat: 50.9413, lon: 6.9583, radiusM: 8000),
            ],
            disc: GeofenceDisc(lat: 50.9413, lon: 6.9583, radiusM: 50000, at: DateTime(2026, 9, 18, 7, 30)),
          ),
        ),
      ));
      expect(find.byKey(const Key('geofence-map')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('one station up close, where its two radii are different things', (tester) async {
      final koeln = station('koeln', 50.9413, 6.9583);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: VGeofenceMap(regions: [koeln], focus: koeln)),
      ));
      expect(find.byKey(const Key('geofence-map')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a focus on a region we have no position for falls back to the whole set', (tester) async {
      const ghost = GeofenceRegion(id: 'ghost', name: 'Ghost');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: VGeofenceMap(regions: [station('koeln', 50.9413, 6.9583), ghost], focus: ghost)),
      ));
      expect(tester.takeException(), isNull);
    });
  });
}
