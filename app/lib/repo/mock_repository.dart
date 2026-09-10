import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/services.dart' show rootBundle;

import '../mock/mock_data.dart';
import '../state/demo_state.dart';
import 'app_repository.dart';

/// The built-in demo, exposed through the same interface as the backend.
/// Wraps [DemoState] and [Mock]; every write goes to DemoState so the
/// existing screens keep following along.
class MockRepository implements AppRepository {
  MockRepository(this.state);

  final DemoState state;

  @override
  String get label => 'Demo (eingebaut)';

  // -- helpers ---------------------------------------------------------------

  static DateTime _at(TimeOfDay t, [DateTime? day]) {
    final d = day ?? Mock.today;
    return DateTime.utc(d.year, d.month, d.day, t.hour, t.minute);
  }

  static int _cents(double euros) => (euros * 100).round();

  static ApiCategory _cat(TrainCategory c) => switch (c) {
        TrainCategory.s => ApiCategory.s,
        TrainCategory.rb => ApiCategory.rb,
        TrainCategory.re => ApiCategory.re,
        TrainCategory.fern => ApiCategory.fern,
        TrainCategory.bus => ApiCategory.bus,
      };

  static String _stationId(String name) => 'mock:${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}';

  static ApiStop _stop(Stop s, {int delay = 0}) {
    final planned = _at(s.planned);
    return ApiStop(name: s.name, stationId: _stationId(s.name), scheduledArrival: planned, arrival: planned.add(Duration(minutes: delay)), cancelled: false);
  }

  static ApiDeparture _departure(Departure d) => ApiDeparture(
        tripId: d.id,
        line: d.line,
        destination: d.destination,
        scheduledDeparture: _at(d.planned),
        departure: _at(d.planned).add(Duration(minutes: d.delay)),
        realtime: true,
        platform: d.platform,
        category: _cat(d.category),
        operator: d.operator,
        cancelled: d.cancelled,
        cause: d.cause,
        stops: d.stops.map((s) => _stop(s, delay: d.delay)).toList(),
      );

  Departure? _findDeparture(String tripId) {
    for (final d in Mock.allDepartures) {
      if (d.id == tripId) return d;
    }
    return null;
  }

  // -- journeys (docs/17) ---------------------------------------------------

  static String _norm(String n) => n.toLowerCase().replaceAll('hauptbahnhof', 'hbf').trim();

  /// One leg of an itinerary from a mocked departure, boarded at [from], left at [to].
  static ApiLeg _leg(Departure d, String from, String to, {int? legNo, ApiLegStatus status = ApiLegStatus.planned, int? finalDelay, bool replanned = false, String? reason}) {
    final fromStop = d.stops.firstWhere((s) => _norm(s.name) == _norm(from), orElse: () => d.stops.first);
    final toStop = d.stops.firstWhere((s) => _norm(s.name) == _norm(to), orElse: () => d.stops.last);
    return ApiLeg(
      tripId: d.id,
      line: d.line,
      headsign: d.destination,
      operator: d.operator,
      category: _cat(d.category),
      fromStationId: _stationId(fromStop.name),
      fromStationName: fromStop.name,
      toStationId: _stationId(toStop.name),
      toStationName: toStop.name,
      plannedDeparture: _at(fromStop.planned),
      plannedArrival: _at(toStop.planned),
      liveDeparture: d.delay > 0 ? _at(fromStop.planned).add(Duration(minutes: d.delay)) : null,
      liveArrival: d.delay > 0 ? _at(toStop.planned).add(Duration(minutes: d.delay)) : null,
      platform: d.platform,
      cancelled: d.cancelled,
      delayMin: d.delay,
      legNo: legNo,
      status: status,
      finalDelayMin: finalDelay,
      actualArrival: finalDelay == null ? null : _at(toStop.planned).add(Duration(minutes: finalDelay)),
      replanned: replanned,
      reason: reason,
    );
  }

  static ApiItinerary _itinerary(String id, List<ApiLeg> legs, {bool preferred = false}) {
    final transfers = legs.length - 1;
    final dep = legs.first.plannedDeparture;
    final arr = legs.last.plannedArrival;
    return ApiItinerary(
      id: id,
      preferred: preferred,
      transfers: transfers,
      transferStations: [for (var i = 0; i < legs.length - 1; i++) legs[i].toStationName],
      plannedDeparture: dep,
      plannedArrival: arr,
      durationMin: dep == null || arr == null ? null : arr.difference(dep).inMinutes,
      legs: legs,
    );
  }

  Departure _dep(String id) => _findDeparture(id)!;

  @override
  Future<ApiDestinations> destinations({String? from}) async {
    final atHome = from != null && _norm(from).contains('bonn');
    return ApiDestinations(
      home: const ApiDestination(stationId: 'mock:bonn-hbf', stationName: 'Bonn Hbf'),
      predicted: [
        if (!atHome) const ApiDestination(stationId: 'mock:bonn-hbf', stationName: 'Bonn Hbf', label: 'Nach Hause', count: 12),
        const ApiDestination(stationId: 'mock:d-sseldorf-hbf', stationName: 'Düsseldorf Hbf', count: 5),
      ],
      recent: [
        ApiDestination(stationId: 'mock:l-denscheid', stationName: 'Lüdenscheid', lastAt: Mock.today.subtract(const Duration(days: 3))),
        ApiDestination(stationId: 'mock:aachen-hbf', stationName: 'Aachen Hbf', lastAt: Mock.today.subtract(const Duration(days: 5))),
        ApiDestination(stationId: 'mock:m-nster-westf-hbf', stationName: 'Münster (Westf) Hbf', lastAt: Mock.today.subtract(const Duration(days: 9))),
      ],
    );
  }

