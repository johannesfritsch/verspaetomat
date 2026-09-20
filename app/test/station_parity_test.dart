import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/stations/station_extract.dart';
import 'package:verspaetomat/stations/station_index.dart';
import 'package:verspaetomat/stations/station_rules.dart';
import 'package:verspaetomat/stations/station_download.dart';
import 'package:verspaetomat/stations/station_store.dart';

/// No network in a unit test: any rung that tried would fail loudly rather than pass quietly.
class _NoDownload extends StationDownload {
  @override
  Future<StationPointerResult> fetchPointer({String? etag}) async => const StationDownloadFailed('no network in a unit test');
  @override
  Future<StationDownloadResult> fetchExtract(String url) async => const StationDownloadFailed('no network in a unit test');
}

/// The website, answering with bytes taken off disk.
class _CannedDownload extends StationDownload {
  _CannedDownload({required this.pointer, required this.bytes});
  final StationPointer pointer;
  final Uint8List bytes;
  @override
  Future<StationPointerResult> fetchPointer({String? etag}) async =>
      StationPointerFresh(pointer: pointer, etag: '"dlketfybpe2t35ls"');
  @override
  Future<StationDownloadResult> fetchExtract(String url) async {
    expect(url, pointer.url);
    return StationDownloadFresh(bytes);
  }
}

/// The acceptance of issue #39, over the extract that actually ships.
///
/// Everything else in `test/station_*` runs against fixtures this repository writes itself, which
/// proves the reader agrees with our reading of the format. This file is the one that reads the
/// bytes the backend produced, and it is where a disagreement between the two halves shows up.
///
/// `flutter test` runs with `app/` as the working directory.
File? findExtract() {
  final candidates = <String>[
    'assets/stations/${StationStore.fileName}',
    'assets/stations/stations.vst',
    '../site/static/stations/stations.vst',
  ];
  for (final p in candidates) {
    final f = File(p);
    if (f.existsSync()) return f;
  }
  for (final dir in ['../site/static/stations', '../site/dist/stations']) {
    final d = Directory(dir);
    if (!d.existsSync()) continue;
    final versioned = d
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.vst'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (versioned.isNotEmpty) return versioned.last;
  }
  return null;
}

