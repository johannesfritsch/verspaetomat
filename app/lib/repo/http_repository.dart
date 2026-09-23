import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kReleaseMode;

import '../api/client.dart';
import '../api/token_store.dart';
import '../platform/diagnose_log.dart';
import '../stations/station_store.dart';
import 'app_repository.dart';

/// The real thing: every call goes to the backend — except the two that no longer have to.
class HttpRepository implements AppRepository {
  HttpRepository({required this.client, required this.tokens, StationStore? stations})
      : stations = stations ?? StationStore();

  final ApiClient client;
  final TokenStore tokens;

  /// The phone's own copy of the station table (issue #39).
  final StationStore stations;

  /// Where Stellwerk says this customer is.
  ///
  /// The client-side half of what `handlers::stations_nearby` used to do server-side
  /// (backend/src/handlers.rs:66-73): the override wins over the phone's own fix. It arrives on
  /// the SSE `location` event (backend/src/admin.rs:422) and is seeded from `hello`
  /// (backend/src/events.rs:82); `repo_scope.dart` sets it.
  ApiSimLocation? simLocation;

  void setSimLocation(ApiSimLocation? at) => simLocation = at;

  /// Called with the `flags` map off every authenticated payload that carries one (issue #41),
  /// or with null when the server sent no such key.
  ///
  /// It lives here rather than at the call sites because the payload that matters most is
  /// `GET /v1/me/geofence`, and that one is refetched on every resume by `GeofenceSync`
  /// (app/lib/platform/geofence_sync.dart) — code this must not reach into. Hooking the
  /// repository catches the resume path, the cold start and every settings write with one seam
  /// and no change to the callers.
  ///
  /// `Session` sets it. Nothing else listens.
  void Function(Map<String, Object?>? flags)? onFlags;

  ApiCustomer _noteFlags(ApiCustomer c) {
    onFlags?.call(c.flags);
    return c;
  }

  /// The rung issue #39 leaves out, kept alive for `workflow_test.dart` and `stellwerk locate`.
  ///
  /// A compile-time constant, so a release build has **no reachable call** to
  /// `/v1/stations/nearby` or `/v1/stations/search` at all: `!kReleaseMode` closes the door even
  /// if somebody passed the define to a store build. The same shape as `GeofenceSync.automation`
  /// (app/lib/platform/geofence_sync.dart:36) and `TicketPhoto.automation`
  /// (app/lib/screens/claims/ticket_photo.dart:25).
  static const bool allowServerStations = !kReleaseMode &&
      (String.fromEnvironment('E2E') == 'true' ||
          String.fromEnvironment('NO_LOCATION') == '1' ||
          String.fromEnvironment('NO_LOCATION') == 'true');

  @override
  String get label => 'Lokal (${client.baseUrl})';

  /// Creates the device on first launch. Returns true when a token exists afterwards.
  /// A device for this install, made only when the keychain has answered „none". One at a
  /// time: the session, the 401 handler and the geofence sync used to ask in the same second,
  /// and each made an account of its own — four in seven seconds on 23 September 2026.
  /// A locked keychain throws [KeychainUnavailable] through to the caller.
  Future<bool> ensureDevice() => _ensuring ??= _ensureDevice().whenComplete(() => _ensuring = null);
  Future<bool>? _ensuring;

  Future<bool> _ensureDevice() async {
    if (await tokens.token() != null) return true;
    final auth = await client.createDevice();
    await tokens.save(deviceId: auth.deviceId, token: auth.token);
    return true;
  }

  Future<void> recover(String recoveryCode) async {
    final auth = await client.recoverDevice(recoveryCode);
    await tokens.save(deviceId: auth.deviceId, token: auth.token);
  }

  @override
  Future<bool> health() => client.health();
  @override
  Future<ApiCustomer> getMe() async => _noteFlags(await client.me());
  @override
  Future<ApiCustomer> patchMe(MePatch patch) async => _noteFlags(await client.patchMe(patch));
  @override
  Future<ApiCustomer> putPersonalData(ApiPersonalData data) async => _noteFlags(await client.putPersonalData(data));
  @override
  Future<ApiCustomer> deletePersonalData() async => _noteFlags(await client.deletePersonalData());
  @override
  Future<String?> recoveryCode({bool rotate = false}) => client.recoveryCode(rotate: rotate);
  @override
  Future<void> putPushToken({required String platform, required String token}) => client.putPushToken(platform: platform, token: token);

