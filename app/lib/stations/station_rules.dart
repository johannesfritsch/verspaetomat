/// The backend's station rules, ported line for line (issue #39).
///
/// The phone answers „welcher Bahnhof ist hier?" from its own copy of the table now, so every
/// rule that decides an answer has to exist twice: once in Rust, once here. Each function below
/// names the Rust it mirrors. If one of them drifts, the app and the server disagree about which
/// station a passenger is standing at — so they are tested against numbers taken from the Rust,
/// not against themselves.
///
/// Pure and synchronous: no Flutter, no I/O, no state.
library;

import 'dart:math' as math;

/// `train::transitous::RANK_BAND_M` (backend/src/train/transitous.rs:26). Two stations inside
/// one band are ranked by what kind of station they are, not by which is nearer.
const int kRankBandM = 300;

/// `stations::NEARBY_MAX_M` (backend/src/stations/mod.rs:40). Beyond this the answer is empty
/// rather than a station in the next Bundesland.
const double kNearbyMaxM = 50000.0;

/// `handlers::stations_nearby`'s `q.limit.unwrap_or(3)` (backend/src/handlers.rs:80).
const int kNearbyDefaultLimit = 3;

/// The same handler's `.clamp(1, 25)`, and `GeofenceRules.nearbyLimit`
/// (app/ios/Runner/Geofence.swift:131).
///
/// No Dart caller passes a limit today — [StationIndex.nearby] takes one so the native follow-up
/// can ask for the wider list it needs without a wire change.
const int kNearbyLimitMax = 25;

/// `handlers::SEARCH_RESULTS` (backend/src/handlers.rs:119).
const int kSearchResults = 12;

/// Record byte 13, bit 0 of the extract: `looks_like_station` of this station's name, baked in at
/// build time so the ranking never has to decode a string (05-VERIFY §1.2).
const int kFlagLooksLikeStation = 1 << 0;

/// `stations::wire_id` (backend/src/stations/mod.rs:57). The table's ids are ours; the wire form
/// says so, which is what lets a handler tell one of ours from a MOTIS id without guessing.
String wireStationId(int id) => 'vs:$id';

/// `train::haversine_m` (backend/src/train/mod.rs:393). R = 6_371_000, `atan2(sqrt(a), sqrt(1-a))`.
double haversineM(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final p1 = lat1 * _degToRad;
  final p2 = lat2 * _degToRad;
  final dp = (lat2 - lat1) * _degToRad;
  final dl = (lon2 - lon1) * _degToRad;
  final sdp = math.sin(dp / 2.0);
  final sdl = math.sin(dl / 2.0);
  final a = sdp * sdp + math.cos(p1) * math.cos(p2) * sdl * sdl;
  return 2.0 * r * math.atan2(math.sqrt(a), math.sqrt(1.0 - a));
}

const double _degToRad = math.pi / 180.0;

/// `train::transitous::looks_like_station` (backend/src/train/transitous.rs:498).
///
/// A name that says „this is a railway station" rather than „this is a stop somewhere". The order
/// is load-bearing: every trailing ')' goes first, then both ends are trimmed, and only then the
/// suffix tests run. „Köln Hbf (DE)" → „Köln Hbf (DE" → true, through `contains(' Hbf')`.
///
/// The extract carries the answer in [kFlagLooksLikeStation], so nothing on the ranking path calls
/// this. It is here because the phone has to be able to check that the flag still means what the
/// server means by it.
bool looksLikeStation(String name) {
  var end = name.length;
  while (end > 0 && name.codeUnitAt(end - 1) == 0x29) {
    end--;
  }
  final n = name.substring(0, end).trim();
  return n.endsWith('Hbf') ||
      n.endsWith('Hauptbahnhof') ||
      n.endsWith('Bahnhof') ||
      n.endsWith(' Bf') ||
      n.contains(' Hbf');
}

