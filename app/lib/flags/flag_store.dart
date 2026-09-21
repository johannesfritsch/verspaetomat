import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show ChangeNotifier, kReleaseMode, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/diagnose_log.dart';
import 'flag_client.dart';
import 'flag_doc.dart';
import 'flags.dart';

/// The one flag document this app holds, and everything that decides when to ask for another
/// (issue #41).
///
/// **Nothing here is ever awaited on a path that draws a screen.** [flags] is a field, read
/// synchronously out of the preferences the app loaded before its first frame, so a flag has its
/// value in the first `build()` of the first screen — there is no await, no null and no flash of
/// the other path while a fetch is in flight. Every fetch is started with `unawaited`, every
/// failure leaves the held document exactly where it was, and if the flag service is slow, down,
/// or answering with nonsense, the only thing that happens is that the app keeps doing what it
/// was already doing.
///
/// **When it asks.** Once per foregrounding, not on a timer: [maybeCheckForUpdate] is called ten
/// seconds after launch and on every resume, and returns without a request until [checkEvery] has
/// passed — so a resume storm is free and a busy day is two or three conditional GETs. On top of
/// that, [refreshSoon] answers an SSE `flags` event after a random wait of up to [maxJitter]. The
/// jitter is not decoration: a flip with every foregrounded phone answering at once is thousands
/// of requests in one second.
class FlagStore extends ChangeNotifier {
  FlagStore({
    required this.prefs,
    required String apiUrl,
    FlagClient? client,
    Random? random,
  })  : _client = client ?? FlagClient(baseUrl: flagsUrlFor(apiUrl)),
        _random = random ?? Random() {
    _flags = _read();
  }

  /// The app's own preferences, already loaded before the first frame — which is what lets the
  /// held document be read synchronously.
  final SharedPreferences prefs;
  final FlagClient _client;
  final Random _random;

  /// The happy cadence, and the promise: a foregrounded phone whose event stream is down still
  /// sees a flip within this. With a four-minute average session it is well under one request per
  /// foreground session.
  static const Duration checkEvery = Duration(minutes: 30);

  /// After a check that failed, so an app opened during a blip does not then wait half an hour.
  static const Duration retryAfter = Duration(minutes: 5);

  /// How long an SSE `flags` event is spread over. Every foregrounded phone gets the same
  /// broadcast in the same second; without this they would all answer in that second.
  static const Duration maxJitter = Duration(seconds: 30);

  static const _docKey = 'flags.doc';
  static const _etagKey = 'flags.etag';
  static const _confirmedKey = 'flags.confirmed_at';
  static const _nextCheckKey = 'flags.next_check_at';

  /// `--dart-define=FLAGS_URL`. Empty — the normal case, including production — means the API
  /// host, so there is exactly one host to point at and the local loop works unchanged.
  static const String _flagsUrl = String.fromEnvironment('FLAGS_URL');

  static String flagsUrlFor(String apiUrl) => _flagsUrl.isEmpty ? apiUrl : _flagsUrl;

  /// `--dart-define=FLAGS=stations_local,other_flag=off`.
  ///
  /// `!kReleaseMode` is the door, the same shape as `HttpRepository.allowServerStations`
  /// (app/lib/repo/http_repository.dart:39): a store build cannot be told from outside to turn a
  /// flag on, even if somebody passes the define.
  static const String _forced = kReleaseMode ? '' : String.fromEnvironment('FLAGS');

  Flags _flags = Flags.none;
  String? _etag;
  DateTime? _nextCheckAt;
  Timer? _jitter;
  Future<void>? _inFlight;
  bool _disposed = false;

  /// What the server last said, resolved for this phone. Never null, never stale in a way that
  /// throws, and safe to read from `build()`.
  Flags get flags => _flags;

  /// The one-liner most call sites want: `store.on(Flag.stationsLocal)`.
  bool on(Flag f) => _flags.on(f);

  /// When the next [maybeCheckForUpdate] will actually go out. The Entwicklung page shows it.
  DateTime? get nextCheckAt => _nextCheckAt;

  /// The ETag of the document in hand — the server's hash over the bytes it served. It is the one
  /// identifier a flip can be recognised by, so the Entwicklung page prints it and a pasted log
  /// carries it.
  String? get etag => _etag;

  /// Names passed to `--dart-define=FLAGS=` that this build does not know. A typo in a define is
  /// otherwise a flag that silently does not turn on, which is the failure this whole issue is
  /// about — so it is logged and the Entwicklung page prints it.
  final List<String> unknownForced = [];

  // ---------------------------------------------------------------------------------------------
  // Reading what is held
  // ---------------------------------------------------------------------------------------------

