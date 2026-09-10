import 'dart:typed_data';
import '../api/models.dart';

export '../api/models.dart';

/// Everything a screen may ask for. Two implementations: the built-in demo
/// (wrapping DemoState and Mock) and the HTTP backend.
abstract class AppRepository {
  String get label;

  // -- health / customer ----------------------------------------------------
  Future<bool> health();
  Future<ApiCustomer> getMe();
  Future<ApiCustomer> patchMe(MePatch patch);

  /// The stations the phone should watch in the background (docs/15). Empty when unsupported.
  Future<ApiGeofence> geofence();
  Future<ApiCustomer> putPersonalData(ApiPersonalData data);
  Future<String> recoveryCode();
  Future<void> deleteMe();
  /// Stores the phone's push token on the device row; a no-op in Demo mode.
  Future<void> putPushToken({required String platform, required String token});
  Future<String> exportMe();

  // -- reference ------------------------------------------------------------
  Future<ApiNearby> nearbyStations({double? lat, double? lon});
  Future<List<ApiStation>> searchStations(String query);
  Future<List<ApiDeparture>> departures(String stationId);
  Future<ApiTrip> trip(String tripId);
  Future<List<ApiOperator>> operators();
  Future<List<ApiNgo>> ngos();
  Future<List<ApiBadge>> badges();

  // -- rides ----------------------------------------------------------------
  Future<List<ApiRide>> rides();
  Future<ApiRide> checkIn(CheckInRequest request);
  Future<ApiRideLive?> currentRide();
  Future<ApiArrivalResult> arrival(ArrivalRequest request);
  Future<void> dismissRide();
  Future<ApiArrivalResult> nachtrag(NachtragRequest request);

  // -- ledger and claims ----------------------------------------------------
  Future<ApiIncidents> incidents();
  Future<List<ApiClaim>> claims();
  Future<ApiClaimDraft> draftClaim({required String desk, List<String>? incidentIds});
  Future<ApiClaim> patchClaim(String id, {String? ngoId, List<String>? attachmentUploadIds});
  Future<ApiUpload> upload({required String kind, required String filename, required List<int> bytes});
  Future<ApiClaim> signClaim(String id, {required String typedName, String? signatureUploadId});
  Future<ApiSendResult> sendClaim(String id);
  Future<Uint8List> claimPdf(String id);
  Future<List<ApiMail>> mails();
  Future<ApiMail> replyToMail(String id, String body);

  /// Demo control: the railway answers the most recent sent claim.
  Future<ApiInboundResult> simulateInbound({required String body, String? claimId});

  // -- community ------------------------------------------------------------
  Future<ApiCommunity> community();
  Future<List<ApiBoardEntry>> boards(String scope);
}
