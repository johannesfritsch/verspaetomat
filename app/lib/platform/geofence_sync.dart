import 'dart:async';

import 'package:flutter/widgets.dart';

import '../api/events.dart';
import '../api/models.dart';
import '../repo/app_repository.dart' show AppRepository, RideWrite;
import '../repo/repo_scope.dart';
import '../state/demo_state.dart' show LocationMode;
import 'diagnose_log.dart';
import 'geofence.dart';

/// The Entwicklung page's switch: ignored nudges do not mute a station (#64, test phones only).
const noAutoMuteKey = 'debug.noAutoMute';

/// Keeps the native geofence layer in step with the account (docs/15).
///
/// Syncs after the session loads, on every session change (settings, muted stations, mode
/// switch), when the app returns to the foreground, on every event that touches a ride, and —
/// at once, without the debounce — after every write of this app's that starts, moves or ends
/// one (#80). Debounced otherwise, so a burst of changes is one `configure`; a sync still
/// waiting when the app goes to the background runs on the way out.
class GeofenceSync with WidgetsBindingObserver {
  /// [events] and [repo] are the session's own unless a test hands in others.
  GeofenceSync({required this.session, required this.onNudge, Geofence? geofence, Stream<AppEvent>? events, AppRepository? repo})
      : _geofence = geofence ?? Geofence.instance,
        _eventsIn = events,
        _repoIn = repo;

  final Session session;

  /// Called with the station when the customer tapped a nudge notification.
  final void Function(GeofenceNudge nudge) onNudge;

  final Geofence _geofence;
  final Stream<AppEvent>? _eventsIn;
  final AppRepository? _repoIn;
  AppRepository get _repo => _repoIn ?? session.repo;

  Timer? _debounce;
  StreamSubscription<GeofenceNudge>? _taps;
  StreamSubscription<PushToken>? _tokens;
  StreamSubscription<AppEvent>? _events;
  StreamSubscription<RideWrite>? _writes;
  bool _started = false;
  bool _disposed = false;
  String? _lastFingerprint;

  /// The last answer to "is a ride running?" — see [sync].
  bool _lastRiding = false;
  static const _pushKey = 'push_token_sent';

  /// Screenshots and the E2E must never trigger the OS permission dialog; the sync itself is harmless.
  static const bool automation = String.fromEnvironment('NO_LOCATION') == '1' || String.fromEnvironment('NO_LOCATION') == 'true' || String.fromEnvironment('E2E') == 'true';

