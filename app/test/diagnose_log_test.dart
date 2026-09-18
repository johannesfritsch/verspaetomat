import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/platform/diagnose_log.dart';

/// The log is the thing that has actually settled the last two bugs, so what it records matters
/// as much as what the app does. Two rules here: it must say enough to distinguish "the server
/// found nothing" from "we asked about the wrong place" (issue #31), and it must never put a
/// body, a claim or a railway's reply in the clipboard.
void main() {
  group('a request line says what was asked and what shape came back', () {
    test('the query is in it, with coordinates cut to about eleven metres', () {
      // The line that could not answer issue #31 was "GET /v1/stations/nearby → 200 · 91 B".
      expect(
        DiagnoseLog.formatQuery({'lat': '47.68170123', 'lon': '9.83310987'}),
        '?lat=47.6817&lon=9.8331',
      );
      expect(DiagnoseLog.formatQuery(null), '');
      expect(DiagnoseLog.formatQuery({}), '');
    });

    test('a long value is clipped rather than pasted whole', () {
      final q = DiagnoseLog.formatQuery({'q': 'a' * 100});
      expect(q.length, lessThan(50));
      expect(q, endsWith('…'));
    });

    test('nearby names what came back, and says plainly when nothing did', () {
      expect(
        DiagnoseLog.summarise('/v1/stations/nearby', {
          'stations': [
            {'name': 'Wangen Bahnhof'},
            {'name': 'Hergatz'},
          ],
        }),
        '2: Wangen Bahnhof, Hergatz',
      );
      // The exact case from Johannes' log: an hour of these, and the old line could not show it.
      expect(DiagnoseLog.summarise('/v1/stations/nearby', {'stations': []}), 'keine Station');
    });

    test('the fence answers with its own state', () {
      expect(
        DiagnoseLog.summarise('/v1/me/geofence', {
          'enabled': true,
          'stations': [
            {'id': 'a'},
            {'id': 'b'},
          ],
        }),
        'an · 2 Stammbahnhöfe',
      );
      expect(DiagnoseLog.summarise('/v1/me/geofence', {'enabled': false, 'idle': true}), 'aus · ruhend');
    });

    test('an endpoint nobody taught it gets no summary rather than a guess', () {
      expect(DiagnoseLog.summarise('/v1/me', {'full_name': 'Johannes', 'email': 'j@example.de'}), isNull);
      expect(DiagnoseLog.summarise('/v1/claims/abc', {'signature': '…'}), isNull);
      expect(DiagnoseLog.summarise('/v1/stations/nearby', null), isNull);
    });
  });

  group('what it refuses to keep', () {
    test('a summary never carries a value out of the body', () {
      // Shapes and counts only. If this ever started returning field values, a paste of the log
      // would carry a claim or an address with it.
      final summary = DiagnoseLog.summarise('/v1/incidents', {
        'incidents': [
          {'amount_cents': 150, 'line': 'RE 7'},
        ],
      });
      expect(summary, '1 Fälle');
      expect(summary, isNot(contains('150')));
      expect(summary, isNot(contains('RE 7')));
    });

    test('a server error is kept, short, because that is the useful half', () {
      expect(DiagnoseLog.serverError('{"error":"no open incidents for this desk"}'), 'no open incidents for this desk');
      expect(DiagnoseLog.serverError(''), isNull);
      final long = DiagnoseLog.serverError('x' * 400);
      expect(long!.length, lessThanOrEqualTo(121));
      expect(long, endsWith('…'));
    });
  });

  group('a line that went wrong is marked', () {
    setUp(DiagnoseLog.instance.clear);

    test('a failed status marks the line, a good one does not', () {
      DiagnoseLog.instance.http('GET', '/v1/me', 200, const Duration(milliseconds: 12));
      DiagnoseLog.instance.http('POST', '/v1/claims/draft', 412, const Duration(milliseconds: 30), error: 'under 4 €');
      final lines = DiagnoseLog.instance.lines.toList();
      expect(lines[0].bad, isFalse);
      expect(lines[1].bad, isTrue);
      expect(lines[1].text, contains('under 4 €'));
    });

    test('the native lines worth noticing are recognised by what they say', () {
      final merged = DiagnoseLog.instance.merged([
        '2026-09-17T18:41:51Z\tgeofence\trecentred on 25 km disc, nearest 0',
        '2026-09-17T18:41:52Z\tgeofence\tenter Wangen Bahnhof',
        '2026-09-17T18:41:53Z\tgeofence\tiOS refused Langenargen: Error',
      ]);
      expect(merged.where((l) => l.bad).length, 2);
      expect(merged.firstWhere((l) => l.text.contains('enter')).bad, isFalse);
    });

    test('a malformed native line is dropped, not guessed at', () {
      expect(DiagnoseLog.instance.merged(['nonsense', 'also\tnonsense']), isEmpty);
    });
  });

  group('the ring', () {
    test('holds its cap and keeps the newest', () {
      DiagnoseLog.instance.clear();
      for (var i = 0; i < DiagnoseLog.cap + 50; i++) {
        DiagnoseLog.instance.add('app', 'line $i');
      }
      final lines = DiagnoseLog.instance.lines;
      expect(lines.length, DiagnoseLog.cap);
      expect(lines.last.text, 'line ${DiagnoseLog.cap + 49}');
    });
  });
}