  @override
  Future<void> deleteMe() async {
    await client.deleteMe();
    await tokens.clear();
  }

  @override
  Future<String> exportMe() => client.exportMe();

  /// The stations around a point, from the phone's own table (issue #39).
  ///
  /// The ladder: the downloaded extract, else the one shipped with the build, else — only under
  /// the automation defines, and never in a release build — the server. There is deliberately no
  /// „ask the server" rung for a passenger: the whole point of the exercise is that a coordinate
  /// stops leaving the phone for this question.
  @override
  Future<ApiNearby> nearbyStations({double? lat, double? lon}) async {
    final local = await _localNearby(lat: lat, lon: lon);
    if (local != null && local.stations.isNotEmpty) return local;
    // Asking the server only after an empty local answer means the E2E exercises the new code
    // when it works, and still passes on a machine whose asset is stale.
    if (allowServerStations) return client.stationsNearby(lat: lat, lon: lon);
    return local ?? const ApiNearby(stations: [], source: 'none');
  }

  /// Rungs 1–2: the extract, around the Stellwerk override when there is one and the phone's own
  /// fix otherwise. Null when no extract could be read at all.
  Future<ApiNearby?> _localNearby({double? lat, double? lon}) async {
    final ix = await stations.index();
    if (ix == null) return null;
    final sim = simLocation;
    if (sim != null) {
      final answer = ix.nearby(lat: sim.lat, lon: sim.lon, source: 'stellwerk', label: sim.label);
      _logNearby(answer);
      return answer;
    }
    // No fix and no override is the same nothing the server answered (backend/src/handlers.rs:73).
    if (lat == null || lon == null) return const ApiNearby(stations: [], source: 'none');
    final answer = ix.nearby(lat: lat, lon: lon);
    _logNearby(answer);
    return answer;
  }

  /// The shape of the answer, never the query. The log has to stay safe to paste into a message
  /// (app/lib/platform/diagnose_log.dart:12-16), and writing the passenger's position into it for
  /// a lookup that no longer leaves the phone would add a disclosure at the moment this work
  /// removes one.
  void _logNearby(ApiNearby answer) {
    if (answer.stations.isEmpty) {
      DiagnoseLog.instance.add('stations', 'nearby → 0 · nichts in 50 km');
      return;
    }
    DiagnoseLog.instance.add(
      'stations',
      'nearby → ${answer.stations.length} · ${answer.searchRadiusM} m${answer.complete ? ' · complete' : ''}',
    );
  }

  @override
  Future<List<ApiStation>> searchStations(String query) async {
    final ix = await stations.index();
    if (ix != null) {
      final hits = ix.search(query);
      DiagnoseLog.instance.add('stations', 'suche → ${hits.length}');
      if (hits.isNotEmpty || !allowServerStations) return hits;
    }
    if (allowServerStations) return client.stationsSearch(query);
    return const [];
  }
  @override
  Future<List<ApiDeparture>> departures(String stationId) => client.departures(stationId);
  @override
  Future<ApiTrip> trip(String tripId) => client.trip(tripId);
  @override
  Future<List<ApiOperator>> operators() => client.operators();
  @override
  Future<List<ApiNgo>> ngos() => client.ngos();
  @override
  Future<List<ApiBadge>> badges() => client.badges();

  @override
  Future<List<ApiRide>> rides() => client.rides();
  @override
  Future<ApiGeofence> geofence() async {
    try {
      final g = await client.geofence();
      // The payload refetched on every resume, so this is what keeps a warm app's flags current.
      onFlags?.call(g.flags);
      return g;
    } on ApiException catch (e) {
      // An older backend without the route: no stations, nothing to watch. And nothing learned
      // about flags either — `ApiGeofence.empty` carries null, not an empty map.
      if (e.status == 404) return ApiGeofence.empty;
      rethrow;
    }
  }
  @override
  Future<ApiRideLive?> currentRide() => client.currentRide();
  @override
  Future<ApiArrivalResult> arrival(ArrivalRequest request) => client.arrival(request);
  @override
  Future<void> dismissRide() => client.dismissRide();
  @override
  Future<ApiArrivalResult> nachtrag(NachtragRequest request) => client.nachtrag(request);

  // Journeys: an older backend without the routes answers 404 → empty, never an error.
  @override
  Future<ApiDestinations> destinations({String? from}) async {
    try {
      return await client.destinations(from: from);
    } on ApiException catch (e) {
      if (e.status == 404) return ApiDestinations.empty;
      rethrow;
    }
  }

