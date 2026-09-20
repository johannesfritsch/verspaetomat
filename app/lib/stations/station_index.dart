import '../api/models.dart';
import 'station_extract.dart';
import 'station_rules.dart';

/// `stations::Index` on the phone (backend/src/stations/mod.rs): the same two answers, computed
/// from the same numbers, in the same order.
///
/// Pure and synchronous. Both answers are a scan over the whole table — 7,604 rows, measured at
/// 1.9 ms cold for [nearby] — so there is no index to build and nothing to keep warm.
class StationIndex {
  StationIndex(this.extract);

  final StationExtract extract;

  /// The two search folds, built on first use and never at load.
  ///
  /// Together they cost about 14 ms for 7,604 names and only [search] needs them; [nearby] is the
  /// launch-path caller and must not pay for them. By the time a fold is built the passenger has
  /// typed two characters into a field that is already showing its spinner
  /// (app/lib/screens/ride/ride_widgets.dart:701).
  late final List<String> _plain =
      List<String>.generate(extract.count, (i) => extract.names[i].toLowerCase(), growable: false);
  late final List<String> _normal =
      List<String>.generate(extract.count, (i) => serverStationFold(extract.names[i]), growable: false);

  /// `stations::Index::nearby` (backend/src/stations/mod.rs:204), wrapped in the JSON
  /// `handlers::stations_nearby` builds around it (backend/src/handlers.rs:85-98).
  ///
  /// [source] and [label] are what the server put there: `gps` for the phone's own fix,
  /// `stellwerk` plus the station's name when an override decides where the customer is.
  ApiNearby nearby({
    required double lat,
    required double lon,
    int limit = kNearbyDefaultLimit,
    String source = 'gps',
    String? label,
  }) {
    final count = extract.count;
    final elat = extract.lat;
    final elon = extract.lon;
    // (rounded metres, record index). The index is the id tiebreaker: records are in ascending id
    // order, so ordering by it reproduces what Rust's stable sorts leave behind.
    final hits = <_Hit>[];
    for (var i = 0; i < count; i++) {
      final d = haversineM(lat, lon, elat[i], elon[i]);
      if (d <= kNearbyMaxM) hits.add(_Hit(d.round(), i));
    }
    // Round before anything else: the Rust stores `d.round() as i64` and `nearby_order` divides
    // *that*, so a station 299.6 m away is in the first band on both sides.
    hits.sort((a, b) {
      final c = a.distance.compareTo(b.distance);
      return c != 0 ? c : a.at.compareTo(b.at);
    });
    if (hits.length > limit) hits.removeRange(limit, hits.length);
    // After the cut and before the re-sort: how far this answer actually reaches, which is the
    // number the native layer sizes its umbrella from.
    final searchRadiusM = hits.isEmpty ? 0 : hits.last.distance;
    // Nearest first for the cut, best-ranked first for the answer — the same two-step the server
    // does, and for the same reason: truncating after the rank sort could drop a nearer station
    // in favour of a better one further out.
    hits.sort((a, b) {
      final c = compareNearbyOrder(
        a.distance,
        extract.rank[a.at],
        extract.namedLikeStation(a.at),
        b.distance,
        extract.rank[b.at],
        extract.namedLikeStation(b.at),
      );
      return c != 0 ? c : a.at.compareTo(b.at);
    });
    return ApiNearby(
      stations: [
        for (final h in hits)
          ApiStation(
            id: wireStationId(extract.ids[h.at]),
            name: extract.names[h.at],
            lat: extract.lat[h.at],
            lon: extract.lon[h.at],
            distanceM: h.distance,
            railRank: extract.rank[h.at],
          ),
      ],
      source: source,
      label: label,
      searchRadiusM: searchRadiusM,
      complete: hits.isNotEmpty,
    );
  }

  /// `stations::Index::search` (backend/src/stations/mod.rs:235).
  ///
  /// Two needles for two folds, exactly as the server: the plain lowercase name keeps every prefix
  /// a passenger can type, the normalised one is what makes „Berlin Hbf" find a station the feed
  /// spells out in full. `railRank` and `distanceM` are null on every hit, as they are on the
  /// server's — a search result is not a ranking.
  List<ApiStation> search(String query, {int limit = kSearchResults}) {
    final plain = query.trim().toLowerCase();
    final normal = serverStationFold(query);
    if (plain.isEmpty) return const [];
    final hits = <_Match>[];
    for (var i = 0; i < extract.count; i++) {
      final p = _plain[i];
      final n = _normal[i];
      final starts = p.startsWith(plain) || (normal.isNotEmpty && n.startsWith(normal));
      final holds = p.contains(plain) || (normal.isNotEmpty && n.contains(normal));
      if (!starts && !holds) continue;
      hits.add(_Match(starts ? 0 : 1, i));
    }
    hits.sort((a, b) {
      var c = a.rankClass.compareTo(b.rankClass);
      if (c != 0) return c;
      c = (-extract.rank[a.at]).compareTo(-extract.rank[b.at]);
      if (c != 0) return c;
      // The same tiebreaker the nearby list uses: among stations that match equally well and rank
      // equally, the one whose name says „Bahnhof" is the one the passenger meant.
      c = (extract.namedLikeStation(a.at) ? 0 : 1).compareTo(extract.namedLikeStation(b.at) ? 0 : 1);
      if (c != 0) return c;
      c = extract.names[a.at].compareTo(extract.names[b.at]);
      // Dart's `List.sort` is not stable; the record index is the id, and ascending id is what
      // the Rust's stable sort leaves behind.
      return c != 0 ? c : a.at.compareTo(b.at);
    });
    if (hits.length > limit) hits.removeRange(limit, hits.length);
    return [
      for (final h in hits)
        ApiStation(
          id: wireStationId(extract.ids[h.at]),
          name: extract.names[h.at],
          lat: extract.lat[h.at],
          lon: extract.lon[h.at],
        ),
    ];
  }
}

class _Hit {
  _Hit(this.distance, this.at);
  final int distance;
  final int at;
}

class _Match {
  _Match(this.rankClass, this.at);
  final int rankClass;
  final int at;
}
