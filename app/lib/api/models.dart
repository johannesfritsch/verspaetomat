// Wire models for the Verspätomat API (backend/openapi.yaml, tonight's contract).
// Amounts are euro cents. Timestamps are UTC. Enums are shared with the mock
// types where the names already match the wire (TicketType, IncidentStatus).

import '../mock/mock_data.dart' show TicketType, IncidentStatus;
import '../state/demo_state.dart' show LocationMode;

// ---------------------------------------------------------------------------
// Parsing helpers
// ---------------------------------------------------------------------------

String _s(dynamic v, [String d = '']) => v == null ? d : v.toString();
String? _sn(dynamic v) => v?.toString();
int _i(dynamic v, [int d = 0]) => v == null ? d : (v is int ? v : (v is num ? v.toInt() : int.tryParse(v.toString()) ?? d));
int? _in(dynamic v) => v == null ? null : _i(v);
bool _b(dynamic v, [bool d = false]) => v == null ? d : (v is bool ? v : v.toString() == 'true');
double _f(dynamic v, [double d = 0]) => v == null ? d : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? d);
DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toUtc();
DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
List<String> _sl(dynamic v) => v == null ? const [] : (v as List).map((e) => e.toString()).toList();
List<Map<String, dynamic>> _ml(dynamic v) => v == null ? const [] : (v as List).map((e) => (e as Map).cast<String, dynamic>()).toList();
Map<String, dynamic>? _m(dynamic v) => v == null ? null : (v as Map).cast<String, dynamic>();
String _fmtDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ---------------------------------------------------------------------------
// Enum wire mapping
// ---------------------------------------------------------------------------

TicketType ticketFromWire(String? s) => TicketType.values.firstWhere((t) => t.name == s, orElse: () => TicketType.deutschlandticket);
String ticketToWire(TicketType t) => t.name;

/// The wire has `gedeckelt` (capped) which the mock enum lacks; it is shown as verfallen.
IncidentStatus incidentStatusFromWire(String? s) {
  if (s == 'gedeckelt') return IncidentStatus.verfallen;
  return IncidentStatus.values.firstWhere((t) => t.name == s, orElse: () => IncidentStatus.gesammelt);
}

String incidentStatusToWire(IncidentStatus s) => s.name;

LocationMode locationFromWire(String? s) => switch (s) {
      'never' => LocationMode.never,
      'while_using' => LocationMode.whileUsing,
      _ => LocationMode.always,
    };
String locationToWire(LocationMode m) => switch (m) {
      LocationMode.never => 'never',
      LocationMode.whileUsing => 'while_using',
      LocationMode.always => 'always',
    };

enum ApiCategory { s, rb, re, fern, bus, other }

ApiCategory categoryFromWire(String? s) => switch (s) {
      's' || 'SUBURBAN' => ApiCategory.s,
      'rb' || 'REGIONAL_RAIL' => ApiCategory.rb,
      're' || 'REGIONAL_FAST_RAIL' => ApiCategory.re,
      'fern' || 'HIGHSPEED_RAIL' || 'LONG_DISTANCE' || 'RAIL' => ApiCategory.fern,
      'bus' || 'BUS' || 'COACH' => ApiCategory.bus,
      _ => ApiCategory.other,
    };

enum ApiRideStatus { riding, arrived, abandoned }

enum ApiClaimStatus { draft, sent, question, accepted, rejected, bounced }

ApiClaimStatus claimStatusFromWire(String? s) => ApiClaimStatus.values.firstWhere((v) => v.name == s, orElse: () => ApiClaimStatus.draft);

enum ApiMailDirection { out, inbound }

enum ApiMailOutcome { accepted, question, rejected, bounce, other }

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

class DeviceAuth {
  const DeviceAuth({required this.deviceId, required this.token});
  final String deviceId;
  final String token;
  factory DeviceAuth.fromJson(Map<String, dynamic> j) => DeviceAuth(deviceId: _s(j['device_id']), token: _s(j['token']));
}

// ---------------------------------------------------------------------------
// Reference data
// ---------------------------------------------------------------------------

/// Nearby stations plus where the position came from: gps, stellwerk (with a label), demo, or none.
class ApiNearby {
  const ApiNearby({required this.stations, required this.source, this.label});
  final List<ApiStation> stations;
  final String source;
  final String? label;
  bool get simulated => source == 'stellwerk';
  bool get none => source == 'none';

  /// The phone is still being asked where it is (docs/23 §1): no station is shown yet, and
  /// never the last one. Only the demo answers with this source; in local mode the screen
  /// knows it from its own pending fix.
  bool get checking => source == 'locating';

  /// A list that does not depend on a fresh fix from this phone.
  bool get independentOfFix => simulated || source == 'demo';

  factory ApiNearby.fromJson(dynamic j) {
    if (j is List) return ApiNearby(stations: j.map((e) => ApiStation.fromJson(e as Map<String, dynamic>)).toList(), source: 'gps');
    final m = j as Map<String, dynamic>;
    final list = (m['stations'] as List? ?? const []).map((e) => ApiStation.fromJson(e as Map<String, dynamic>)).toList();
    return ApiNearby(stations: list, source: (m['source'] ?? 'gps').toString(), label: m['label'] as String?);
  }
}

class ApiStation {
  const ApiStation({required this.id, required this.name, this.lat = 0, this.lon = 0, this.distanceM, this.eva, this.railRank});
  final String id;
  final String name;
  final double lat;
  final double lon;
  final int? distanceM;
  final String? eva;

  /// How much of a railway station this stop is (docs/23 §1): 3 long distance, 2 rail or
  /// regional, 1 S-Bahn only or a station by its name. Set on nearby stations only.
  final int? railRank;

  String get distanceLabel {
    final d = distanceM;
    if (d == null) return '';
    return d < 1000 ? '$d m' : '${(d / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
  }

  factory ApiStation.fromJson(Map<String, dynamic> j) =>
      ApiStation(id: _s(j['id']), name: _s(j['name']), lat: _f(j['lat']), lon: _f(j['lon']), distanceM: _in(j['distance_m']), eva: _sn(j['eva']), railRank: _in(j['rail_rank']));
}

class ApiStop {
  const ApiStop({required this.name, this.stationId, this.scheduledArrival, this.arrival, this.scheduledDeparture, this.departure, this.cancelled = false});
  final String name;
  final String? stationId;
  final DateTime? scheduledArrival;
  final DateTime? arrival;
  final DateTime? scheduledDeparture;
  final DateTime? departure;
  final bool cancelled;

  /// Delay at this stop in minutes, from the arrival forecast when known.
  int get delayMinutes {
    final p = scheduledArrival ?? scheduledDeparture;
    final a = arrival ?? departure;
    if (p == null || a == null) return 0;
    return a.difference(p).inMinutes;
  }

  factory ApiStop.fromJson(Map<String, dynamic> j) => ApiStop(
        name: _s(j['name']),
        stationId: _sn(j['station_id'] ?? j['stop_id']),
        scheduledArrival: _dt(j['scheduled_arrival']),
        arrival: _dt(j['arrival'] ?? j['live_arrival']),
        scheduledDeparture: _dt(j['scheduled_departure']),
        departure: _dt(j['departure'] ?? j['live_departure']),
        cancelled: _b(j['cancelled']),
      );
}

class ApiDeparture {
  const ApiDeparture({
    required this.tripId,
    required this.line,
    required this.destination,
    required this.scheduledDeparture,
    this.departure,
    this.realtime = false,
    this.platform,
    this.category = ApiCategory.other,
    required this.operator,
    this.desk = '',
    this.cancelled = false,
    this.cause,
    this.stops = const [],
  });
  final String tripId;
  final String line;
  final String destination;
  final DateTime scheduledDeparture;
  final DateTime? departure;
  final bool realtime;
  final String? platform;
  final ApiCategory category;
  final String operator;
  final String desk;
  final bool cancelled;
  final String? cause;
  final List<ApiStop> stops;

