import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../platform/diagnose_log.dart';
import 'premise_file.dart';
import 'station_download.dart';
import 'station_extract.dart' show ExtractFormatException;

/// Keeps the station premises on disk (issue #64, docs/48), where the native geofence layer reads
/// them: `<Application Support>/stations/umrisse.bin`, beside the station extract.
///
/// Built like [StationStore] and deliberately simpler. There is **no bundled copy**: without a
/// premise file the phone watches the 300 m circles it always did, so a phone that has never been
/// online loses nothing. The serial is compared in one place only — the website's pointer against
/// the copy we downloaded — because both come from the same server.
///
/// The website serves the file from the API's memory (`/stations/umrisse-latest.json`, then
/// `/stations/umrisse-<version>.bin`), not from the repo; the request carries no token and no
/// position, like the extract's.
class PremiseStore {
  PremiseStore({StationDownload? download, Future<Directory> Function()? directory})
      : _download = download ?? StationDownload(),
        _directory = directory ?? getApplicationSupportDirectory;

  final StationDownload _download;
  final Future<Directory> Function() _directory;

  static const String pointerPath = '/stations/umrisse-latest.json';

  /// The native layer reads this name (`Geofence.swift`, `GeofenceManager.kt`).
  static const String fileName = 'umrisse.bin';
  static const String metaName = 'umrisse.meta.json';
  static const Duration checkEvery = Duration(days: 7);
  static const Duration retryAfter = Duration(hours: 1);

  /// The table has held over 6,000 premises since the first import; a file far smaller is a
  /// mistake upstream, not a smaller Germany.
  static const int minPlausibleCount = 1000;

  int? _version;
  bool _loaded = false;
  _Meta? _meta;
  bool _metaRead = false;

  /// The version of the file on disk, or null when there is none. The geofence sync sends it to
  /// native, so a new file re-registers the regions.
  int? get version => _version;

  /// Reads the file on disk once, so [version] is known. A file that does not read is deleted:
  /// kept, it would be retried on every launch and native would trip over it on every wake.
  Future<int?> load() async {
    if (_loaded) return _version;
    _loaded = true;
    final file = await _file();
    if (file == null || !file.existsSync()) return null;
    try {
      final read = PremiseFile.decode(await file.readAsBytes());
      if (read.count < minPlausibleCount) throw ExtractFormatException('${read.count} Gelände sind zu wenige');
      _version = read.version;
      DiagnoseLog.instance.add('gelaende', 'v${read.version} · ${read.count} Gelände');
    } catch (e) {
      DiagnoseLog.instance.add('gelaende', 'Datei verworfen · ${_why(e)}', bad: true);
      try {
        await file.delete();
      } catch (_) {}
      _version = null;
    }
    return _version;
  }

  Future<void> maybeCheckForUpdate() async {
    if (await _dir() == null) return;
    final next = (await _readMeta())?.nextCheckAt;
    if (next != null && DateTime.now().toUtc().isBefore(next)) return;
    await checkForUpdate();
  }

  /// True when a newer file was installed.
  Future<bool> checkForUpdate() async {
    await load();
    final meta = await _readMeta();
    final result = await _download.fetchPointer(etag: meta?.etag, path: pointerPath);
    switch (result) {
      case StationPointerNotModified():
        await _touch(nextIn: checkEvery);
        return false;
      case StationDownloadFailed(reason: final reason):
        DiagnoseLog.instance.add('gelaende', 'update failed · $reason', bad: true);
        await _touch(nextIn: retryAfter);
        return false;
      case StationPointerFresh(pointer: final pointer, etag: final etag):
        final held = _version;
        if (held != null && pointer.version <= held) {
          await _touch(nextIn: checkEvery, etag: etag);
          return false;
        }
        return _install(pointer, etag);
    }
  }