  /// Demo: direct trains straight from the Köln board; Düsseldorf and Lüdenscheid also via Hagen.
  @override
  Future<ApiPlan> planJourney({required String from, required String to, String? firstTrip}) async {
    final fromName = from.startsWith('mock:') ? 'Köln Hbf' : from;
    final target = _norm(to.startsWith('mock:') ? to.substring(5).replaceAll('-', ' ') : to);
    final targetName = to.startsWith('mock:') ? _nameFromId(to) : to;
    final list = <ApiItinerary>[];
    if (target.contains('sseldorf')) {
      list.add(_itinerary('it-s6', [_leg(_dep('s6-0751'), 'Köln Hbf', 'Düsseldorf Hbf')], preferred: true));
      list.add(_itinerary('it-re5', [_leg(_dep('re5-0755'), 'Köln Hbf', 'Düsseldorf Hbf')]));
      list.add(_itinerary('it-re7-re4', [_leg(_dep('re7-0747'), 'Köln Hbf', 'Hagen Hbf'), _leg(_dep('re4-0850'), 'Hagen Hbf', 'Düsseldorf Hbf')]));
    } else if (target.contains('denscheid')) {
      list.add(_itinerary('it-re7-rb52', [_leg(_dep('re7-0747'), 'Köln Hbf', 'Hagen Hbf'), _leg(_dep('rb52-0855'), 'Hagen Hbf', 'Lüdenscheid')], preferred: true));
    } else if (target.contains('bonn')) {
      list.add(_itinerary('it-rb26', [_leg(_dep('rb26-0805'), 'Köln Hbf', 'Bonn Hbf')], preferred: true));
    } else {
      // Any train from the board whose stops reach the destination.
      var first = true;
      for (final d in Mock.departuresKoelnHbf) {
        if (d.cancelled) continue;
        if (d.stops.any((st) => _norm(st.name) == target || _norm(st.name).startsWith(target))) {
          list.add(_itinerary('it-${d.id}', [_leg(d, fromName, targetName)], preferred: first));
          first = false;
        }
      }
    }
    if (firstTrip != null) {
      final filtered = list.where((i) => i.legs.first.tripId == firstTrip).toList();
      if (filtered.isNotEmpty) {
        list
          ..clear()
          ..addAll(filtered);
      } else {
        final d = _findDeparture(firstTrip);
        if (d != null) {
          final reaches = d.stops.any((st) => _norm(st.name) == target);
          list
            ..clear()
            ..add(_itinerary('it-$firstTrip', [_leg(d, fromName, reaches ? targetName : d.stops.last.name)], preferred: true));
        }
      }
    }
    return ApiPlan(from: ApiStation(id: from, name: fromName), to: ApiStation(id: to, name: targetName), itineraries: list);
  }

  static String _nameFromId(String id) {
    const known = {
      'mock:bonn-hbf': 'Bonn Hbf',
      'mock:d-sseldorf-hbf': 'Düsseldorf Hbf',
      'mock:l-denscheid': 'Lüdenscheid',
      'mock:aachen-hbf': 'Aachen Hbf',
      'mock:m-nster-westf-hbf': 'Münster (Westf) Hbf',
      'mock:hagen-hbf': 'Hagen Hbf',
      'mock:k-ln-hbf': 'Köln Hbf',
    };
    return known[id] ?? id.substring(5);
  }

  @override
  Future<ApiJourneyLive> startJourney(StartJourneyRequest r) async {
    if (r.ticket != null) state.setTicket(r.ticket!);
    final legs = <DemoLeg>[];
    var from = r.fromStationName;
    for (final l in r.legs) {
      final d = _findDeparture(l.tripId);
      if (d == null) throw StateError('unknown trip ${l.tripId}');
      final toName = l.toStationName.isNotEmpty ? l.toStationName : _nameFromId(l.toStationId);
      final exit = d.stops.firstWhere((s) => _norm(s.name) == _norm(toName), orElse: () => d.stops.last);
      legs.add(DemoLeg(departure: d, from: from, exit: exit));
      from = exit.name;
    }
    if (legs.isEmpty) throw StateError('no legs');
    state.startJourney(origin: r.fromStationName, destination: r.toStationName, legs: legs, locationVerified: r.location != null);
    return (await currentJourney())!;
  }