  int get delayMinutes => departure == null ? 0 : departure!.difference(scheduledDeparture).inMinutes;

  factory ApiDeparture.fromJson(Map<String, dynamic> j) => ApiDeparture(
        tripId: _s(j['trip_id']),
        line: _s(j['line']),
        destination: _s(j['destination'] ?? j['headsign']),
        scheduledDeparture: _dt(j['scheduled_departure'] ?? j['planned_departure']) ?? DateTime.now().toUtc(),
        departure: _dt(j['departure'] ?? j['live_departure']),
        realtime: _b(j['realtime']),
        platform: _sn(j['platform']),
        category: categoryFromWire(_sn(j['category'] ?? j['mode'])),
        operator: _s(j['operator'] ?? j['agency'] ?? j['agency_name']),
        desk: _s(j['desk'] ?? ''),
        cancelled: _b(j['cancelled']),
        cause: _sn(j['cause']),
        stops: _ml(j['stops']).map(ApiStop.fromJson).toList(),
      );
}

class ApiTrip {
  const ApiTrip({required this.tripId, required this.line, required this.operator, this.category = ApiCategory.other, this.cancelled = false, this.cause, required this.stops});
  final String tripId;
  final String line;
  final String operator;
  final ApiCategory category;
  final bool cancelled;
  final String? cause;
  final List<ApiStop> stops;

  factory ApiTrip.fromJson(Map<String, dynamic> j) => ApiTrip(
        tripId: _s(j['trip_id'] ?? j['id']),
        line: _s(j['line']),
        operator: _s(j['operator'] ?? j['agency'] ?? j['agency_name']),
        category: categoryFromWire(_sn(j['category'] ?? j['mode'])),
        cancelled: _b(j['cancelled']),
        cause: _sn(j['cause']),
        stops: _ml(j['stops']).map(ApiStop.fromJson).toList(),
      );
}

class ApiOperator {
  const ApiOperator({required this.name, required this.desk, required this.postalAddress, this.email, this.acceptsEmail = false});
  final String name;
  final String desk;
  final String postalAddress;
  final String? email;
  final bool acceptsEmail;
  factory ApiOperator.fromJson(Map<String, dynamic> j) =>
      ApiOperator(name: _s(j['name']), desk: _s(j['desk']), postalAddress: _s(j['postal_address']), email: _sn(j['email']), acceptsEmail: _b(j['accepts_email']));
}

class ApiNgo {
  const ApiNgo({
    required this.id,
    required this.name,
    required this.tagline,
    this.story = const [],
    required this.accountHolder,
    required this.iban,
    this.donationUrl = '',
    this.lastReport,
    this.confirmedTotalCents = 0,
    this.submittedTotalCents = 0,
  });
  final String id;
  final String name;
  final String tagline;
  final List<String> story;
  final String accountHolder;
  final String iban;
  final String donationUrl;
  final DateTime? lastReport;
  final int confirmedTotalCents;
  final int submittedTotalCents;

  factory ApiNgo.fromJson(Map<String, dynamic> j) => ApiNgo(
        id: _s(j['id']),
        name: _s(j['name']),
        tagline: _s(j['tagline']),
        story: _sl(j['story']),
        accountHolder: _s(j['account_holder']),
        iban: _s(j['iban']),
        donationUrl: _s(j['donation_url']),
        lastReport: _date(j['last_report']),
        confirmedTotalCents: _i(j['confirmed_total_cents']),
        submittedTotalCents: _i(j['submitted_total_cents']),
      );
}

class ApiBadge {
  const ApiBadge({required this.id, required this.name, required this.rule, this.earnedOn});
  final String id;
  final String name;
  final String rule;
  final DateTime? earnedOn;
  bool get earned => earnedOn != null;
  factory ApiBadge.fromJson(Map<String, dynamic> j) => ApiBadge(id: _s(j['id']), name: _s(j['name']), rule: _s(j['rule']), earnedOn: _date(j['earned_on']));
}

// ---------------------------------------------------------------------------
// Customer
// ---------------------------------------------------------------------------

class ApiPersonalData {
  const ApiPersonalData({required this.name, required this.address, required this.email, this.ticketNumber});
  final String name;
  final String address;
  final String email;
  final String? ticketNumber;
  factory ApiPersonalData.fromJson(Map<String, dynamic> j) =>
      ApiPersonalData(name: _s(j['name']), address: _s(j['address']), email: _s(j['email']), ticketNumber: _sn(j['ticket_number']));
  Map<String, dynamic> toJson() => {'name': name, 'address': address, 'email': email, if (ticketNumber != null) 'ticket_number': ticketNumber};
}

/// A station the customer never wants the nudge for. Part of the account.
/// A station that stays quiet. [until] null is the mute a passenger set by hand, which has no
/// end; a date is the automatic one from docs/25 §4, which runs out on its own.
class ApiMutedStation {
  const ApiMutedStation({required this.id, required this.name, this.until});
  final String id;
  final String name;
  final DateTime? until;

  /// Still silent. An automatic mute that has run out is no mute at all.
  bool get active => until == null || until!.isAfter(DateTime.now());

  /// Set by the passenger rather than by three ignored nudges.
  bool get byHand => until == null;

  factory ApiMutedStation.fromJson(Map<String, dynamic> j) =>
      ApiMutedStation(id: _s(j['id']), name: _s(j['name']), until: DateTime.tryParse(_s(j['until']))?.toLocal());
  Map<String, dynamic> toJson() => {'id': id, 'name': name, if (until != null) 'until': until!.toUtc().toIso8601String()};
}

class ApiSettings {
  const ApiSettings({
    required this.ticket,
    required this.ngoId,
    required this.locationMode,
    this.notifications = true,
    this.showOnBoards = true,
    this.keepCorrespondence = false,
    this.traewellingLinked = false,
    this.onboardingDone = false,
    this.mutedStations = const [],
    this.nudgeEnabled = true,
    this.quietFrom = '22:00',
    this.quietTo = '06:00',
    this.nudgeSnoozeUntil,
  });
  final TicketType ticket;
  final String ngoId;
  final LocationMode locationMode;
  final bool notifications;
  final bool showOnBoards;
  final bool keepCorrespondence;
  final bool traewellingLinked;
  final bool onboardingDone;
  final List<ApiMutedStation> mutedStations;

  /// Station nudge on/off and the quiet window ("HH:MM", null = no quiet hours). See docs/15.
  final bool nudgeEnabled;
  final String? quietFrom;
  final String? quietTo;
  bool get quietHours => quietFrom != null && quietTo != null;

  /// docs/24 §3: station nudges are paused until this moment. Null means no pause. An
  /// open-ended pause is a date far enough out that nothing else will ever reach it.
  final DateTime? nudgeSnoozeUntil;

  /// A pause that is still running. An expired one is no pause at all.
  bool get snoozed {
    final t = nudgeSnoozeUntil;
    return t != null && t.isAfter(DateTime.now());
  }

  /// True when the pause has no end the passenger chose: "bis ich sie wieder einschalte".
  bool get snoozedOpenEnded => snoozed && nudgeSnoozeUntil!.difference(DateTime.now()).inDays > 30;

  bool isMuted(String stationId) => mutedStations.any((m) => m.id == stationId);

  factory ApiSettings.fromJson(Map<String, dynamic> j) => ApiSettings(
        ticket: ticketFromWire(_sn(j['ticket'])),
        ngoId: _s(j['ngo_id'], 'bahnhofsmission'),
        locationMode: locationFromWire(_sn(j['location_mode'])),
        notifications: _b(j['notifications'], true),
        showOnBoards: _b(j['show_on_boards'], true),
        keepCorrespondence: _b(j['keep_correspondence']),
        traewellingLinked: _b(j['traewelling_linked']),
        onboardingDone: _b(j['onboarding_done']),
        mutedStations: (j['muted_stations'] as List? ?? const []).whereType<Map<String, dynamic>>().map(ApiMutedStation.fromJson).toList(),
        nudgeEnabled: _b(j['nudge_enabled'], true),
        quietFrom: j.containsKey('quiet_from') ? _sn(j['quiet_from']) : '22:00',
        quietTo: j.containsKey('quiet_to') ? _sn(j['quiet_to']) : '06:00',
        nudgeSnoozeUntil: DateTime.tryParse(_s(j['nudge_snooze_until']))?.toLocal(),
      );
}

