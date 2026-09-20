import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/stations/station_download.dart';
import 'package:verspaetomat/stations/station_store.dart';

import 'support/vst_fixture.dart';

/// Which copy of the table wins, and what happens to a download that cannot be trusted.
///
/// The rule this file is really about: a valid-but-wrong extract reaches every phone at once, so
/// the store has floors (a version that must not go backwards, a count that must be plausible, a
/// checksum) and an hour's retry after anything it refused.
class _FakeDownload extends StationDownload {
  _FakeDownload({this.pointer, this.etag, this.bytes, this.pointerFails = false, this.extractFails = false});

  StationPointer? pointer;
  String? etag;
  Uint8List? bytes;
  bool pointerFails;
  bool extractFails;
  bool notModified = false;
  int pointerCalls = 0;
  int extractCalls = 0;

  @override
  Future<StationPointerResult> fetchPointer({String? etag}) async {
    pointerCalls++;
    if (pointerFails) return const StationDownloadFailed('offline');
    if (notModified) return const StationPointerNotModified();
    return StationPointerFresh(pointer: pointer!, etag: this.etag);
  }

  @override
  Future<StationDownloadResult> fetchExtract(String url) async {
    extractCalls++;
    if (extractFails) return const StationDownloadFailed('500');
    return StationDownloadFresh(bytes!);
  }
}

StationPointer pointerFor(Uint8List bytes, int version, {int count = 0, int crc = 0}) => StationPointer(
      version: version,
      format: 1,
      count: count,
      bytes: bytes.length,
      crc32: crc,
      url: '/stations/stations-$version.vst',
    );