  ApiJourney _journey(DemoJourney j) {
    final legs = <ApiLeg>[];
    for (var i = 0; i < j.legs.length; i++) {
      final l = j.legs[i];
      final no = i + 1;
      final status = j.phase == JourneyPhase.arrived
          ? ApiLegStatus.arrived
          : no < j.currentLeg
              ? ApiLegStatus.arrived
              : no == j.currentLeg
                  ? (j.phase == JourneyPhase.transfer ? ApiLegStatus.arrived : ApiLegStatus.riding)
                  : ApiLegStatus.planned;
      legs.add(_leg(l.departure, l.from, l.exit.name, legNo: no, status: status, finalDelay: l.finalDelay));
    }
    ApiLeg? next;
    if (j.phase == JourneyPhase.transfer) {
      final planned = j.next;
      if (j.proposal != null) {
        next = _leg(j.proposal!, j.current.exit.name, planned?.exit.name ?? j.destination, legNo: j.currentLeg + 1, replanned: true, reason: j.current.cancelled ? 'ausfall' : 'verpasst');
      } else if (planned != null) {
        next = _leg(planned.departure, planned.from, planned.exit.name, legNo: j.currentLeg + 1);
      }
    }
    return ApiJourney(
      id: j.id,
      status: switch (j.phase) {
        JourneyPhase.riding => ApiJourneyStatus.riding,
        JourneyPhase.transfer => ApiJourneyStatus.transfer,
        JourneyPhase.arrived => ApiJourneyStatus.arrived,
        JourneyPhase.abandoned => ApiJourneyStatus.abandoned,
      },
      originStationId: _stationId(j.origin),
      originStationName: j.origin,
      destinationStationId: _stationId(j.destination),
      destinationStationName: j.destination,
      plannedDeparture: _at(j.legs.first.departure.planned),
      plannedArrival: _at(j.plannedArrivalStop.planned),
      actualArrival: j.finalDelay == null ? null : _at(j.plannedArrivalStop.planned).add(Duration(minutes: j.finalDelay!)),
      finalDelayMin: j.finalDelay,
      missedConnection: j.missedConnection,
      cancelled: j.legs.any((l) => l.cancelled),
      points: j.finalDelay ?? 0,
      ticket: state.ticket,
      currentLeg: j.currentLeg,
      legs: legs,
      nextLeg: next,
      transferStationName: j.phase == JourneyPhase.transfer ? j.current.exit.name : null,
      transferDeadline: j.phase == JourneyPhase.transfer ? _at(j.current.exit.planned).add(const Duration(hours: 2)) : null,
      createdAt: j.startedAt.toUtc(),
      finalisedAt: j.phase == JourneyPhase.arrived ? DateTime.now().toUtc() : null,
    );
  }

  @override
  Future<ApiJourneyLive?> currentJourney() async {
    final j = state.journey;
    if (j == null) return null;
    final live = await currentRide();
    final api = _journey(j);
    if (j.phase == JourneyPhase.transfer) {
      final t = state.trip;
      return ApiJourneyLive(
        journey: api,
        ride: t == null ? null : _ride(t, status: ApiRideStatus.arrived, finalDelay: j.current.finalDelay, cancelled: j.current.cancelled, points: j.current.finalDelay ?? 0),
        stops: t == null ? const [] : t.departure.stops.map((s) => _stop(s, delay: j.current.finalDelay ?? 0)).toList(),
        nextLeg: api.nextLeg,
      );
    }
    return ApiJourneyLive(journey: api, ride: live?.ride, stops: live?.stops ?? const [], eta: live?.eta, justArrived: j.phase == JourneyPhase.arrived);
  }

  @override
  Future<ApiJourneyLive> confirmLeg(String journeyId, String tripId) async {
    final d = _findDeparture(tripId);
    if (d == null) throw StateError('unknown trip $tripId');
    state.confirmLeg(d);
    return (await currentJourney())!;
  }

  @override
  Future<ApiJourney> finishJourney(String journeyId, {required bool arrived}) async {
    final j = state.journey;
    if (j == null) throw StateError('no journey');
    state.finishJourney(arrived: arrived);
    return _journey(j);
  }

  @override
  Future<List<ApiJourney>> journeys() async {
    final list = <ApiJourney>[];
    if (state.journey != null && state.journey!.phase == JourneyPhase.arrived) list.add(_journey(state.journey!));
    for (final j in state.journeyHistory) {
      if (!list.any((x) => x.id == j.id)) list.add(_journey(j));
    }
    // The seeded ride records as single-leg journeys.
    for (var i = 0; i < state.rides.length; i++) {
      final r = state.rides[i];
      final planned = DateTime.utc(r.date.year, r.date.month, r.date.day, 8, 0);
      list.add(ApiJourney(
        id: 'journey-hist-$i',
        status: ApiJourneyStatus.arrived,
        originStationId: _stationId(r.from),
        originStationName: r.from,
        destinationStationId: _stationId(r.to),
        destinationStationName: r.to,
        plannedDeparture: planned,
        plannedArrival: planned.add(const Duration(minutes: 50)),
        actualArrival: planned.add(Duration(minutes: 50 + r.delay)),
        finalDelayMin: r.delay,
        cancelled: r.cancelled,
        points: r.cancelled ? 60 : r.delay,
        legs: [
          ApiLeg(tripId: '', line: r.line, fromStationId: _stationId(r.from), fromStationName: r.from, toStationId: _stationId(r.to), toStationName: r.to, legNo: 1, status: ApiLegStatus.arrived, finalDelayMin: r.delay, plannedDeparture: planned),
        ],
        createdAt: r.date.toUtc(),
      ));
    }
    return list;
  }

