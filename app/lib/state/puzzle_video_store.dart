import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../api/models.dart';
import '../platform/diagnose_log.dart';

/// Where a picture's film is (docs/51 §9b).
enum VideoPhase { none, queued, downloading, ready, failed }

@immutable
class PuzzleVideoState {
  const PuzzleVideoState(this.phase, {this.progress = 0, this.file, this.asset});
  final VideoPhase phase;

  /// 0 … 1 while downloading.
  final double progress;

  /// The film on the phone, once it is there.
  final File? file;

  /// Demo mode's bundled film instead of a file.
  final String? asset;

  static const none = PuzzleVideoState(VideoPhase.none);
  static const queued = PuzzleVideoState(VideoPhase.queued);
  static const failed = PuzzleVideoState(VideoPhase.failed);

  bool get ready => phase == VideoPhase.ready;

  @override
  bool operator ==(Object other) => other is PuzzleVideoState && other.phase == phase && other.progress == progress && other.file?.path == file?.path && other.asset == asset;

  @override
  int get hashCode => Object.hash(phase, progress, file?.path, asset);

  @override
  String toString() => 'PuzzleVideoState($phase${phase == VideoPhase.downloading ? ' ${(progress * 100).round()} %' : ''})';
}

/// Fetches a film from [from] on: the client's `puzzleVideo`, or a fake in a test.
typedef VideoFetch = Future<http.StreamedResponse> Function(String url, {int from});

/// Each finished picture's film, fetched once and kept (docs/51 §9b).
///
/// The server names a film only for a finished picture and serves it only to whoever finished it,
/// so a download starts only then: when the last piece arrives, when the Puzzles page or Ich finds
/// a finished picture whose film is not on the phone, and at the next start for the same. One
/// download at a time, in the order asked for. A film is written to `.part` and renamed only once
/// its size is right; a wrong size starts it once more, a broken connection resumes from where it
/// stopped.
class PuzzleVideoStore {
  PuzzleVideoStore({required this.fetch, this.reload, Future<Directory> Function()? directory, this.idle = const Duration(seconds: 20)})
      : _directory = directory ?? getApplicationSupportDirectory;

  final VideoFetch fetch;

  /// The pictures as the server has them now: after a 404, the film may have been replaced.
  final Future<ApiPuzzles> Function()? reload;
  final Future<Directory> Function() _directory;

  /// How long a download may hear nothing before it counts as broken: a train in a tunnel holds a
  /// connection open that brings no more bytes.
  final Duration idle;

  final Map<String, ValueNotifier<PuzzleVideoState>> _states = {};

  /// The film each notifier stands for: a picture's film can be replaced, and a new digest starts
  /// it over.
  final Map<String, String> _shas = {};
  final List<ApiPuzzle> _queue = [];
  bool _running = false;

  ValueNotifier<PuzzleVideoState> _notifier(ApiPuzzle p) {
    final sha = p.video?.sha256;
    final n = _states.putIfAbsent(p.imageId, () => ValueNotifier(PuzzleVideoState.none));
    if (sha != null && _shas[p.imageId] != sha) {
      // A film this store has not seen for the picture (or the first look): from the start.
      _shas[p.imageId] = sha;
      if (n.value.phase != VideoPhase.downloading && n.value.phase != VideoPhase.queued) n.value = PuzzleVideoState.none;
      _look(p, n);
    }
    return n;
  }

  /// Where this picture's film stands. Starts nothing.
  ValueListenable<PuzzleVideoState> watch(ApiPuzzle p) => _notifier(p);

  /// The film, once it is on the phone (or bundled, in Demo).
  PuzzleVideoState stateOf(ApiPuzzle p) => _notifier(p).value;

  /// Fetch the film if the picture is finished, has one, and it is not here or under way.
  void ensure(ApiPuzzle p) {
    final v = p.video;
    if (!p.complete || v == null) return;
    final n = _notifier(p);
    if (v.url.startsWith('assets/')) {
      n.value = PuzzleVideoState(VideoPhase.ready, asset: v.url);
      return;
    }
    if (n.value.phase != VideoPhase.none) return;
    n.value = PuzzleVideoState.queued;
    _queue.add(p);
    unawaited(_pump());
  }

  /// After a failure: once more, from the start of the queue's end.
  void retry(ApiPuzzle p) {
    final n = _notifier(p);
    if (n.value.phase != VideoPhase.failed) return;
    n.value = PuzzleVideoState.none;
    ensure(p);
  }

