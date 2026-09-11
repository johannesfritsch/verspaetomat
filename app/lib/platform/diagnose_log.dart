import 'dart:collection';

/// The log behind the debug page (docs/25 §5).
///
/// It exists so a question like "why no nudge at Memmingen?" can be answered from the phone
/// instead of guessed at from a laptop. Dart keeps its own ring for what happens while the app
/// is awake — HTTP, pushes, lifecycle — and merges the native `geofence` lines in when the page
/// is opened, because nearly all of those are written while the app is suspended.
///
/// It holds paths, never bodies, and no claim content. Nothing in it leaves the phone by itself.
class DiagnoseLog {
  DiagnoseLog._();
  static final DiagnoseLog instance = DiagnoseLog._();

  static const cap = 500;
  final Queue<LogLine> _lines = Queue<LogLine>();

  UnmodifiableListView<LogLine> get lines => UnmodifiableListView(_lines);

  void add(String source, String text) {
    _lines.addLast(LogLine(at: DateTime.now(), source: source, text: text));
    while (_lines.length > cap) {
      _lines.removeFirst();
    }
  }

  /// One request, as the interceptor in `client.dart` records it: what was asked, what came
  /// back and how long it took. Never the body.
  void http(String method, String path, int status, Duration took, {int? bytes}) {
    final size = bytes == null ? '' : ' · ${bytes >= 1024 ? '${(bytes / 1024).toStringAsFixed(1)} kB' : '$bytes B'}';
    add('http', '$method $path → $status · ${took.inMilliseconds} ms$size');
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
      all.add(LogLine(at: at.toLocal(), source: parts[1], text: parts.sublist(2).join('\t')));
    }
    all.sort((a, b) => a.at.compareTo(b.at));
    return all;
  }
}

class LogLine {
  const LogLine({required this.at, required this.source, required this.text});
  final DateTime at;

  /// `geofence` · `http` · `push` · `app`.
  final String source;
  final String text;

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// "13:52:07 geofence enter Köln Hbf" — short, for reading a trip on the phone.
  String get plain {
    final t = at.toLocal();
    return '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)} $source $text';
  }

  /// The same line with its date, for `Alles kopieren`: a buffer can span days, and whoever
  /// reads the paste later is not the person who was there.
  String get plainWithDate {
    final t = at.toLocal();
    return '${t.year}-${_two(t.month)}-${_two(t.day)} $plain';
  }
}