  ApiRide _ride(Trip t, {required ApiRideStatus status, int? finalDelay, bool cancelled = false, bool selfEntered = false, int points = 0}) => ApiRide(
        id: 'ride-${t.checkedInAt.millisecondsSinceEpoch}',
        tripId: t.departure.id,
        line: t.departure.line,
        operator: t.departure.operator,
        category: _cat(t.departure.category),
        fromStationId: _stationId(t.fromStation),
        fromStationName: t.fromStation,
        exitStationId: _stationId(t.exitStop.name),
        exitStationName: t.exitStop.name,
        plannedArrival: _at(t.exitStop.planned),
        ticket: t.ticket,
        checkedInAt: t.checkedInAt.toUtc(),
        locationVerified: t.locationVerified,
        status: status,
        passedStops: state.passedStops,
        liveDelayMinutes: state.liveDelay,
        cause: state.liveCause,
        finalDelayMinutes: finalDelay,
        cancelled: cancelled,
        selfEntered: selfEntered,
        points: points,
        date: Mock.today,
      );

  static ApiRide _rideRecord(RideRecord r, int i) => ApiRide(
        id: 'ride-hist-$i',
        tripId: '',
        line: r.line,
        operator: '',
        fromStationId: _stationId(r.from),
        fromStationName: r.from,
        exitStationId: _stationId(r.to),
        exitStationName: r.to,
        ticket: TicketType.deutschlandticket,
        checkedInAt: r.date.toUtc(),
        locationVerified: r.verified,
        status: ApiRideStatus.arrived,
        finalDelayMinutes: r.delay,
        cancelled: r.cancelled,
        points: r.cancelled ? 60 : r.delay,
        date: r.date,
      );

  static ApiIncident _incident(Incident i) => ApiIncident(
        id: i.id,
        date: i.date,
        line: i.line,
        from: i.from,
        to: i.to,
        delayMinutes: i.delayMinutes,
        amountCents: _cents(i.amount),
        ticket: i.ticket,
        operator: i.operator,
        desk: i.desk,
        status: i.status,
        cancelled: i.cancelled,
        selfEntered: i.selfEntered,
        ngoId: i.ngoId,
        claimId: i.bundleId,
        fareCents: i.fare == null ? null : _cents(i.fare!),
        legalDeadline: i.legalDeadline,
        evidence: i.plannedArrival == null
            ? null
            : ApiEvidence(
                plannedArrival: _at(i.plannedArrival!, i.date),
                actualArrival: i.actualArrival == null ? null : _at(i.actualArrival!, i.date),
                source: i.selfEntered ? 'selbst eingetragen' : 'Live-Daten Transitous',
                fetchedAt: i.date.toUtc(),
              ),
      );

  static ApiMail _mail(RailMail m) => ApiMail(
        id: m.id,
        incidentIds: m.incidentIds,
        direction: m.direction == MailDirection.inbound ? ApiMailDirection.inbound : ApiMailDirection.out,
        from: m.from,
        to: m.to,
        bcc: m.direction == MailDirection.out ? Mock.userEmail : null,
        subject: m.subject,
        body: m.body,
        date: m.date.toUtc(),
        attachments: m.attachments,
        amountCents: m.amount == null ? null : _cents(m.amount!),
        outcome: switch (m.outcome) {
          MailOutcome.accepted => ApiMailOutcome.accepted,
          MailOutcome.question => ApiMailOutcome.question,
          MailOutcome.rejected => ApiMailOutcome.rejected,
          null => null,
        },
      );

  static ApiNgo _ngo(Ngo n) => ApiNgo(
        id: n.id,
        name: n.name,
        tagline: n.tagline,
        story: n.story,
        accountHolder: n.accountHolder,
        iban: n.iban,
        donationUrl: n.donationUrl,
        confirmedTotalCents: _cents(n.confirmedTotal),
        submittedTotalCents: _cents(n.submittedTotal),
      );

  ApiClaim _draftClaim() {
    final ngo = Mock.ngoById(state.draftNgoId ?? state.ngoId);
    final months = state.incidents.where((i) => state.draftIncidentIds.contains(i.id)).map((i) => '${i.date.year}-${i.date.month.toString().padLeft(2, '0')}').toSet().toList()..sort();
    return ApiClaim(
      id: 'draft',
      desk: state.draftDesk ?? '',
      incidentIds: List.of(state.draftIncidentIds),
      ngoId: ngo.id,
      accountHolder: ngo.accountHolder,
      iban: ngo.iban,
      ticketMonths: months,
      attachments: state.draftTicketAttached ? const ['ticket.png'] : const [],
      signedBy: state.draftSigned ? Mock.userName : null,
      status: ApiClaimStatus.draft,
      amountClaimedCents: _cents(state.draftAmount),
    );
  }

  // -- customer -------------------------------------------------------------

  @override
  Future<bool> health() async => true;