  /// Forgets every film: the files on the phone, the states, the queue — the account is gone or
  /// another one came in its place.
  Future<void> clear() async {
    _queue.clear();
    for (final n in _states.values) {
      n.value = PuzzleVideoState.none;
    }
    _states.clear();
    _shas.clear();
    try {
      final dir = Directory('${(await _directory()).path}/puzzle-videos');
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  /// Shows [state] for [p] whatever is under way: the preview bench draws each state with it.
  @visibleForTesting
  void debugShow(ApiPuzzle p, PuzzleVideoState state) => _notifier(p).value = state;

  /// A film already on disk shows as ready from the first look.
  Future<void> _look(ApiPuzzle p, ValueNotifier<PuzzleVideoState> n) async {
    final v = p.video;
    if (v == null) return;
    if (v.url.startsWith('assets/')) {
      n.value = PuzzleVideoState(VideoPhase.ready, asset: v.url);
      return;
    }
    try {
      final f = await _file(p.imageId, v);
      if (n.value.phase == VideoPhase.none && f.existsSync() && f.lengthSync() == v.bytes) n.value = PuzzleVideoState(VideoPhase.ready, file: f);
    } catch (_) {}
  }

  Future<File> _file(String imageId, ApiPuzzleVideo v) async {
    final base = await _directory();
    final id = imageId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    // Keyed on the digest: a replaced film is another file, never the old one under a new name.
    final sha = v.sha256.length >= 8 ? v.sha256.substring(0, 8) : 'film';
    return File('${base.path}/puzzle-videos/$id-$sha.mp4');
  }

  /// A replaced film's file goes once the new one is here — the same picture, another digest —
  /// and so does any half of it.
  Future<void> _forgetOlder(String imageId, File current) async {
    try {
      final id = imageId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      await for (final f in current.parent.list()) {
        final name = f.uri.pathSegments.last;
        if (f is File && name.startsWith('$id-') && f.path != current.path && f.path != '${current.path}.part') await f.delete();
      }
    } catch (_) {}
  }

  /// After a 404: true when the server now names another film for the picture, which is then
  /// queued in this one's place.
  Future<bool> _replaced(ApiPuzzle p) async {
    final ask = reload;
    if (ask == null) return false;
    try {
      final now = (await ask()).puzzles.where((x) => x.imageId == p.imageId).firstOrNull;
      final v = now?.video;
      if (now == null || v == null || (v.url == p.video!.url && v.sha256 == p.video!.sha256)) return false;
      final n = _notifier(now);
      n.value = PuzzleVideoState.queued;
      _queue.add(now);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty) {
        final p = _queue.removeAt(0);
        // One film that throws must not stop the ones behind it.
        try {
          await _download(p);
        } catch (e) {
          DiagnoseLog.instance.add('video', '${p.imageId} · $e', bad: true);
          _notifier(p).value = PuzzleVideoState.failed;
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _download(ApiPuzzle p) async {
    final v = p.video!;
    final n = _notifier(p);
    final File file;
    try {
      file = await _file(p.imageId, v);
      await file.parent.create(recursive: true);
    } catch (e) {
      n.value = PuzzleVideoState.failed;
      return;
    }
    if (file.existsSync() && file.lengthSync() == v.bytes) {
      await _forgetOlder(p.imageId, file);
      n.value = PuzzleVideoState(VideoPhase.ready, file: file);
      return;
    }
    final part = File('${file.path}.part');
    for (var attempt = 0; attempt < 2; attempt++) {
      var have = part.existsSync() ? part.lengthSync() : 0;
      if (have >= v.bytes) {
        await part.delete();
        have = 0;
      }
      try {
        n.value = PuzzleVideoState(VideoPhase.downloading, progress: v.bytes == 0 ? 0 : have / v.bytes);
        final r = await fetch(v.url, from: have);
        if (r.statusCode != 200 && r.statusCode != 206) {
          await r.stream.drain<void>().catchError((_) {});
          DiagnoseLog.instance.add('video', '${p.imageId} · HTTP ${r.statusCode}', bad: true);
          // 404: the film may have been replaced since the list was read — ask once more, and
          // fetch the new one if there is one. 403 (not finished) and the rest: no better twice.
          if (r.statusCode == 404 && await _replaced(p)) return;
          n.value = PuzzleVideoState.failed;
          return;
        }
        // A 200 to a range request is the whole film again: start the file over.
        if (r.statusCode == 200) have = 0;
        final sink = part.openWrite(mode: r.statusCode == 206 ? FileMode.append : FileMode.write);
        var shown = -1;
        try {
          await for (final chunk in r.stream.timeout(idle)) {
            sink.add(chunk);
            have += chunk.length;
            final percent = v.bytes == 0 ? 0 : (have * 100 ~/ v.bytes);
            if (percent != shown) {
              shown = percent;
              n.value = PuzzleVideoState(VideoPhase.downloading, progress: (have / v.bytes).clamp(0.0, 1.0));
            }
          }
        } finally {
          await sink.close();
        }
        if (part.lengthSync() == v.bytes) {
          await part.rename(file.path);
          await _forgetOlder(p.imageId, file);
          DiagnoseLog.instance.add('video', '${p.imageId} · ${v.bytes} B geladen');
          n.value = PuzzleVideoState(VideoPhase.ready, file: file);
          return;
        }
        // The wrong size is a broken file: away with it, and once more from the start.
        DiagnoseLog.instance.add('video', '${p.imageId} · ${part.lengthSync()} statt ${v.bytes} B', bad: true);
        await part.delete();
      } catch (e) {
        // A broken connection: the part stays, and the next attempt asks for the rest.
        DiagnoseLog.instance.add('video', '${p.imageId} · $e', bad: true);
      }
    }
    n.value = PuzzleVideoState.failed;
  }
}