/// PATCH /v1/me body. Only set fields are sent.
class MePatch {
  const MePatch({
    this.ticket,
    this.ngoId,
    this.locationMode,
    this.notifications,
    this.showOnBoards,
    this.keepCorrespondence,
    this.traewellingLinked,
    this.onboardingDone,
    this.nickname,
    this.mutedStations,
    this.nudgeEnabled,
    this.quietFrom,
    this.quietTo,
    this.nudgeSnoozeUntil,
  });
  final TicketType? ticket;
  final String? ngoId;
  final LocationMode? locationMode;
  final bool? notifications;
  final bool? showOnBoards;
  final bool? keepCorrespondence;
  final bool? traewellingLinked;
  final bool? onboardingDone;
  final String? nickname;
  /// Full replacement of the muted list.
  final List<ApiMutedStation>? mutedStations;
  final bool? nudgeEnabled;
  /// "HH:MM"; an empty string clears the quiet window.
  final String? quietFrom;
  final String? quietTo;

  /// docs/24 §3: RFC 3339, or the empty string to lift the pause.
  final String? nudgeSnoozeUntil;

  Map<String, dynamic> toJson() => {
        if (ticket != null) 'ticket': ticketToWire(ticket!),
        if (ngoId != null) 'ngo_id': ngoId,
        if (locationMode != null) 'location_mode': locationToWire(locationMode!),
        if (notifications != null) 'notifications': notifications,
        if (showOnBoards != null) 'show_on_boards': showOnBoards,
        if (keepCorrespondence != null) 'keep_correspondence': keepCorrespondence,
        if (traewellingLinked != null) 'traewelling_linked': traewellingLinked,
        if (onboardingDone != null) 'onboarding_done': onboardingDone,
        if (nickname != null) 'nickname': nickname,
        if (mutedStations != null) 'muted_stations': mutedStations!.map((m) => m.toJson()).toList(),
        if (nudgeEnabled != null) 'nudge_enabled': nudgeEnabled,
        if (quietFrom != null) 'quiet_from': quietFrom,
        if (quietTo != null) 'quiet_to': quietTo,
        if (nudgeSnoozeUntil != null) 'nudge_snooze_until': nudgeSnoozeUntil,
      };
}

/// GET /v1/me/geofence: the stations the phone should watch (docs/15).
class ApiGeofence {
  const ApiGeofence({
    required this.enabled,
    required this.stations,
    this.quietFrom,
    this.quietTo,
    this.snoozeUntil,
    this.idle = false,
    this.lastCheckin,
  });
  final bool enabled;
  final List<ApiGeofenceStation> stations;
  final String? quietFrom;
  final String? quietTo;

  /// docs/24 §3: the backend already folds a running pause into [enabled]; this is only so
  /// the app can say until when without a second call.
  final DateTime? snoozeUntil;

  /// docs/25 §4: thirty days without a check-in switched background scanning off. Folded into
  /// [enabled] as well; Home says so in one line and offers it back. Nothing was deleted and
  /// no permission was revoked.
  final bool idle;
  final DateTime? lastCheckin;

  static const empty = ApiGeofence(enabled: false, stations: []);

  factory ApiGeofence.fromJson(Map<String, dynamic> j) => ApiGeofence(
        enabled: _b(j['enabled']),
        stations: (j['stations'] as List? ?? const []).whereType<Map<String, dynamic>>().map(ApiGeofenceStation.fromJson).toList(),
        quietFrom: _sn(j['quiet_from']),
        quietTo: _sn(j['quiet_to']),
        snoozeUntil: DateTime.tryParse(_s(j['nudge_snooze_until'] ?? j['snooze_until']))?.toLocal(),
        idle: _b(j['idle']),
        lastCheckin: DateTime.tryParse(_s(j['last_checkin']))?.toLocal(),
      );
}

class ApiGeofenceStation {
  const ApiGeofenceStation({required this.id, required this.name, required this.lat, required this.lon, this.checkins = 0});
  final String id;
  final String name;
  final double lat;
  final double lon;
  final int checkins;

  factory ApiGeofenceStation.fromJson(Map<String, dynamic> j) => ApiGeofenceStation(
        id: _s(j['id']),
        name: _s(j['name']),
        lat: (j['lat'] as num?)?.toDouble() ?? 0,
        lon: (j['lon'] as num?)?.toDouble() ?? 0,
        checkins: (j['checkins'] as num?)?.toInt() ?? 0,
      );
  Map<String, dynamic> toChannel() => {'id': id, 'name': name, 'lat': lat, 'lon': lon};
}

class ApiCustomer {
  const ApiCustomer({
    required this.id,
    required this.nickname,
    this.relayAddress,
    this.personalData,
    required this.settings,
    this.pointsTotal = 0,
    this.pointsThisWeek = 0,
    this.levelName = '',
    this.nextLevelName = '',
    this.nextLevelAt = 0,
    this.homeStation = '',
  });
  final String id;
  final String nickname;
  final String? relayAddress;
  final ApiPersonalData? personalData;
  final ApiSettings settings;
  final int pointsTotal;
  final int pointsThisWeek;
  final String levelName;
  final String nextLevelName;
  final int nextLevelAt;
  final String homeStation;

  factory ApiCustomer.fromJson(Map<String, dynamic> j) => ApiCustomer(
        id: _s(j['id']),
        nickname: _s(j['nickname']),
        relayAddress: _sn(j['relay_address']),
        personalData: _m(j['personal_data']) == null ? null : ApiPersonalData.fromJson(_m(j['personal_data'])!),
        settings: ApiSettings.fromJson(_m(j['settings']) ?? const {}),
        pointsTotal: _i(j['points_total']),
        pointsThisWeek: _i(j['points_this_week']),
        levelName: _s(j['level_name']),
        nextLevelName: _s(j['next_level_name']),
        nextLevelAt: _i(j['next_level_at']),
        homeStation: _s(j['home_station']),
      );
}

// ---------------------------------------------------------------------------
// Rides
// ---------------------------------------------------------------------------

class ApiLocation {
  const ApiLocation({required this.lat, required this.lon, this.accuracyM});
  final double lat;
  final double lon;
  final double? accuracyM;
  Map<String, dynamic> toJson() => {'lat': lat, 'lon': lon, if (accuracyM != null) 'accuracy_m': accuracyM};
}

class CheckInRequest {
  const CheckInRequest({
    required this.tripId,
    required this.fromStationId,
    required this.fromStationName,
    required this.exitStationId,
    required this.exitStationName,
    this.ticket,
    this.location,
    this.fromLat,
    this.fromLon,
  });
  final String tripId;
  final String fromStationId;
  final String fromStationName;
  final String exitStationId;
  final String exitStationName;
  final TicketType? ticket;
  final ApiLocation? location;
  /// The from-station's own coordinates (not the phone's): feed the geofence set.
  final double? fromLat;
  final double? fromLon;
  Map<String, dynamic> toJson() => {
        'trip_id': tripId,
        'from_station_id': fromStationId,
        'from_station_name': fromStationName,
        'exit_station_id': exitStationId,
        'exit_station_name': exitStationName,
        if (ticket != null) 'ticket': ticketToWire(ticket!),
        if (location != null) 'location': location!.toJson(),
        if (fromLat != null && fromLon != null) ...{'from_lat': fromLat, 'from_lon': fromLon},
      };
}

class ArrivalRequest {
  const ArrivalRequest({this.delayMinutes, this.actualArrival, this.cancelled = false, this.selfEntered = false});
  final int? delayMinutes;
  final DateTime? actualArrival;
  final bool cancelled;
  final bool selfEntered;
  Map<String, dynamic> toJson() => {
        if (delayMinutes != null) 'delay_minutes': delayMinutes,
        if (actualArrival != null) 'actual_arrival': actualArrival!.toUtc().toIso8601String(),
        'cancelled': cancelled,
        'self_entered': selfEntered,
      };
}