  @override
  Future<ApiCustomer> getMe() async => ApiCustomer(
        id: 'demo-device',
        nickname: state.nickname,
        relayAddress: state.personalDataEntered ? Mock.relayAddress : null,
        personalData: state.personalDataEntered
            ? const ApiPersonalData(name: Mock.userName, address: Mock.userAddress, email: Mock.userEmail, ticketNumber: Mock.ticketNumber)
            : null,
        settings: ApiSettings(
          ticket: state.ticket,
          ngoId: state.ngoId,
          locationMode: state.locationMode,
          notifications: state.notificationsGranted,
          showOnBoards: state.showOnBoards,
          keepCorrespondence: state.keepCorrespondence,
          traewellingLinked: state.traewellingLinked,
          onboardingDone: state.onboardingDone,
          mutedStations: [for (final m in state.mutedStations) ApiMutedStation(id: m['id'] ?? '', name: m['name'] ?? '')],
          nudgeEnabled: state.nudgeEnabled,
          quietFrom: state.quietHours ? '22:00' : null,
          quietTo: state.quietHours ? '06:00' : null,
        ),
        pointsTotal: Mock.pointsTotal + state.bonusPoints,
        pointsThisWeek: Mock.pointsThisWeek + state.bonusPoints,
        levelName: Mock.levelName,
        nextLevelName: Mock.nextLevelName,
        nextLevelAt: Mock.nextLevelAt,
        homeStation: Mock.homeStation,
      );

  @override
  Future<ApiCustomer> patchMe(MePatch p) async {
    if (p.ticket != null) state.setTicket(p.ticket!);
    if (p.ngoId != null) state.setNgo(p.ngoId!);
    if (p.locationMode != null) state.setLocationMode(p.locationMode!);
    if (p.notifications != null) {
      state.notificationsGranted = p.notifications!;
    }
    if (p.showOnBoards != null) state.setShowOnBoards(p.showOnBoards!);
    if (p.keepCorrespondence != null) state.setKeepCorrespondence(p.keepCorrespondence!);
    if (p.traewellingLinked != null) state.setTraewellingLinked(p.traewellingLinked!);
    if (p.onboardingDone == true) state.completeOnboarding();
    if (p.nickname != null) state.setNickname(p.nickname!);
    if (p.mutedStations != null) state.setMutedStations([for (final m in p.mutedStations!) {'id': m.id, 'name': m.name}]);
    if (p.nudgeEnabled != null) state.setNudgeEnabled(p.nudgeEnabled!);
    if (p.quietFrom != null || p.quietTo != null) state.setQuietHours((p.quietFrom ?? p.quietTo ?? '').isNotEmpty);
    return getMe();
  }

  /// Demo: the mock's nearby stations, minus muted ones, so the simulator can be tested without a backend.
  @override
  Future<ApiGeofence> geofence() async {
    final muted = state.mutedStations.map((m) => m['id']).toSet();
    return ApiGeofence(
      enabled: state.locationMode == LocationMode.always && state.nudgeEnabled,
      stations: [
        for (final s in Mock.nearbyStations)
          if (!muted.contains(s.id)) ApiGeofenceStation(id: s.id, name: s.name, lat: s.lat, lon: s.lon, checkins: s.id == 'koeln-hbf' ? 12 : 1),
      ],
      quietFrom: state.quietHours ? '22:00' : null,
      quietTo: state.quietHours ? '06:00' : null,
    );
  }

  @override
  Future<ApiCustomer> putPersonalData(ApiPersonalData data) async {
    state.savePersonalData();
    return getMe();
  }

  @override
  Future<String> recoveryCode() async => 'gleis sieben wartet ruhig am bahnsteig';

  @override
  Future<void> deleteMe() async => state.reset();
  @override
  Future<void> putPushToken({required String platform, required String token}) async {}

  @override
  Future<String> exportMe() async => jsonEncode({'demo': true, 'incidents': state.incidents.length, 'rides': state.rides.length});

  // -- reference ------------------------------------------------------------

  @override
  Future<ApiNearby> nearbyStations({double? lat, double? lon}) async => ApiNearby(
        stations: Mock.nearbyStations
            .map((s) => ApiStation(id: s.id, name: s.name, distanceM: state.awayFromStation ? s.distanceM + 2400 : s.distanceM, eva: s.evaNr, lat: s.lat, lon: s.lon))
            .toList(),
        source: 'demo',
      );

  @override
  Future<List<ApiStation>> searchStations(String query) async {
    final q = query.toLowerCase();
    return (await nearbyStations()).stations.where((s) => s.name.toLowerCase().contains(q)).toList();
  }

  @override
  Future<List<ApiDeparture>> departures(String stationId) async =>
      (stationId.contains('hagen') ? Mock.departuresHagenHbf : Mock.departuresKoelnHbf).map(_departure).toList();

  @override
  Future<ApiTrip> trip(String tripId) async {
    final d = _findDeparture(tripId);
    if (d == null) throw StateError('unknown trip $tripId');
    final delay = state.trip?.departure.id == tripId ? state.liveDelay : d.delay;
    return ApiTrip(tripId: d.id, line: d.line, operator: d.operator, category: _cat(d.category), cancelled: d.cancelled, cause: d.cause, stops: d.stops.map((s) => _stop(s, delay: delay)).toList());
  }

