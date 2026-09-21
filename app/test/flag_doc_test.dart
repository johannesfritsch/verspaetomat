import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/flags/flag_doc.dart';

/// #41: the parser reads bytes somebody else wrote, so its whole job is never to throw and never
/// to invent an answer.
void main() {
  test('a document is read, and the values are kept exactly as they arrived', () {
    final doc = FlagDoc.parse('{"flags":{"stations_local":true,"nudge_delay_s":90,"mode":"ruhig"}}')!;
    expect(doc.values['stations_local'], true);
    expect(doc.values['nudge_delay_s'], 90);
    expect(doc.values['mode'], 'ruhig');
  });

  test('an empty document is a document — it is the ordinary state', () {
    // The server sends a key only when its value differs from the default, so nothing switched on
    // anywhere means `{"flags":{}}`. That must not read as „no answer".
    final doc = FlagDoc.parse('{"flags":{}}')!;
    expect(doc.values, isEmpty);
    expect(doc.isEmpty, isTrue);
  });

  test('unknown fields beside the flags are ignored, so a newer server does not break an older app', () {
    final doc = FlagDoc.parse('{"flags":{"a":true},"serial":12,"published_at":"2026-09-21T10:00:00Z"}')!;
    expect(doc.values, {'a': true});
  });

  test('a name this build does not know is kept, because somebody has to be told', () {
    final doc = FlagDoc.parse('{"flags":{"something_new":true}}')!;
    expect(doc.values.keys, contains('something_new'));
  });

  test('nothing that is not a document is read as one, and nothing throws', () {
    for (final body in <String>[
      '',
      'not json at all',
      '<html>502 Bad Gateway</html>',
      '[]',
      'null',
      '{}',
      '{"serial":1}',
      '{"flags":[]}',
      '{"flags":"stations_local"}',
    ]) {
      expect(() => FlagDoc.parse(body), returnsNormally, reason: body);
      expect(FlagDoc.parse(body), isNull, reason: '$body must leave the held document standing');
    }
  });
}
