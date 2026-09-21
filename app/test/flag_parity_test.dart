import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/flags/flags.dart';

/// #41: two vocabularies, one in Rust and one in Dart, with nothing generated in between.
///
/// The failure this catches is benign and confusing: `stellwerk` says a flag is on, the phone
/// reads false, and nothing anywhere says why — because the name the app asks about is not the
/// name the server publishes. Same class of bug as `station_parity_test.dart`, caught the same
/// way: by reading the other half's source.
///
/// `flutter test` runs with `app/` as the working directory.
void main() {
  final registry = File('../backend/src/flags.rs');

  if (!registry.existsSync()) {
    test('the two registries agree', () {
      markTestSkipped(
        'backend/src/flags.rs is not in the tree. While this skips, the Dart names have been '
        'checked against the specification and not against the backend, which is exactly the '
        'disagreement this test exists to find. It runs as soon as the registry lands.',
      );
    });
    return;
  }

  final source = registry.readAsStringSync();

  /// Every `pub static NAME: XFlag = XFlag { … };` block in the registry.
  final declarations = RegExp(r'pub\s+static\s+\w+\s*:\s*(\w+)\s*=\s*\w+\s*\{(.*?)\n\};', dotAll: true)
      .allMatches(source)
      .map((m) => (kind: m.group(1)!, body: m.group(2)!))
      .toList();

  test('flags.rs is still shaped the way this test reads it', () {
    // Everything below is a regex over somebody else's source, so it has to fail loudly when the
    // file is reshaped rather than quietly find nothing and pass.
    expect(declarations, isNotEmpty, reason: 'no `pub static … = …Flag { … };` block in backend/src/flags.rs');
    for (final d in declarations) {
      expect(RegExp(r'key:\s*"[a-z][a-z0-9_]*"').hasMatch(d.body), isTrue,
          reason: 'a ${d.kind} declaration with no `key:` — this test can no longer read the registry');
    }
  });

  test('every Dart flag is a flag the backend publishes', () {
    for (final flag in Flag.values) {
      expect(
        source.contains('"${flag.wire}"'),
        isTrue,
        reason: 'Flag.${flag.name} asks for "${flag.wire}", which backend/src/flags.rs never '
            'names — so the server will never publish it and the app will read false for ever',
      );
    }
  });

  test('every flag the backend puts on the wire is one this build can read', () {
    for (final d in declarations) {
      final key = RegExp(r'key:\s*"([a-z][a-z0-9_]*)"').firstMatch(d.body)!.group(1)!;
      final onTheWire = RegExp(r'wire:\s*true').hasMatch(d.body);
      if (!onTheWire) continue;

      // Dart's `Flag` is boolean-only, because `BoolFlag` is the only kind the registry has ever
      // held. A typed flag reaching the wire is not a bug in itself — it is the moment the Dart
      // side needs a typed API, and this is where that gets noticed instead of resolving to a
      // silent false on every phone.
      expect(d.kind, 'BoolFlag',
          reason: '$key is a ${d.kind} with wire: true, and app/lib/flags/flags.dart only reads '
              'booleans. Either take it off the wire or give Dart a typed flag.');
      expect(Flag.parse(key), isNotNull,
          reason: '$key is published to the app and no `Flag` reads it. Add it to '
              'app/lib/flags/flags.dart, or set `wire: false` if it is backend-only.');
    }
  });
}