  Future<bool> _install(StationPointer pointer, String? etag) async {
    final got = await _download.fetchExtract(pointer.url);
    if (got is StationDownloadFailed) {
      DiagnoseLog.instance.add('gelaende', 'update failed · ${got.reason}', bad: true);
      await _touch(nextIn: retryAfter);
      return false;
    }
    final bytes = (got as StationDownloadFresh).bytes;
    final PremiseFile read;
    try {
      read = PremiseFile.decode(bytes);
      final reason = _refuse(read, pointer);
      if (reason != null) throw ExtractFormatException(reason);
    } catch (e) {
      DiagnoseLog.instance.add('gelaende', 'update verworfen · ${_why(e)}', bad: true);
      await _touch(nextIn: retryAfter);
      return false;
    }
    final file = await _file();
    if (file == null) {
      await _touch(nextIn: retryAfter);
      return false;
    }
    try {
      // Aside, then renamed: native never sees half a file, because the rename is the commit.
      final part = File('${file.path}.part');
      // Native reads the plain bytes; a gzipped body is unwrapped by the decoder, not on disk.
      await part.writeAsBytes(_plain(bytes, read), flush: true);
      await part.rename(file.path);
    } catch (e) {
      DiagnoseLog.instance.add('gelaende', 'update nicht gespeichert · ${_why(e)}', bad: true);
      await _touch(nextIn: retryAfter);
      return false;
    }
    _version = read.version;
    await _writeMeta(_Meta(etag: etag, nextCheckAt: DateTime.now().toUtc().add(checkEvery)));
    DiagnoseLog.instance.add('gelaende', 'update → v${read.version} · ${read.count} Gelände · ${(read.byteLength / 1024).round()} kB');
    return true;
  }

  /// The bytes native reads: never gzipped. [PremiseFile.decode] has already unwrapped and checked
  /// a gzip body; what goes on disk is the same unwrapped bytes.
  List<int> _plain(List<int> bytes, PremiseFile read) {
    if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) return gzip.decode(bytes);
    return bytes;
  }

  String? _refuse(PremiseFile read, StationPointer pointer) {
    if (read.count < minPlausibleCount) return '${read.count} Gelände sind zu wenige';
    if (read.version != pointer.version) return 'Datei v${read.version} passt nicht zum Zeiger v${pointer.version}';
    if (pointer.crc32 != 0 && read.crc32 != pointer.crc32) return 'CRC passt nicht zum Zeiger';
    if (pointer.count != 0 && read.count != pointer.count) return 'Anzahl passt nicht zum Zeiger';
    if (pointer.bytes != 0 && read.byteLength != pointer.bytes) return '${read.byteLength} Bytes statt ${pointer.bytes} laut Zeiger';
    final held = _version;
    if (held != null && read.version < held) return 'Datei v${read.version} ist älter als v$held';
    return null;
  }

  Directory? _dirCache;
  bool _dirTried = false;

  Future<Directory?> _dir() async {
    if (_dirTried) return _dirCache;
    _dirTried = true;
    try {
      final base = await _directory();
      final dir = Directory('${base.path}/stations');
      if (!dir.existsSync()) await dir.create(recursive: true);
      _dirCache = dir;
    } catch (e) {
      DiagnoseLog.instance.add('gelaende', 'kein Ablageort · ${_why(e)}', bad: true);
    }
    return _dirCache;
  }

  Future<File?> _file() async {
    final dir = await _dir();
    return dir == null ? null : File('${dir.path}/$fileName');
  }

  Future<_Meta?> _readMeta() async {
    if (_metaRead) return _meta;
    _metaRead = true;
    final dir = await _dir();
    if (dir == null) return null;
    try {
      final f = File('${dir.path}/$metaName');
      if (f.existsSync()) _meta = _Meta.fromJson(jsonDecode(await f.readAsString()));
    } catch (_) {}
    return _meta;
  }

  Future<void> _writeMeta(_Meta meta) async {
    _meta = meta;
    _metaRead = true;
    final dir = await _dir();
    if (dir == null) return;
    try {
      await File('${dir.path}/$metaName').writeAsString(jsonEncode(meta.toJson()), flush: true);
    } catch (_) {}
  }

  Future<void> _touch({required Duration nextIn, String? etag}) async {
    final old = await _readMeta();
    await _writeMeta(_Meta(etag: etag ?? old?.etag, nextCheckAt: DateTime.now().toUtc().add(nextIn)));
  }

  static String _why(Object e) => e is ExtractFormatException ? e.message : e.toString().split('\n').first;
}

class _Meta {
  const _Meta({this.etag, this.nextCheckAt});
  final String? etag;
  final DateTime? nextCheckAt;

  static _Meta? fromJson(Object? j) {
    if (j is! Map) return null;
    return _Meta(etag: j['etag'] as String?, nextCheckAt: DateTime.tryParse('${j['next_check_at']}'));
  }

  Map<String, dynamic> toJson() => {
        if (etag != null) 'etag': etag,
        if (nextCheckAt != null) 'next_check_at': nextCheckAt!.toIso8601String(),
      };
}