void main() {
  final file = findExtract();

  if (file == null) {
    test('the shipped extract is read by the shipped reader', () {
      markTestSkipped(
        'No station extract in the tree. This test is the only one that reads bytes the backend '
        'wrote rather than bytes this repository wrote, so while it skips, the reader has been '
        'checked against the format spec and not against the format. Drop the file at '
        'app/assets/stations/stations.vst (and add it to pubspec.yaml) and it runs.',
      );
    });
    return;
  }

  late StationExtract extract;
  late StationIndex ix;

  setUpAll(() {
    extract = StationExtract.decode(file.readAsBytesSync());
    ix = StationIndex(extract);
  });

  test('it is the format this reader was written for', () {
    expect(extract.formatVersion, StationExtract.supportedFormatVersion);
    expect(extract.headerLen, greaterThanOrEqualTo(StationExtract.minHeaderLen));
    expect(extract.recordLen, greaterThanOrEqualTo(StationExtract.minRecordLen));
    expect(extract.tableVersion, greaterThan(0), reason: 'a version-0 extract must never be published');
    expect(extract.generatedAt.isAfter(DateTime.utc(2025)), isTrue);
    // The checksum was already verified by `decode`; this is the table being a table.
    expect(extract.count, greaterThan(7000), reason: 'the table has held over 7,000 stations since #37');
    expect(extract.count, greaterThanOrEqualTo(StationStore.minPlausibleCount));
  });

  test('the records are in ascending id order, which both sorts depend on', () {
    for (var i = 1; i < extract.count; i++) {
      expect(extract.ids[i], greaterThan(extract.ids[i - 1]),
          reason: 'record $i (id ${extract.ids[i]}) does not follow ${extract.ids[i - 1]}');
    }
  });

  test('every station is on this planet and has a name', () {
    for (var i = 0; i < extract.count; i++) {
      expect(extract.lat[i], inInclusiveRange(-90, 90));
      expect(extract.lon[i], inInclusiveRange(-180, 180));
      expect(extract.names[i], isNotEmpty);
      expect(extract.rank[i], inInclusiveRange(0, 3));
    }
  });

  test('the baked looks_like_station bit is what our port says it is', () {
    // The ranking reads the flag rather than the name, so if the two ever disagreed the phone
    // would rank by one rule and the server by another and nothing would say so.
    final wrong = <String>[];
    for (var i = 0; i < extract.count; i++) {
      if (extract.namedLikeStation(i) != looksLikeStation(extract.names[i])) {
        wrong.add('${extract.names[i]} — flag ${extract.namedLikeStation(i)}');
      }
    }
    expect(wrong, isEmpty, reason: wrong.take(10).join('\n'));
    // And it is a live tiebreak rather than a constant.
    final named = List.generate(extract.count, (i) => extract.namedLikeStation(i)).where((b) => b).length;
    expect(named, greaterThan(500));
    expect(named, lessThan(extract.count - 500));
  });

  test('UTF-16 and UTF-8 name order agree over every real name', () {
    // `search` sorts by name; Rust compares UTF-8 bytes and Dart UTF-16 code units. This is the
    // assumption checked against the whole table rather than against a handful of umlauts.
    final wrong = <String>[];
    for (var i = 1; i < extract.count; i++) {
      final a = extract.names[i - 1];
      final b = extract.names[i];
      final byUnits = a.compareTo(b);
      final byBytes = _compareUtf8(a, b);
      if (byUnits.sign != byBytes.sign) wrong.add('$a vs $b');
    }
    expect(wrong, isEmpty, reason: wrong.take(10).join('\n'));
  });

  test('a station standing on its own coordinate finds itself at nought metres', () {
    final rnd = math.Random(39);
    for (var n = 0; n < 300; n++) {
      final i = rnd.nextInt(extract.count);
      final near = ix.nearby(lat: extract.lat[i], lon: extract.lon[i], limit: kNearbyLimitMax);
      expect(near.complete, isTrue);
      final self = near.stations.where((s) => s.id == wireStationId(extract.ids[i]));
      expect(self, isNotEmpty, reason: '${extract.names[i]} did not find itself');
      expect(self.first.distanceM, 0);
    }
  });

  test('a passenger near a station gets a complete answer, and the radius is the last one', () {
    // 300 probes at a random bearing and up to 1.5 km out, the shape of standing near a station.
    final rnd = math.Random(3939);
    for (var n = 0; n < 300; n++) {
      final i = rnd.nextInt(extract.count);
      final bearing = rnd.nextDouble() * 2 * math.pi;
      final metres = rnd.nextDouble() * 1500;
      final dLat = metres * math.cos(bearing) / 111320.0;
      final dLon = metres * math.sin(bearing) / (111320.0 * math.cos(extract.lat[i] * math.pi / 180));
      final near = ix.nearby(lat: extract.lat[i] + dLat, lon: extract.lon[i] + dLon);
      expect(near.complete, isTrue);
      expect(near.stations, isNotEmpty);
      expect(near.searchRadiusM, near.stations.map((s) => s.distanceM!).reduce(math.max));
      // The answer is ranked, not sorted: every station in it is inside the scan.
      for (final s in near.stations) {
        expect(s.distanceM, lessThanOrEqualTo(kNearbyMaxM.round()));
      }
    }
  });

  test('somewhere with no station within fifty kilometres is an honest empty answer', () {
    // Not Paris: the table is not German-only — the Transitous feeds carry international
    // long-distance stops, and a Paris query really does return Paris Gare de Lyon. These three
    // are genuinely empty.
    for (final probe in [
      (40.4168, -3.7038, 'Madrid'),
      (54.5000, 4.0000, 'North Sea'),
      (48.0000, -5.0000, 'Atlantic'),
    ]) {
      final near = ix.nearby(lat: probe.$1, lon: probe.$2);
      expect(near.stations, isEmpty, reason: probe.$3);
      expect(near.complete, isFalse, reason: '${probe.$3}: an empty answer is never complete');
      expect(near.searchRadiusM, 0, reason: probe.$3);
    }
  });

  test('the table is not German-only, which is what keeps `complete` honest', () {
    // The cheapest guard against someone filtering a future import to a German bounding box and
    // silently changing what an empty answer means.
    final paris = ix.nearby(lat: 48.8566, lon: 2.3522);
    expect(paris.stations, isNotEmpty, reason: 'Paris Est and Paris Gare de Lyon are in the table');
    expect(paris.complete, isTrue);
  });

  test('the stations a person would actually look for are there and are named right', () {
    // By name and distance rather than by id: ids move with every import, and a test that
    // hardcoded them would fail on the next one for no reason worth knowing about.
    for (final probe in [
      (48.1402, 11.5600, 'München Hbf'),
      (50.9430, 6.9586, 'Köln Hbf'),
      (52.5251, 13.3694, 'Berlin'),
      (47.7914, 9.8921, 'Kißlegg'),
    ]) {
      final near = ix.nearby(lat: probe.$1, lon: probe.$2);
      expect(near.stations, isNotEmpty, reason: probe.$3);
      expect(near.stations.first.name, contains(probe.$3), reason: 'at ${probe.$1}, ${probe.$2}');
      expect(near.stations.first.id, startsWith('vs:'));
      expect(near.searchRadiusM, greaterThanOrEqualTo(near.stations.first.distanceM!));
    }
  });

  test('the search finds what the Bahnsteig search field is typed at', () {
    for (final q in ['köln', 'Köln Hbf', 'berlin haupt', 'berlin hbf', 'münch', 'kiss', 'hbf']) {
      expect(ix.search(q), isNotEmpty, reason: '„$q" found nothing');
      expect(ix.search(q).length, lessThanOrEqualTo(kSearchResults));
    }
    expect(ix.search(''), isEmpty);
    expect(ix.search('köln').first.name, contains('Köln'));
    // Both folds, on the real names: the feed spells one of these out and the other short.
    expect(ix.search('Berlin Hauptbahnhof'), isNotEmpty);
    expect(ix.search('Berlin Hbf'), isNotEmpty);
  });

  test('the store finds the real asset through the bundle, which is the pubspec wiring', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Only the download is faked. The asset comes through `rootBundle` and the directory through
    // `path_provider`, which has no platform channel here — so this also exercises the fallback
    // that has to keep `index()` answering on a device with nowhere to write.
    final store = StationStore(download: _NoDownload());
    final ix = await store.index();
    expect(ix, isNotNull, reason: 'assets/stations/stations.vst is not in pubspec.yaml');
    expect(store.sourceKind, StationSourceKind.asset);
    expect(ix!.extract.count, greaterThan(7000));
    expect(store.tableVersion, greaterThan(0));
    expect(ix.nearby(lat: 50.9430, lon: 6.9586).stations.first.name, contains('Köln'));
  });

  test('the real extract installs through the download path, gzipped or not', () async {
    // The last mile: the pointer, the transfer and the install, over the real bytes. Both cases
    // the wire can produce are covered — the HTTP client decompressed a `Content-Encoding: gzip`
    // response, or it handed the gzip straight through — because which one happens depends on
    // headers the app does not control.
    final raw = file.readAsBytesSync();
    final real = StationExtract.decode(raw);
    final gz = Uint8List.fromList(gzip.encode(raw));
    final pointer = StationPointer(
      version: real.tableVersion,
      format: real.formatVersion,
      count: real.count,
      bytes: real.byteLength,
      crc32: real.crc32,
      url: '/stations/stations-${real.tableVersion}.vst',
    );
    for (final body in [raw, gz]) {
      final tmp = await Directory.systemTemp.createTemp('vst_wire_');
      final store = StationStore(
        download: _CannedDownload(pointer: pointer, bytes: body),
        directory: () async => tmp,
        // An older build than the published table, so the download is the one that wins.
        asset: () async => throw const FileSystemException('pretend an older build'),
      );
      expect(await store.checkForUpdate(), isTrue, reason: 'the real extract was refused');
      expect(store.sourceKind, StationSourceKind.downloaded);
      final ix = (await store.index())!;
      expect(ix.extract.count, real.count);
      expect(ix.extract.crc32, real.crc32);
      expect(ix.extract.byteLength, real.byteLength);
      expect(ix.nearby(lat: 50.9430, lon: 6.9586).stations.first.name, contains('Köln'));
      await tmp.delete(recursive: true);
    }
  });

  test('a cold load of the real table is fast enough to sit on the launch path', () {
    final bytes = file.readAsBytesSync();
    final sw = Stopwatch()..start();
    final x = StationExtract.decode(bytes);
    final decodeMs = sw.elapsedMilliseconds;
    sw.reset();
    StationIndex(x).nearby(lat: 50.9430, lon: 6.9586);
    final scanMs = sw.elapsedMilliseconds;
    // Generous: this is the JIT VM on a laptop and the budget for a cold AOT mid-range Android
    // core is about three times the measurement. It is here to catch an order of magnitude, not
    // to police milliseconds.
    expect(decodeMs, lessThan(400), reason: 'decode took $decodeMs ms');
    expect(scanMs, lessThan(200), reason: 'the nearby scan took $scanMs ms');
  });
}

int _compareUtf8(String a, String b) {
  final x = a.runes.toList();
  final y = b.runes.toList();
  // For every code point below U+10000 the UTF-8 byte order is the code point order; above it,
  // UTF-8 keeps sorting by code point while UTF-16 does not. Comparing code points is therefore
  // the UTF-8 order.
  for (var i = 0; i < x.length && i < y.length; i++) {
    if (x[i] != y[i]) return x[i] - y[i];
  }
  return x.length - y.length;
}
