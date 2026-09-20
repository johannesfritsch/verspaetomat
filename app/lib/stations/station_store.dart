import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../platform/diagnose_log.dart';
import 'station_download.dart';
import 'station_extract.dart';
import 'station_index.dart';

/// Which copy of the table the app is answering from.
enum StationSourceKind { none, asset, downloaded }

/// Holds the one [StationIndex] the app uses and decides which copy of the extract it is built
/// from (issue #39). One per `HttpRepository`; Demo never touches it.
///
/// Two copies exist, and they are not peers. **The download always wins once it validates; the
/// bundled asset is the cold-start floor and never a thing to beat.** It is the reason a phone
/// knows where the stations are before it has ever been online, and that is its whole job.
///
/// The asset is never compared with anything, on any axis, because nothing about it is
/// comparable. Its `version` is a `station_imports` id, meaningful only inside the database that
/// issued it — production's newest committed import is id 1 while a laptop's is 7, so
/// „keep the download when `downloaded.version >= asset.version`" reads `1 >= 7`, drops every
/// real download, and pins the phone to the bundled snapshot for years without a word in the log.
/// Its `generatedAt` is no better: it is when *that* database's import finished, and a laptop's
/// render today is newer by the clock than production's import from last week. Two axes, the same
/// silent failure.
///
/// So the serial is compared in exactly one place — the website's pointer against the copy we
/// downloaded — where both numbers come from the same database and the comparison means
/// something. With nothing on disk the pointer always wins, which costs one download per install
/// and buys immunity to the whole class.
///
/// **An extract is a snapshot.** A station retired after it was built stays in the phone's copy
/// until the next refresh, which may be months — the table is cut about twice a year and this
/// checks weekly, so a phone that is rarely online can offer a station that has closed. Ids are
/// never reused, so the failure is always „this station is gone", never „this is a different
/// station".
class StationStore {
  StationStore({
    StationDownload? download,
    Future<Directory> Function()? directory,
    Future<Uint8List> Function()? asset,
  })  : _download = download ?? StationDownload(),
        _directory = directory ?? getApplicationSupportDirectory,
        _asset = asset ?? _loadBundledAsset;

  final StationDownload _download;
  final Future<Directory> Function() _directory;
  final Future<Uint8List> Function() _asset;

  /// The copy that ships with the build. Raw `.vst`, as `stellwerk stations extract --asset`
  /// writes it.
  static const String assetPath = 'assets/stations/stations.vst';
  static const String fileName = 'stations.vst';
  static const String metaName = 'stations.meta.json';

  /// The happy cadence. The table moves about twice a year; a week is already far more often
  /// than it needs to be, and it costs one conditional GET of a 200-byte pointer.
  static const Duration checkEvery = Duration(days: 7);

  /// After a rejected or failed download, so a bad file published on the website is replaced
  /// within an hour rather than within a week. A valid-but-wrong extract reaches every phone at
  /// once and this is what bounds how long it stays there.
  static const Duration retryAfter = Duration(hours: 1);

  /// A truncated-but-structurally-valid extract is not an extract. The table has held over 7,000
  /// stations since #37, so anything this small is a mistake somewhere upstream, not a smaller
  /// Germany.
  static const int minPlausibleCount = 1000;

  StationIndex? _index;
  StationSourceKind _sourceKind = StationSourceKind.none;
  Future<StationIndex?>? _loading;
  _Meta? _meta;
  bool _metaRead = false;

  /// The `version` of the copy on disk, or null when there is none.
  ///
  /// Kept apart from [tableVersion] on purpose: this one is the only serial that may ever be
  /// compared with the website's pointer, because the two come from the same database. The
  /// asset's serial is never comparable with anything.
  int? _downloadedVersion;

  StationIndex? get indexOrNull => _index;
  StationSourceKind get sourceKind => _sourceKind;
  int? get tableVersion => _index?.extract.tableVersion;

