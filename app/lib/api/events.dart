import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// One event from the backend's per-customer stream (`GET /v1/events`).
/// Kinds: hello, location, ride, journey, incident, claim, mail, clock, reset, resync.
class AppEvent {
  const AppEvent(this.kind, this.data);
  final String kind;
  final Map<String, dynamic> data;

  bool get touchesRide => kind == 'ride' || kind == 'journey' || kind == 'reset' || kind == 'clock' || kind == 'resync';
  bool get touchesLedger => kind == 'incident' || kind == 'claim' || kind == 'mail' || kind == 'ride' || kind == 'journey' || kind == 'reset' || kind == 'clock' || kind == 'resync';

  /// A journey event (docs/17): transfer, arrived, finished.
  bool get isJourney => kind == 'journey';
  bool get journeyTransfer => isJourney && data['transfer'] == true;
  bool get journeyArrived => isJourney && (data['arrived'] == true || data['finished'] == true);
  bool get touchesLocation => kind == 'location' || kind == 'reset' || kind == 'resync';

  @override
  String toString() => 'AppEvent($kind, $data)';
}

/// Keeps a server-sent-events connection open and re-opens it with backoff.
/// The app refreshes what an event names; polling stays as the fallback.
class EventStream {
  EventStream({required this.baseUrl, required this.token});

  final String baseUrl;
  final String Function() token;

  final _controller = StreamController<AppEvent>.broadcast();
  http.Client? _client;
  bool _closed = false;
  int _attempt = 0;

  Stream<AppEvent> get events => _controller.stream;
  bool get connected => _client != null;

  void start() {
    if (_closed) return;
    _connect();
  }

  Future<void> _connect() async {
    while (!_closed) {
      final client = http.Client();
      _client = client;
      try {
        final req = http.Request('GET', Uri.parse('$baseUrl/v1/events'))
          ..headers['Authorization'] = 'Bearer ${token()}'
          ..headers['Accept'] = 'text/event-stream';
        final res = await client.send(req);
        if (res.statusCode != 200) throw http.ClientException('events → ${res.statusCode}');
        _attempt = 0;
        var kind = 'message';
        final data = StringBuffer();
        await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
          if (_closed) break;
          if (line.isEmpty) {
            if (data.isNotEmpty) {
              Map<String, dynamic> parsed;
              try {
                final v = jsonDecode(data.toString());
                parsed = v is Map<String, dynamic> ? v : <String, dynamic>{};
              } catch (_) {
                parsed = <String, dynamic>{};
              }
              _controller.add(AppEvent(kind, parsed));
            }
            kind = 'message';
            data.clear();
          } else if (line.startsWith('event:')) {
            kind = line.substring(6).trim();
          } else if (line.startsWith('data:')) {
            data.write(line.substring(5).trim());
          }
          // ':ping' keep-alives and other fields are ignored.
        }
      } catch (_) {
        // fall through to reconnect
      } finally {
        client.close();
        _client = null;
      }
      if (_closed) break;
      _attempt = (_attempt + 1).clamp(1, 6);
      await Future<void>.delayed(Duration(seconds: 1 << _attempt)); // 2, 4, 8 … 64 s
    }
  }

  void dispose() {
    _closed = true;
    _client?.close();
    _controller.close();
  }
}
