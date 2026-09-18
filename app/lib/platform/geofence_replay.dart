import 'diagnose_log.dart';
import 'geofence.dart';

/// One log line placed on the fence set: when it happened, and at which registered region.
class GeofencePlacedEvent {
  const GeofencePlacedEvent({required this.at, required this.text, required this.regionId, required this.stationName});

  final DateTime at;
  final String text;
  final String regionId;
  final String stationName;
}

/// The result of placing the log on the map: what could be placed, and how much could not.
class GeofenceReplay {
  const GeofenceReplay({required this.events, required this.unplaceable});

  /// Oldest first, the order the phone lived them in.
  final List<GeofencePlacedEvent> events;

  /// Geofence lines that name no currently registered region. Counted, never guessed at.
  final int unplaceable;

  bool get isEmpty => events.isEmpty;

  /// Joins the native geofence log to the region set (issue #29).
  ///
  /// This is the whole of "the state at different times", and it is built out of what the phone
  /// already wrote rather than out of new recording. Native's lines name the station they are
  /// about — "enter Köln Hbf", "312 m from Memmingen", "cancelled Bonn Hbf: left the region" —
  /// and the region set says where those stations are, so joining the two places an event in
  /// time *and* space without a single new coordinate being stored anywhere.
  ///
  /// Its one limit is exactly that join. A line about a station that is no longer registered
  /// cannot be placed, because nothing on the phone remembers where that station was: the region
  /// set is a snapshot, `stopAllRegions` wipes it on every re-registration, and no log line has
  /// ever carried a coordinate. Those lines are counted in [unplaceable] and left off the map,
  /// because a guessed position on a diagnostics page is worse than an admitted gap.
  static GeofenceReplay place(List<GeofenceRegion> regions, List<LogLine> log) {
    // Longest name first, so "Köln Hbf Tief" wins over "Köln Hbf" on a line that names it. The
    // umbrella is not a station and never appears in a line.
    final placeable = [
      for (final r in regions)
        if (r.hasPosition && !r.isUmbrella && r.name.isNotEmpty) r,
    ]..sort((a, b) => b.name.length.compareTo(a.name.length));

    final events = <GeofencePlacedEvent>[];
    var seen = 0;
    for (final line in log) {
      if (line.source != 'geofence') continue;
      seen++;
      for (final r in placeable) {
        if (line.text.contains(r.name)) {
          events.add(GeofencePlacedEvent(at: line.at, text: line.text, regionId: r.id, stationName: r.name));
          break;
        }
      }
    }
    return GeofenceReplay(events: events, unplaceable: seen - events.length);
  }
}