class NachtragRequest {
  const NachtragRequest({required this.tripId, required this.fromStationId, required this.fromStationName, required this.exitStationId, required this.exitStationName, required this.date});
  final String tripId;
  final String fromStationId;
  final String fromStationName;
  final String exitStationId;
  final String exitStationName;
  final DateTime date;
  Map<String, dynamic> toJson() => {
        'trip_id': tripId,
        'from_station_id': fromStationId,
        'from_station_name': fromStationName,
        'exit_station_id': exitStationId,
        'exit_station_name': exitStationName,
        'date': _fmtDate(date),
      };
}

class ApiRide {
  const ApiRide({
    required this.id,
    required this.tripId,
    required this.line,
    required this.operator,
    this.category = ApiCategory.other,
    required this.fromStationId,
    required this.fromStationName,
    required this.exitStationId,
    required this.exitStationName,
    this.plannedArrival,
    required this.ticket,
    required this.checkedInAt,
    this.locationVerified = false,
    required this.status,
    this.passedStops = 0,
    this.liveDelayMinutes = 0,
    this.cause,
    this.finalDelayMinutes,
    this.cancelled = false,
    this.selfEntered = false,
    this.nachtrag = false,
    this.points = 0,
    required this.date,
  });
  final String id;
  final String tripId;
  final String line;
  final String operator;
  final ApiCategory category;
  final String fromStationId;
  final String fromStationName;
  final String exitStationId;
  final String exitStationName;
  final DateTime? plannedArrival;
  final TicketType ticket;
  final DateTime checkedInAt;
  final bool locationVerified;
  final ApiRideStatus status;
  final int passedStops;
  final int liveDelayMinutes;
  final String? cause;
  final int? finalDelayMinutes;
  final bool cancelled;
  final bool selfEntered;
  final bool nachtrag;
  final int points;
  final DateTime date;

  factory ApiRide.fromJson(Map<String, dynamic> j) => ApiRide(
        id: _s(j['id']),
        tripId: _s(j['trip_id'] ?? j['departure_id']),
        line: _s(j['line']),
        operator: _s(j['operator']),
        category: categoryFromWire(_sn(j['category'])),
        fromStationId: _s(j['from_station_id']),
        fromStationName: _s(j['from_station_name'] ?? j['from_station']),
        exitStationId: _s(j['exit_station_id']),
        exitStationName: _s(j['exit_station_name'] ?? j['exit_stop']),
        plannedArrival: _dt(j['planned_arrival']),
        ticket: ticketFromWire(_sn(j['ticket'])),
        checkedInAt: _dt(j['checked_in_at']) ?? DateTime.now().toUtc(),
        locationVerified: _b(j['location_verified']),
        status: switch (_s(j['status'])) { 'arrived' => ApiRideStatus.arrived, 'abandoned' => ApiRideStatus.abandoned, _ => ApiRideStatus.riding },
        passedStops: _i(j['passed_stops']),
        liveDelayMinutes: _i(j['live_delay_minutes'] ?? j['live_delay_min']),
        cause: _sn(j['cause']),
        finalDelayMinutes: _in(j['final_delay_minutes'] ?? j['final_delay_min']),
        cancelled: _b(j['cancelled']),
        selfEntered: _b(j['self_entered']),
        nachtrag: _b(j['nachtrag']),
        points: _i(j['points']),
        date: _date(j['date']) ?? _dt(j['planned_arrival'])?.toLocal() ?? DateTime.now(),
      );
}

class ApiRideLive {
  const ApiRideLive({required this.ride, this.stops = const [], this.eta});
  final ApiRide ride;
  final List<ApiStop> stops;
  final DateTime? eta;
  factory ApiRideLive.fromJson(Map<String, dynamic> j) =>
      ApiRideLive(ride: ApiRide.fromJson(_m(j['ride'])!), stops: _ml(j['stops']).map(ApiStop.fromJson).toList(), eta: _dt(j['eta']));
}

class ApiArrivalResult {
  const ApiArrivalResult({required this.ride, this.incident, this.bundleReady = false, this.newBadge});
  final ApiRide ride;
  final ApiIncident? incident;
  final bool bundleReady;
  final ApiBadge? newBadge;
  factory ApiArrivalResult.fromJson(Map<String, dynamic> j) => ApiArrivalResult(
        ride: ApiRide.fromJson(_m(j['ride'])!),
        incident: _m(j['incident']) == null ? null : ApiIncident.fromJson(_m(j['incident'])!),
        bundleReady: _b(j['bundle_ready']),
        newBadge: _m(j['new_badge']) == null ? null : ApiBadge.fromJson(_m(j['new_badge'])!),
      );
}

// ---------------------------------------------------------------------------
// Ledger and claims
// ---------------------------------------------------------------------------

class ApiEvidence {
  const ApiEvidence({this.plannedArrival, this.actualArrival, required this.source, this.fetchedAt});
  final DateTime? plannedArrival;
  final DateTime? actualArrival;
  final String source;
  final DateTime? fetchedAt;
  factory ApiEvidence.fromJson(Map<String, dynamic> j) =>
      ApiEvidence(plannedArrival: _dt(j['planned_arrival']), actualArrival: _dt(j['actual_arrival']), source: _s(j['source']), fetchedAt: _dt(j['fetched_at']));
}

class ApiIncident {
  const ApiIncident({
    required this.id,
    this.rideId,
    this.journeyId,
    required this.date,
    required this.line,
    required this.from,
    required this.to,
    required this.delayMinutes,
    required this.amountCents,
    required this.ticket,
    required this.operator,
    required this.desk,
    required this.status,
    this.cancelled = false,
    this.selfEntered = false,
    required this.ngoId,
    this.claimId,
    this.fareCents,
    required this.legalDeadline,
    this.evidence,
    this.discardedAt,
    this.discardReason,
  });
  final String id;
  final String? rideId;
  final String? journeyId;
  final DateTime date;
  final String line;
  final String from;
  final String to;
  final int delayMinutes;
  final int amountCents;
  final TicketType ticket;
  final String operator;
  final String desk;
  final IncidentStatus status;
  final bool cancelled;
  final bool selfEntered;
  final String ngoId;
  final String? claimId;
  final int? fareCents;
  final DateTime legalDeadline;
  final ApiEvidence? evidence;

  /// Set when the passenger took this case out of the bundle (docs/21 §4).
  final DateTime? discardedAt;
  final String? discardReason;

  bool get discarded => discardedAt != null;
  bool get isOpen => !discarded && (status == IncidentStatus.gesammelt || status == IncidentStatus.bereit);

  factory ApiIncident.fromJson(Map<String, dynamic> j) => ApiIncident(
        id: _s(j['id']),
        rideId: _sn(j['ride_id']),
        journeyId: _sn(j['journey_id']),
        date: _date(j['date'] ?? j['ride_date']) ?? DateTime.now(),
        line: _s(j['line']),
        from: _s(j['from'] ?? j['from_name']),
        to: _s(j['to'] ?? j['to_name']),
        delayMinutes: _i(j['delay_minutes'] ?? j['delay_min']),
        amountCents: _i(j['amount_cents']),
        ticket: ticketFromWire(_sn(j['ticket'])),
        operator: _s(j['operator']),
        desk: _s(j['desk']),
        status: incidentStatusFromWire(_sn(j['status'])),
        cancelled: _b(j['cancelled']),
        selfEntered: _b(j['self_entered']),
        ngoId: _s(j['ngo_id']),
        claimId: _sn(j['claim_id']),
        fareCents: _in(j['fare_cents']),
        legalDeadline: _date(j['legal_deadline']) ?? DateTime.now(),
        evidence: _m(j['evidence']) == null ? null : ApiEvidence.fromJson(_m(j['evidence'])!),
        discardedAt: _dt(j['discarded_at']),
        discardReason: _sn(j['discard_reason']),
      );
}