  @override
  Future<List<ApiOperator>> operators() async => Mock.desks.entries
      .map((e) => ApiOperator(
            name: e.key,
            desk: e.value,
            postalAddress: (Mock.deskAddresses[e.value] ?? '').split('\n').first,
            email: e.value == 'Servicecenter Fahrgastrechte' ? 'EUAntragFGR@deutschebahn.com' : null,
            acceptsEmail: e.value == 'Servicecenter Fahrgastrechte',
          ))
      .toList();

  @override
  Future<List<ApiNgo>> ngos() async => Mock.ngos.map(_ngo).toList();

  @override
  Future<List<ApiBadge>> badges() async => Mock.badges.map((b) => ApiBadge(id: b.id, name: b.name, rule: b.rule, earnedOn: b.earned ? Mock.today : null)).toList();

  // -- rides ----------------------------------------------------------------

  @override
  Future<List<ApiRide>> rides() async {
    final list = <ApiRide>[];
    for (var i = 0; i < state.rides.length; i++) {
      list.add(_rideRecord(state.rides[i], i));
    }
    return list;
  }

  @override
  Future<ApiRide> checkIn(CheckInRequest r) async {
    final d = _findDeparture(r.tripId);
    if (d == null) throw StateError('unknown trip ${r.tripId}');
    final stop = d.stops.firstWhere((s) => s.name == r.exitStationName, orElse: () => d.stops.last);
    if (r.ticket != null) state.setTicket(r.ticket!);
    state.checkIn(departure: d, exitStop: stop, fromStation: r.fromStationName, locationVerified: r.location != null);
    return _ride(state.trip!, status: ApiRideStatus.riding);
  }

  @override
  Future<ApiRideLive?> currentRide() async {
    final t = state.trip;
    if (t == null) return null;
    // Like the backend: the arrived ride stays current until it is dismissed.
    if (state.phase == TripPhase.arrived) {
      return ApiRideLive(
        ride: _ride(t, status: ApiRideStatus.arrived, finalDelay: state.finalDelay, cancelled: state.finalCancelled, selfEntered: state.finalSelfEntered, points: state.finalDelay ?? 0),
        stops: t.departure.stops.map((s) => _stop(s, delay: state.finalDelay ?? 0)).toList(),
      );
    }
    if (state.phase != TripPhase.riding) return null;
    return ApiRideLive(
      ride: _ride(t, status: ApiRideStatus.riding),
      stops: t.departure.stops.map((s) => _stop(s, delay: state.liveDelay)).toList(),
      eta: _at(t.exitStop.planned).add(Duration(minutes: state.liveDelay)),
    );
  }

  @override
  Future<ApiArrivalResult> arrival(ArrivalRequest a) async {
    final t = state.trip;
    if (t == null) throw StateError('no ride in progress');
    int? minutes = a.delayMinutes;
    if (minutes == null && a.actualArrival != null) {
      minutes = a.actualArrival!.difference(_at(t.exitStop.planned)).inMinutes;
    }
    state.simulateArrival(minutes: minutes, cancelled: a.cancelled, selfEntered: a.selfEntered);
    final inc = state.lastLiveIncidentId == null ? null : state.incidents.where((i) => i.id == state.lastLiveIncidentId).firstOrNull;
    final badge = state.newBadge;
    return ApiArrivalResult(
      ride: _ride(t, status: ApiRideStatus.arrived, finalDelay: state.finalDelay, cancelled: state.finalCancelled, selfEntered: state.finalSelfEntered, points: state.finalDelay ?? 0),
      incident: inc == null ? null : _incident(inc),
      bundleReady: inc != null && state.bundleReady(inc.desk),
      newBadge: badge == null ? null : ApiBadge(id: badge.id, name: badge.name, rule: badge.rule, earnedOn: Mock.today),
    );
  }

  @override
  Future<void> dismissRide() async => state.dismissArrival();

  @override
  Future<ApiArrivalResult> nachtrag(NachtragRequest n) async {
    final d = _findDeparture(n.tripId);
    if (d == null) throw StateError('unknown trip ${n.tripId}');
    final stop = d.stops.firstWhere((s) => s.name == n.exitStationName, orElse: () => d.stops.last);
    state.addNachtrag(departure: d, exitStop: stop, date: n.date);
    final rec = state.rides.first;
    final inc = d.delay >= 60 ? state.incidents.first : null;
    return ApiArrivalResult(ride: _rideRecord(rec, 0), incident: inc == null ? null : _incident(inc));
  }

  // -- ledger and claims ----------------------------------------------------

  @override
  Future<ApiIncidents> incidents() async {
    final desks = state.openByDesk.entries.map((e) {
      final open = _cents(state.openAmountFor(e.key));
      return ApiDeskSummary(desk: e.key, openCents: open, ready: state.bundleReady(e.key), missingCents: (400 - open).clamp(0, 400), incidentIds: e.value.map((i) => i.id).toList());
    }).toList();
    final oldest = state.oldestOpen;
    return ApiIncidents(
      incidents: state.incidents.map(_incident).toList(),
      summary: ApiIncidentSummary(
        desks: desks,
        readyDesk: state.readyDesk,
        confirmedCents: _cents(state.confirmedTotal),
        submittedCents: _cents(state.submittedTotal),
        oldestOpen: oldest == null ? null : ApiOldestOpen(id: oldest.id, line: oldest.line, date: oldest.date, deadline: oldest.legalDeadline, daysLeft: state.daysUntilOldestExpires ?? 0),
      ),
    );
  }

