import 'dart:async';

import 'package:flutter/widgets.dart';

import '../api/models.dart';
import '../repo/repo_scope.dart';
import '../state/demo_state.dart' show LocationMode;
import 'diagnose_log.dart';
import 'geofence.dart';

/// Keeps the native geofence layer in step with the account (docs/15).
///
/// Syncs after the session loads, on every session change (settings, muted
/// stations, mode switch), when the app returns to the foreground and after a
/// check-in or arrival. Debounced, so a burst of changes is one `configure`.
class GeofenceSync with WidgetsBindingObserver {
  GeofenceSync({required this.session, required this.onNudge, Geofence? geofence}) : _geofence = geofence ?? Geofence.instance;

  final Session session;

  /// Called with the station when the customer tapped a nudge notification.
  final void Function(GeofenceNudge nudge) onNudge;

  final Geofence _geofence;
  Timer? _debounce;
  StreamSubscription<GeofenceNudge>? _taps;
  StreamSubscription<PushToken>? _tokens;
  bool _started = false;
  String? _lastFingerprint;
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
    _checkPending();
    scheduleSync();
  }

  void dispose() {
    _debounce?.cancel();
    _snoozeTimer?.cancel();
    _taps?.cancel();
    _tokens?.cancel();
    session.removeListener(scheduleSync);
    if (_started) WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    DiagnoseLog.instance.add('app', state.name);
    if (state == AppLifecycleState.resumed) {
      _checkPending();
      scheduleSync();
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

  /// Once per launch: an account that said yes to notifications or background location
  /// while the OS was never asked (an older build skipped the prompt) gets asked now.
  Future<void> _repairPermissions(GeofenceStatus status) async {
    if (automation) return;
    for (var i = 0; i < 20 && session.me == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    final settings = session.me?.settings;
    if (settings == null || !session.isLocal) return;
    if (settings.notifications && !status.notifications) {
      await _geofence.registerPush();
    }
    if (settings.locationMode == LocationMode.always && status.permission == GeofencePermission.notDetermined) {
      await requestFor(LocationMode.always);
    }
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

  /// One `configure` with the current account state. Never throws.
  Future<void> sync() async {
    _debounce?.cancel();
    if (session.me == null || session.healthy != true) return;
    try {
      final geo = await session.repo.geofence();
      var riding = false;
      try {
        riding = (await session.repo.currentRide())?.ride.status == ApiRideStatus.riding;
      } catch (_) {
        // no ride or no answer: not riding
      }
      final config = GeofenceConfig(
        apiUrl: session.apiUrl,
        token: session.isLocal ? await session.tokens.token() : null,
        enabled: geo.enabled,
        riding: riding,
        stations: [for (final s in geo.stations) GeofenceStationConfig(id: s.id, name: s.name, lat: s.lat, lon: s.lon)],
        quietFrom: geo.quietFrom,
        quietTo: geo.quietTo,
      );
      // Identical config → no round trip to native (it re-registers regions on every configure).
      final fp = '${config.enabled}|${config.riding}|${config.quietFrom}|${config.quietTo}|${config.stations.map((s) => s.id).join(',')}|${config.token?.length}';
      if (fp == _lastFingerprint) return;
      _lastFingerprint = fp;
      await _geofence.configure(config);
      _scheduleSnoozeExpiry(geo.snoozeUntil);
      // docs/25 §4: stations whose nudges nobody answered three times running go quiet for a
      // month. The tally is native, because it is counted while the app is not running.
      final status = await _geofence.status();
      if (status.ignored.isNotEmpty) {
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