class ApiDeskSummary {
  const ApiDeskSummary({required this.desk, required this.openCents, required this.ready, required this.missingCents, required this.incidentIds});
  final String desk;
  final int openCents;
  final bool ready;
  final int missingCents;
  final List<String> incidentIds;
  factory ApiDeskSummary.fromJson(Map<String, dynamic> j) => ApiDeskSummary(
        desk: _s(j['desk']),
        openCents: _i(j['open_cents']),
        ready: _b(j['ready']),
        missingCents: _i(j['missing_cents']),
        incidentIds: _sl(j['incident_ids']),
      );
}

class ApiOldestOpen {
  const ApiOldestOpen({required this.id, required this.line, required this.date, required this.deadline, required this.daysLeft});
  final String id;
  final String line;
  final DateTime date;
  final DateTime deadline;
  final int daysLeft;
  factory ApiOldestOpen.fromJson(Map<String, dynamic> j) => ApiOldestOpen(
        id: _s(j['id']),
        line: _s(j['line']),
        date: _date(j['date']) ?? DateTime.now(),
        deadline: _date(j['deadline']) ?? DateTime.now(),
        daysLeft: _i(j['days_left']),
      );
}

class ApiIncidentSummary {
  const ApiIncidentSummary({this.desks = const [], this.readyDesk, this.confirmedCents = 0, this.submittedCents = 0, this.oldestOpen, this.minPayoutCents = 400});
  final List<ApiDeskSummary> desks;
  final String? readyDesk;
  final int confirmedCents;
  final int submittedCents;
  final ApiOldestOpen? oldestOpen;
  final int minPayoutCents;
  factory ApiIncidentSummary.fromJson(Map<String, dynamic> j) => ApiIncidentSummary(
        desks: _ml(j['desks']).map(ApiDeskSummary.fromJson).toList(),
        readyDesk: _sn(j['ready_desk']),
        confirmedCents: _i(j['confirmed_cents']),
        submittedCents: _i(j['submitted_cents']),
        oldestOpen: _m(j['oldest_open']) == null ? null : ApiOldestOpen.fromJson(_m(j['oldest_open'])!),
        minPayoutCents: _i(j['min_payout_cents'], 400),
      );
}

class ApiIncidents {
  const ApiIncidents({required this.incidents, required this.summary});
  final List<ApiIncident> incidents;
  final ApiIncidentSummary summary;
  factory ApiIncidents.fromJson(Map<String, dynamic> j) =>
      ApiIncidents(incidents: _ml(j['incidents']).map(ApiIncident.fromJson).toList(), summary: ApiIncidentSummary.fromJson(_m(j['summary']) ?? const {}));
}

class ApiClaim {
  const ApiClaim({
    required this.id,
    required this.desk,
    required this.incidentIds,
    required this.ngoId,
    required this.accountHolder,
    required this.iban,
    this.ticketMonths = const [],
    this.attachments = const [],
    this.signedBy,
    required this.status,
    this.sentAt,
    this.expectedReplyBy,
    this.amountClaimedCents = 0,
    this.amountConfirmedCents,
    this.pdfUrl,
    this.replyAddress,
  });
  final String id;
  final String desk;
  final List<String> incidentIds;
  final String ngoId;
  final String accountHolder;
  final String iban;
  final List<String> ticketMonths;
  final List<String> attachments;
  final String? signedBy;
  final ApiClaimStatus status;
  final DateTime? sentAt;
  final DateTime? expectedReplyBy;
  final int amountClaimedCents;
  final int? amountConfirmedCents;
  final String? pdfUrl;

  /// The claim's own mail address (`antrag-…@users.…`), assigned at send time (docs/18).
  final String? replyAddress;

  factory ApiClaim.fromJson(Map<String, dynamic> j) => ApiClaim(
        id: _s(j['id']),
        desk: _s(j['desk']),
        incidentIds: j['incident_ids'] != null ? _sl(j['incident_ids']) : _ml(j['incidents']).map((e) => _s(e['id'])).toList(),
        ngoId: _s(j['ngo_id']),
        accountHolder: _s(j['account_holder']),
        iban: _s(j['iban']),
        ticketMonths: _sl(j['ticket_months']),
        attachments: _labels(j['attachments']),
        signedBy: _sn(j['signed_by']),
        status: claimStatusFromWire(_sn(j['status'])),
        sentAt: _dt(j['sent_at']),
        expectedReplyBy: _date(j['expected_reply_by']),
        amountClaimedCents: _i(j['amount_claimed_cents']),
        amountConfirmedCents: _in(j['amount_confirmed_cents']),
        pdfUrl: _sn(j['pdf_url']),
        replyAddress: _sn(j['reply_address']),
      );
}

class ApiClaimDraft {
  const ApiClaimDraft({required this.claim, this.deskAddress, this.deskEmail, this.personalDataRequired = false, this.relayAddress});
  final ApiClaim claim;
  final String? deskAddress;
  final String? deskEmail;
  final bool personalDataRequired;
  final String? relayAddress;
  factory ApiClaimDraft.fromJson(Map<String, dynamic> j) => ApiClaimDraft(
        claim: ApiClaim.fromJson(_m(j['claim']) ?? j),
        deskAddress: _sn(j['desk_address']),
        deskEmail: _sn(j['desk_email']),
        personalDataRequired: _b(j['personal_data_required']),
        relayAddress: _sn(j['relay_address']),
      );
}

class ApiUpload {
  const ApiUpload({required this.uploadId});
  final String uploadId;
  factory ApiUpload.fromJson(Map<String, dynamic> j) => ApiUpload(uploadId: _s(j['upload_id'] ?? j['id']));
}

class ApiMail {
  const ApiMail({
    required this.id,
    this.claimId,
    this.incidentIds = const [],
    required this.direction,
    required this.from,
    required this.to,
    this.bcc,
    required this.subject,
    required this.body,
    required this.date,
    this.attachments = const [],
    this.amountCents,
    this.outcome,
  });
  final String id;
  final String? claimId;
  final List<String> incidentIds;
  final ApiMailDirection direction;
  final String from;
  final String to;
  final String? bcc;
  final String subject;
  final String body;
  final DateTime date;
  final List<String> attachments;
  final int? amountCents;
  final ApiMailOutcome? outcome;

  factory ApiMail.fromJson(Map<String, dynamic> j) => ApiMail(
        id: _s(j['id']),
        claimId: _sn(j['claim_id']),
        incidentIds: _sl(j['incident_ids']),
        direction: _s(j['direction']) == 'inbound' ? ApiMailDirection.inbound : ApiMailDirection.out,
        from: _s(j['from'] ?? j['from_addr']),
        to: _s(j['to'] ?? j['to_addr']),
        bcc: _sn(j['bcc'] ?? j['bcc_addr']),
        subject: _s(j['subject']),
        body: _s(j['body']),
        date: _dt(j['date'] ?? j['received_at'] ?? j['sent_at'] ?? j['occurred_at']) ?? DateTime.now().toUtc(),
        attachments: _labels(j['attachments']),
        amountCents: _in(j['amount_cents']),
        outcome: j['outcome'] == null ? null : ApiMailOutcome.values.firstWhere((o) => o.name == j['outcome'], orElse: () => ApiMailOutcome.other),
      );
}

class ApiSendResult {
  const ApiSendResult({required this.claim, required this.mail});
  final ApiClaim claim;
  final ApiMail mail;
  factory ApiSendResult.fromJson(Map<String, dynamic> j) => ApiSendResult(claim: ApiClaim.fromJson(_m(j['claim'])!), mail: ApiMail.fromJson(_m(j['mail'])!));
}

class ApiInboundResult {
  const ApiInboundResult({required this.mail, required this.outcome});
  final ApiMail mail;
  final ApiMailOutcome outcome;
  factory ApiInboundResult.fromJson(Map<String, dynamic> j) => ApiInboundResult(
        mail: ApiMail.fromJson(_m(j['mail'])!),
        outcome: ApiMailOutcome.values.firstWhere((o) => o.name == j['outcome'], orElse: () => ApiMailOutcome.other),
      );
}

