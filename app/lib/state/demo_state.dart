import 'package:flutter/material.dart';

import '../mock/mock_data.dart';
import '../widgets/kit.dart';

/// The one place that turns a ticket, a train and a delay into a claim amount.
/// Deutschlandticket 1,50 €; other season tickets 1,50 € (Nahverkehr) or 5 € (Fernverkehr);
/// single tickets 25 % of the fare from 60 minutes, 50 % from 120.
double claimAmountFor(TicketType ticket, TrainCategory category, int delay, {double fare = 39.9}) {
  if (delay < 60) return 0;
  return switch (ticket) {
    TicketType.deutschlandticket => 1.5,
    TicketType.zeitkarte => category == TrainCategory.fern ? 5.0 : 1.5,
    TicketType.einzelfahrkarte => (delay >= 120 ? 0.5 : 0.25) * fare,
  };
}

/// The small label shown under the amount, or null for the Deutschlandticket.
String? claimSubLabelFor(TicketType ticket, TrainCategory category, int delay, {double fare = 39.9}) => switch (ticket) {
      TicketType.deutschlandticket => null,
      TicketType.zeitkarte => category == TrainCategory.fern ? 'Zeitkarte Fernverkehr' : 'Zeitkarte Nahverkehr',
      TicketType.einzelfahrkarte => '${delay >= 120 ? '50' : '25'} % von ${fmtEuro(fare)}',
    };

enum TripPhase { idle, riding, arrived }

/// Demo journey phase (docs/17): between two legs the journey is in `transfer`.
enum JourneyPhase { riding, transfer, arrived, abandoned }

/// One leg of a demo journey: a departure, boarded at [from], left at [exit].
class DemoLeg {
  DemoLeg({required this.departure, required this.from, required this.exit});
  final Departure departure;
  final String from;
  final Stop exit;
  int? finalDelay;
  bool cancelled = false;
}

/// A demo journey: destination first, legs confirmed one at a time.
class DemoJourney {
  DemoJourney({required this.id, required this.origin, required this.destination, required this.legs, required this.startedAt});
  final String id;
  final String origin;
  final String destination;
  final List<DemoLeg> legs;
  final DateTime startedAt;
  int currentLeg = 1;
  JourneyPhase phase = JourneyPhase.riding;
  bool missedConnection = false;

  /// How it ended (docs/21 §3): `beendet`, `aufgegeben`, `nicht_gefahren`, or null.
  String? endReason;

  /// Geduldspunkte the journey was worth. Giving up keeps the waiting (docs/22 §1).
  int points = 0;

  /// The passenger asked to continue: this transfer is a Weiterfahrt (docs/21 §2).
  bool replanned = false;

  /// The destination arrival of the earliest onward connection at the moment of the
  /// interruption, as a clock time. Everything later is the passenger's own pause and
  /// never counts. The repository converts it like every other planned time.
  TimeOfDay? earliestOnwardArrival;

  /// The re-planned next leg after a missed connection (null = the planned one still works).
  Departure? proposal;
  int? finalDelay;
  DateTime date = DateTime.now();

  DemoLeg get current => legs[(currentLeg - 1).clamp(0, legs.length - 1)];
  DemoLeg? get next => currentLeg < legs.length ? legs[currentLeg] : null;
  bool get onLastLeg => currentLeg >= legs.length;
  Stop get plannedArrivalStop => legs.last.exit;
}

/// One in-memory state for the whole showcase. No persistence.
class DemoState extends ChangeNotifier {
  DemoState() {
    _refreshReady();
  }

  // -- Onboarding -----------------------------------------------------------
  bool onboardingDone = false;
  bool notificationsGranted = true;
  LocationMode locationMode = LocationMode.always;
  TicketType ticket = TicketType.deutschlandticket;
  String ngoId = 'bahnhofsmission';
  bool personalDataEntered = false;
  String nickname = Mock.userName;
  bool showOnBoards = true;
  bool keepCorrespondence = false;
  bool offline = false;