  /// Loads once and caches. Concurrent callers share the one in-flight future, the way
  /// `NearbyMonitor.refresh` shares `_inFlight` (app/lib/state/nearby_monitor.dart:184) — two
  /// screens asking at the same moment must not decode the table twice.
  Future<StationIndex?> index() {
    final cached = _index;
    if (cached != null) return Future<StationIndex?>.value(cached);
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<StationIndex?> _load() async {
    final started = DateTime.now();
    StationExtract? downloaded;
    final file = await _extractFile();
    if (file != null && file.existsSync()) {
      try {
        final read = StationExtract.decode(await file.readAsBytes());
        if (read.count < minPlausibleCount) {
          throw ExtractFormatException('${read.count} stations is fewer than $minPlausibleCount');
        }
        downloaded = read;
        _downloadedVersion = read.tableVersion;
      } catch (e) {
        // A file we cannot read is worse than no file: it would be retried on every launch.
        await _discardDownload('der Auszug ist unbrauchbar: ${_why(e)}');
      }
    }

    StationExtract? asset;
    try {
      asset = StationExtract.decode(await _asset());
    } catch (e) {
      // Bundled, so this can only mean the build is broken or the asset was never committed. The
      // downloaded copy may still answer.
      DiagnoseLog.instance.add('stations', 'asset nicht lesbar · ${_why(e)}', bad: true);
    }

    // A download that got this far has passed every floor there is — magic, format, lengths,
    // checksum, a plausible count, and the pointer's own version, count and size. That is what
    // „valid" means here, and a valid download is by construction the table the website is
    // publishing. It wins. The asset is not consulted, because nothing about it is comparable
    // (see the class comment): the moment this line asks „which is newer?" it is asking a
    // question with no answer, and the wrong answer is silent and lasts years.
    final useDownload = downloaded != null;
    final chosen = useDownload ? downloaded : asset;
    if (chosen == null) {
      _sourceKind = StationSourceKind.none;
      DiagnoseLog.instance.add('stations', 'kein Auszug · weder Asset noch Download lesbar', bad: true);
      return null;
    }
    _sourceKind = useDownload ? StationSourceKind.downloaded : StationSourceKind.asset;
    _index = StationIndex(chosen);
    final ms = DateTime.now().difference(started).inMilliseconds;
    DiagnoseLog.instance.add(
      'stations',
      '${_sourceKind.name} v${chosen.tableVersion} · ${chosen.count} Stationen · $ms ms',
    );
    return _index;
  }

  /// A no-op until the interval has passed. The gate lives here rather than in the callers, so
  /// the worst a stray extra call can cost is a file read.
  Future<void> maybeCheckForUpdate() async {
    // Nowhere to put a download is a reason not to make one: without the meta file there is no
    // interval either, so this would otherwise fetch the whole extract on every foreground and
    // throw it away again.
    if (await _stationsDir() == null) return;
    final meta = await _readMeta();
    final next = meta?.nextCheckAt;
    if (next != null && DateTime.now().toUtc().isBefore(next)) return;
    await checkForUpdate();
  }

  /// The check itself. True when a newer extract was installed and [indexOrNull] was replaced.
  Future<bool> checkForUpdate() async {
    // Load first, so both copies' timestamps and the downloaded serial are known before the
    // pointer is judged against them. Without this a check that ran before anything had asked for
    // a station would have nothing to compare and would fetch the whole extract to find out.
    await index();
    final meta = await _readMeta();
    // The serial of the copy we downloaded, never of the bundled asset: the pointer and the
    // download come from the same database, the asset may not. Null means „nothing on disk", and
    // then the pointer always wins whatever number it carries.
    final held = _downloadedVersion ?? meta?.tableVersion;
    final result = await _download.fetchPointer(etag: meta?.etag);
    switch (result) {
      case StationPointerNotModified():
        DiagnoseLog.instance.add('stations', 'update → 304');
        await _touchMeta(checkedAt: DateTime.now().toUtc(), nextIn: checkEvery);
        return false;
      case StationDownloadFailed(reason: final reason):
        DiagnoseLog.instance.add('stations', 'update failed · $reason', bad: true);
        await _touchMeta(checkedAt: DateTime.now().toUtc(), nextIn: retryAfter);
        return false;
      case StationPointerFresh(pointer: final pointer, etag: final etag):
        if (_alreadyHave(pointer, held)) {
          DiagnoseLog.instance.add('stations', 'update → v${pointer.version} · schon aktuell');
          await _touchMeta(checkedAt: DateTime.now().toUtc(), nextIn: checkEvery, etag: etag);
          return false;
        }
        return _install(pointer, etag);
    }
  }

  /// Is this pointer naming something we already hold?
  ///
  /// Only ever asked of a copy we downloaded, where the pointer's serial and ours come from the
  /// same database. With nothing on disk the answer is always no: the asset's serial belongs to
  /// whichever database rendered it and comparing the two is the bug this class is shaped around.
  bool _alreadyHave(StationPointer pointer, int? held) => held != null && pointer.version <= held;

  Future<bool> _install(StationPointer pointer, String? etag) async {
    final got = await _download.fetchExtract(pointer.url);
    if (got is StationDownloadFailed) {
      DiagnoseLog.instance.add('stations', 'update failed · ${got.reason}', bad: true);
      await _touchMeta(checkedAt: DateTime.now().toUtc(), nextIn: retryAfter);
      return false;
    }
    final bytes = (got as StationDownloadFresh).bytes;
    final StationExtract read;
    try {
      read = StationExtract.decode(bytes);
      final reason = _refuse(read, pointer);
      if (reason != null) throw ExtractFormatException(reason);
    } catch (e) {
      DiagnoseLog.instance.add('stations', 'update verworfen · ${_why(e)}', bad: true);
      await _touchMeta(checkedAt: DateTime.now().toUtc(), nextIn: retryAfter);
      return false;
    }

    // Written aside, decoded, and only then renamed onto the real name: a kill mid-write leaves
    // the previous state whole, because the rename is the commit.
    final file = await _extractFile();
    if (file == null) {
      DiagnoseLog.instance.add('stations', 'update verworfen · kein Ablageort', bad: true);
      await _touchMeta(checkedAt: DateTime.now().toUtc(), nextIn: retryAfter);
      return false;
    }
    try {
      final part = File('${file.path}.part');
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(file.path);
    } catch (e) {
      DiagnoseLog.instance.add('stations', 'update nicht gespeichert · ${_why(e)}', bad: true);
      await _touchMeta(checkedAt: DateTime.now().toUtc(), nextIn: retryAfter);
      return false;
    }
    await _writeMeta(_Meta(
      etag: etag,
      checkedAt: DateTime.now().toUtc(),
      nextCheckAt: DateTime.now().toUtc().add(checkEvery),
      tableVersion: read.tableVersion,
      generatedAt: read.generatedAt,
      bytes: bytes.length,
    ));
    _index = StationIndex(read);
    _sourceKind = StationSourceKind.downloaded;
    _downloadedVersion = read.tableVersion;
    final kb = (bytes.length / 1024).round();
    DiagnoseLog.instance.add('stations', 'update → 200 · v${read.tableVersion} · $kb kB');
    return true;
  }

  /// Every reason to throw a downloaded extract away and keep what is held. A plausible-looking
  /// file that does not match the pointer it came from is the one failure the floors here cannot
  /// catch later.
  String? _refuse(StationExtract read, StationPointer pointer) {
    if (read.count < minPlausibleCount) return '${read.count} Stationen sind zu wenige';
    if (read.tableVersion != pointer.version) {
      return 'Auszug v${read.tableVersion} passt nicht zum Zeiger v${pointer.version}';
    }
    if (pointer.crc32 != 0 && read.crc32 != pointer.crc32) return 'CRC passt nicht zum Zeiger';
    if (pointer.count != 0 && read.count != pointer.count) return 'Anzahl passt nicht zum Zeiger';
    // The decompressed size, never `Content-Length`: the latter is the compressed length whenever
    // Caddy serves the `.gz` sibling (measured 147.232 against 280.244).
    if (pointer.bytes != 0 && read.byteLength != pointer.bytes) {
      return '${read.byteLength} Bytes statt ${pointer.bytes} laut Zeiger';
    }
    // Again the downloaded copy's serial, not the asset's: a download going backwards against
    // its own database is a mistake, going „backwards" against a laptop's numbering is not.
    final held = _downloadedVersion;
    if (held != null && read.tableVersion < held) {
      return 'Auszug v${read.tableVersion} ist älter als v$held';
    }
    return null;
  }

  Future<void> _discardDownload(String why) async {
    DiagnoseLog.instance.add('stations', 'Download verworfen · $why', bad: true);
    _downloadedVersion = null;
    final file = await _extractFile();
    try {
      if (file != null && file.existsSync()) await file.delete();
    } catch (_) {}
    await _touchMeta(checkedAt: _meta?.checkedAt, nextIn: retryAfter, clearVersion: true);
  }

  Directory? _dir;
  bool _dirTried = false;

  Future<Directory?> _stationsDir() async {
    if (_dirTried) return _dir;
    _dirTried = true;
    try {
      final base = await _directory();
      final dir = Directory('${base.path}/stations');
      if (!dir.existsSync()) await dir.create(recursive: true);
      _dir = dir;
    } catch (e) {
      // No writable place to keep a download. `index()` still answers, from the asset.
      DiagnoseLog.instance.add('stations', 'kein Ablageort · ${_why(e)}', bad: true);
      _dir = null;
    }
    return _dir;
  }

  Future<File?> _extractFile() async {
    final dir = await _stationsDir();
    return dir == null ? null : File('${dir.path}/$fileName');
  }

  Future<_Meta?> _readMeta() async {
    if (_metaRead) return _meta;
    _metaRead = true;
    final dir = await _stationsDir();
    if (dir == null) return null;
    final f = File('${dir.path}/$metaName');
    try {
      if (!f.existsSync()) return null;
      _meta = _Meta.fromJson(jsonDecode(await f.readAsString()));
    } catch (_) {
      _meta = null;
    }
    return _meta;
  }

  Future<void> _writeMeta(_Meta meta) async {
    _meta = meta;
    _metaRead = true;
    final dir = await _stationsDir();
    if (dir == null) return;
    try {
      await File('${dir.path}/$metaName').writeAsString(jsonEncode(meta.toJson()), flush: true);
    } catch (_) {}
  }

  Future<void> _touchMeta({
    DateTime? checkedAt,
    required Duration nextIn,
    String? etag,
    bool clearVersion = false,
  }) async {
    final old = await _readMeta();
    await _writeMeta(_Meta(
      etag: etag ?? old?.etag,
      checkedAt: checkedAt ?? old?.checkedAt,
      nextCheckAt: DateTime.now().toUtc().add(nextIn),
      tableVersion: clearVersion ? null : old?.tableVersion,
      generatedAt: clearVersion ? null : old?.generatedAt,
      bytes: clearVersion ? null : old?.bytes,
    ));
  }

  static Future<Uint8List> _loadBundledAsset() async {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  static String _why(Object e) => e is ExtractFormatException ? e.message : e.toString().split('\n').first;
}

/// What the phone remembers between launches about the copy it downloaded. Written only after the
/// blob is in place.
class _Meta {
  const _Meta({this.etag, this.checkedAt, this.nextCheckAt, this.tableVersion, this.generatedAt, this.bytes});

  final String? etag;
  final DateTime? checkedAt;

  /// When the store will ask again: a week after a good check, an hour after a bad one.
  final DateTime? nextCheckAt;
  final int? tableVersion;
  final DateTime? generatedAt;
  final int? bytes;

  static _Meta? fromJson(Object? j) {
    if (j is! Map) return null;
    return _Meta(
      etag: j['etag'] as String?,
      checkedAt: DateTime.tryParse('${j['checked_at']}'),
      nextCheckAt: DateTime.tryParse('${j['next_check_at']}'),
      tableVersion: (j['table_version'] as num?)?.toInt(),
      generatedAt: DateTime.tryParse('${j['generated_at']}'),
      bytes: (j['bytes'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        if (etag != null) 'etag': etag,
        if (checkedAt != null) 'checked_at': checkedAt!.toIso8601String(),
        if (nextCheckAt != null) 'next_check_at': nextCheckAt!.toIso8601String(),
        if (tableVersion != null) 'table_version': tableVersion,
        if (generatedAt != null) 'generated_at': generatedAt!.toIso8601String(),
        if (bytes != null) 'bytes': bytes,
      };
}
