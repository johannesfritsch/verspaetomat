import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/flags/flag_doc.dart';
import 'package:verspaetomat/flags/flags.dart';

/// #41: how a flag resolves, and the one rule underneath all of it — **false is the behaviour
/// that already shipped**, and every way of not knowing produces it.
void main() {
  Flags withDoc(String body) => Flags(doc: FlagDoc.parse(body)!, confirmedAt: DateTime.now().toUtc());

  const f = Flag.stationsLocal;

  test('a flag is off until somebody says otherwise', () {
    expect(Flags.none.on(f), isFalse);
    expect(Flags.none.stateOf(f).source, FlagSource.shipped);
  });

  test('every way of not knowing is the same false', () {
    // No document at all — a phone that has never reached the server.
    expect(Flags.none.on(f), isFalse);
    // A document that mentions nothing, which is what the server publishes when nothing is on.
    expect(withDoc('{"flags":{}}').on(f), isFalse);
    // A document that mentions other flags only.
    expect(withDoc('{"flags":{"something_else":true}}').on(f), isFalse);
    // And all three say the same thing about where the answer came from.
    for (final flags in [Flags.none, withDoc('{"flags":{}}'), withDoc('{"flags":{"x":true}}')]) {
      expect(flags.stateOf(f).source, FlagSource.shipped);
    }
  });

  test('the absent key is the path every build takes every day', () {
    // The point of the design: the server sends a key only when it differs from the default, so
    // the fallback is not an untested branch that rots — it is the branch that always runs.
    final everyday = withDoc('{"flags":{}}');
    expect(everyday.doc.values.containsKey(f.wire), isFalse);
    expect(everyday.on(f), isFalse);
  });

  test('the server saying true is the only thing that turns it on', () {
    final flags = withDoc('{"flags":{"stations_local":true}}');
    expect(flags.on(f), isTrue);
    expect(flags.stateOf(f).source, FlagSource.server);
  });

  test('the server saying false says so, and is still false', () {
    final flags = withDoc('{"flags":{"stations_local":false}}');
    expect(flags.on(f), isFalse);
    expect(flags.stateOf(f).source, FlagSource.server);
  });

  test('a value this build cannot read is false, and says it cannot read it', () {
    // A flag that became an `int` or a `string` server-side while this build still reads
    // booleans. (A wrong-typed *row* never gets this far: `value_of` coerces it back to the
    // default, so the key is absent and reads as „Standard".) Answering false is right; answering
    // false *silently* is how „der Server sagt an, das Telefon sagt aus" becomes unanswerable.
    for (final body in ['{"flags":{"stations_local":90}}', '{"flags":{"stations_local":"ja"}}', '{"flags":{"stations_local":null}}']) {
      final flags = withDoc(body);
      expect(flags.on(f), isFalse, reason: body);
      expect(flags.stateOf(f).source, FlagSource.unreadable, reason: body);
    }
  });

  test('a pin beats the server, which is what makes a test about a flagged path not flaky', () {
    final flags = withDoc('{"flags":{}}').copyWith(pins: {Flag.stationsLocal: true});
    expect(flags.on(f), isTrue);
    expect(flags.stateOf(f).source, FlagSource.pinned);

    final off = withDoc('{"flags":{"stations_local":true}}').copyWith(pins: {Flag.stationsLocal: false});
    expect(off.on(f), isFalse, reason: 'pinning off is as explicit as pinning on');
  });

  test('a name the server publishes and this build does not know is reported, not obeyed', () {
    final flags = withDoc('{"flags":{"stations_local":true,"etwas_neues":true}}');
    expect(flags.unknownNames, ['etwas_neues']);
    expect(flags.onNames, ['stations_local'], reason: 'a flag with no code behind it turns nothing on');
  });

  test('the enum is the only key there is', () {
    expect(Flag.parse('stations_local'), Flag.stationsLocal);
    expect(Flag.parse('stations-local'), Flag.stationsLocal, reason: 'stellwerk spells it with a dash');
    expect(Flag.parse('stations_lokal'), isNull, reason: 'a typo is not a flag');
    expect(Flag.parse(''), isNull);
    for (final flag in Flag.values) {
      expect(flag.about, isNotEmpty, reason: '${flag.name} has nothing to tell the operator');
      expect(flag.wire, matches(RegExp(r'^[a-z][a-z0-9_]*$')), reason: '${flag.name} is not a wire name');
    }
  });

  test('sameAnswersAs is what stops a 304 every half hour rebuilding the tree', () {
    final a = withDoc('{"flags":{"stations_local":true}}');
    expect(a.sameAnswersAs(a.copyWith(confirmedAt: DateTime.now().toUtc())), isTrue,
        reason: 'a fresh confirmation of the same document is not news');
    expect(a.sameAnswersAs(withDoc('{"flags":{}}')), isFalse);
    expect(a.sameAnswersAs(a.copyWith(pins: {Flag.stationsLocal: false})), isFalse);
    // Same answer, different reason: still worth telling the page about.
    expect(
      withDoc('{"flags":{}}').sameAnswersAs(withDoc('{"flags":{"stations_local":false}}')),
      isFalse,
    );
  });
}