  Ngo get ngo => Mock.ngoById(ngoId);

  void savePersonalData() {
    personalDataEntered = true;
    notifyListeners();
  }

  void completeOnboarding() {
    onboardingDone = true;
    notifyListeners();
  }

  void setTicket(TicketType t) {
    ticket = t;
    notifyListeners();
  }

  void setNgo(String id) {
    ngoId = id;
    notifyListeners();
  }

  void setLocationMode(LocationMode m) {
    locationMode = m;
    notifyListeners();
  }

  /// Station nudge and quiet hours (docs/15). Demo keeps a fixed 22:00–06:00 window.
  bool nudgeEnabled = true;
  /// Demo: pretend the phone is away from every station (the Bahnsteig shows the compact row).
  bool awayFromStation = false;
  /// Demo: an account without journey history (the Einchecken card shows only the Wohin? field).
  bool noHistory = false;
  /// Demo: the phone is still being asked where it is (docs/23 §1), so the card says so.
  bool locatingStation = false;
  /// Demo: the journey is hours past its planned arrival and nobody closed it (docs/23 §3).
  bool staleRide = false;
  /// Demo: railway mails nobody opened yet; the Anträge tab badge (docs/18).
  int unreadMails = 2;
  /// Demo: what the last reply would have attached (docs/18 §5).
  bool lastReplyAttachTicket = false;
  List<String> lastReplyUploadIds = const [];

  void markClaimSeen(String claimId) {
    if (unreadMails == 0) return;
    unreadMails = 0;
    notifyListeners();
  }
  bool quietHours = true;

  void setNudgeEnabled(bool v) {
    nudgeEnabled = v;
    notifyListeners();
  }

  void setQuietHours(bool v) {
    quietHours = v;
    notifyListeners();
  }

  void toggleOffline() {
    offline = !offline;
    notifyListeners();
  }

  void setShowOnBoards(bool v) {
    showOnBoards = v;
    notifyListeners();
  }

  void setNickname(String v) {
    nickname = v.trim().isEmpty ? Mock.userName : v.trim();
    notifyListeners();
  }

  void setKeepCorrespondence(bool v) {
    keepCorrespondence = v;
    notifyListeners();
  }

  /// Träwelling as a potential check-in provider. Showcase only.
  bool traewellingLinked = false;

  /// Stumme Bahnhöfe in demo mode: [{id, name}]. Starts empty, like a fresh account.
  final List<Map<String, String>> mutedStations = [];

  void setMutedStations(List<Map<String, String>> list) {
    mutedStations
      ..clear()
      ..addAll(list);
    notifyListeners();
  }

  void setTraewellingLinked(bool v) {
    traewellingLinked = v;
    notifyListeners();
  }

  // -- Ride -----------------------------------------------------------------
  TripPhase phase = TripPhase.idle;
  Trip? trip;

  /// Live delay during the ride, in minutes. Grows with [tickRide].
  int liveDelay = 0;
  int passedStops = 0;
  String? liveCause;

  /// The delay the ride ended with. Null until arrived.
  int? finalDelay;
  bool finalCancelled = false;
  bool finalSelfEntered = false;
  VBadge? newBadge;

  /// Geduldspunkte the last abandoned journey was worth, for the "Aufgegeben" card (docs/22 §1).
  int lastAbandonPoints = 0;

  bool get hasClaimFromLastRide => finalDelay != null && finalDelay! >= 60;

  // -- Journey (docs/17) ------------------------------------------------------
  DemoJourney? journey;
  final List<DemoJourney> journeyHistory = [];

  /// Destination first: the itinerary's legs become the journey, leg 1 rides now.
  void startJourney({required String origin, required String destination, required List<DemoLeg> legs, bool locationVerified = true}) {
    final j = DemoJourney(id: 'j-${DateTime.now().millisecondsSinceEpoch}', origin: origin, destination: destination, legs: legs, startedAt: DateTime.now());
    journey = j;
    _board(j.legs.first, locationVerified: locationVerified);
  }

