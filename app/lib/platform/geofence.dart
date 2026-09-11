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
  final _pushTokens = StreamController<PushToken>.broadcast();
  final _umbrellaExits = StreamController<void>.broadcast();

  /// The customer tapped a station notification.
  Stream<GeofenceNudge> get onNudgeTapped => _nudges.stream;

  /// The OS handed the app a (new) push token; the session sends it to the server.
  Stream<PushToken> get onPushToken => _pushTokens.stream;

  /// Native left the umbrella and re-registered its stations (docs/15). The app has moved far
  /// enough that whatever station it last showed is stale, so `NearbyMonitor` resolves again
  /// and a card backgrounded across half of Germany is right the moment it is seen
  /// (docs/24 §0).
  Stream<void> get onUmbrellaExit => _umbrellaExits.stream;

  Future<dynamic> _fromNative(MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
    if (call.method == 'nudgeTapped') {
      _nudges.add(GeofenceNudge.fromMap(args));
    } else if (call.method == 'umbrellaExit') {
      _umbrellaExits.add(null);
    } else if (call.method == 'pushToken') {
      _pushTokens.add(PushToken(platform: '${args['platform'] ?? 'ios'}', token: '${args['token'] ?? ''}'));
    }
    return null;
  }

  /// Asks for notification permission and registers with the push service. True when granted.
  Future<bool> registerPush() async {
    try {
      return await _channel.invokeMethod<bool>('registerPush') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
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
        pushToken: m['pushToken'] is String && (m['pushToken'] as String).isNotEmpty ? PushToken(platform: 'ios', token: m['pushToken'] as String) : null,
        registered: (m['registered'] as num?)?.toInt() ?? 0,
        lastEvent: m['lastEvent']?.toString(),
        pendingNudge: pending == null ? null : GeofenceNudge.fromMap(pending),
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
  const GeofenceStatus({required this.permission, required this.notifications, required this.registered, this.lastEvent, this.pendingNudge, this.pushToken});
  const GeofenceStatus.unavailable()
      : permission = GeofencePermission.notDetermined,
        notifications = false,
        registered = 0,
        lastEvent = null,
        pendingNudge = null,
        pushToken = null;
  final GeofencePermission permission;
  final bool notifications;
  final int registered;
  final String? lastEvent;
  final GeofenceNudge? pendingNudge;
  final PushToken? pushToken;
}

class PushToken {
  const PushToken({required this.platform, required this.token});
  final String platform; // ios | android
  final String token;
}

/// A tapped notification: a station nudge (`kind: station`), the nudge's own "Ruhe" action
/// (`kind: snooze`, with `hours`, docs/24 §3) or a server push (`kind: journey | mail |
/// incident | claim | ride`, with the push's data fields).
class GeofenceNudge {
  const GeofenceNudge({required this.stationId, required this.stationName, this.kind = 'station', this.data = const {}});
  final String stationId;
  final String stationName;
  final String kind;
  final Map<String, String> data;

  bool get isStation => kind == 'station' && stationId.isNotEmpty;
  bool get isJourney => kind == 'journey';
  String? get journeyId => data['journey_id'];
  bool get journeyTransfer => data['transfer'] == 'true';
  bool get journeyArrived => data['arrived'] == 'true';
  /// The claim a railway-mail push belongs to (backend push data `claim_id`), if any.
  String? get claimId => (data['claim_id'] ?? '').isEmpty ? null : data['claim_id'];

  factory GeofenceNudge.fromMap(Map<String, dynamic> m) {
    final data = <String, String>{for (final e in m.entries) e.key: '${e.value ?? ''}'};
    return GeofenceNudge(stationId: '${m['stationId'] ?? ''}', stationName: '${m['stationName'] ?? ''}', kind: '${m['kind'] ?? 'station'}', data: data);
  }
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
