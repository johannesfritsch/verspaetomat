import 'dart:typed_data';
import '../api/models.dart';

export '../api/models.dart';

/// A write that may have started, moved or ended a ride (#80): which call it was.
class RideWrite {
  const RideWrite(this.call, {this.checkedInAt});
  final String call;

  /// The station a check-in that went through starts from (#86); null for every other write
  /// and for a check-in that failed.
  final String? checkedInAt;
}

/// The seam both repositories report ride writes through (#80). The screens call
/// `session.repo.startJourney` and friends from half a dozen places; hooking the repository
/// catches every one of them without touching a caller — the same reasoning as `onFlags`.
///
/// `Session` sets [onRideWrite]. A failed write reports too: a timeout after the server
/// committed is still a ride that started, and asking once more costs one lookup.
mixin RideWriteHook {
  void Function(RideWrite write)? onRideWrite;

  Future<T> rideWrite<T>(String call, Future<T> Function() write, {String? checkedInAt}) async {
    var done = false;
    try {
      final result = await write();
      done = true;
      return result;
    } finally {
      onRideWrite?.call(RideWrite(call, checkedInAt: done ? checkedInAt : null));
    }
  }
}

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

  /// Name, address, private e-mail and ticket number gone; the relay address stays.
  Future<ApiCustomer> deletePersonalData();
  Future<String?> recoveryCode({bool rotate = false});
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

  // -- fares and tickets (#66, docs/49 §5) -----------------------------------
  /// The fare catalogue: what each kind of ticket is owed, in the server's words.
  Future<ApiFares> fares();
  /// The passenger's tickets, the one used last first; archived ones only with [all].
  Future<List<ApiTicket>> tickets({bool all = false});
  Future<ApiTicket> createTicket(TicketInput ticket);
  Future<ApiTicket> updateTicket(String id, TicketInput ticket);
  /// A ticket someone no longer has. Its journeys and cases keep it.
  Future<void> archiveTicket(String id);

  // -- rides ----------------------------------------------------------------
  Future<List<ApiRide>> rides();
  Future<ApiRideLive?> currentRide();
  Future<ApiArrivalResult> arrival(ArrivalRequest request);
  Future<void> dismissRide();
  Future<ApiArrivalResult> nachtrag(NachtragRequest request);

  // -- journeys (docs/17) ---------------------------------------------------
  /// Predicted and recent destinations; `from` is the station the customer stands at.
  Future<ApiDestinations> destinations({String? from});
  /// Itineraries from one station to another; `firstTrip` keeps only those starting with that train.
  /// [time]: plan from then instead of now (#67, „Früher"). Without it the plan starts half an
  /// hour back, so the train that just left is on the list too.
  Future<ApiPlan> planJourney({required String from, required String to, String? firstTrip, DateTime? time});
  Future<ApiJourneyLive> startJourney(StartJourneyRequest request);
  /// The current journey (riding, in transfer, or arrived in the last two hours), else null.
  Future<ApiJourneyLive?> currentJourney();
  Future<ApiJourneyLive> confirmLeg(String journeyId, String tripId);
  /// "Ich bin da" (arrived: true) or the abort with its reason (docs/21 §1).
  Future<ApiJourney> finishJourney(String journeyId, {required bool arrived, String? reason});
  /// "Ich fahre später weiter": the leg ends here, the journey waits for the next train (docs/21 §2).
  /// „Leider verpasst" at a change (#57).
  Future<ApiJourneyLive> missedConnection(String journeyId);
  Future<ApiJourneyLive> replanJourney(String journeyId, {String? fromStationId, String? fromStationName});

  /// "Zug wechseln" (docs/24 §2): another train to the same destination, from wherever the
  /// passenger is now. Replaces the leg when nothing has happened yet, ends it otherwise.
  Future<ApiJourneyLive> changeTrain(String journeyId, String tripId, {String? fromStationId, String? fromStationName});
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
  /// A claim for one pot (#66: `summary.pots[].id`), or for a desk against a server before pots.
  Future<ApiClaimDraft> draftClaim({String? desk, String? pot, List<String>? incidentIds});
  /// Moves a case to another of the passenger's tickets (#66). True when a draft that held it
  /// fell below its minimum and went.
  Future<bool> setIncidentTicket(String incidentId, String ticketId);
  Future<ApiClaim> patchClaim(String id, {String? ngoId, List<ApiClaimAttachment>? attachments});
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
  /// The share cards' figures (issue #49). Empty on a server that predates them.
  Future<ApiShareFacts> shareFacts();
  Future<List<ApiBoardEntry>> boards(String scope);
}