  /// The transfer confirmed ("Ich bin drin"): the given train becomes the next leg.
  void confirmLeg(Departure departure) {
    final j = journey;
    if (j == null || j.phase != JourneyPhase.transfer) return;
    final planned = j.next;
    final exitName = planned?.exit.name ?? j.destination;
    final exit = departure.stops.firstWhere((s) => s.name == exitName, orElse: () => departure.stops.last);
    final leg = DemoLeg(departure: departure, from: j.current.exit.name, exit: exit);
    if (planned != null) {
      j.legs[j.currentLeg] = leg;
    } else {
      j.legs.add(leg);
    }
    j.currentLeg += 1;
    j.phase = JourneyPhase.riding;
    j.proposal = null;
    _board(leg, locationVerified: true);
  }

  /// "Ich fahre später weiter" (docs/21 §2): the leg ends here, no points, and the journey
  /// waits at this station for a train the passenger picks. The planned arrival stays.
  void replanJourney({String? at}) {
    final j = journey;
    if (j == null || j.phase != JourneyPhase.riding) return;
    if (at != null && at.isNotEmpty && at != j.current.exit.name) {
      final stop = j.current.departure.stops.where((s) => s.name == at).firstOrNull;
      if (stop != null) j.legs[j.currentLeg - 1] = DemoLeg(departure: j.current.departure, from: j.current.from, exit: stop);
    }
    final leaveAfter = j.current.exit.planned.hour * 60 + j.current.exit.planned.minute + liveDelay;
    // The earliest train that still gets the passenger onward: it sets the ceiling.
    j.proposal = Mock.allDepartures
        .where((d) => d.stops.any((x) => x.name == j.destination) && d.planned.hour * 60 + d.planned.minute >= leaveAfter && !d.cancelled)
        .firstOrNull;
    final onward = j.proposal;
    if (onward != null) {
      j.earliestOnwardArrival = onward.stops.firstWhere((x) => x.name == j.destination, orElse: () => onward.stops.last).planned;
    }
    j.phase = JourneyPhase.transfer;
    j.replanned = true;
    j.current.finalDelay = liveDelay;
    // Everything planned after this leg is gone; the passenger chooses the next train.
    if (j.legs.length > j.currentLeg) j.legs.removeRange(j.currentLeg, j.legs.length);
    phase = TripPhase.riding;
    notifyListeners();
  }

  /// "Ich bin da" / the abort with its reason (docs/21 §1).
  void finishJourney({required bool arrived, String? reason}) {
    final j = journey;
    if (j == null) return;
    if (!arrived) {
      j.endReason = reason ?? 'aufgegeben';
      // docs/22 §1: the claim is gone, the patience is not — except for a trip never taken.
      j.points = j.endReason == 'aufgegeben' ? (j.current.departure.cancelled ? (liveDelay < 60 ? 60 : liveDelay) : (liveDelay < 0 ? 0 : liveDelay)) : 0;
      lastAbandonPoints = j.points;
      j.phase = JourneyPhase.abandoned;
      journeyHistory.insert(0, j);
      journey = null;
      phase = TripPhase.idle;
      trip = null;
      notifyListeners();
      return;
    }
    j.endReason = 'beendet';
    if (j.phase == JourneyPhase.transfer) {
      // Ended at the transfer stop: the delay there counts, marked incomplete by the backend.
      j.phase = JourneyPhase.arrived;
      j.finalDelay = j.current.finalDelay ?? liveDelay;
      finalDelay = j.finalDelay;
      phase = TripPhase.arrived;
      journeyHistory.insert(0, j);
      _refreshReady();
      notifyListeners();
      return;
    }
    simulateArrival(minutes: liveDelay);
  }

