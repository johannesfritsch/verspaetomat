import 'dart:async';

import 'package:flutter/services.dart';

/// Thin typed wrapper over the native geofence layer (docs/15). MethodChannel
/// `de.verspaetomat/geofence`; iOS and Android implement it, everything else
/// (web, macOS, tests) gets safe defaults instead of a MissingPluginException.
class Geofence {
  Geofence._() {
    _channel.setMethodCallHandler(_fromNative);
  }
  static final Geofence instance = Geofence._();

  static const _channel = MethodChannel('de.verspaetomat/geofence');

  final _nudges = StreamController<GeofenceNudge>.broadcast();

  /// The customer tapped a station notification.
  Stream<GeofenceNudge> get onNudgeTapped => _nudges.stream;

  Future<dynamic> _fromNative(MethodCall call) async {
    if (call.method == 'nudgeTapped') {
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
      _nudges.add(GeofenceNudge(stationId: '${args['stationId'] ?? ''}', stationName: '${args['stationName'] ?? ''}'));
    }
    return null;
  }

  /// Registers the station set and the umbrella. Returns how many regions native registered.
  Future<int> configure(GeofenceConfig config) async {
    try {
      final r = await _channel.invokeMethod<dynamic>('configure', config.toChannel());
      final m = (r as Map?)?.cast<String, dynamic>();
      return (m?['registered'] as num?)?.toInt() ?? 0;
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }

  Future<GeofencePermission> requestPermission({required bool always}) async {
    try {
      final r = await _channel.invokeMethod<dynamic>('requestPermission', {'always': always});
      return GeofencePermission.parse('$r');
    } on MissingPluginException {
      return GeofencePermission.notDetermined;
    } on PlatformException {
      return GeofencePermission.notDetermined;
    }
  }

  Future<GeofenceStatus> status() async {
    try {
      final r = await _channel.invokeMethod<dynamic>('status');
      final m = (r as Map?)?.cast<String, dynamic>() ?? const {};
      final pending = (m['pendingNudge'] as Map?)?.cast<String, dynamic>();
      return GeofenceStatus(
        permission: GeofencePermission.parse('${m['permission'] ?? 'notDetermined'}'),
        notifications: m['notifications'] == true,
        registered: (m['registered'] as num?)?.toInt() ?? 0,
        lastEvent: m['lastEvent']?.toString(),
        pendingNudge: pending == null ? null : GeofenceNudge(stationId: '${pending['stationId'] ?? ''}', stationName: '${pending['stationName'] ?? ''}'),
      );
    } on MissingPluginException {
      return const GeofenceStatus.unavailable();
    } on PlatformException {
      return const GeofenceStatus.unavailable();
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<dynamic>('stop');
    } on MissingPluginException {
      // no native side
    } on PlatformException {
      // nothing to stop
    }
  }
}

enum GeofencePermission {
  notDetermined,
  denied,
  whileInUse,
  always;

  static GeofencePermission parse(String s) => switch (s) {
        'always' => GeofencePermission.always,
        'whileInUse' => GeofencePermission.whileInUse,
        'denied' => GeofencePermission.denied,
        _ => GeofencePermission.notDetermined,
      };
}

class GeofenceStatus {
  const GeofenceStatus({required this.permission, required this.notifications, required this.registered, this.lastEvent, this.pendingNudge});
  const GeofenceStatus.unavailable()
      : permission = GeofencePermission.notDetermined,
        notifications = false,
        registered = 0,
        lastEvent = null,
        pendingNudge = null;
  final GeofencePermission permission;
  final bool notifications;
  final int registered;
  final String? lastEvent;
  final GeofenceNudge? pendingNudge;
}

class GeofenceNudge {
  const GeofenceNudge({required this.stationId, required this.stationName});
  final String stationId;
  final String stationName;
}

class GeofenceStationConfig {
  const GeofenceStationConfig({required this.id, required this.name, required this.lat, required this.lon});
  final String id;
  final String name;
  final double lat;
  final double lon;
  Map<String, dynamic> toChannel() => {'id': id, 'name': name, 'lat': lat, 'lon': lon};
}

/// Everything native needs. Sent whole on every change; native persists it.
class GeofenceConfig {
  const GeofenceConfig({
    required this.apiUrl,
    required this.token,
    required this.enabled,
    required this.riding,
    required this.stations,
    this.umbrellaRadiusM = 8000,
    this.stationRadiusM = 300,
    this.quietFrom,
    this.quietTo,
  });
  final String apiUrl;
  final String? token;
  final bool enabled;
  final bool riding;
  final List<GeofenceStationConfig> stations;
  final int umbrellaRadiusM;
  final int stationRadiusM;
  final String? quietFrom;
  final String? quietTo;

  Map<String, dynamic> toChannel() => {
        'apiUrl': apiUrl,
        'token': token,
        'enabled': enabled,
        'riding': riding,
        'stations': stations.map((s) => s.toChannel()).toList(),
        'umbrellaRadiusM': umbrellaRadiusM,
        'stationRadiusM': stationRadiusM,
        'quietFrom': quietFrom,
        'quietTo': quietTo,
      };
}
