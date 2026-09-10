import 'dart:async';

import 'package:flutter/widgets.dart';

import '../api/models.dart';
import '../repo/repo_scope.dart';
import '../state/demo_state.dart' show LocationMode;
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
  bool _started = false;
  String? _lastFingerprint;

  /// Screenshots and the E2E must never trigger the OS permission dialog; the sync itself is harmless.
  static const bool automation = String.fromEnvironment('NO_LOCATION') == '1' || String.fromEnvironment('NO_LOCATION') == 'true' || String.fromEnvironment('E2E') == 'true';

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    session.addListener(scheduleSync);
    _taps = _geofence.onNudgeTapped.listen(onNudge);
    _checkPending();
    scheduleSync();
  }

  void dispose() {
    _debounce?.cancel();
    _taps?.cancel();
    session.removeListener(scheduleSync);
    if (_started) WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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

  Future<void> _checkPending() async {
    final status = await _geofence.status();
    final pending = status.pendingNudge;
    if (pending != null && pending.stationId.isNotEmpty) onNudge(pending);
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
    } catch (_) {
      // The nudge is a convenience; the app never fails because of it.
    }
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