  void _board(DemoLeg leg, {required bool locationVerified}) {
    trip = Trip(
      departure: leg.departure,
      fromStation: leg.from,
      exitStop: leg.exit,
      ticket: ticket,
      checkedInAt: DateTime.now(),
      locationVerified: locationVerified,
    );
    phase = TripPhase.riding;
    liveDelay = leg.departure.delay;
    liveCause = leg.departure.cause;
    passedStops = 0;
    finalDelay = null;
    finalCancelled = leg.departure.cancelled;
    finalSelfEntered = false;
    newBadge = null;
    notifyListeners();
  }

  /// A single train, destination = its exit stop: a one-leg journey.
  void checkIn({required Departure departure, required Stop exitStop, required String fromStation, bool locationVerified = true}) {
    journey = DemoJourney(
      id: 'j-${DateTime.now().millisecondsSinceEpoch}',
      origin: fromStation,
      destination: exitStop.name,
      legs: [DemoLeg(departure: departure, from: fromStation, exit: exitStop)],
      startedAt: DateTime.now(),
    );
    trip = Trip(
      departure: departure,
      fromStation: fromStation,
      exitStop: exitStop,
      ticket: ticket,
      checkedInAt: DateTime.now(),
      locationVerified: locationVerified,
    );
    phase = TripPhase.riding;
    liveDelay = departure.delay;
    liveCause = departure.cause;
    passedStops = 0;
    finalDelay = null;
    finalCancelled = departure.cancelled;
    finalSelfEntered = false;
    newBadge = null;
    notifyListeners();
  }

  /// Demo: advance the ride by one stop and let the delay grow a little.
  void tickRide() {
    if (phase != TripPhase.riding || trip == null) return;
    final stops = trip!.departure.stops;
    final exitIndex = stops.indexWhere((s) => s.name == trip!.exitStop.name);
    if (passedStops < exitIndex) {
      passedStops += 1;
      liveDelay += [3, 5, 9, 14, 21, 12, 4][passedStops % 7];
      if (liveDelay >= 20 && liveCause == null) liveCause = 'Stellwerksstörung';
    }
    notifyListeners();
  }

  /// Demo: jump to arrival with a chosen delay. 60+ creates a claim.
  void simulateArrival({int? minutes, bool cancelled = false, bool selfEntered = false}) {
    final j = journey;
    final legDelay = minutes ?? (liveDelay < 60 ? 68 : liveDelay);
    if (j != null && j.phase == JourneyPhase.riding && !j.onLastLeg) {
      // Leg done, journey not: the transfer. Missed when we arrive after the next leg leaves.
      final leg = j.current;
      leg.finalDelay = legDelay;
      leg.cancelled = cancelled;
      final next = j.next!;
      final arrivalMin = leg.exit.planned.hour * 60 + leg.exit.planned.minute + legDelay;
      final nextDep = next.departure.planned.hour * 60 + next.departure.planned.minute;
      if (arrivalMin > nextDep || cancelled) {
        j.missedConnection = true;
        j.proposal = Mock.allDepartures
            .where((d) => d.line == next.departure.line && d.id != next.departure.id && d.planned.hour * 60 + d.planned.minute > arrivalMin)
            .firstOrNull;
      }
      j.phase = JourneyPhase.transfer;
      phase = TripPhase.idle;
      finalDelay = legDelay;
      notifyListeners();
      return;
    }
    if (j != null) {
      j.current.finalDelay = legDelay;
      j.phase = JourneyPhase.arrived;
      // The delay that counts: at the destination, including what a missed connection cost.
      final plannedArrival = j.plannedArrivalStop.planned.hour * 60 + j.plannedArrivalStop.planned.minute;
      final actualArrival = j.current.exit.planned.hour * 60 + j.current.exit.planned.minute + legDelay;
      j.finalDelay = cancelled ? 60 : (actualArrival - plannedArrival).clamp(legDelay, 24 * 60);
      journeyHistory.insert(0, j);
    }
    finalDelay = j?.finalDelay ?? legDelay;
    finalCancelled = cancelled;
    finalSelfEntered = selfEntered;
    phase = TripPhase.arrived;
    if (finalDelay! >= 60) {
      newBadge = Mock.badges.firstWhere((b) => b.id == 'stunde');
    } else if (finalDelay! < 10 && finalDelay! > 0) {
      newBadge = Mock.badges.firstWhere((b) => b.id == 'gegenzug');
    } else {
      newBadge = null;
    }
    if (trip != null && finalDelay! >= 60) {
      final t = trip!;
      final amount = claimAmountFor(t.ticket, t.departure.category, finalDelay!);
      final inc = Incident(
        id: 'i-live-${DateTime.now().millisecondsSinceEpoch}',
        date: DateTime.now(),
        line: j == null ? t.departure.line : j.legs.map((l) => l.departure.line).join(' · '),
        from: j?.origin ?? t.fromStation,
        to: j?.destination ?? t.exitStop.name,
        delayMinutes: finalDelay!,
        amount: amount,
        ticket: t.ticket,
        operator: t.departure.operator,
        desk: Mock.deskFor(t.departure.operator),
        status: IncidentStatus.gesammelt,
        plannedArrival: t.exitStop.planned,
        actualArrival: _add(t.exitStop.planned, finalDelay!),
        cancelled: cancelled,
        selfEntered: selfEntered,
        ngoId: ngoId,
        fare: t.ticket == TicketType.einzelfahrkarte ? 39.9 : null,
      );
      incidents.insert(0, inc);
      lastLiveIncidentId = inc.id;
    }
    _refreshReady();
    notifyListeners();
  }