  /// The cached document, straight off the preferences the app already has in hand.
  ///
  /// Synchronous on purpose. `SharedPreferences` is loaded in `main()` before `runApp`, so this
  /// costs a map lookup and a `jsonDecode` of a few hundred bytes, and it buys the property that
  /// matters: the first frame already knows.
  Flags _read() {
    final body = prefs.getString(_docKey);
    _etag = prefs.getString(_etagKey);
    _nextCheckAt = _time(prefs.getString(_nextCheckKey));
    final doc = body == null ? null : FlagDoc.parse(body);
    if (body != null && doc == null) {
      // Written by this class, so this can only mean a half-written preference or a downgrade.
      DiagnoseLog.instance.add('flags', 'zwischengespeichertes Dokument unlesbar', bad: true);
    }
    return Flags(
      doc: doc ?? FlagDoc.empty,
      confirmedAt: _time(prefs.getString(_confirmedKey)),
      pins: _pinsFromDefine(),
    );
  }

  Map<Flag, bool> _pinsFromDefine() {
    final out = <Flag, bool>{};
    for (final part in _forced.split(',')) {
      final text = part.trim();
      if (text.isEmpty) continue;
      final eq = text.indexOf('=');
      final name = eq < 0 ? text : text.substring(0, eq).trim();
      final value = eq < 0 ? 'on' : text.substring(eq + 1).trim().toLowerCase();
      final flag = Flag.parse(name);
      if (flag == null) {
        unknownForced.add(name);
        DiagnoseLog.instance.add('flags', 'FLAGS=$name — diese Flagge kennt der Build nicht', bad: true);
        continue;
      }
      out[flag] = value != 'off' && value != 'false' && value != '0';
    }
    if (out.isNotEmpty) {
      DiagnoseLog.instance.add('flags', 'erzwungen · ${out.entries.map((e) => '${e.key.cli}=${e.value ? 'an' : 'aus'}').join(' ')}');
    }
    return out;
  }

  // ---------------------------------------------------------------------------------------------
  // Pinning
  // ---------------------------------------------------------------------------------------------

  /// Pin [f] for this process, above everything the server says.
  ///
  /// This is how a test pins a flag instead of inheriting whatever the process default happens to
  /// be — without it, every test touching a flagged path reads the shipped behaviour by accident
  /// and passes for the wrong reason. It is also what `--dart-define=FLAGS=` uses, so there is one
  /// mechanism rather than two.
  @visibleForTesting
  void pin(Flag f, {required bool on}) => _apply(_flags.copyWith(pins: {..._flags.pins, f: on}));

  /// Back to whatever the server says.
  @visibleForTesting
  void unpin(Flag f) => _apply(_flags.copyWith(pins: {..._flags.pins}..remove(f)));

  // ---------------------------------------------------------------------------------------------
  // The authenticated answer
  // ---------------------------------------------------------------------------------------------

  /// This customer's resolved set, off `/v1/me` or `/v1/me/geofence` (issue #41).
  ///
  /// [raw] null means the payload carried no `flags` key at all — an older backend, or a build
  /// pointed at one. Nothing is learned and nothing is forgotten: the public document keeps
  /// answering. That distinction is the reason `ApiCustomer.flags` is nullable rather than
  /// defaulting to `{}`; folding the two together would let a build pointed at a server without
  /// the key blank every flag on the phone.
  ///
  /// **The map replaces the public document wholesale — it is never merged into it.** See
  /// [Flags.personal] for the rollout-exit case that a per-key merge silently breaks.
  ///
  /// **Ordering, and why last-one-wins is the rule.** `/v1/me` and `/v1/me/geofence` carry the
  /// same map and can land in either order, with `flags.json` possibly between them. Two rules,
  /// in this priority:
  ///
  /// 1. *An authenticated answer always beats the public document*, however recently the document
  ///    arrived, because only the authenticated one knows who is asking. The document cannot
  ///    express an override or a rollout at all, so a fresher document is not a better answer —
  ///    it is an answer to a different question. [_apply] never clears [Flags.personal].
  /// 2. *Among authenticated answers, the last one received wins.* Both are rendered from the
  ///    same in-memory snapshot on the same server, so they can only disagree across a flip that
  ///    happened between the two requests — a window of milliseconds. Ordering them properly
  ///    would mean carrying the issue time of each request down to here, which buys correctness
  ///    measured in milliseconds for a value whose delivery is measured in minutes, and the next
  ///    resume corrects it regardless. What matters is that neither is ever merged.
  void setPersonal(Map<String, Object?>? raw) {
    if (raw == null) return;
    _apply(_flags.copyWith(personal: FlagDoc.fromMap(raw)));
  }

