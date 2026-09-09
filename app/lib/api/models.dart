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

enum ApiRideStatus { riding, arrived }

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

class ApiStation {
  const ApiStation({required this.id, required this.name, this.lat = 0, this.lon = 0, this.distanceM, this.eva});
  final String id;
  final String name;
  final double lat;
  final double lon;
  final int? distanceM;
  final String? eva;

  String get distanceLabel {
    final d = distanceM;
    if (d == null) return '';
    return d < 1000 ? '$d m' : '${(d / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
  }

  factory ApiStation.fromJson(Map<String, dynamic> j) =>
      ApiStation(id: _s(j['id']), name: _s(j['name']), lat: _f(j['lat']), lon: _f(j['lon']), distanceM: _in(j['distance_m']), eva: _sn(j['eva']));
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
  });
  final TicketType ticket;
  final String ngoId;
  final LocationMode locationMode;
  final bool notifications;
  final bool showOnBoards;
  final bool keepCorrespondence;
  final bool traewellingLinked;
  final bool onboardingDone;

  factory ApiSettings.fromJson(Map<String, dynamic> j) => ApiSettings(
        ticket: ticketFromWire(_sn(j['ticket'])),
        ngoId: _s(j['ngo_id'], 'bahnhofsmission'),
        locationMode: locationFromWire(_sn(j['location_mode'])),
        notifications: _b(j['notifications'], true),
        showOnBoards: _b(j['show_on_boards'], true),
        keepCorrespondence: _b(j['keep_correspondence']),
        traewellingLinked: _b(j['traewelling_linked']),
        onboardingDone: _b(j['onboarding_done']),
      );
}

/// PATCH /v1/me body. Only set fields are sent.
class MePatch {
  const MePatch({this.ticket, this.ngoId, this.locationMode, this.notifications, this.showOnBoards, this.keepCorrespondence, this.traewellingLinked, this.onboardingDone, this.nickname});
  final TicketType? ticket;
  final String? ngoId;
  final LocationMode? locationMode;
  final bool? notifications;
  final bool? showOnBoards;
  final bool? keepCorrespondence;
  final bool? traewellingLinked;
  final bool? onboardingDone;
  final String? nickname;

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
      };
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
  });
  final String tripId;
  final String fromStationId;
  final String fromStationName;
  final String exitStationId;
  final String exitStationName;
  final TicketType? ticket;
  final ApiLocation? location;
  Map<String, dynamic> toJson() => {
        'trip_id': tripId,
        'from_station_id': fromStationId,
        'from_station_name': fromStationName,
        'exit_station_id': exitStationId,
        'exit_station_name': exitStationName,
        if (ticket != null) 'ticket': ticketToWire(ticket!),
        if (location != null) 'location': location!.toJson(),
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
        status: _s(j['status']) == 'arrived' ? ApiRideStatus.arrived : ApiRideStatus.riding,
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
  });
  final String id;
  final String? rideId;
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

  bool get isOpen => status == IncidentStatus.gesammelt || status == IncidentStatus.bereit;

  factory ApiIncident.fromJson(Map<String, dynamic> j) => ApiIncident(
        id: _s(j['id']),
        rideId: _sn(j['ride_id']),
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

class ApiTeam {
  const ApiTeam({required this.id, required this.name, this.members = const [], this.minutes = 0, this.eurosCents = 0, this.topMember, this.inviteToken});
  final String id;
  final String name;
  final List<String> members;
  final int minutes;
  final int eurosCents;
  final String? topMember;
  final String? inviteToken;
  factory ApiTeam.fromJson(Map<String, dynamic> j) => ApiTeam(
        id: _s(j['id']),
        name: _s(j['name']),
        members: _sl(j['members']),
        minutes: _i(j['minutes']),
        eurosCents: _i(j['euros_cents']),
        topMember: _sn(j['top_member']),
        inviteToken: _sn(j['invite_token']),
      );
}


/// Attachment labels from plain strings or `{label|name|upload_id}` objects.
List<String> _labels(dynamic v) => (v as List? ?? const [])
    .map((e) => e is Map ? (e['label'] ?? e['name'] ?? e['upload_id'] ?? '').toString() : e.toString())
    .where((e) => e.isNotEmpty)
    .toList();