  String? lastLiveIncidentId;

  // -- Rides and Nachtrag ---------------------------------------------------
  final List<RideRecord> rides = List.of(Mock.rides);

  /// Points earned in this session on top of the mocked weekly figure.
  int bonusPoints = 0;

  /// E4: a ride entered after the fact. One point, claimable, never ranks.
  void addNachtrag({required Departure departure, required Stop exitStop, required DateTime date}) {
    final delay = departure.cancelled ? 60 : departure.delay;
    rides.insert(0, RideRecord(date: date, line: departure.line, from: Mock.homeStation, to: exitStop.name, delay: delay, cancelled: departure.cancelled, verified: false));
    bonusPoints += 1;
    if (delay >= 60) {
      incidents.insert(
        0,
        Incident(
          id: 'i-nachtrag-${DateTime.now().millisecondsSinceEpoch}',
          date: date,
          line: departure.line,
          from: Mock.homeStation,
          to: exitStop.name,
          delayMinutes: delay,
          amount: claimAmountFor(ticket, departure.category, delay),
          ticket: ticket,
          operator: departure.operator,
          desk: Mock.deskFor(departure.operator),
          status: IncidentStatus.gesammelt,
          plannedArrival: exitStop.planned,
          actualArrival: _add(exitStop.planned, delay),
          cancelled: departure.cancelled,
          ngoId: ngoId,
          fare: ticket == TicketType.einzelfahrkarte ? 39.9 : null,
        ),
      );
    }
    _refreshReady();
    notifyListeners();
  }

  /// Marks open incidents "bereit" when their desk's bundle can be sent.
  void _refreshReady() {
    for (final i in incidents) {
      if (!i.isOpen) continue;
      i.status = bundleReady(i.desk) ? IncidentStatus.bereit : IncidentStatus.gesammelt;
    }
  }

  void dismissArrival() {
    phase = TripPhase.idle;
    trip = null;
    journey = null;
    finalDelay = null;
    newBadge = null;
    notifyListeners();
  }

  void changeTrain(Departure other) {
    if (trip == null) return;
    final exit = other.stops.firstWhere((s) => s.name == trip!.exitStop.name, orElse: () => other.stops.last);
    checkIn(departure: other, exitStop: exit, fromStation: trip!.fromStation, locationVerified: trip!.locationVerified);
  }

