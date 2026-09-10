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

  bool get hasClaimFromLastRide => finalDelay != null && finalDelay! >= 60;

  void checkIn({required Departure departure, required Stop exitStop, required String fromStation, bool locationVerified = true}) {
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
    finalDelay = minutes ?? (liveDelay < 60 ? 68 : liveDelay);
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
        line: t.departure.line,
        from: t.fromStation,
        to: t.exitStop.name,
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

  List<Incident> get openIncidents => incidents.where((i) => i.isOpen).toList();

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
    rides
      ..clear()
      ..addAll(Mock.rides);
    phase = TripPhase.idle;
    trip = null;
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