// ---------------------------------------------------------------------------
// Community
// ---------------------------------------------------------------------------

class ApiNgoTotal {
  const ApiNgoTotal({required this.id, required this.name, required this.confirmedCents, required this.submittedCents});
  final String id;
  final String name;
  final int confirmedCents;
  final int submittedCents;
  factory ApiNgoTotal.fromJson(Map<String, dynamic> j) =>
      ApiNgoTotal(id: _s(j['id']), name: _s(j['name']), confirmedCents: _i(j['confirmed_cents']), submittedCents: _i(j['submitted_cents']));
}

class ApiCommunity {
  const ApiCommunity({required this.minutes, required this.submittedCents, required this.confirmedCents, required this.users, this.ngos = const []});
  final int minutes;
  final int submittedCents;
  final int confirmedCents;
  final int users;
  final List<ApiNgoTotal> ngos;
  factory ApiCommunity.fromJson(Map<String, dynamic> j) => ApiCommunity(
        minutes: _i(j['minutes']),
        submittedCents: _i(j['submitted_cents']),
        confirmedCents: _i(j['confirmed_cents']),
        users: _i(j['users']),
        ngos: _ml(j['ngos']).map(ApiNgoTotal.fromJson).toList(),
      );
}

class ApiBoardEntry {
  const ApiBoardEntry({required this.rank, required this.name, required this.points, this.isMe = false});
  final int rank;
  final String name;
  final int points;
  final bool isMe;
  factory ApiBoardEntry.fromJson(Map<String, dynamic> j) => ApiBoardEntry(rank: _i(j['rank']), name: _s(j['name']), points: _i(j['points']), isMe: _b(j['is_me']));
}
/// Attachment labels from plain strings or `{label|name|upload_id}` objects.
List<String> _labels(dynamic v) => (v as List? ?? const [])
    .map((e) => e is Map ? (e['label'] ?? e['name'] ?? e['upload_id'] ?? '').toString() : e.toString())
    .where((e) => e.isNotEmpty)
    .toList();

// ---------------------------------------------------------------------------
// Standing: everything the Bahnsteig shows below the action block (docs/16).
// ---------------------------------------------------------------------------

class ApiStanding {
  const ApiStanding({
    this.pointsThisWeek = 0,
    this.pointsLastWeek = 0,
    this.ridesThisWeek = 0,
    this.level,
    this.money,
    this.board,
    this.community,
    this.next,
    this.unreadMails = 0,
  });
  final int pointsThisWeek;
  final int pointsLastWeek;
  final int ridesThisWeek;
  final ApiStandingLevel? level;
  final ApiStandingMoney? money;
  final ApiStandingBoard? board;
  final ApiStandingCommunity? community;
  final ApiStandingNext? next;

  /// Inbound railway mails nobody has opened yet, all claims (docs/18). The Anträge tab badge.
  final int unreadMails;

  /// What an older backend without the endpoint amounts to: nothing to show.
  static const empty = ApiStanding();

  factory ApiStanding.fromJson(Map<String, dynamic> j) => ApiStanding(
        pointsThisWeek: _i(j['points_this_week']),
        pointsLastWeek: _i(j['points_last_week']),
        ridesThisWeek: _i(j['rides_this_week']),
        level: _m(j['level']) == null ? null : ApiStandingLevel.fromJson(_m(j['level'])!),
        money: _m(j['money']) == null ? null : ApiStandingMoney.fromJson(_m(j['money'])!),
        board: _m(j['board']) == null ? null : ApiStandingBoard.fromJson(_m(j['board'])!),
        community: _m(j['community']) == null ? null : ApiStandingCommunity.fromJson(_m(j['community'])!),
        next: _m(j['next']) == null ? null : ApiStandingNext.fromJson(_m(j['next'])!),
        unreadMails: _i(j['unread_mails']),
      );
}

class ApiStandingLevel {
  const ApiStandingLevel({required this.name, required this.nextName, required this.pointsToNext, required this.progress});
  final String name;
  final String nextName;
  final int pointsToNext;
  final double progress; // 0..1
  factory ApiStandingLevel.fromJson(Map<String, dynamic> j) => ApiStandingLevel(
        name: _s(j['name']),
        nextName: _s(j['next_name']),
        pointsToNext: _i(j['points_to_next']),
        progress: ((j['progress'] as num?)?.toDouble() ?? 0).clamp(0, 1),
      );
}

class ApiStandingMoney {
  const ApiStandingMoney({required this.openCents, required this.missingCents, required this.ready, this.readyDesk, required this.ngoName});
  final int openCents;
  final int missingCents;
  final bool ready;
  final String? readyDesk;
  final String ngoName;
  factory ApiStandingMoney.fromJson(Map<String, dynamic> j) => ApiStandingMoney(
        openCents: _i(j['open_cents']),
        missingCents: _i(j['missing_cents']),
        ready: _b(j['ready']),
        readyDesk: _sn(j['ready_desk']),
        ngoName: _s(j['ngo_name']),
      );
}

class ApiStandingBoard {
  const ApiStandingBoard({required this.scope, required this.key, required this.rank, required this.size, required this.points, this.gapToNext});
  final String scope; // line | city
  final String key;
  final int rank;
  final int size;
  final int points;
  final int? gapToNext;
  factory ApiStandingBoard.fromJson(Map<String, dynamic> j) => ApiStandingBoard(
        scope: _s(j['scope']),
        key: _s(j['key']),
        rank: _i(j['rank']),
        size: _i(j['size']),
        points: _i(j['points']),
        gapToNext: j['gap_to_next'] == null ? null : _i(j['gap_to_next']),
      );
}

class ApiStandingCommunity {
  const ApiStandingCommunity({required this.minutesTotal, required this.myMinutes, required this.confirmedCents, required this.myConfirmedCents});
  final int minutesTotal;
  final int myMinutes;
  final int confirmedCents;
  final int myConfirmedCents;
  factory ApiStandingCommunity.fromJson(Map<String, dynamic> j) => ApiStandingCommunity(
        minutesTotal: _i(j['minutes_total']),
        myMinutes: _i(j['my_minutes']),
        confirmedCents: _i(j['confirmed_cents']),
        myConfirmedCents: _i(j['my_confirmed_cents']),
      );
}

/// The one thing the Bahnsteig suggests next: mail | deadline | nachtrag | badge.
class ApiStandingNext {
  const ApiStandingNext({required this.kind, required this.title, required this.body, this.claimId, this.incidentId, this.badgeId, this.daysLeft});
  final String kind;
  final String title;
  final String body;
  final String? claimId;
  final String? incidentId;
  final String? badgeId;
  final int? daysLeft;
  factory ApiStandingNext.fromJson(Map<String, dynamic> j) => ApiStandingNext(
        kind: _s(j['kind']),
        title: _s(j['title']),
        body: _s(j['body']),
        claimId: _sn(j['claim_id']),
        incidentId: _sn(j['incident_id']),
        badgeId: _sn(j['badge_id']),
        daysLeft: j['days_left'] == null ? null : _i(j['days_left']),
      );
}

// ---------------------------------------------------------------------------
// Journeys (docs/17): destination first, legs confirmed one at a time
// ---------------------------------------------------------------------------

enum ApiJourneyStatus { riding, transfer, arrived, abandoned }

ApiJourneyStatus journeyStatusFromWire(String? s) => switch (s) {
      'transfer' => ApiJourneyStatus.transfer,
      'arrived' => ApiJourneyStatus.arrived,
      'abandoned' => ApiJourneyStatus.abandoned,
      _ => ApiJourneyStatus.riding,
    };

enum ApiLegStatus { planned, riding, arrived, cancelled, skipped }

