import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/stations/station_extract.dart';
import 'package:verspaetomat/stations/station_index.dart';
import 'package:verspaetomat/stations/station_store.dart';

/// The Dart reader against `testdata/stations/nearby-probes.tsv` (issue #40's fixture).
///
/// `station_parity_test.dart` proves this reader agrees with the format and with itself. This one
/// proves it agrees with **`stations::Index::nearby`**, because the fixture is generated from the
/// Rust the server answers with — so a regression here cannot hide behind a reference that
/// regressed with it. Swift and Kotlin assert against the same file, which is what stops four
/// readings of one ordering becoming four orderings.
///
/// `flutter test` runs with `app/` as the working directory.
void main() {
  final fixture = File('../testdata/stations/nearby-probes.tsv');
  final asset = File('assets/stations/${StationStore.fileName}');

  if (!fixture.existsSync() || !asset.existsSync()) {
    test('the Dart reader answers what Index::nearby answers', () {
      markTestSkipped(
        'testdata/stations/nearby-probes.tsv or the bundled extract is missing. Regenerate with '
        '`cd backend && cargo test --release --lib write_the_nearby_probe_fixture -- --ignored`.',
      );
    });
    return;
  }

  late StationIndex ix;
  late List<String> lines;

  setUpAll(() {
    ix = StationIndex(StationExtract.decode(asset.readAsBytesSync()));
    lines = fixture.readAsLinesSync();
  });

  test('the fixture was generated from the extract this build bundles', () {
    // `crc32` covers `[header_len, EOF)`, so it identifies the table without moving with the
    // import serial or the timestamp — the three numbers that cannot order extracts are also the
    // three that cannot identify one. A fixture left behind by an older table fails here rather
    // than quietly testing the wrong file.
    final header = lines.firstWhere((l) => l.contains('crc32='), orElse: () => '');
    expect(header, isNotEmpty, reason: 'no crc32 line in the fixture');
    final crc = RegExp(r'crc32=0x([0-9a-fA-F]+)').firstMatch(header)!.group(1)!;
    final count = int.parse(RegExp(r'count=(\d+)').firstMatch(header)!.group(1)!);
    expect(int.parse(crc, radix: 16), ix.extract.crc32);
    expect(count, ix.extract.count);
  });

  test('the Dart reader answers what Index::nearby answers, on every probe', () {
    // Parsed by column **name**, off the line that names them, found by content. The fixture has
    // been revised once already; a positional parser would have read one column as another and
    // asserted on it without noticing.
    final headerLine = lines.firstWhere(
      (l) => l.startsWith('#') && l.contains('lat') && l.contains('search_radius_m') && l.contains('ids'),
      orElse: () => '',
    );
    expect(headerLine, isNotEmpty, reason: 'no column-name line in the fixture');
    final cols = headerLine.replaceFirst('#', '').trim().split(RegExp(r'\s+'));
    expect(cols, containsAll(['lat', 'lon', 'limit', 'search_radius_m', 'complete', 'ids']));

    final wrong = <String>[];
    var checked = 0;
    for (final line in lines) {
      if (line.startsWith('#') || line.trim().isEmpty) continue;
      final fields = line.split('\t');
      final row = {for (var i = 0; i < cols.length && i < fields.length; i++) cols[i]: fields[i]};
      final where = '${row['lat']},${row['lon']} limit ${row['limit']} (${row['label'] ?? ''})';

      final near = ix.nearby(
        lat: double.parse(row['lat']!),
        lon: double.parse(row['lon']!),
        limit: int.parse(row['limit']!),
      );
      // Bare record ids in the answer's order: the wire's `vs:` prefix has no business in a
      // fixture four languages read.
      final got = near.stations.map((s) => s.id.substring(3)).join(',');
      if (got != row['ids']) wrong.add('ids at $where\n  want ${row['ids']}\n  got  $got');
      if (near.searchRadiusM != int.parse(row['search_radius_m']!)) {
        wrong.add('search_radius_m at $where: want ${row['search_radius_m']}, got ${near.searchRadiusM}');
      }
      if (near.complete != (row['complete'] == '1')) {
        wrong.add('complete at $where: want ${row['complete']}, got ${near.complete}');
      }
      checked++;
    }
    expect(checked, greaterThan(100), reason: 'the fixture parsed as almost no rows');
    expect(wrong, isEmpty, reason: wrong.take(8).join('\n'));
  });
}
