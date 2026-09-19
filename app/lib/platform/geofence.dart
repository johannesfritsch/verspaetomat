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
        ignored: {
          for (final e in (m['ignored'] as Map?)?.cast<String, dynamic>().entries ?? const <MapEntry<String, dynamic>>[])
            e.key: (e.value as num?)?.toInt() ?? 0,
        },
        disc: m['discLat'] is num && m['discLon'] is num
            ? GeofenceDisc(
                lat: (m['discLat'] as num).toDouble(),
                lon: (m['discLon'] as num).toDouble(),
                radiusM: (m['discRadiusM'] as num?)?.toDouble() ?? 0,
                at: m['discAt'] is num
                    ? DateTime.fromMillisecondsSinceEpoch(((m['discAt'] as num).toDouble() * 1000).round())
                    : null,
              )
            : null,
        counters: {
          for (final e in (m['counters'] as Map?)?.cast<String, dynamic>().entries ?? const <MapEntry<String, dynamic>>[])
            e.key: (e.value as num?)?.toInt() ?? 0,
        },
        regionsAt: _at(m['regionsAt']),
        regionsCentre: m['regionsLat'] is num && m['regionsLon'] is num
            ? (lat: (m['regionsLat'] as num).toDouble(), lon: (m['regionsLon'] as num).toDouble())
            : null,
        nearestAt: _at(m['nearestAt']),
        nearestCount: (m['nearestCount'] as num?)?.toInt() ?? 0,
        nearestCentre: m['nearestLat'] is num && m['nearestLon'] is num
            ? (lat: (m['nearestLat'] as num).toDouble(), lon: (m['nearestLon'] as num).toDouble())
            : null,
        mode: m['mode']?.toString(),
        lastEventAt: _at(m['lastEventAt']),
        umbrellaUp: m['umbrellaUp'] == true,
        umbrellaRadiusM: (m['umbrellaRadiusM'] as num?)?.toDouble() ?? 0,
        maxRegionRadiusM: (m['maxRegionRadiusM'] as num?)?.toDouble() ?? 0,
        umbrellaComputed: m['umbrellaComputed'] == true,
        umbrellaWhy: m['umbrellaWhy']?.toString(),
        regions: [
          for (final r in (m['regions'] as List? ?? const []).whereType<Map>())
            GeofenceRegion(
              id: '${r['id'] ?? ''}',
              name: '${r['name'] ?? r['id'] ?? ''}',
              lat: (r['lat'] as num?)?.toDouble(),
              lon: (r['lon'] as num?)?.toDouble(),
              distanceM: (r['distanceM'] as num?)?.toDouble(),
              inside: r['inside'] == true,
              radiusM: (r['radiusM'] as num?)?.toDouble() ?? 0,
            ),
        ],
      );
    } on MissingPluginException {
      return const GeofenceStatus.unavailable();
    } on PlatformException {
      return const GeofenceStatus.unavailable();
    }
  }

  /// docs/25 §5: the native log, newest last, as `timestamp \t source \t text` lines. Written
  /// while the app was suspended, which is where nearly all of it happens.
  Future<List<String>> readLog() async {
    try {
      final r = await _channel.invokeMethod<dynamic>('readLog');
      return (r as List?)?.map((e) => '$e').toList() ?? const [];
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  Future<void> clearLog() async {
    try {
      await _channel.invokeMethod<dynamic>('clearLog');
    } on MissingPluginException {
      // no native side
    } on PlatformException {
      // nothing to clear
    }
  }

  /// The counters of the last [days] days, newest first (issue #29).
  ///
  /// Nothing new is recorded for this: native has written one key per day since the counters
  /// existed and never deleted any, so this reads history that was already on the phone and
  /// simply unreachable. Days with no traffic are absent rather than zero — the phone was off,
  /// or the app was not installed, and a drawn zero would claim otherwise.
  Future<List<GeofenceDay>> countersHistory({int days = 7}) async {
    try {
      final r = await _channel.invokeMethod<dynamic>('countersHistory', {'days': days});
      return [
        for (final e in (r as List? ?? const []).whereType<Map>())
          GeofenceDay(
            day: '${e['day'] ?? ''}',
            counters: {
              for (final c in (e['counters'] as Map?)?.cast<String, dynamic>().entries ?? const <MapEntry<String, dynamic>>[])
                c.key: (c.value as num?)?.toInt() ?? 0,
            },
          ),
      ];
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  /// docs/25 §5: redraw the region set around a fresh fix, now.
  ///
  /// It refuses rather than interrupts, so the answer is not a yes/no — the screen has to be able
  /// to say *why* nothing happened, and "busy" in particular means the phone is in the middle of
  /// the very thing the button would have tested.
  Future<GeofenceRefresh> refreshNow() async {
    try {
      return GeofenceRefresh.parse('${await _channel.invokeMethod<dynamic>('refreshNow')}');
    } on MissingPluginException {
      return GeofenceRefresh.unavailable;
    } on PlatformException {
      return GeofenceRefresh.unavailable;
    }
  }

  /// docs/25 §5: a notification to this phone in [delay], carrying nothing and doing nothing
  /// when tapped. It answers whether hints arrive at all, which no status row can.
  ///
  /// False means the system refused it — which is the answer the button exists to give, so it
  /// must never be reported as a success.
  Future<bool> testNudge({Duration delay = const Duration(seconds: 10)}) async {
    try {
      return await _channel.invokeMethod<bool>('testNudge', {'delay': delay.inSeconds.toDouble()}) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// docs/25 §4: the tally for this station has been turned into a mute, so it starts over.
  Future<void> clearIgnored(String stationId) async {
    try {
      await _channel.invokeMethod<dynamic>('clearIgnored', {'stationId': stationId});
    } on MissingPluginException {
      // no native side
    } on PlatformException {
      // nothing to clear
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

/// What `refreshNow` did, in the words the screen needs (issue #29).
enum GeofenceRefresh {
  /// A fresh fix was asked for; the set is redrawn when it lands.
  started,

  /// No location permission, so there is nothing to ask.
  denied,

  /// Background scanning is off, in the account or on the phone.
  off,

  /// Something is already running — usually the near-watch at a station, which is exactly what
  /// this button must not interrupt.
  busy,

  /// No native layer at all (Android, a widget test, the simulator without the plugin).
  unavailable;

  static GeofenceRefresh parse(String s) => switch (s) {
        'started' => GeofenceRefresh.started,
        'denied' => GeofenceRefresh.denied,
        'off' => GeofenceRefresh.off,
        'busy' => GeofenceRefresh.busy,
        _ => GeofenceRefresh.unavailable,
      };
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

/// Seconds-since-epoch from the channel, or null. Native sends `NSNull` for an absent date.
DateTime? _at(dynamic v) =>
    v is num ? DateTime.fromMillisecondsSinceEpoch((v.toDouble() * 1000).round()) : null;

class GeofenceStatus {
  const GeofenceStatus({
    required this.permission,
    required this.notifications,
    required this.registered,
    this.lastEvent,
    this.pendingNudge,
    this.pushToken,
    this.ignored = const {},
    this.disc,
    this.counters = const {},
    this.regions = const [],
    this.regionsAt,
    this.regionsCentre,
    this.nearestAt,
    this.nearestCount = 0,
    this.nearestCentre,
    this.mode,
    this.lastEventAt,
    this.umbrellaUp = false,
    this.umbrellaRadiusM = 0,
    this.maxRegionRadiusM = 0,
    this.umbrellaComputed = false,
    this.umbrellaWhy,
  });
  const GeofenceStatus.unavailable()
      : permission = GeofencePermission.notDetermined,
        notifications = false,
        registered = 0,
        lastEvent = null,
        pendingNudge = null,
        pushToken = null,
        ignored = const {},
        disc = null,
        counters = const {},
        regions = const [],
        regionsAt = null,
        regionsCentre = null,
        nearestAt = null,
        nearestCount = 0,
        nearestCentre = null,
        mode = null,
        lastEventAt = null,
        umbrellaUp = false,
        umbrellaRadiusM = 0,
        maxRegionRadiusM = 0,
        umbrellaComputed = false,
        umbrellaWhy = null;
  final GeofencePermission permission;
  final bool notifications;
  final int registered;
  final String? lastEvent;
  final GeofenceNudge? pendingNudge;
  final PushToken? pushToken;

  /// docs/25 §4: station id → how many nudges in a row went unanswered there, for those that
  /// have reached the threshold. The app mutes them for 30 days.
  final Map<String, int> ignored;

  /// docs/25 §1: where the station set was last drawn and how far it reaches.
  final GeofenceDisc? disc;

  /// docs/25 §5: counts since midnight — `requests`, `nearby`, `scheduled`, `fired`, `cancelled`.
  final Map<String, int> counters;

  /// Every monitored region, with whether the phone is inside it right now.
  final List<GeofenceRegion> regions;

  /// When the station set was last handed to iOS, and the centre it was chosen around (issue
  /// #31). Deliberately separate from the disc: `configure` moves the disc to wherever its fix
  /// lands while re-registering the set it already had, so the two can be hours and kilometres
  /// apart — and until these existed, the page could only show the disc's date and call it the
  /// age of the set.
  final DateTime? regionsAt;
  final ({double lat, double lon})? regionsCentre;

  /// When the nearby list behind that set was last fetched, and how many stations came back.
  /// This is the one that goes stale without anything on screen changing.
  final DateTime? nearestAt;
  final int nearestCount;

  /// Where that list was fetched. A list from the right time in the wrong town looks exactly like
  /// a good one without it — which is how Langenargen stayed registered in Kißlegg (issue #31).
  final ({double lat, double lon})? nearestCentre;

  /// What the layer is waiting for: `idle`, `configureFix`, `umbrellaFix`, `dwell:<station>`.
  final String? mode;

  /// When the native layer last did anything at all. A log that stops looks identical whether iOS
  /// delivered nothing, the app was force-quit, or the log was cleared — this says which.
  final DateTime? lastEventAt;

  /// Whether the umbrella is actually registered. Without it the stations stay in place and the
  /// page still looks populated, but nothing re-evaluates again — the quietest failure here.
  final bool umbrellaUp;

  /// The umbrella as it is actually registered — computed from the last complete answer, or the
  /// cautious default. No longer a constant (issue #31).
  final double umbrellaRadiusM;

  /// The widest circle this device will monitor. Nobody had ever read it off a phone.
  final double maxRegionRadiusM;

  /// Whether the radius above was worked out from a server answer, or is the cautious fallback.
  /// Without this the page prints the same „8,0 km" for both, which is what made the first
  /// report of this feature undiagnosable.
  final bool umbrellaComputed;

  /// The reason in the words the rule used: „nearest unwatched station 12 km off".
  final String? umbrellaWhy;
}

/// One registered region as the debug page lists it (docs/25 §5).
class GeofenceRegion {
  const GeofenceRegion({
    required this.id,
    required this.name,
    this.lat,
    this.lon,
    this.distanceM,
    this.inside = false,
    this.radiusM = 0,
  });
  final String id;
  final String name;

  /// Where the circle actually is. Native has always sent this; it was thrown away here until
  /// issue #29 wanted the set drawn rather than listed.
  final double? lat;
  final double? lon;

  final double? distanceM;
  final bool inside;
  final double radiusM;

  bool get hasPosition => lat != null && lon != null;

  /// The umbrella is a region too, but it is not a station.
  bool get isUmbrella => id == 'umbrella';
}

/// One day's counters, as `countersHistory` reads them back off the phone (issue #29).
class GeofenceDay {
  const GeofenceDay({required this.day, required this.counters});

  /// `yyyy-MM-dd`, the key the native side has always written under.
  final String day;
  final Map<String, int> counters;

  int get(String name) => counters[name] ?? 0;
}

/// The coverage disc as the debug page shows it (docs/25 §1, §5).
class GeofenceDisc {
  const GeofenceDisc({required this.lat, required this.lon, required this.radiusM, this.at});
  final double lat;
  final double lon;
  final double radiusM;
  final DateTime? at;

  /// Which band of the speed table this radius came from, in the words docs/25 §1 uses.
  String get band => radiusM <= 5000 ? 'zu Fuß oder lokal' : (radiusM <= 25000 ? 'Regionalzug' : 'Fernverkehr');
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
    this.umbrellaRadiusM = defaultUmbrellaRadiusM,
    this.stationRadiusM = defaultStationRadiusM,
    this.nudgeRadiusM = defaultNudgeRadiusM,
    this.quietFrom,
    this.quietTo,
  });
  // The three radii the whole layer is made of. `GeofenceSync` never overrides them, so these
  // are the numbers in force on every phone — and the debug page names them, because they are
  // invisible everywhere else (issue #29).
  static const defaultUmbrellaRadiusM = 8000;
  static const defaultStationRadiusM = 300;
  static const defaultNudgeRadiusM = 50;

  final String apiUrl;
  final String? token;
  final bool enabled;
  final bool riding;
  final List<GeofenceStationConfig> stations;
  final int umbrellaRadiusM;
  /// The circle iOS monitors: wide, because small regions are delivered late or not at all.
  final int stationRadiusM;

  /// How close the phone has to actually be before the nudge is scheduled (issue #8, docs/35).
  /// The wide region is the wake-up; this is the nudge.
  final int nudgeRadiusM;
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
        'nudgeRadiusM': nudgeRadiusM,
        'quietFrom': quietFrom,
        'quietTo': quietTo,
      };
}
