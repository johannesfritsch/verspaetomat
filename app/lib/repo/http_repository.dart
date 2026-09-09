import '../api/client.dart';
import '../api/token_store.dart';
import 'app_repository.dart';

/// The real thing: every call goes to the backend.
class HttpRepository implements AppRepository {
  HttpRepository({required this.client, required this.tokens});

  final ApiClient client;
  final TokenStore tokens;

  @override
  String get label => 'Lokal (${client.baseUrl})';

  /// Creates the device on first launch. Returns true when a token exists afterwards.
  Future<bool> ensureDevice() async {
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
  Future<ApiCustomer> getMe() => client.me();
  @override
  Future<ApiCustomer> patchMe(MePatch patch) => client.patchMe(patch);
  @override
  Future<ApiCustomer> putPersonalData(ApiPersonalData data) => client.putPersonalData(data);
  @override
  Future<String> recoveryCode() => client.recoveryCode();
  @override
  Future<void> deleteMe() async {
    await client.deleteMe();
    await tokens.clear();
  }

  @override
  Future<String> exportMe() => client.exportMe();

  @override
  Future<ApiNearby> nearbyStations({double? lat, double? lon}) => client.stationsNearby(lat: lat, lon: lon);
  @override
  Future<List<ApiStation>> searchStations(String query) => client.stationsSearch(query);
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
  Future<ApiRide> checkIn(CheckInRequest request) => client.checkIn(request);
  @override
  Future<ApiRideLive?> currentRide() => client.currentRide();
  @override
  Future<ApiArrivalResult> arrival(ArrivalRequest request) => client.arrival(request);
  @override
  Future<void> dismissRide() => client.dismissRide();
  @override
  Future<ApiArrivalResult> nachtrag(NachtragRequest request) => client.nachtrag(request);

  @override
  Future<ApiIncidents> incidents() => client.incidents();
  @override
  Future<List<ApiClaim>> claims() => client.claims();
  @override
  Future<ApiClaimDraft> draftClaim({required String desk, List<String>? incidentIds}) => client.draftClaim(desk: desk, incidentIds: incidentIds);
  @override
  Future<ApiClaim> patchClaim(String id, {String? ngoId, List<String>? attachmentUploadIds}) =>
      client.patchClaim(id, ngoId: ngoId, attachmentUploadIds: attachmentUploadIds);
  @override
  Future<ApiUpload> upload({required String kind, required String filename, required List<int> bytes}) =>
      client.upload(kind: kind, filename: filename, bytes: bytes);
  @override
  Future<ApiClaim> signClaim(String id, {required String typedName, String? signatureUploadId}) =>
      client.signClaim(id, typedName: typedName, signatureUploadId: signatureUploadId);
  @override
  Future<ApiSendResult> sendClaim(String id) => client.sendClaim(id);
  @override
  Future<List<ApiMail>> mails() => client.mails();
  @override
  Future<ApiMail> replyToMail(String id, String body) => client.replyToMail(id, body);
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
  Future<List<ApiBoardEntry>> boards(String scope) => client.boards(scope);
  @override
  Future<List<ApiTeam>> teams() => client.teams();
  @override
  Future<ApiTeam> createTeam(String name) => client.createTeam(name);
  @override
  Future<ApiTeam> joinTeam(String inviteToken) => client.joinTeam(inviteToken);
}