  @override
  Future<List<ApiClaim>> claims() async {
    final byBundle = <String, List<Incident>>{};
    for (final i in state.incidents) {
      if (i.bundleId != null) byBundle.putIfAbsent(i.bundleId!, () => []).add(i);
    }
    return byBundle.entries.map((e) {
      final first = e.value.first;
      final ngo = Mock.ngoById(first.ngoId);
      final status = switch (first.status) {
        IncidentStatus.bestaetigt => ApiClaimStatus.accepted,
        IncidentStatus.abgelehnt => ApiClaimStatus.rejected,
        _ => ApiClaimStatus.sent,
      };
      final mail = state.mails.where((m) => m.direction == MailDirection.out && m.incidentIds.contains(first.id)).firstOrNull;
      return ApiClaim(
        id: e.key,
        desk: first.desk,
        incidentIds: e.value.map((i) => i.id).toList(),
        ngoId: ngo.id,
        accountHolder: ngo.accountHolder,
        iban: ngo.iban,
        status: status,
        sentAt: mail?.date.toUtc(),
        expectedReplyBy: mail?.date.add(const Duration(days: 28)),
        amountClaimedCents: _cents(e.value.fold(0.0, (s, i) => s + i.amount)),
        amountConfirmedCents: status == ApiClaimStatus.accepted ? _cents(e.value.fold(0.0, (s, i) => s + i.amount)) : null,
      );
    }).toList();
  }

  @override
  Future<ApiClaimDraft> draftClaim({required String desk, List<String>? incidentIds}) async {
    state.startClaim(desk);
    if (incidentIds != null) {
      for (final id in List.of(state.draftIncidentIds)) {
        if (!incidentIds.contains(id)) state.toggleDraftIncident(id);
      }
    }
    final addr = Mock.deskAddresses[desk];
    return ApiClaimDraft(
      claim: _draftClaim(),
      deskAddress: addr?.split('\n').first,
      deskEmail: addr != null && addr.contains('\n') ? addr.split('\n').last : null,
      personalDataRequired: !state.personalDataEntered,
      relayAddress: Mock.relayAddress,
    );
  }

  @override
  Future<ApiClaim> patchClaim(String id, {String? ngoId, List<String>? attachmentUploadIds}) async {
    if (ngoId != null) state.setDraftNgo(ngoId);
    if (attachmentUploadIds != null && attachmentUploadIds.isNotEmpty) state.attachTicket();
    return _draftClaim();
  }