ApiLegStatus legStatusFromWire(String? s) => switch (s) {
      'riding' => ApiLegStatus.riding,
      'arrived' => ApiLegStatus.arrived,
      'cancelled' => ApiLegStatus.cancelled,
      'skipped' => ApiLegStatus.skipped,
      _ => ApiLegStatus.planned,
    };

/// One train of a journey: inside an itinerary (planned), inside a journey (with its
/// ride and outcome), or as the proposed next leg during a transfer.
class ApiLeg {
  const ApiLeg({
    required this.tripId,
    required this.line,
    this.headsign = '',
    this.operator = '',
    this.category = ApiCategory.other,
    required this.fromStationId,
    required this.fromStationName,
    required this.toStationId,
    required this.toStationName,
    this.plannedDeparture,
    this.plannedArrival,
    this.liveDeparture,
    this.liveArrival,
    this.platform,
    this.cancelled = false,
    this.delayMin = 0,
    this.legNo,
    this.rideId,
    this.status = ApiLegStatus.planned,
    this.actualArrival,
    this.finalDelayMin,
    this.replanned = false,
    this.reason,
  });
  final String tripId;
  final String line;
  final String headsign;
  final String operator;
  final ApiCategory category;
  final String fromStationId;
  final String fromStationName;
  final String toStationId;
  final String toStationName;
  final DateTime? plannedDeparture;
  final DateTime? plannedArrival;
  final DateTime? liveDeparture;
  final DateTime? liveArrival;
  final String? platform;
  final bool cancelled;
  final int delayMin;
  final int? legNo;
  final String? rideId;
  final ApiLegStatus status;
  final DateTime? actualArrival;
  final int? finalDelayMin;
  /// Next leg only: true after a missed connection, with [reason] "verpasst" or "ausfall".
  final bool replanned;
  final String? reason;

  /// The departure this leg looks like on a board.
  ApiDeparture toDeparture() => ApiDeparture(
        tripId: tripId,
        line: line,
        destination: headsign.isNotEmpty ? headsign : toStationName,
        scheduledDeparture: plannedDeparture ?? DateTime.now().toUtc(),
        departure: liveDeparture ?? plannedDeparture?.add(Duration(minutes: delayMin)),
        realtime: liveDeparture != null,
        platform: platform,
        category: category,
        operator: operator,
        cancelled: cancelled,
      );

  factory ApiLeg.fromJson(Map<String, dynamic> j) => ApiLeg(
        tripId: _s(j['trip_id']),
        line: _s(j['line']),
        headsign: _s(j['headsign'] ?? j['destination']),
        operator: _s(j['operator']),
        category: categoryFromWire(_sn(j['category'])),
        fromStationId: _s(j['from_station_id']),
        fromStationName: _s(j['from_station_name']),
        toStationId: _s(j['to_station_id']),
        toStationName: _s(j['to_station_name']),
        plannedDeparture: _dt(j['planned_departure']),
        plannedArrival: _dt(j['planned_arrival']),
        liveDeparture: _dt(j['live_departure']),
        liveArrival: _dt(j['live_arrival']),
        platform: _sn(j['platform']),
        cancelled: _b(j['cancelled']),
        delayMin: _i(j['delay_min'] ?? j['delay_minutes']),
        legNo: _in(j['leg_no']),
        rideId: _sn(j['ride_id']),
        status: legStatusFromWire(_sn(j['status'])),
        actualArrival: _dt(j['actual_arrival']),
        finalDelayMin: _in(j['final_delay_min'] ?? j['final_delay_minutes']),
        replanned: _b(j['replanned']),
        reason: _sn(j['reason']),
      );

  /// The check-in re-reads every trip, so only the ids need to travel — plus the operator the
  /// plan resolved, because for a through-service the trip names the whole run's railway and
  /// the plan the leg's, and the claim's desk follows the leg (see `settle_operator` on the
  /// backend). The backend ignores it unless it names a railway in its directory.
  Map<String, dynamic> toStartJson() => {
        'trip_id': tripId,
        'from_station_id': fromStationId,
        'to_station_id': toStationId,
        if (operator.isNotEmpty) 'operator': operator,
      };
}

/// One way to get there: rail legs only, transfers folded in between.
class ApiItinerary {
  const ApiItinerary({
    required this.id,
    this.preferred = false,
    this.transfers = 0,
    this.transferStations = const [],
    this.plannedDeparture,
    this.plannedArrival,
    this.liveArrival,
    this.durationMin,
    required this.legs,
  });
  final String id;
  final bool preferred;
  final int transfers;
  final List<String> transferStations;
  final DateTime? plannedDeparture;
  final DateTime? plannedArrival;
  final DateTime? liveArrival;
  final int? durationMin;
  final List<ApiLeg> legs;

  ApiLeg get first => legs.first;
  bool get direct => transfers == 0;

