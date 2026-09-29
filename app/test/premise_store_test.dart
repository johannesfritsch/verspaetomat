import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/stations/premise_file.dart';
import 'package:verspaetomat/stations/premise_store.dart';
import 'package:verspaetomat/stations/station_download.dart';

import 'support/vsol_fixture.dart';

class _FakeDownload extends StationDownload {
  _FakeDownload(this.pointer, this.bytes);
  StationPointer pointer;
  Uint8List bytes;
  String? askedPath;
  int fileCalls = 0;
  bool notModified = false;

  @override
  Future<StationPointerResult> fetchPointer({String? etag, String path = StationDownload.pointerPath}) async {
    askedPath = path;
    if (notModified) return const StationPointerNotModified();
    return StationPointerFresh(pointer: pointer, etag: '"p${pointer.version}"');
  }

  @override
  Future<StationDownloadResult> fetchExtract(String url) async {
    fileCalls++;
    return StationDownloadFresh(bytes);
  }
}

StationPointer pointerFor(Uint8List b, int version, {int? count}) => StationPointer(
      version: version,
      format: 1,
      count: count ?? PremiseFile.decode(b).count,
      bytes: b.length,
      crc32: PremiseFile.decode(b).crc32,
      url: '/stations/umrisse-$version.bin',
    );

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('vsol_store_'));
  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  File onDisk() => File('${tmp.path}/stations/${PremiseStore.fileName}');

  test('installs the file the pointer names, where native reads it, and only once', () async {
    final b = buildVsol(count: 1200, version: 100);
    final dl = _FakeDownload(pointerFor(b, 100), b);
    final store = PremiseStore(download: dl, directory: () async => tmp);
    expect(await store.checkForUpdate(), isTrue);
    expect(dl.askedPath, PremiseStore.pointerPath);
    expect(store.version, 100);
    expect(onDisk().readAsBytesSync(), b);
    // Same version again: nothing downloaded.
    expect(await store.checkForUpdate(), isFalse);
    expect(dl.fileCalls, 1);
    // A fresh store reads what is on disk.
    expect(await PremiseStore(download: dl, directory: () async => tmp).load(), 100);
  });

  test('a gzipped body is stored unwrapped, because native reads plain bytes', () async {
    final b = buildVsol(count: 1200, version: 7);
    final dl = _FakeDownload(pointerFor(b, 7), Uint8List.fromList(gzip.encode(b)));
    final store = PremiseStore(download: dl, directory: () async => tmp);
    expect(await store.checkForUpdate(), isTrue);
    expect(onDisk().readAsBytesSync(), b);
  });

  test('a file that does not match its pointer, or is too small, is refused and nothing changes', () async {
    final good = buildVsol(count: 1200, version: 5);
    final store = PremiseStore(download: _FakeDownload(pointerFor(good, 5), good), directory: () async => tmp);
    await store.checkForUpdate();
    final other = buildVsol(count: 1200, version: 6);
    expect(await PremiseStore(download: _FakeDownload(pointerFor(other, 9), other), directory: () async => tmp).checkForUpdate(), isFalse);
    final tiny = buildVsol(count: 10, version: 8);
    expect(await PremiseStore(download: _FakeDownload(pointerFor(tiny, 8), tiny), directory: () async => tmp).checkForUpdate(), isFalse);
    expect(await PremiseStore(download: _FakeDownload(pointerFor(good, 5), good), directory: () async => tmp).load(), 5);
  });

  test('a damaged file on disk is deleted, and then there is none — the 300 m guard', () async {
    Directory('${tmp.path}/stations').createSync(recursive: true);
    onDisk().writeAsBytesSync([1, 2, 3]);
    final b = buildVsol(count: 1200, version: 1);
    final store = PremiseStore(download: _FakeDownload(pointerFor(b, 1), b), directory: () async => tmp);
    expect(await store.load(), isNull);
    expect(onDisk().existsSync(), isFalse);
  });
}