  @override
  Future<ApiPlan> planJourney({required String from, required String to, String? firstTrip}) => client.planJourney(from: from, to: to, firstTrip: firstTrip);
  @override
  Future<ApiJourneyLive> startJourney(StartJourneyRequest request) => client.startJourney(request);
  @override
  Future<ApiJourneyLive?> currentJourney() => client.currentJourney();
  @override
  Future<ApiJourneyLive> confirmLeg(String journeyId, String tripId) => client.confirmLeg(journeyId, tripId);
  @override
  Future<ApiJourney> finishJourney(String journeyId, {required bool arrived, String? reason}) => client.finishJourney(journeyId, arrived: arrived, reason: reason);
  @override
  Future<ApiJourneyLive> missedConnection(String journeyId) => client.missedConnection(journeyId);
  @override
  Future<ApiJourneyLive> replanJourney(String journeyId, {String? fromStationId, String? fromStationName}) =>
      client.replanJourney(journeyId, fromStationId: fromStationId, fromStationName: fromStationName);
  @override
  Future<ApiJourneyLive> changeTrain(String journeyId, String tripId, {String? fromStationId, String? fromStationName}) =>
      client.changeTrain(journeyId, tripId, fromStationId: fromStationId, fromStationName: fromStationName);
  @override
  Future<List<ApiJourney>> journeys() async {
    try {
      return await client.journeys();
    } on ApiException catch (e) {
      if (e.status == 404) return const [];
      rethrow;
    }
  }

  @override
  Future<bool> deleteJourney(String id) => client.deleteJourney(id);
  @override
  Future<bool> deleteRide(String id) => client.deleteRide(id);

  @override
  Future<ApiIncidents> incidents() => client.incidents();
  @override
  Future<bool> discardIncident(String id, String reason) => client.discardIncident(id, reason);
  @override
  Future<void> restoreIncident(String id) => client.restoreIncident(id);
  @override
  Future<List<ApiClaim>> claims() => client.claims();
  @override
  Future<void> markClaimSeen(String claimId) => client.markClaimSeen(claimId);
  @override
  Future<ApiClaimDraft> draftClaim({required String desk, List<String>? incidentIds}) => client.draftClaim(desk: desk, incidentIds: incidentIds);
  @override
  Future<ApiClaim> patchClaim(String id, {String? ngoId, List<ApiClaimAttachment>? attachments}) =>
      client.patchClaim(id, ngoId: ngoId, attachments: attachments);
  @override
  Future<ApiUpload> upload({required String kind, required String filename, required List<int> bytes}) =>
      client.upload(kind: kind, filename: filename, bytes: bytes);
  @override
  Future<ApiClaim> signClaim(String id, {required String typedName, String? signatureUploadId}) =>
      client.signClaim(id, typedName: typedName, signatureUploadId: signatureUploadId);
  @override
  Future<ApiSendResult> sendClaim(String id) => client.sendClaim(id);

  @override
  Future<Uint8List> claimPdf(String id) => client.claimPdf(id);
  @override
  Future<List<ApiMail>> mails() => client.mails();
  @override
  Future<ApiMail> replyToMail(String id, String body, {bool attachTicket = false, List<String> uploadIds = const []}) =>
      client.replyToMail(id, body, attachTicket: attachTicket, uploadIds: uploadIds);
  @override
  Future<ApiInboundResult> simulateInbound({required String body, String? claimId}) async {
    String? relay;
    try {
      relay = (await client.me()).relayAddress;
    } catch (_) {}
    return client.simulateInbound(body: body, claimId: claimId, relayAddress: relay);
  }

  @override
  Future<ApiCommunity> community() => client.community();

  @override
  Future<ApiShareFacts> shareFacts() async {
    try {
      return await client.shareFacts();
    } on ApiException catch (e) {
      if (e.status == 404) return ApiShareFacts.empty;
      rethrow;
    }
  }

  /// An older backend without the endpoint answers 404: nothing to show, no error.
  @override
  Future<ApiStanding> standing() async {
    try {
      return await client.standing();
    } on ApiException catch (e) {
      if (e.status == 404) return ApiStanding.empty;
      rethrow;
    }
  }
  @override
  Future<List<ApiBoardEntry>> boards(String scope) => client.boards(scope);
}