  factory ApiItinerary.fromJson(Map<String, dynamic> j) => ApiItinerary(
        id: _s(j['id']),
        preferred: _b(j['preferred']),
        transfers: _i(j['transfers']),
        transferStations: (j['transfer_stations'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        plannedDeparture: _dt(j['planned_departure']),
        plannedArrival: _dt(j['planned_arrival']),
        liveArrival: _dt(j['live_arrival']),
        durationMin: _in(j['duration_min']),
        legs: _ml(j['legs']).map(ApiLeg.fromJson).toList(),
      );
}

class ApiPlan {
  const ApiPlan({this.from, this.to, required this.itineraries});
  final ApiStation? from;
  final ApiStation? to;
  final List<ApiItinerary> itineraries;
  factory ApiPlan.fromJson(Map<String, dynamic> j) => ApiPlan(
        from: _m(j['from']) == null ? null : ApiStation.fromJson(_m(j['from'])!),
        to: _m(j['to']) == null ? null : ApiStation.fromJson(_m(j['to'])!),
        itineraries: _ml(j['itineraries']).map(ApiItinerary.fromJson).toList(),
      );
}

class ApiJourney {
  const ApiJourney({
    required this.id,
    required this.status,
    required this.originStationId,
    required this.originStationName,
    required this.destinationStationId,
    required this.destinationStationName,
    this.plannedDeparture,
    this.plannedArrival,
    this.actualArrival,
    this.finalDelayMin,
    this.missedConnection = false,
    this.incomplete = false,
    this.cancelled = false,
    this.points = 0,
    this.ticket = TicketType.deutschlandticket,
    this.currentLeg = 1,
    this.legs = const [],
    this.nextLeg,
    this.transferStationName,
    this.transferDeadline,
    this.endReason,
    this.replanned = false,
    this.transferReason,
    this.earliestOnwardArrival,
    this.deletable = true,
    this.deleteRefusal,
    this.stale = false,
    this.legacy = false,
    required this.createdAt,
    this.finalisedAt,
  });
  final String id;
  final ApiJourneyStatus status;
  final String originStationId;
  final String originStationName;
  final String destinationStationId;
  final String destinationStationName;
  final DateTime? plannedDeparture;
  final DateTime? plannedArrival;
  final DateTime? actualArrival;
  final int? finalDelayMin;
  final bool missedConnection;
  final bool incomplete;
  final bool cancelled;
  final int points;
  final TicketType ticket;
  final int currentLeg;
  final List<ApiLeg> legs;
  final ApiLeg? nextLeg;
  final String? transferStationName;
  final DateTime? transferDeadline;

  /// How the journey ended (docs/21 §3): `beendet`, `aufgegeben`, `nicht_gefahren`, or null.
  final String? endReason;

  /// The passenger asked to continue, so this transfer is a Weiterfahrt, not an Umstieg.
  final bool replanned;

  /// `umstieg` (planned or missed) or `weiterfahrt` (the passenger's own decision).
  final String? transferReason;

  /// When the journey was interrupted (docs/21 §2): the destination arrival of the earliest
  /// onward connection that existed at that moment. A self-chosen pause beyond it is the
  /// passenger's own time and never counts, so this is the ceiling for everything we show.
  final DateTime? earliestOnwardArrival;

  /// The most the delay can still come to: the railway's part, in minutes. Null when the
  /// journey was never interrupted, so nothing is capped.
  int? get countedCeilingMinutes {
    final e = earliestOnwardArrival, p = plannedArrival;
    if (e == null || p == null) return null;
    final m = e.difference(p).inMinutes;
    return m < 0 ? 0 : m;
  }

  /// A delay to show the passenger, never more than the claim can contain.
  int cappedDelay(int liveMinutes) {
    final ceiling = countedCeilingMinutes;
    if (ceiling == null) return liveMinutes;
    return liveMinutes < ceiling ? liveMinutes : ceiling;
  }

  /// May the passenger throw this ride away (docs/23 §2)? False once its case is out of
  /// the house; [deleteRefusal] then says why, so the action is never silently absent.
  final bool deletable;
  final String? deleteRefusal;

  /// Still under way three hours past the planned arrival (docs/23 §3): the bar asks.
  final bool stale;

  /// A ride from before journeys existed: it is deleted through its own route.
  final bool legacy;

  final DateTime createdAt;
  final DateTime? finalisedAt;

  bool get gaveUp => endReason == 'aufgegeben';
  bool get neverTravelled => endReason == 'nicht_gefahren';

  /// A transfer the passenger asked for (docs/21 §2), as opposed to a planned change or a
  /// missed connection. The backend says which; older payloads fall back to the shape.
  bool get waitingForOwnTrain =>
      inTransfer && (transferReason == 'weiterfahrt' || (transferReason == null && (replanned || (nextLeg == null && !missedConnection))));

  bool get riding => status == ApiJourneyStatus.riding;
  bool get inTransfer => status == ApiJourneyStatus.transfer;
  bool get arrived => status == ApiJourneyStatus.arrived;
  bool get done => status == ApiJourneyStatus.arrived || status == ApiJourneyStatus.abandoned;
  int get transfers => legs.length > 1 ? legs.length - 1 : 0;
  ApiLeg? get currentLegInfo => legs.where((l) => l.legNo == currentLeg).firstOrNull ?? (legs.isEmpty ? null : legs[(currentLeg - 1).clamp(0, legs.length - 1)]);
  DateTime get date => (plannedDeparture ?? createdAt).toLocal();
  String get lineLabel => legs.map((l) => l.line).where((l) => l.isNotEmpty).join(' · ');

  factory ApiJourney.fromJson(Map<String, dynamic> j) => ApiJourney(
        id: _s(j['id']),
        status: journeyStatusFromWire(_sn(j['status'])),
        originStationId: _s(j['origin_station_id'] ?? j['from_station_id']),
        originStationName: _s(j['origin_station_name'] ?? j['from_station_name']),
        destinationStationId: _s(j['destination_station_id'] ?? j['to_station_id']),
        destinationStationName: _s(j['destination_station_name'] ?? j['to_station_name']),
        plannedDeparture: _dt(j['planned_departure']),
        plannedArrival: _dt(j['planned_arrival']),
        actualArrival: _dt(j['actual_arrival']),
        finalDelayMin: _in(j['final_delay_min'] ?? j['final_delay_minutes']),
        missedConnection: _b(j['missed_connection']),
        incomplete: _b(j['incomplete']),
        cancelled: _b(j['cancelled']),
        points: _i(j['points']),
        ticket: ticketFromWire(_sn(j['ticket'])),
        currentLeg: _i(j['current_leg'], 1),
        legs: _ml(j['legs']).map(ApiLeg.fromJson).toList(),
        nextLeg: _m(j['next_leg']) == null ? null : ApiLeg.fromJson(_m(j['next_leg'])!),
        transferStationName: _sn(j['transfer_station_name']),
        transferDeadline: _dt(j['transfer_deadline']),
        endReason: _sn(j['end_reason']),
        replanned: _b(j['replanned']),
        transferReason: _sn(j['transfer_reason']),
        earliestOnwardArrival: _dt(j['earliest_onward_arrival']),
        deletable: j['deletable'] == null ? true : _b(j['deletable']),
        deleteRefusal: _sn(j['delete_refusal']),
        stale: _b(j['stale']),
        legacy: _b(j['legacy']),
        createdAt: _dt(j['created_at']) ?? DateTime.now().toUtc(),
        finalisedAt: _dt(j['finalised_at']),
      );
}

/// `GET /v1/journeys/current`: the journey plus the live view of its current leg.
class ApiJourneyLive {
  const ApiJourneyLive({required this.journey, this.ride, this.stops = const [], this.eta, this.nextLeg, this.justArrived = false, this.claimFromMinute = 60});
  final ApiJourney journey;
  final ApiRide? ride;
  final List<ApiStop> stops;
  final DateTime? eta;
  final ApiLeg? nextLeg;
  final bool justArrived;
  final int claimFromMinute;

  /// The same view the old ride screens consume, for the current leg.
  ApiRideLive? get asRideLive => ride == null ? null : ApiRideLive(ride: ride!, stops: stops, eta: eta);

  factory ApiJourneyLive.fromJson(Map<String, dynamic> j) {
    final jm = _m(j['journey']) ?? j;
    return ApiJourneyLive(
      journey: ApiJourney.fromJson(jm),
      ride: _m(j['ride']) == null ? null : ApiRide.fromJson(_m(j['ride'])!),
      stops: _ml(j['stops']).map(ApiStop.fromJson).toList(),
      eta: _dt(j['eta']),
      nextLeg: _m(j['next_leg']) == null ? (_m(jm['next_leg']) == null ? null : ApiLeg.fromJson(_m(jm['next_leg'])!)) : ApiLeg.fromJson(_m(j['next_leg'])!),
      justArrived: _b(j['just_arrived']),
      claimFromMinute: _i(j['claim_from_minute'], 60),
    );
  }
}

class StartJourneyRequest {
  const StartJourneyRequest({
    required this.fromStationId,
    required this.fromStationName,
    required this.toStationId,
    required this.toStationName,
    required this.legs,
    this.ticket,
    this.location,
    this.fromLat,
    this.fromLon,
  });
  final String fromStationId;
  final String fromStationName;
  final String toStationId;
  final String toStationName;
  final List<ApiLeg> legs;
  final TicketType? ticket;
  final ApiLocation? location;
  final double? fromLat;
  final double? fromLon;
  Map<String, dynamic> toJson() => {
        'from_station_id': fromStationId,
        'from_station_name': fromStationName,
        'to_station_id': toStationId,
        'to_station_name': toStationName,
        'legs': legs.map((l) => l.toStartJson()).toList(),
        if (ticket != null) 'ticket': ticketToWire(ticket!),
        if (location != null) 'location': location!.toJson(),
        if (fromLat != null && fromLon != null) ...{'from_lat': fromLat, 'from_lon': fromLon},
      };
}

/// A place the customer goes to: predicted (with a label such as "Nach Hause"), recent, or home.
class ApiDestination {
  const ApiDestination({required this.stationId, required this.stationName, this.label, this.count = 0, this.lastAt});
  final String stationId;
  final String stationName;
  final String? label;
  final int count;
  final DateTime? lastAt;
  ApiStation get station => ApiStation(id: stationId, name: stationName);
  factory ApiDestination.fromJson(Map<String, dynamic> j) => ApiDestination(
        stationId: _s(j['station_id'] ?? j['id']),
        stationName: _s(j['station_name'] ?? j['name']),
        label: _sn(j['label']),
        count: _i(j['count']),
        lastAt: _dt(j['last_at']),
      );
}

class ApiDestinations {
  const ApiDestinations({this.home, this.predicted = const [], this.recent = const []});
  static const empty = ApiDestinations();
  final ApiDestination? home;
  final List<ApiDestination> predicted;
  final List<ApiDestination> recent;
  factory ApiDestinations.fromJson(Map<String, dynamic> j) => ApiDestinations(
        home: _m(j['home']) == null ? null : ApiDestination.fromJson(_m(j['home'])!),
        predicted: _ml(j['predicted']).map(ApiDestination.fromJson).toList(),
        recent: _ml(j['recent']).map(ApiDestination.fromJson).toList(),
      );
}