  // ---------------------------------------------------------------------------------------------
  // Asking the server
  // ---------------------------------------------------------------------------------------------

  /// A no-op until the interval has passed. The gate lives here rather than in the callers, so the
  /// worst a stray extra call can cost is a map lookup — the same shape as
  /// `StationStore.maybeCheckForUpdate`.
  Future<void> maybeCheckForUpdate() {
    final next = _nextCheckAt;
    if (next != null && DateTime.now().toUtc().isBefore(next)) return Future<void>.value();
    return refreshNow();
  }

  /// Ask now, gate or no gate. The tail of [refreshSoon], and the way a test drives a fetch.
  ///
  /// Concurrent callers share the one in-flight request: a resume and an SSE event landing
  /// together must not open two sockets.
  Future<void> refreshNow() => _inFlight ??= _fetch().whenComplete(() => _inFlight = null);

  /// Answer an SSE `flags` event, after a random wait of up to [maxJitter].
  ///
  /// Every foregrounded phone is told in the same second. Spreading them is the difference between
  /// a flip costing a few hundred requests a second for half a minute and costing all of them at
  /// once. A second event while one is already pending does not add a second request.
  void refreshSoon() {
    if (_disposed || _jitter != null) return;
    final wait = Duration(milliseconds: _random.nextInt(maxJitter.inMilliseconds + 1));
    _jitter = Timer(wait, () {
      _jitter = null;
      if (!_disposed) unawaited(refreshNow());
    });
  }

  Future<void> _fetch() async {
    final result = await _client.fetch(etag: _etag);
    if (_disposed) return;
    switch (result) {
      case FlagFetchNotModified():
        // A 304 is a real answer, and the answer nearly every check gets: the document in hand
        // is current, and now it is current *as of now*, which is what the Entwicklung page
        // reports when somebody asks how old this phone's answer is.
        DiagnoseLog.instance.add('flags', 'update → 304 · ${_short(_etag)}');
        await _confirm(_flags.doc, _etag, nextIn: checkEvery);
      case FlagFetchFailed(reason: final reason):
        // Nothing was learned. The document in hand still stands, and its age is untouched — a
        // failed call is not an answer, and must not be shown as one.
        DiagnoseLog.instance.add('flags', 'update fehlgeschlagen · $reason', bad: true);
        await _touchNextCheck(retryAfter);
      case FlagFetchFresh(body: final body, etag: final etag):
        final doc = FlagDoc.parse(body);
        if (doc == null) {
          // 200 with something that is not a document. Keep what we hold; do not let a bad
          // publish blank every flag on every phone at once.
          DiagnoseLog.instance.add('flags', 'update verworfen · kein Dokument', bad: true);
          await _touchNextCheck(retryAfter);
          return;
        }
        DiagnoseLog.instance.add('flags', 'update → 200 · ${_short(etag)} · ${doc.values.length} gesetzt');
        await prefs.setString(_docKey, body);
        await _confirm(doc, etag, nextIn: checkEvery);
    }
  }

  Future<void> _confirm(FlagDoc doc, String? etag, {required Duration nextIn}) async {
    final now = DateTime.now().toUtc();
    _etag = etag;
    if (etag == null) {
      await prefs.remove(_etagKey);
    } else {
      await prefs.setString(_etagKey, etag);
    }
    await prefs.setString(_confirmedKey, now.toIso8601String());
    await _touchNextCheck(nextIn);
    _apply(_flags.copyWith(doc: doc, confirmedAt: now));
  }

  Future<void> _touchNextCheck(Duration inHowLong) async {
    _nextCheckAt = DateTime.now().toUtc().add(inHowLong);
    await prefs.setString(_nextCheckKey, _nextCheckAt!.toIso8601String());
  }

  /// Swap the held answer in, and tell the app only when an answer actually changed. A 304 every
  /// half hour must not rebuild the tree.
  void _apply(Flags next) {
    final changed = !_flags.sameAnswersAs(next);
    _flags = next;
    if (changed && !_disposed) notifyListeners();
  }

  static DateTime? _time(String? s) => s == null ? null : DateTime.tryParse(s)?.toUtc();

  /// An ETag is a 16-character hash in quotes; the first few characters are enough to tell one
  /// document from another in a log line.
  static String _short(String? etag) {
    if (etag == null || etag.isEmpty) return 'ohne ETag';
    final bare = etag.replaceAll('"', '').replaceAll('W/', '');
    return bare.length <= 8 ? bare : bare.substring(0, 8);
  }

  @override
  void dispose() {
    _disposed = true;
    _jitter?.cancel();
    _client.close();
    super.dispose();
  }
}