  void start() {
    if (_started) return;
    _started = true;
    DiagnoseLog.instance.add('app', 'launch');
    WidgetsBinding.instance.addObserver(this);
    session.addListener(scheduleSync);
    _taps = _geofence.onNudgeTapped.listen(onNudge);
    _tokens = _geofence.onPushToken.listen(_sendPushToken);
    // #80: the server's word that a ride started or ended elsewhere — Stellwerk, another
    // phone, the arrival the backend detected itself.
    _events = (_eventsIn ?? session.events).listen((e) {
      if (e.touchesRide) scheduleSync();
    });
    // #80: this app's own check-in. The app is in the background seconds later (eight in the
    // report), so this one does not wait for the debounce.
    _writes = session.rideWrites.listen((w) {
      // docs/25 §4: a nudge counts as ignored when no check-in follows, so a check-in at its
      // station answers it, and the tally starts over (#86). Before the sync, which reads the
      // tally to mute.
      final at = w.checkedInAt;
      if (at != null && at.isNotEmpty) unawaited(_geofence.clearIgnored(at));
      unawaited(sync());
    });
    _checkPending();
    scheduleSync();
  }

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _snoozeTimer?.cancel();
    _taps?.cancel();
    _tokens?.cancel();
    _events?.cancel();
    _writes?.cancel();
    session.removeListener(scheduleSync);
    if (_started) WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    DiagnoseLog.instance.add('app', state.name);
    if (state == AppLifecycleState.resumed) {
      _checkPending();
      scheduleSync();
    } else if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      // On the way out a debounced sync would fire into a suspended isolate and be lost until
      // the next resume — after the station it was meant to silence (#80).
      if (_debounce?.isActive ?? false) unawaited(sync());
    }
  }

  /// Debounced `configure`. Safe to call often.
  void scheduleSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => sync());
  }

  bool _repaired = false;

  Future<void> _checkPending() async {
    final status = await _geofence.status();
    final pending = status.pendingNudge;
    if (pending != null && (pending.stationId.isNotEmpty || pending.kind != 'station')) onNudge(pending);
    if (status.pushToken != null) _sendPushToken(status.pushToken!);
    if (!_repaired) {
      _repaired = true;
      _repairPermissions(status);
    }
  }

  /// Once per launch: make the account's settings agree with what the phone actually allows.
  ///
  /// It used to do the opposite — see a setting saying yes, see the OS saying no, and ask the OS
  /// to catch up. That fired system dialogs at launch, with no screen behind them and no sentence
  /// explaining them, and it could fire two in a row.
  ///
  /// **A fresh install is not a fresh account.** `FlutterSecureStorage` keeps the device token in
  /// the iOS Keychain, and Keychain items survive deleting the app. So reinstalling comes back as
  /// the same customer, carrying `notifications = true` and maybe `loc_mode = always` — while the
  /// OS permissions were wiped with the app and are back to notDetermined. Both conditions true,
  /// both dialogs up, before anything was drawn. That is the bug reported against builds 70 and
  /// 71, and „sometimes" was simply whether that account had ever said yes.
  ///
  /// So the repair runs the other way now. The phone is the authority on what the phone allows;
  /// a setting that claims more than the OS grants is wrong, and writing it down false has two
  /// good effects on its own: the server stops sending push nobody can receive, and the Bahnsteig
  /// notices the missing permission and offers it back on a card somebody taps
  /// (`location_nudge.dart`), which is a screen with a reason on it.
  ///
  /// Nothing here ever opens a system dialog.
  Future<void> _repairPermissions(GeofenceStatus status) async {
    if (automation) return;
    for (var i = 0; i < 20 && session.me == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    final settings = session.me?.settings;
    if (settings == null || !session.isLocal) return;
    // Not while the setup is still running: those screens are in the middle of asking, and a
    // correction written from under them would race their own answers.
    if (!settings.onboardingDone) return;

    final patch = MePatch(
      notifications: settings.notifications && !status.notifications ? false : null,
      // Only a refusal contradicts „always". „whileInUse" does not: iOS grants the upgrade on
      // its own schedule and reports the lesser state until it does, so writing the setting down
      // on that basis would take the reminder away from somebody who had just asked for it — and
      // `nudges_enabled` would then have the server report `enabled: false` and the layer would
      // register nothing. The Bahnsteig card is what closes that gap, on a screen, by asking.
      locationMode: settings.locationMode == LocationMode.always && status.permission == GeofencePermission.denied
          ? LocationMode.never
          : null,
    );
    if (patch.notifications == null && patch.locationMode == null) return;
    await session.updateSettings(patch);
  }

  /// Sends the push token to the server once per account and token. Waits for the
  /// session when it arrives before /v1/me has loaded.
  Future<void> _sendPushToken(PushToken t) async {
    if (t.token.isEmpty) return;
    for (var i = 0; i < 20 && (session.me == null || session.healthy != true); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    final me = session.me;
    if (me == null || !session.isLocal) return;
    final stamp = '${me.id}:${t.platform}:${t.token}';
    if (session.prefs.getString(_pushKey) == stamp) return;
    try {
      await session.repo.putPushToken(platform: t.platform, token: t.token);
      await session.prefs.setString(_pushKey, stamp);
    } catch (_) {
      // Next launch or resume tries again.
    }
  }

  Future<void>? _inFlight;
  bool _again = false;

  /// One `configure` with the current account state. Never throws.
  ///
  /// One at a time. A sync that starts while another is still out runs once more after it,
  /// rather than beside it: two side by side can land in the wrong order, and the one asked
  /// before the check-in — „not riding" — would then be the last thing native heard (#80).
  Future<void> sync() {
    _debounce?.cancel();
    final running = _inFlight;
    if (running != null) {
      _again = true;
      return running;
    }
    return _inFlight = _drain();
  }

  Future<void> _drain() async {
    try {
      do {
        _again = false;
        await _syncOnce();
      } while (_again && !_disposed);
    } finally {
      _inFlight = null;
    }
  }

  /// Whether native should hold its nudges: a journey under way or waiting at a change (#80),
  /// else — only when there is no journey at all — a ride from before journeys, the way
  /// `RideMonitor` reads the two. Throws when the server could not be asked.
  static Future<bool> ridingNow(AppRepository repo) async {
    final journey = await repo.currentJourney();
    if (journey != null) return journey.journey.riding || journey.journey.inTransfer;
    return (await repo.currentRide())?.ride.status == ApiRideStatus.riding;
  }

  Future<void> _syncOnce() async {
    if (session.me == null || session.healthy != true) return;
    try {
      final geo = await _repo.geofence();
      // A failed call is not an answer (issue #11). On a platform with one bar of signal this
      // used to come back as "not riding", the native layer forgot the journey, and every region
      // the phone was already inside nudged — twice, once per station at the same spot. The last
      // known answer is kept instead; the sync runs again on the next change.
      var riding = _lastRiding;
      try {
        riding = await ridingNow(_repo);
      } catch (_) {
        // keep what we last knew
      }
      _lastRiding = riding;
      final config = GeofenceConfig(
        apiUrl: session.apiUrl,
        token: session.isLocal ? await session.tokens.token() : null,
        enabled: geo.enabled,
        riding: riding,
        stations: [for (final s in geo.stations) GeofenceStationConfig(id: s.id, name: s.name, lat: s.lat, lon: s.lon)],
        quietFrom: geo.quietFrom,
        quietTo: geo.quietTo,
        stationsLocal: geo.stationsLocal,
        stationPremises: geo.stationPremises,
        premisesVersion: geo.stationPremises ? await session.premisesVersion() : null,
      );
      // Identical config → no round trip to native (it re-registers regions on every configure).
      // `stationsLocal` belongs in here: it is #40's kill switch, and without it a flip that
      // changes nothing else would be skipped — the switch would test green on a cold start and
      // do nothing at exactly the moment somebody is trying to kill something.
      final fp =
          '${config.enabled}|${config.riding}|${config.stationsLocal}|${config.stationPremises}|${config.premisesVersion}|${config.quietFrom}|${config.quietTo}|${config.stations.map((s) => s.id).join(',')}|${config.token?.length}';
      if (fp == _lastFingerprint) return;
      // `configure` first, then the fingerprint. [Geofence.configure] swallows
      // `MissingPluginException` and `PlatformException` and returns 0, so committing the
      // fingerprint first records a `configure` that never reached native as delivered — and
      // nothing retries it until something else in the fingerprint changes.
      await _geofence.configure(config);
      _lastFingerprint = fp;
      _scheduleSnoozeExpiry(geo.snoozeUntil);
      // docs/25 §4: stations whose nudges nobody answered three times running go quiet for a
      // month. The tally is native, because it is counted while the app is not running.
      final status = await _geofence.status();
      // The Entwicklung page's „Stummschalten aus" (#64): on a test phone three ignored nudges
      // must not quietly end the test at that station for a month.
      if (status.ignored.isNotEmpty && session.prefs.getBool(noAutoMuteKey) == true) {
        DiagnoseLog.instance.add('geofence', 'Stummschalten aus · ${status.ignored.length} Bahnhöfe nicht stummgeschaltet');
      } else if (status.ignored.isNotEmpty) {
        await session.muteIgnoredStations(status.ignored, known: geo.stations);
        for (final id in status.ignored.keys) {
          await _geofence.clearIgnored(id);
        }
      }
    } catch (_) {
      // The nudge is a convenience; the app never fails because of it.
    }
  }

  Timer? _snoozeTimer;

  /// A running pause (docs/24 §3) already reaches native as `enabled: false`; nothing tells
  /// us when it runs out, so the sync wakes itself at that moment and configures again.
  /// Lifting it early comes through the session listener like any other setting.
  void _scheduleSnoozeExpiry(DateTime? until) {
    _snoozeTimer?.cancel();
    if (until == null) return;
    final left = until.difference(DateTime.now());
    // Beyond a day it is the open-ended choice, or far enough that a foreground resume will
    // have synced long before; a timer that long is not worth holding.
    if (left <= Duration.zero || left > const Duration(days: 1)) return;
    _snoozeTimer = Timer(left + const Duration(seconds: 5), scheduleSync);
  }

  /// Ask for the OS permission that matches a location mode. No-op under automation.
  static Future<GeofencePermission> requestFor(LocationMode mode) async {
    if (automation) return GeofencePermission.notDetermined;
    return switch (mode) {
      LocationMode.always => Geofence.instance.requestPermission(always: true),
      LocationMode.whileUsing => Geofence.instance.requestPermission(always: false),
      LocationMode.never => Future.value(GeofencePermission.notDetermined),
    };
  }
}
