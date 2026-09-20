import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/repo/http_repository.dart';

/// The structural half of issue #39: **a release build has no path that asks the server where the
/// stations are.**
///
/// Everything else in this change is behaviour and can be argued about; this is the one property
/// the exercise stands or falls on, so it is checked over the source itself rather than over a
/// code path a test happened to take. `flutter test` runs with `app/` as the working directory.
void main() {
  test('the station endpoints are called from one file, and only behind the escape hatch', () {
    final offenders = <String>[];
    final callers = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!line.contains('stationsNearby') && !line.contains('stationsSearch')) continue;
        // `ApiClient`'s own definitions are the endpoints themselves; they stay on the wire
        // forever for build 64, which is in TestFlight and calls them.
        if (f.path.endsWith('api/client.dart')) continue;
        final where = '${f.path}:${i + 1}';
        callers.add(where);
        if (!f.path.endsWith('repo/http_repository.dart')) {
          offenders.add('$where — outside the one file that may call it');
        } else if (!line.contains('allowServerStations')) {
          offenders.add('$where — not on a line guarded by allowServerStations');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
    // If this drops to zero the guard has stopped guarding anything, which is its own kind of
    // wrong: the E2E and `stellwerk locate` need the rung to exist.
    expect(callers, hasLength(2), reason: callers.join('\n'));
  });

  test('the escape hatch is a compile-time constant that is closed by default', () {
    expect(HttpRepository.allowServerStations, isFalse);

    // And it is closed in a release build whatever the defines say. Reading the source is the
    // only way to assert this from a test, which never runs in release mode.
    final src = File('lib/repo/http_repository.dart').readAsStringSync();
    final decl = src.substring(src.indexOf('static const bool allowServerStations'));
    expect(decl, contains('!kReleaseMode'),
        reason: 'without this, a define passed to a store build would reopen the endpoint');
    expect(decl.substring(0, decl.indexOf(';')), contains('E2E'));
    expect(decl.substring(0, decl.indexOf(';')), contains('NO_LOCATION'));
  });

  test('nothing outside the stations package reaches for the extract by hand', () {
    // The store is the one thing that decides which copy of the table answers. A screen that read
    // an asset or a file itself would be a second, quieter copy of that decision.
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.contains('lib/stations/')) continue;
      final src = f.readAsStringSync();
      if (src.contains('stations.vst') || src.contains('StationExtract.decode')) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