  @override
  /// Demo mode has no backend to render Typst, so it ships a real EU form the backend
  /// rendered once (assets/beispiel-antrag.pdf). Same layout, sample data.
  @override
  Future<Uint8List> claimPdf(String id) async {
    final data = await rootBundle.load('assets/beispiel-antrag.pdf');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  @override
  Future<ApiUpload> upload({required String kind, required String filename, required List<int> bytes}) async {
    if (kind == 'ticket') state.attachTicket();
    return ApiUpload(uploadId: 'mock-upload-${DateTime.now().millisecondsSinceEpoch}');
  }

  @override
  Future<ApiClaim> signClaim(String id, {required String typedName, String? signatureUploadId}) async {
    state.sign();
    return _draftClaim();
  }

  @override
  Future<ApiSendResult> sendClaim(String id) async {
    final claim = _draftClaim();
    state.sendBundle();
    final mail = state.mails.first;
    return ApiSendResult(
      claim: ApiClaim(
        id: state.lastSentBundleId ?? id,
        desk: claim.desk,
        incidentIds: claim.incidentIds,
        ngoId: claim.ngoId,
        accountHolder: claim.accountHolder,
        iban: claim.iban,
        ticketMonths: claim.ticketMonths,
        signedBy: Mock.userName,
        status: ApiClaimStatus.sent,
        sentAt: DateTime.now().toUtc(),
        expectedReplyBy: DateTime.now().add(const Duration(days: 28)),
        amountClaimedCents: claim.amountClaimedCents,
      ),
      mail: _mail(mail),
    );
  }

  @override
  Future<List<ApiMail>> mails() async => state.mails.map(_mail).toList();

  @override
  Future<ApiMail> replyToMail(String id, String body) async {
    final original = state.mails.where((m) => m.id == id).firstOrNull;
    final m = RailMail(
      id: 'm-reply-${DateTime.now().millisecondsSinceEpoch}',
      incidentIds: original?.incidentIds ?? const [],
      direction: MailDirection.out,
      from: '${Mock.userName} <${Mock.relayAddress}>',
      to: original?.from ?? 'fahrgastrechte@deutschebahn.com',
      subject: 'Re: ${original?.subject ?? 'Ihr Antrag'}',
      body: body,
      date: DateTime.now(),
    );
    state.addMail(m);
    return _mail(m);
  }

  @override
  Future<ApiInboundResult> simulateInbound({required String body, String? claimId}) async {
    final lower = body.toLowerCase();
    final outcome = lower.contains('abgelehnt') || lower.contains('nicht entsprechen')
        ? MailOutcome.rejected
        : lower.contains('benötigen') || lower.contains('rückfrage')
            ? MailOutcome.question
            : MailOutcome.accepted;
    final mail = state.receiveReply(outcome: outcome);
    if (mail == null) throw StateError('nothing submitted');
    return ApiInboundResult(mail: _mail(mail), outcome: _mail(mail).outcome ?? ApiMailOutcome.other);
  }

  // -- community ------------------------------------------------------------

  @override
  Future<ApiCommunity> community() async {
    final seededConfirmed = Mock.incidents.where((i) => i.status == IncidentStatus.bestaetigt).fold(0.0, (s, i) => s + i.amount);
    return ApiCommunity(
      minutes: Mock.communityMinutes,
      submittedCents: _cents(Mock.communitySubmitted + state.submittedTotal),
      confirmedCents: _cents(Mock.communityConfirmed + state.confirmedTotal - seededConfirmed),
      users: Mock.communityUsers,
      ngos: Mock.ngos.map((n) => ApiNgoTotal(id: n.id, name: n.name, confirmedCents: _cents(n.confirmedTotal), submittedCents: _cents(n.submittedTotal))).toList(),
    );
  }

  /// Demo: the same shape the backend computes, from the mock and the demo state.
  @override
  Future<ApiStanding> standing() async {
    final pointsTotal = Mock.pointsTotal + state.bonusPoints;
    final open = state.openIncidents;
    final openCents = _cents(open.fold(0.0, (s, i) => s + i.amount));
    final readyDesk = state.readyDesk;
    final missing = readyDesk != null
        ? 0
        : state.openByDesk.entries.map((e) => (400 - _cents(e.value.fold(0.0, (s, i) => s + i.amount))).clamp(0, 400)).fold(400, (m, v) => v < m ? v : m);
    final me = Mock.boardLine.where((e) => e.isMe).firstOrNull;
    final above = me == null ? null : Mock.boardLine.where((e) => e.rank == me.rank - 1).firstOrNull;
    ApiStandingNext? next;
    final inbound = state.mails.where((m) => m.direction == MailDirection.inbound).toList();
    final oldest = state.oldestOpen;
    final days = state.daysUntilOldestExpires;
    if (inbound.isNotEmpty && inbound.first.outcome != null) {
      final m = inbound.first;
      final body = switch (m.outcome!) {
        MailOutcome.accepted => '${(m.amount ?? 0).toStringAsFixed(2).replaceAll('.', ',')} € bestätigt',
        MailOutcome.question => 'Rückfrage zum Antrag',
        MailOutcome.rejected => 'Antrag abgelehnt',
      };
      next = ApiStandingNext(kind: 'mail', title: 'Post von der Bahn', body: body, claimId: m.id);
    } else if (oldest != null && days != null && days <= 21) {
      next = ApiStandingNext(kind: 'deadline', title: 'Läuft bald ab', body: '${oldest.line} vom ${Mock.shortDate(oldest.date)} verfällt in $days Tagen', incidentId: oldest.id, daysLeft: days);
    } else if (state.newBadge != null) {
      next = ApiStandingNext(kind: 'badge', title: 'Neues Abzeichen', body: state.newBadge!.name, badgeId: state.newBadge!.id);
    }
    return ApiStanding(
      pointsThisWeek: Mock.pointsThisWeek + state.bonusPoints,
      pointsLastWeek: 41,
      ridesThisWeek: 3,
      level: ApiStandingLevel(
        name: Mock.levelName,
        nextName: Mock.nextLevelName,
        pointsToNext: (Mock.nextLevelAt - pointsTotal).clamp(0, Mock.nextLevelAt),
        progress: (pointsTotal / Mock.nextLevelAt).clamp(0, 1),
      ),
      money: ApiStandingMoney(openCents: openCents, missingCents: open.isEmpty ? 400 : missing, ready: readyDesk != null, readyDesk: readyDesk, ngoName: state.ngo.name),
      board: me == null || !state.showOnBoards
          ? null
          : ApiStandingBoard(scope: 'line', key: 'RE 7', rank: me.rank, size: Mock.boardLine.length, points: me.points, gapToNext: above == null ? null : above.points - me.points + 1),
      community: ApiStandingCommunity(
        minutesTotal: Mock.communityMinutes,
        myMinutes: pointsTotal,
        confirmedCents: _cents(Mock.communityConfirmed + state.confirmedTotal - Mock.incidents.where((i) => i.status == IncidentStatus.bestaetigt).fold(0.0, (s, i) => s + i.amount)),
        myConfirmedCents: _cents(state.confirmedTotal),
      ),
      next: next,
    );
  }

  @override
  Future<List<ApiBoardEntry>> boards(String scope) async {
    final list = switch (scope) {
      'city' => Mock.boardCity,
      'germany' => Mock.boardGermany,
      _ => Mock.boardLine,
    };
    return list.where((e) => state.showOnBoards || !e.isMe).map((e) => ApiBoardEntry(rank: e.rank, name: e.name, points: e.points, isMe: e.isMe)).toList();
  }

}
