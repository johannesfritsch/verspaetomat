import 'package:flutter/material.dart';

import '../platform/geofence.dart';
import '../theme/tokens.dart';
import 'geofence_map.dart';
import 'kit.dart';

/// The fence drawing on its own, with an invented set (issue #29).
///
/// The real page draws only what the phone reports, which on a desk is nothing at all — so this
/// exists to look at the drawing itself: the three scales it has to survive, and what it does when
/// it is handed a region it cannot place. It lives in the Showcase, where everything is invented
/// and says so; no diagnostics screen ever shows these stations.
class GeofenceMapShowcase extends StatelessWidget {
  const GeofenceMapShowcase({super.key});

  // Real coordinates for real stations, because a drawing test is worthless against made-up
  // geometry: these are far enough apart to catch a projection that stretches.
  static const _koeln = GeofenceRegion(id: 'koeln', name: 'Köln Hbf', lat: 50.9430, lon: 6.9589, radiusM: 300, inside: true);
  static const _duesseldorf = GeofenceRegion(id: 'duesseldorf', name: 'Düsseldorf Hbf', lat: 51.2199, lon: 6.7943, radiusM: 300, distanceM: 34000);
  static const _essen = GeofenceRegion(id: 'essen', name: 'Essen Hbf', lat: 51.4514, lon: 7.0146, radiusM: 300, distanceM: 58000);
  static const _bonn = GeofenceRegion(id: 'bonn', name: 'Bonn Hbf', lat: 50.7320, lon: 7.0972, radiusM: 300, distanceM: 24000);
  static const _umbrella = GeofenceRegion(id: 'umbrella', name: 'Schirm', lat: 50.9430, lon: 6.9589, radiusM: 8000);
  static const _nowhere = GeofenceRegion(id: 'ohne', name: 'Ohne Koordinaten', radiusM: 300);

  static const _set = [_koeln, _duesseldorf, _essen, _bonn, _umbrella, _nowhere];

  @override
  Widget build(BuildContext context) {
    final disc = GeofenceDisc(lat: 50.9430, lon: 6.9589, radiusM: 50000, at: DateTime(2026, 9, 18, 7, 12));
    return VScreen(
      eyebrow: 'Nur für uns',
      title: 'Zaunkarte',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VGap.s(),
          Text(
            'Dieselbe Zeichnung wie unter Einstellungen, Entwicklung — hier mit einem erfundenen '
            'Satz. Keine Kacheln, kein Kartendienst: gezeichnet wird nur, was das Telefon selbst '
            'gemeldet hat.',
            style: VText.body,
          ),
          const VGap.l(),

          const VSection('Der ganze Satz'),
          const VGap.xs(),
          VGeofenceMap(regions: _set, disc: disc, height: 260),
          const VGap.xs(),
          Text(
            'Gestrichelt die Scheibe (50 km) und der Schirm (8 km), das Kreuz ist die Mitte der '
            'Scheibe — nicht der Standort. Hell markiert ist der Kreis, in dem das Telefon nach '
            'dem letzten bekannten Ort steht. Eine Region ohne Koordinaten ist nicht gezeichnet.',
            style: VText.caption,
          ),
          const VGap.xl(),

          const VSection('Ein Bahnhof von nahem'),
          const VGap.xs(),
          const VGeofenceMap(key: Key('zaunkarte-nah'), regions: _set, focus: _koeln, height: 260),
          const VGap.xs(),
          Text(
            'Erst auf dieser Stufe sind die beiden Radien zwei verschiedene Dinge: der überwachte '
            'Kreis mit ${GeofenceConfig.defaultStationRadiusM} m und gestrichelt die '
            '${GeofenceConfig.defaultNudgeRadiusM} m, ab denen ein Hinweis geplant wird.',
            style: VText.caption,
          ),
          const VGap.xl(),

          // Düsseldorf, not Köln: Köln carries `inside`, so it draws lit, and this is the one
          // place the plain appearance is worth showing on its own.
          const VSection('Ein einzelner Bahnhof, ohne Scheibe'),
          const VGap.xs(),
          const VGeofenceMap(regions: [_duesseldorf], height: 200),
          const VGap.xl(),

          const VSection('Nichts registriert'),
          const VGap.xs(),
          const VGeofenceMap(regions: [], height: 140),
          const VGap.xl(),
        ],
      ),
    );
  }
}