void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('vst_store_'));
  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<Directory> dir() async => tmp;

  final assetBytes = buildVst(plausibleTable(count: 1200), version: 10);

  StationStore storeWith(StationDownload download, {Uint8List? asset, void Function()? onAsset}) => StationStore(
        download: download,
        directory: dir,
        asset: () async {
          onAsset?.call();
          final a = asset ?? assetBytes;
          return a;
        },
      );

  test('first launch answers from the asset, before the phone has ever been online', () async {
    final store = storeWith(_FakeDownload());
    final ix = await store.index();
    expect(ix, isNotNull);
    expect(store.sourceKind, StationSourceKind.asset);
    expect(store.tableVersion, 10);
    expect(ix!.extract.count, 1200);
  });

  test('two concurrent loads decode once', () async {
    var loads = 0;
    final store = storeWith(_FakeDownload(), onAsset: () => loads++);
    final both = await Future.wait([store.index(), store.index()]);
    expect(loads, 1);
    expect(identical(both[0], both[1]), isTrue);
    // And a third, after the first settled, is the cached one.
    expect(identical(await store.index(), both[0]), isTrue);
  });

  test('a newer download wins over the asset and survives the next load', () async {
    final newer = buildVst(plausibleTable(count: 1300), version: 11);
    final d = _FakeDownload(pointer: pointerFor(newer, 11), bytes: newer, etag: '"e1"');
    final store = storeWith(d);
    await store.index();
    expect(await store.checkForUpdate(), isTrue);
    expect(store.sourceKind, StationSourceKind.downloaded);
    expect(store.tableVersion, 11);
    expect(File('${tmp.path}/stations/${StationStore.fileName}').existsSync(), isTrue);

    // A fresh store over the same directory reads the file back.
    final again = storeWith(_FakeDownload());
    expect((await again.index())!.extract.tableVersion, 11);
    expect(again.sourceKind, StationSourceKind.downloaded);
  });

  test('a valid download always wins, whatever the two extracts say about themselves', () async {
    // **The regression this file exists for**, with the measured numbers: production's newest
    // committed import is id 1 and a laptop's is 7, and production's import also *finished*
    // earlier than the laptop's render. So both a serial comparison (`1 >= 7`) and a timestamp
    // comparison would drop the real download and pin every phone to the bundled snapshot —
    // silently, for years. The asset is not consulted at all.
    final fromProduction = buildVst(plausibleTable(count: 1300), version: 1, generatedAt: DateTime.utc(2026, 9, 12));
    final fromLaptop = buildVst(plausibleTable(count: 1200), version: 7, generatedAt: DateTime.utc(2026, 9, 20));
    await Directory('${tmp.path}/stations').create(recursive: true);
    await File('${tmp.path}/stations/${StationStore.fileName}').writeAsBytes(fromProduction);
    final store = storeWith(_FakeDownload(), asset: fromLaptop);
    await store.index();
    expect(store.sourceKind, StationSourceKind.downloaded,
        reason: 'neither the serial nor the clock may be compared across databases');
    expect(store.tableVersion, 1);
    expect((await store.index())!.extract.count, 1300);
  });

  test('the asset answers only when there is no valid download', () async {
    // The floor still holds: a download that fails validation is deleted and the asset takes over.
    await Directory('${tmp.path}/stations').create(recursive: true);
    await File('${tmp.path}/stations/${StationStore.fileName}')
        .writeAsBytes(buildVst(plausibleTable(count: 1300), version: 1, flipByteAfterCrc: 400));
    final store = storeWith(_FakeDownload());
    await store.index();
    expect(store.sourceKind, StationSourceKind.asset);
    expect(store.tableVersion, 10);
  });

  test('the pointer is not fetched twice inside the interval, and is after a failure', () async {
    final newer = buildVst(plausibleTable(count: 1300), version: 11);
    final d = _FakeDownload(pointer: pointerFor(newer, 11), bytes: newer);
    final store = storeWith(d);
    await store.index();
    await store.maybeCheckForUpdate();
    expect(d.pointerCalls, 1);
    await store.maybeCheckForUpdate();
    expect(d.pointerCalls, 1, reason: 'a week has not passed');

    // A failed check schedules the next one an hour out rather than a week.
    final meta = File('${tmp.path}/stations/${StationStore.metaName}');
    expect(meta.readAsStringSync(), contains('next_check_at'));
  });

  test('a 304 changes nothing but when we ask again', () async {
    final d = _FakeDownload()..notModified = true;
    final store = storeWith(d);
    await store.index();
    expect(await store.checkForUpdate(), isFalse);
    expect(d.extractCalls, 0);
    expect(store.sourceKind, StationSourceKind.asset);
    expect(store.tableVersion, 10);
  });

  test('with nothing on disk the pointer always wins, whatever number it carries', () async {
    // One download per install, and immunity to the whole cross-database class. A pointer at v1
    // against an asset at v7 must be taken, not skipped.
    final fromLaptop = buildVst(plausibleTable(count: 1200), version: 7, generatedAt: DateTime.utc(2026, 9, 20));
    final fromProduction = buildVst(plausibleTable(count: 1300), version: 1, generatedAt: DateTime.utc(2026, 9, 12));
    final d = _FakeDownload(pointer: pointerFor(fromProduction, 1), bytes: fromProduction);
    final store = storeWith(d, asset: fromLaptop);
    await store.index();
    expect(store.sourceKind, StationSourceKind.asset);
    expect(await store.checkForUpdate(), isTrue, reason: 'pointer v1 was refused against asset v7');
    expect(store.sourceKind, StationSourceKind.downloaded);
    expect(store.tableVersion, 1);

    // And once a copy of production's own numbering is on disk, the serial applies again —
    // because now both numbers come from the same database.
    expect(await store.checkForUpdate(), isFalse, reason: 'v1 is not newer than v1');
    expect(d.extractCalls, 1, reason: 'the second check cost a 200-byte pointer and nothing else');
  });

  group('a download that cannot be trusted is refused and the extract in hand stands', () {
    Future<void> refuses(Uint8List bad, int version, {int count = 0, int crc = 0}) async {
      final d = _FakeDownload(pointer: pointerFor(bad, version, count: count, crc: crc), bytes: bad);
      final store = storeWith(d);
      await store.index();
      expect(await store.checkForUpdate(), isFalse);
      expect(store.sourceKind, StationSourceKind.asset);
      expect(store.tableVersion, 10);
      expect(File('${tmp.path}/stations/${StationStore.fileName}').existsSync(), isFalse,
          reason: 'nothing was installed');
    }

    test('a table too small to be a country', () async {
      await refuses(buildVst(plausibleTable(count: 999), version: 11), 11);
    });

    test('a damaged file', () async {
      await refuses(buildVst(plausibleTable(count: 1300), version: 11, flipByteAfterCrc: 400), 11);
    });

    test('a file whose version does not match the pointer that named it', () async {
      await refuses(buildVst(plausibleTable(count: 1300), version: 4), 11);
    });

    test('a file whose count does not match the pointer', () async {
      await refuses(buildVst(plausibleTable(count: 1300), version: 11), 11, count: 7604);
    });

    test('a file whose checksum does not match the pointer', () async {
      await refuses(buildVst(plausibleTable(count: 1300), version: 11), 11, crc: 1);
    });

    test('a file whose decompressed size does not match the pointer', () async {
      // The size is checked after decompression, because `Content-Length` is the compressed
      // length whenever Caddy serves the `.gz` sibling and cannot be compared to `bytes`.
      final good = buildVst(plausibleTable(count: 1300), version: 11);
      final d = _FakeDownload(
        pointer: StationPointer(
            version: 11, format: 1, count: 0, bytes: good.length + 1, crc32: 0,
            url: '/stations/stations-11.vst'),
        bytes: good,
      );
      final store = storeWith(d);
      await store.index();
      expect(await store.checkForUpdate(), isFalse);
      expect(store.sourceKind, StationSourceKind.asset);
    });

    test('a download the website would not hand over', () async {
      final d = _FakeDownload(pointer: pointerFor(assetBytes, 11), extractFails: true);
      final store = storeWith(d);
      await store.index();
      expect(await store.checkForUpdate(), isFalse);
      expect(store.sourceKind, StationSourceKind.asset);
    });

    test('a website that is not there at all', () async {
      final store = storeWith(_FakeDownload(pointerFails: true));
      await store.index();
      expect(await store.checkForUpdate(), isFalse);
      expect(store.tableVersion, 10);
    });
  });

  test('a stored file that has gone bad is deleted, and the asset answers', () async {
    await Directory('${tmp.path}/stations').create(recursive: true);
    final f = File('${tmp.path}/stations/${StationStore.fileName}');
    await f.writeAsBytes(buildVst(plausibleTable(count: 1300), version: 11, flipByteAfterCrc: 400));
    final store = storeWith(_FakeDownload());
    expect((await store.index())!.extract.tableVersion, 10);
    expect(store.sourceKind, StationSourceKind.asset);
    expect(f.existsSync(), isFalse, reason: 'a file we cannot read would be retried every launch');
  });

  test('a stored file with too few stations is deleted, and the asset answers', () async {
    await Directory('${tmp.path}/stations').create(recursive: true);
    final f = File('${tmp.path}/stations/${StationStore.fileName}');
    await f.writeAsBytes(buildVst(plausibleTable(count: 12), version: 99));
    final store = storeWith(_FakeDownload());
    expect((await store.index())!.extract.tableVersion, 10);
    expect(f.existsSync(), isFalse);
  });

  test('a device with nowhere to write still answers from the asset', () async {
    final d = _FakeDownload();
    final store = StationStore(
      download: d,
      directory: () async => throw const FileSystemException('read-only'),
      asset: () async => assetBytes,
    );
    final ix = await store.index();
    expect(ix, isNotNull);
    expect(store.sourceKind, StationSourceKind.asset);
    // And the weekly check finds nothing to do rather than throwing into a lifecycle callback —
    // or fetching 280 kB on every foreground it could never store.
    await store.maybeCheckForUpdate();
    expect(d.pointerCalls, 0);
  });

  test('no asset and no download is an honest nothing, not a crash', () async {
    final store = StationStore(
      download: _FakeDownload(pointerFails: true),
      directory: dir,
      asset: () async => throw const FileSystemException('no such asset'),
    );
    expect(await store.index(), isNull);
    expect(store.sourceKind, StationSourceKind.none);
    expect(store.tableVersion, isNull);
  });

  test('a gzipped download installs, because the size checked is the decompressed one', () async {
    // The real server hands over gzip bytes; `decode` sniffs them and `byteLength` is the size of
    // the extract inside, which is the number the pointer carries.
    final raw = buildVst(plausibleTable(count: 1300), version: 11);
    final zipped = Uint8List.fromList(gzip.encode(raw));
    expect(zipped.length, lessThan(raw.length));
    final d = _FakeDownload(
      pointer: StationPointer(
          version: 11, format: 1, count: 1300, bytes: raw.length, crc32: 0,
          url: '/stations/stations-11.vst'),
      bytes: zipped,
    );
    final store = storeWith(d);
    await store.index();
    expect(await store.checkForUpdate(), isTrue);
    expect(store.tableVersion, 11);
    expect(store.sourceKind, StationSourceKind.downloaded);
    // And it reads back off disk on the next launch, still gzipped on disk.
    final again = storeWith(_FakeDownload());
    expect((await again.index())!.extract.tableVersion, 11);
  });

  test('the bundled asset path is the one the CLI writes', () {
    expect(StationStore.assetPath, 'assets/stations/stations.vst');
    expect(StationStore.checkEvery, const Duration(days: 7));
    expect(StationStore.retryAfter, const Duration(hours: 1));
    expect(StationStore.minPlausibleCount, 1000);
  });
}
