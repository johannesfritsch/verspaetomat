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

  // -- journeys (docs/17) ---------------------------------------------------
  /// Predicted and recent destinations; `from` is the station the customer stands at.
  Future<ApiDestinations> destinations({String? from});
  /// Itineraries from one station to another; `firstTrip` keeps only those starting with that train.
  Future<ApiPlan> planJourney({required String from, required String to, String? firstTrip});
  Future<ApiJourneyLive> startJourney(StartJourneyRequest request);
  /// The current journey (riding, in transfer, or arrived in the last two hours), else null.
  Future<ApiJourneyLive?> currentJourney();
  Future<ApiJourneyLive> confirmLeg(String journeyId, String tripId);
  /// "Ich bin da" (arrived: true) or the abort with its reason (docs/21 §1).
  Future<ApiJourney> finishJourney(String journeyId, {required bool arrived, String? reason});
  /// "Ich fahre später weiter": the leg ends here, the journey waits for the next train (docs/21 §2).
  Future<ApiJourneyLive> replanJourney(String journeyId, {String? fromStationId, String? fromStationName});
  Future<List<ApiJourney>> journeys();

  /// Deletes a ride the passenger never wanted (docs/23 §2): the journey, its legs and the
  /// case it produced. True when a draft claim fell below the 4 € minimum and went with it.
  /// Refused while the case sits in a claim that is no longer a draft.
  Future<bool> deleteJourney(String id);

  /// The same for a ride from before journeys existed.
  Future<bool> deleteRide(String id);

  // -- ledger and claims ----------------------------------------------------
  Future<ApiIncidents> incidents();
  /// Takes one case out of every open bundle; [restoreIncident] puts it back (docs/21 §4).
  /// True when a draft claim fell below the 4 € minimum and was dropped with it.
  Future<bool> discardIncident(String id, String reason);
  Future<void> restoreIncident(String id);
  Future<List<ApiClaim>> claims();
  /// The claim card's thread was opened: its inbound mails count as seen (docs/18).
  Future<void> markClaimSeen(String claimId);
  Future<ApiClaimDraft> draftClaim({required String desk, List<String>? incidentIds});
  Future<ApiClaim> patchClaim(String id, {String? ngoId, List<String>? attachmentUploadIds});
  Future<ApiUpload> upload({required String kind, required String filename, required List<int> bytes});
  Future<ApiClaim> signClaim(String id, {required String typedName, String? signatureUploadId});
  Future<ApiSendResult> sendClaim(String id);
  Future<Uint8List> claimPdf(String id);
  Future<List<ApiMail>> mails();
  /// [attachTicket]: the claim's existing ticket uploads go along; [uploadIds]: extra photos (docs/18).
  Future<ApiMail> replyToMail(String id, String body, {bool attachTicket = false, List<String> uploadIds = const []});

  /// Demo control: the railway answers the most recent sent claim.
  Future<ApiInboundResult> simulateInbound({required String body, String? claimId});

  // -- community ------------------------------------------------------------
  Future<ApiCommunity> community();
  /// Everything the Bahnsteig shows below the action block (docs/16), computed server-side.
  Future<ApiStanding> standing();
  Future<List<ApiBoardEntry>> boards(String scope);
}