/// `train::normalise_station_name` (backend/src/train/mod.rs:286) — the fold `Index::search`
/// applies to the query and to every station name.
///
/// **Not** the same function as `normaliseStation`
/// (app/lib/screens/ride/ride_widgets.dart:122), which is the display-side fold behind
/// `sameStation`: that one folds ß→ss, keeps a trailing „Bahnhof" and never removes „ Bf".
/// Nothing may use one where the other is meant.
///
/// Steps, in this order, because the order changes the answer: bracketed spans dropped with a
/// depth counter (a stray ')' saturates at 0 and is dropped with it); 'Hauptbahnhof'→'Hbf' then
/// 'hauptbahnhof'→'hbf'; ', Bahnhof', ' Bahnhof', ', Bf', ' Bf' removed in that order; ',' → ' ';
/// whitespace collapsed; lowercased last.
///
/// Ported over code units with a hand-rolled whitespace collapse rather than
/// `split(RegExp(r'\s+'))`: measured over 7,604 names the regex costs 22.2 ms against 12.8 ms
/// cold, and this runs once per station the first time somebody types in the search field.
String serverStationFold(String name) {
  final buf = StringBuffer();
  var depth = 0;
  for (var i = 0; i < name.length; i++) {
    final c = name.codeUnitAt(i);
    if (c == 0x28) {
      depth++;
    } else if (c == 0x29) {
      if (depth > 0) depth--;
    } else if (depth == 0) {
      buf.writeCharCode(c);
    }
  }
  var s = buf.toString();
  s = s.replaceAll('Hauptbahnhof', 'Hbf').replaceAll('hauptbahnhof', 'hbf');
  s = s.replaceAll(', Bahnhof', '').replaceAll(' Bahnhof', '').replaceAll(', Bf', '').replaceAll(' Bf', '');
  s = s.replaceAll(',', ' ');
  return _collapseWhitespace(s).toLowerCase();
}

/// `str::split_whitespace().collect::<Vec<_>>().join(" ")`: every run of whitespace becomes one
/// space and both ends lose theirs. The set is Rust's `char::is_whitespace`, so a non-breaking
/// space in a feed's name folds the same way on both sides.
String _collapseWhitespace(String s) {
  final out = StringBuffer();
  var pending = false;
  var wrote = false;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (_isWhitespace(c)) {
      pending = wrote;
      continue;
    }
    if (pending) {
      out.writeCharCode(0x20);
      pending = false;
    }
    out.writeCharCode(c);
    wrote = true;
  }
  return out.toString();
}

bool _isWhitespace(int c) =>
    c == 0x20 ||
    (c >= 0x09 && c <= 0x0D) ||
    c == 0x85 ||
    c == 0xA0 ||
    c == 0x1680 ||
    (c >= 0x2000 && c <= 0x200A) ||
    c == 0x2028 ||
    c == 0x2029 ||
    c == 0x202F ||
    c == 0x205F ||
    c == 0x3000;

/// `train::transitous::nearby_order` (backend/src/train/transitous.rs:492), as a comparator:
/// `(distanceM ~/ kRankBandM, -railRank, named ? 0 : 1, distanceM)`.
///
/// [distanceA]/[distanceB] are the **rounded** metres — the Rust divides the rounded i64, so
/// rounding after the division would put a station in the wrong band.
///
/// [namedA]/[namedB] are `looks_like_station` of the two names. The Rust computes it from the
/// name; the phone reads it out of the record's `flags` byte, which is the same answer decided
/// at build time (05-VERIFY §1.2).
int compareNearbyOrder(
  int distanceA,
  int rankA,
  bool namedA,
  int distanceB,
  int rankB,
  bool namedB,
) {
  var c = (distanceA ~/ kRankBandM).compareTo(distanceB ~/ kRankBandM);
  if (c != 0) return c;
  c = (-rankA).compareTo(-rankB);
  if (c != 0) return c;
  c = (namedA ? 0 : 1).compareTo(namedB ? 0 : 1);
  if (c != 0) return c;
  return distanceA.compareTo(distanceB);
}