  // -- Ledger ---------------------------------------------------------------
  final List<Incident> incidents = List.of(Mock.incidents);
  final List<RailMail> mails = List.of(Mock.mails);

  /// Cases the passenger took out of the bundle (docs/21 §4): id → reason.
  final Map<String, String> discardedIncidents = {};

  void discardIncident(String id, String reason) {
    discardedIncidents[id] = reason;
    _refreshReady();
    notifyListeners();
  }

  void restoreIncident(String id) {
    discardedIncidents.remove(id);
    _refreshReady();
    notifyListeners();
  }

  /// docs/23 §2: a ride logged by accident. The journey (or the seeded record), its case and
  /// its points go; nothing comes back. The id is a journey id, a seeded ride's id, or the
  /// id of the case the ride produced.
  void deleteRide(String id) {
    incidents.removeWhere((i) => i.id == id);
    discardedIncidents.remove(id);
    journeyHistory.removeWhere((j) => j.id == id);
    if (journey?.id == id) {
      journey = null;
      trip = null;
      phase = TripPhase.idle;
    }
    const seeded = 'journey-hist-';
    if (id.startsWith(seeded)) {
      final n = int.tryParse(id.substring(seeded.length));
      if (n != null && n >= 0 && n < rides.length) rides.removeAt(n);
    }
    _refreshReady();
    notifyListeners();
  }

  List<Incident> get openIncidents => incidents.where((i) => i.isOpen && !discardedIncidents.containsKey(i.id)).toList();

  /// Open incidents grouped by claims desk.
  Map<String, List<Incident>> get openByDesk {
    final map = <String, List<Incident>>{};
    for (final i in openIncidents) {
      map.putIfAbsent(i.desk, () => []).add(i);
    }
    return map;
  }

  double openAmountFor(String desk) => (openByDesk[desk] ?? []).fold(0.0, (s, i) => s + i.amount);

  bool bundleReady(String desk) {
    final list = openByDesk[desk] ?? [];
    if (list.isEmpty) return false;
    if (list.any((i) => i.ticket == TicketType.einzelfahrkarte)) return true;
    return openAmountFor(desk) >= 4.0;
  }

  /// The desk whose bundle is ready, if any (Servicecenter first).
  String? get readyDesk {
    final desks = openByDesk.keys.toList()..sort((a, b) => a.startsWith('Service') ? -1 : 1);
    for (final d in desks) {
      if (bundleReady(d)) return d;
    }
    return null;
  }

  double get confirmedTotal => incidents.where((i) => i.status == IncidentStatus.bestaetigt).fold(0.0, (s, i) => s + i.amount);
  double get submittedTotal => incidents.where((i) => i.status == IncidentStatus.eingereicht).fold(0.0, (s, i) => s + i.amount);

  Incident? get oldestOpen {
    final open = openIncidents;
    if (open.isEmpty) return null;
    open.sort((a, b) => a.date.compareTo(b.date));
    return open.first;
  }

  int? get daysUntilOldestExpires {
    final o = oldestOpen;
    if (o == null) return null;
    return o.legalDeadline.difference(Mock.today).inDays;
  }

  // -- Claim flow -----------------------------------------------------------
  String? draftDesk;
  List<String> draftIncidentIds = [];
  bool draftTicketAttached = false;
  String? draftNgoId;
  bool draftSigned = false;
  String? lastSentBundleId;

  void startClaim(String desk) {
    draftDesk = desk;
    draftIncidentIds = (openByDesk[desk] ?? []).map((i) => i.id).toList();
    draftTicketAttached = false;
    draftNgoId = ngoId;
    draftSigned = false;
    notifyListeners();
  }

  void toggleDraftIncident(String id) {
    if (draftIncidentIds.contains(id)) {
      draftIncidentIds.remove(id);
    } else {
      draftIncidentIds.add(id);
    }
    notifyListeners();
  }

