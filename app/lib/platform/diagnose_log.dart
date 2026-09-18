import 'dart:collection';
import 'dart:convert';

/// The log behind the debug page (docs/25 §5).
///
/// It exists so a question like "why no nudge at Memmingen?" can be answered from the phone
/// instead of guessed at from a laptop. Dart keeps its own ring for what happens while the app
/// is awake — HTTP, pushes, lifecycle — and merges the native `geofence` lines in when the page
/// is opened, because nearly all of those are written while the app is suspended.
///
/// **What it may hold, and what it may not.** Paths, queries, statuses, sizes and one-line
/// summaries of an answer's *shape*. Never a response body, never anything from a claim, a mail
/// or the passenger's own record — the log has to stay safe to paste into a message. The one
/// exception is the server's own error text on a failed request, which is short, written for a
/// developer, and the thing most worth having when something breaks.
class DiagnoseLog {
  DiagnoseLog._();
  static final DiagnoseLog instance = DiagnoseLog._();

  static const cap = 500;
  final Queue<LogLine> _lines = Queue<LogLine>();

  UnmodifiableListView<LogLine> get lines => UnmodifiableListView(_lines);

  void add(String source, String text, {bool bad = false}) {
    _lines.addLast(LogLine(at: DateTime.now(), source: source, text: text, bad: bad));
    while (_lines.length > cap) {
      _lines.removeFirst();
    }
  }

  /// One request, as the interceptor in `client.dart` records it (issue #31 follow-up).
  ///
  /// The query is in here because the one that mattered — `stations/nearby?lat=…&lon=…` — is the
  /// difference between "the app asked the wrong place" and "the server answered with nothing",
  /// and the log could not tell them apart. Coordinates are rounded to four decimals, about
  /// eleven metres, which is the precision the page already prints for the coverage disc.
  ///
  /// [summary] describes the *shape* of the answer, never its contents: how many stations came
  /// back, whether a ride is running. [error] is the server's own message on a failure.
  void http(
    String method,
    String path,
    int status,
    Duration took, {
    int? bytes,
    Map<String, String>? query,
    String? summary,
    String? error,
  }) {
    final size = bytes == null ? '' : ' · ${bytes >= 1024 ? '${(bytes / 1024).toStringAsFixed(1)} kB' : '$bytes B'}';
    final q = formatQuery(query);
    add(
      'http',
      '$method $path$q → $status · ${took.inMilliseconds} ms$size'
      '${summary == null || summary.isEmpty ? '' : ' · $summary'}'
      '${error == null || error.isEmpty ? '' : ' · $error'}',
      bad: status >= 400,
    );
  }

  /// `?lat=47.6817&lon=9.8331`, with coordinates cut to four decimals and long values clipped.
  static String formatQuery(Map<String, String>? query) {
    if (query == null || query.isEmpty) return '';
    final parts = <String>[];
    for (final e in query.entries) {
      var v = e.value;
      if (e.key == 'lat' || e.key == 'lon') {
        final n = double.tryParse(v);
        if (n != null) v = n.toStringAsFixed(4);
      }
      if (v.length > 32) v = '${v.substring(0, 32)}…';
      parts.add('${e.key}=$v');
    }
    return '?${parts.join('&')}';
  }

  /// A one-line description of what came back, for the endpoints worth describing.
  ///
  /// Deliberately a short allow-list rather than a generic dump. A generic "12 keys" would be
  /// noise, and a generic body would put a claim, an address or a mail in the clipboard. These
  /// are the answers that have actually been needed to explain something: how many stations the
  /// server found, whether the fence is on, whether a ride or journey is running.
  static String? summarise(String path, Object? decoded) {
    if (decoded == null) return null;
    List<dynamic>? listAt(String key) {
      final m = decoded is Map ? decoded[key] : null;
      return m is List ? m : null;
    }

    if (path.endsWith('/stations/nearby')) {
      final stations = listAt('stations');
      if (stations == null) return null;
      if (stations.isEmpty) return 'keine Station';
      final names = stations.whereType<Map>().map((s) => '${s['name'] ?? '?'}').take(3).join(', ');
      return '${stations.length}: $names';
    }
    if (path.endsWith('/stations/search')) {
      return decoded is List ? '${decoded.length} Treffer' : null;
    }
    if (path.endsWith('/me/geofence')) {
      if (decoded is! Map) return null;
      final stations = listAt('stations');
      return [
        decoded['enabled'] == true ? 'an' : 'aus',
        if (stations != null) '${stations.length} Stammbahnhöfe',
        if (decoded['idle'] == true) 'ruhend',
        if (decoded['snooze_until'] != null) 'pausiert',
      ].join(' · ');
    }
    if (path.endsWith('/rides/current') || path.endsWith('/journeys/current')) {
      if (decoded is! Map) return null;
      final ride = decoded['ride'] ?? decoded['journey'];
      if (ride is! Map) return null;
      return [
        if (ride['status'] != null) '${ride['status']}',
        if (ride['line'] != null) '${ride['line']}',
      ].join(' · ');
    }
    if (path.endsWith('/incidents')) {
      final incidents = listAt('incidents');
      return incidents == null ? null : '${incidents.length} Fälle';
    }
    return null;
  }

  /// The server's own error text, clipped. A failed request is the one time the body is worth
  /// keeping: it is short, written for a developer, and says what the status alone cannot.
  static String? serverError(String body) {
    if (body.isEmpty) return null;
    var text = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] != null) text = '${decoded['error']}';
    } catch (_) {
      // Not JSON: keep the raw line, clipped below.
    }
    if (text.isEmpty) return null;
    return text.length > 120 ? '${text.substring(0, 120)}…' : text;
  }

  void clear() => _lines.clear();

  /// The native lines (tab-separated `timestamp \t source \t text`) merged in, newest last.
  List<LogLine> merged(List<String> native) {
    final all = [..._lines];
    for (final raw in native) {
      final parts = raw.split('\t');
      if (parts.length < 3) continue;
      final at = DateTime.tryParse(parts[0]);
      if (at == null) continue;
      final text = parts.sublist(2).join('\t');
      all.add(LogLine(at: at.toLocal(), source: parts[1], text: text, bad: _nativeLooksBad(text)));
    }
    all.sort((a, b) => a.at.compareTo(b.at));
    return all;
  }

  /// Native writes prose, not levels, so the lines worth noticing are recognised by what they
  /// say. Every one of these has been the answer to a real question at least once.
  static bool _nativeLooksBad(String text) {
    const markers = ['refused', 'failed', 'denied', 'no fix', 'cancelled', 'nearest 0', 'left the region'];
    return markers.any(text.contains);
  }
}

class LogLine {
  const LogLine({required this.at, required this.source, required this.text, this.bad = false});
  final DateTime at;

  /// `geofence` · `http` · `push` · `app`.
  final String source;
  final String text;

  /// Something went wrong, or went nowhere. Drawn heavier so a long log can be scanned for it.
  final bool bad;

  static String _two(int v) => v.toString().padLeft(2, '0');

  String get time {
    final t = at.toLocal();
    return '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
  }

  /// "13:52:07 geofence enter Köln Hbf" — short, for reading a trip on the phone.
  String get plain => '$time $source $text';

  /// The same line with its date, for copying: a buffer can span days, and whoever reads the
  /// paste later is not the person who was there.
  String get plainWithDate {
    final t = at.toLocal();
    return '${t.year}-${_two(t.month)}-${_two(t.day)} $plain';
  }
}