  void attachTicket() {
    draftTicketAttached = true;
    notifyListeners();
  }

  void setDraftNgo(String id) {
    draftNgoId = id;
    notifyListeners();
  }

  void sign() {
    draftSigned = true;
    notifyListeners();
  }

  double get draftAmount => incidents.where((i) => draftIncidentIds.contains(i.id)).fold(0.0, (s, i) => s + i.amount);

  /// Sends the draft: incidents become "eingereicht", an outgoing mail appears.
  void sendBundle() {
    final id = 'b-${DateTime.now().millisecondsSinceEpoch}';
    for (final i in incidents.where((i) => draftIncidentIds.contains(i.id))) {
      i.status = IncidentStatus.eingereicht;
      i.bundleId = id;
    }
    final ngo = Mock.ngoById(draftNgoId ?? ngoId);
    mails.insert(
      0,
      RailMail(
        id: 'm-$id-out',
        incidentIds: List.of(draftIncidentIds),
        direction: MailDirection.out,
        from: '${Mock.userName} <${Mock.relayAddress}>',
        to: draftDesk == 'NordWestBahn' ? 'fahrgastrechte@nordwestbahn.de' : 'EUAntragFGR@deutschebahn.com',
        subject: 'Fahrgastrechte: EU-Antragsformular',
        body:
            'Sehr geehrte Damen und Herren,\n\nanbei mein gesammelter Antrag auf Entschädigung nach VO (EU) 2021/782 (wiederholte Verspätungen, Zeitfahrkarte Deutschlandticket). Die Einzelfälle sind im Formular unter Punkt 6 aufgeführt.\n\nKontoinhaber: ${ngo.accountHolder}\n\nDiese E-Mail wurde über Verspätomat übermittelt, eine Ausfüll- und Weiterleitungshilfe. Antragsteller ist ${Mock.userName}.\n\nMit freundlichen Grüßen\n${Mock.userName}',
        date: DateTime.now(),
        attachments: ['EU-Antrag_Buendel.pdf', 'Deutschlandticket.png'],
      ),
    );
    lastSentBundleId = id;
    _refreshReady();
    draftDesk = null;
    draftIncidentIds = [];
    draftSigned = false;
    draftTicketAttached = false;
    notifyListeners();
  }

  /// Repository hook: record a mail the customer wrote (a reply to a question).
  void addMail(RailMail mail) {
    mails.insert(0, mail);
    notifyListeners();
  }

  /// Demo: the railway answers the most recent submitted bundle.
  RailMail? receiveReply({MailOutcome outcome = MailOutcome.accepted}) {
    final submitted = incidents.where((i) => i.status == IncidentStatus.eingereicht).toList();
    if (submitted.isEmpty) return null;
    final bundleId = submitted.first.bundleId;
    final group = submitted.where((i) => i.bundleId == bundleId).toList();
    final amount = group.fold(0.0, (s, i) => s + i.amount);
    final ngo = Mock.ngoById(group.first.ngoId);
    final body = switch (outcome) {
      MailOutcome.accepted =>
        'Sehr geehrter Herr ${Mock.userName},\n\nvielen Dank für Ihren Antrag. Wir haben die angegebenen Fahrten geprüft und eine Entschädigung von insgesamt ${amount.toStringAsFixed(2).replaceAll('.', ',')} EUR festgestellt.\n\nDer Betrag wird auf das angegebene Konto überwiesen:\nKontoinhaber: ${ngo.accountHolder}\n\nMit freundlichen Grüßen\nIhr Servicecenter Fahrgastrechte',
      MailOutcome.question =>
        'Sehr geehrter Herr ${Mock.userName},\n\nzur Bearbeitung Ihres Antrags benötigen wir noch eine Kopie Ihres Deutschlandtickets für den Monat Juli 2026. Bitte senden Sie diese als Antwort auf diese E-Mail.\n\nMit freundlichen Grüßen\nIhr Servicecenter Fahrgastrechte',
      MailOutcome.rejected =>
        'Sehr geehrter Herr ${Mock.userName},\n\nleider können wir Ihrem Antrag nicht entsprechen. Die Verspätung am 22.07.2026 (RE 7) beruhte auf außergewöhnlichen Umständen (Unwetter), für die nach VO (EU) 2021/782 Art. 19 Abs. 10 keine Entschädigung geleistet wird.\n\nMit freundlichen Grüßen\nIhr Servicecenter Fahrgastrechte',
    };
    final mail = RailMail(
      id: 'm-${DateTime.now().millisecondsSinceEpoch}-in',
      incidentIds: group.map((i) => i.id).toList(),
      direction: MailDirection.inbound,
      from: 'Servicecenter Fahrgastrechte <fahrgastrechte@deutschebahn.com>',
      to: Mock.relayAddress,
      subject: 'Ihr Antrag auf Entschädigung – Vorgang 2026-09-${DateTime.now().millisecondsSinceEpoch % 10000000}',
      body: body,
      date: DateTime.now(),
      amount: outcome == MailOutcome.accepted ? amount : null,
      outcome: outcome,
    );
    mails.insert(0, mail);
    if (outcome == MailOutcome.accepted) {
      for (final i in group) {
        i.status = IncidentStatus.bestaetigt;
      }
    } else if (outcome == MailOutcome.rejected) {
      for (final i in group) {
        i.status = IncidentStatus.abgelehnt;
      }
    }
    _refreshReady();
    notifyListeners();
    return mail;
  }

  /// Demo: reset everything to the seeded state.
  void reset() {
    onboardingDone = false;
    personalDataEntered = false;
    bonusPoints = 0;
    unreadMails = 2;
    noHistory = false;
    locatingStation = false;
    staleRide = false;
    rides
      ..clear()
      ..addAll(Mock.rides);
    phase = TripPhase.idle;
    trip = null;
    journey = null;
    journeyHistory.clear();
    finalDelay = null;
    newBadge = null;
    incidents
      ..clear()
      ..addAll(Mock.incidents.map((i) => Incident(
            id: i.id,
            date: i.date,
            line: i.line,
            from: i.from,
            to: i.to,
            delayMinutes: i.delayMinutes,
            amount: i.amount,
            ticket: i.ticket,
            operator: i.operator,
            desk: i.desk,
            status: i.status,
            plannedArrival: i.plannedArrival,
            actualArrival: i.actualArrival,
            cancelled: i.cancelled,
            selfEntered: i.selfEntered,
            ngoId: i.ngoId,
            bundleId: i.bundleId,
            fare: i.fare,
          )));
    mails
      ..clear()
      ..addAll(Mock.mails);
    _refreshReady();
    notifyListeners();
  }

  static TimeOfDay _add(TimeOfDay t, int minutes) {
    final total = (t.hour * 60 + t.minute + minutes) % (24 * 60);
    return TimeOfDay(hour: total ~/ 60, minute: total % 60);
  }
}

enum LocationMode { never, whileUsing, always }

extension LocationModeX on LocationMode {
  String get label => switch (this) {
        LocationMode.never => 'Aus. Ich checke selbst ein.',
        LocationMode.whileUsing => 'Nur wenn die App offen ist',
        LocationMode.always => 'Auch im Hintergrund',
      };
}

/// Makes a [DemoState] available to the tree. Rebuilds listeners on change.
class DemoScope extends InheritedNotifier<DemoState> {
  const DemoScope({super.key, required DemoState state, required super.child}) : super(notifier: state);

  static DemoState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<DemoScope>();
    assert(scope != null, 'DemoScope missing above this context');
    return scope!.notifier!;
  }

  /// Read without subscribing (for callbacks).
  static DemoState read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<DemoScope>();
    return scope!.notifier!;
  }
}
