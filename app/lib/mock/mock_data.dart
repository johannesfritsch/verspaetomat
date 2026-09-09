import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

enum TicketType { deutschlandticket, zeitkarte, einzelfahrkarte }

extension TicketTypeX on TicketType {
  String get label => switch (this) {
        TicketType.deutschlandticket => 'Deutschlandticket',
        TicketType.zeitkarte => 'Andere Zeitkarte',
        TicketType.einzelfahrkarte => 'Einzelfahrkarte',
      };
  String get rule => switch (this) {
        TicketType.deutschlandticket => '1,50 € pro Verspätung ab 60 Minuten. Ausgezahlt ab 4 €. Wir sammeln für dich.',
        TicketType.zeitkarte => '1,50 € (Nahverkehr) oder 5 € (Fernverkehr) pro Verspätung ab 60 Minuten.',
        TicketType.einzelfahrkarte => '25 % des Fahrpreises ab 60 Minuten, 50 % ab 120 Minuten. Jede Fahrt einzeln.',
      };
}

class Station {
  const Station({required this.id, required this.name, required this.distanceM, this.evaNr});
  final String id;
  final String name;
  final int distanceM;
  final String? evaNr;
  String get distanceLabel => distanceM < 1000 ? '$distanceM m' : '${(distanceM / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
}

enum TrainCategory { s, rb, re, fern, bus }

class Stop {
  const Stop({required this.name, required this.planned, this.delay = 0});
  final String name;
  final TimeOfDay planned;
  final int delay;
}

class Departure {
  const Departure({
    required this.id,
    required this.line,
    required this.destination,
    required this.planned,
    required this.platform,
    required this.category,
    required this.operator,
    required this.stops,
    this.delay = 0,
    this.cancelled = false,
    this.cause,
  });
  final String id;
  final String line;
  final String destination;
  final TimeOfDay planned;
  final String platform;
  final TrainCategory category;
  final String operator;
  final List<Stop> stops;
  final int delay;
  final bool cancelled;
  final String? cause;
}

/// A ride the customer checked in to.
class Trip {
  const Trip({
    required this.departure,
    required this.fromStation,
    required this.exitStop,
    required this.ticket,
    required this.checkedInAt,
    this.locationVerified = true,
  });
  final Departure departure;
  final String fromStation;
  final Stop exitStop;
  final TicketType ticket;
  final DateTime checkedInAt;
  final bool locationVerified;
}

enum IncidentStatus { gesammelt, bereit, eingereicht, bestaetigt, abgelehnt, verfallen }

extension IncidentStatusX on IncidentStatus {
  String get label => switch (this) {
        IncidentStatus.gesammelt => 'gesammelt',
        IncidentStatus.bereit => 'bereit',
        IncidentStatus.eingereicht => 'eingereicht',
        IncidentStatus.bestaetigt => 'bestätigt',
        IncidentStatus.abgelehnt => 'abgelehnt',
        IncidentStatus.verfallen => 'verfallen',
      };
}

/// A delay that created a claim (60+ minutes), living in the ledger.
class Incident {
  Incident({
    required this.id,
    required this.date,
    required this.line,
    required this.from,
    required this.to,
    required this.delayMinutes,
    required this.amount,
    required this.ticket,
    required this.operator,
    required this.desk,
    required this.status,
    this.plannedArrival,
    this.actualArrival,
    this.cancelled = false,
    this.selfEntered = false,
    this.ngoId = 'bahnhofsmission',
    this.bundleId,
    this.fare,
  });
  final String id;
  final DateTime date;
  final String line;
  final String from;
  final String to;
  final int delayMinutes;
  final double amount;
  final TicketType ticket;
  final String operator;
  final String desk; // e.g. "Servicecenter Fahrgastrechte" or "NordWestBahn"
  IncidentStatus status;
  final TimeOfDay? plannedArrival;
  final TimeOfDay? actualArrival;
  final bool cancelled;
  final bool selfEntered;
  final String ngoId;
  String? bundleId;
  final double? fare;

  DateTime get legalDeadline => DateTime(date.year, date.month + 3, date.day);
  bool get isOpen => status == IncidentStatus.gesammelt || status == IncidentStatus.bereit;
}

class Ngo {
  const Ngo({
    required this.id,
    required this.name,
    required this.tagline,
    required this.story,
    required this.accountHolder,
    required this.iban,
    required this.confirmedTotal,
    required this.submittedTotal,
    required this.donationUrl,
    required this.lastReport,
  });
  final String id;
  final String name;
  final String tagline;
  final List<String> story;
  final String accountHolder;
  final String iban;
  final double confirmedTotal;
  final double submittedTotal;
  final String donationUrl;
  final String lastReport;
}

class VBadge {
  const VBadge({required this.id, required this.name, required this.rule, required this.earned, this.earnedOn});
  final String id;
  final String name;
  final String rule;
  final bool earned;
  final String? earnedOn;
}

class BoardEntry {
  const BoardEntry({required this.rank, required this.name, required this.points, this.isMe = false});
  final int rank;
  final String name;
  final int points;
  final bool isMe;
}

class Team {
  const Team({required this.id, required this.name, required this.members, required this.minutes, required this.euros, this.topMember});
  final String id;
  final String name;
  final int members;
  final int minutes;
  final double euros;
  final String? topMember;
}

class RailMail {
  const RailMail({
    required this.id,
    required this.incidentIds,
    required this.direction,
    required this.from,
    required this.to,
    required this.subject,
    required this.body,
    required this.date,
    this.attachments = const [],
    this.amount,
    this.outcome,
  });
  final String id;
  final List<String> incidentIds;
  final MailDirection direction;
  final String from;
  final String to;
  final String subject;
  final String body;
  final DateTime date;
  final List<String> attachments;
  final double? amount;
  final MailOutcome? outcome;
}

enum MailDirection { out, inbound }

enum MailOutcome { accepted, question, rejected }

class RideRecord {
  const RideRecord({required this.date, required this.line, required this.from, required this.to, required this.delay, this.cancelled = false, this.verified = true});
  final DateTime date;
  final String line;
  final String from;
  final String to;
  final int delay;
  final bool cancelled;
  final bool verified;
}

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

class Mock {
  Mock._();

  static const userName = 'Johannes';
  static const userAddress = 'Venloer Straße 123\n50823 Köln';
  static const userEmail = 'johannes@example.de';
  static const relayAddress = 'fahrgast-4711@verspaetomat.de';
  static const ticketNumber = 'D-2026-0904-771-2201';

  static final today = DateTime(2026, 9, 9, 10, 46);

  // Stations near the customer (Köln)
  static const nearbyStations = [
    Station(id: 'koeln-hbf', name: 'Köln Hbf', distanceM: 380, evaNr: '8000207'),
    Station(id: 'koeln-deutz', name: 'Köln Messe/Deutz', distanceM: 1200, evaNr: '8003368'),
    Station(id: 'koeln-hansaring', name: 'Köln Hansaring', distanceM: 1700, evaNr: '8003367'),
  ];

  static const homeStation = 'Köln Hbf';

  static final re7Stops = <Stop>[
    const Stop(name: 'Köln Hbf', planned: TimeOfDay(hour: 7, minute: 47)),
    const Stop(name: 'Solingen Hbf', planned: TimeOfDay(hour: 8, minute: 3)),
    const Stop(name: 'Wuppertal Hbf', planned: TimeOfDay(hour: 8, minute: 16)),
    const Stop(name: 'Hagen Hbf', planned: TimeOfDay(hour: 8, minute: 38)),
    const Stop(name: 'Unna', planned: TimeOfDay(hour: 8, minute: 56)),
    const Stop(name: 'Hamm (Westf) Hbf', planned: TimeOfDay(hour: 9, minute: 10)),
    const Stop(name: 'Münster (Westf) Hbf', planned: TimeOfDay(hour: 9, minute: 38)),
    const Stop(name: 'Rheine', planned: TimeOfDay(hour: 10, minute: 5)),
  ];

  static final departuresKoelnHbf = <Departure>[
    Departure(
      id: 're7-0747',
      line: 'RE 7',
      destination: 'Rheine',
      planned: const TimeOfDay(hour: 7, minute: 47),
      platform: '6',
      category: TrainCategory.re,
      operator: 'National Express',
      stops: re7Stops,
      delay: 3,
    ),
    Departure(
      id: 're1-0749',
      line: 'RE 1',
      destination: 'Aachen Hbf',
      planned: const TimeOfDay(hour: 7, minute: 49),
      platform: '4',
      category: TrainCategory.re,
      operator: 'National Express',
      stops: const [
        Stop(name: 'Köln Hbf', planned: TimeOfDay(hour: 7, minute: 49)),
        Stop(name: 'Horrem', planned: TimeOfDay(hour: 8, minute: 2)),
        Stop(name: 'Düren', planned: TimeOfDay(hour: 8, minute: 14)),
        Stop(name: 'Eschweiler Hbf', planned: TimeOfDay(hour: 8, minute: 25)),
        Stop(name: 'Aachen Hbf', planned: TimeOfDay(hour: 8, minute: 40)),
      ],
    ),
    Departure(
      id: 's6-0751',
      line: 'S 6',
      destination: 'Essen Hbf',
      planned: const TimeOfDay(hour: 7, minute: 51),
      platform: '10',
      category: TrainCategory.s,
      operator: 'DB Regio NRW',
      stops: const [
        Stop(name: 'Köln Hbf', planned: TimeOfDay(hour: 7, minute: 51)),
        Stop(name: 'Köln-Mülheim', planned: TimeOfDay(hour: 7, minute: 58)),
        Stop(name: 'Leverkusen Mitte', planned: TimeOfDay(hour: 8, minute: 6)),
        Stop(name: 'Düsseldorf Hbf', planned: TimeOfDay(hour: 8, minute: 37)),
        Stop(name: 'Essen Hbf', planned: TimeOfDay(hour: 9, minute: 12)),
      ],
    ),
    Departure(
      id: 're5-0755',
      line: 'RE 5',
      destination: 'Wesel',
      planned: const TimeOfDay(hour: 7, minute: 55),
      platform: '5',
      category: TrainCategory.re,
      operator: 'DB Regio NRW',
      stops: const [
        Stop(name: 'Köln Hbf', planned: TimeOfDay(hour: 7, minute: 55)),
        Stop(name: 'Düsseldorf Hbf', planned: TimeOfDay(hour: 8, minute: 19)),
        Stop(name: 'Duisburg Hbf', planned: TimeOfDay(hour: 8, minute: 33)),
        Stop(name: 'Wesel', planned: TimeOfDay(hour: 9, minute: 1)),
      ],
      delay: 12,
      cause: 'Stellwerksstörung',
    ),
    Departure(
      id: 'ice512-0758',
      line: 'ICE 512',
      destination: 'Hamburg-Altona',
      planned: const TimeOfDay(hour: 7, minute: 58),
      platform: '2',
      category: TrainCategory.fern,
      operator: 'DB Fernverkehr',
      stops: const [
        Stop(name: 'Köln Hbf', planned: TimeOfDay(hour: 7, minute: 58)),
        Stop(name: 'Düsseldorf Hbf', planned: TimeOfDay(hour: 8, minute: 20)),
        Stop(name: 'Essen Hbf', planned: TimeOfDay(hour: 8, minute: 40)),
        Stop(name: 'Münster (Westf) Hbf', planned: TimeOfDay(hour: 9, minute: 32)),
        Stop(name: 'Hamburg Hbf', planned: TimeOfDay(hour: 11, minute: 51)),
        Stop(name: 'Hamburg-Altona', planned: TimeOfDay(hour: 12, minute: 4)),
      ],
    ),
    Departure(
      id: 'rb48-0802',
      line: 'RB 48',
      destination: 'Wuppertal-Oberbarmen',
      planned: const TimeOfDay(hour: 8, minute: 2),
      platform: '9',
      category: TrainCategory.rb,
      operator: 'National Express',
      stops: const [
        Stop(name: 'Köln Hbf', planned: TimeOfDay(hour: 8, minute: 2)),
        Stop(name: 'Leverkusen Mitte', planned: TimeOfDay(hour: 8, minute: 14)),
        Stop(name: 'Solingen Hbf', planned: TimeOfDay(hour: 8, minute: 31)),
        Stop(name: 'Wuppertal-Oberbarmen', planned: TimeOfDay(hour: 9, minute: 0)),
      ],
      cancelled: true,
      cause: 'Kurzfristiger Personalausfall',
    ),
    Departure(
      id: 're9-0804',
      line: 'RE 9',
      destination: 'Siegen Hbf',
      planned: const TimeOfDay(hour: 8, minute: 4),
      platform: '8',
      category: TrainCategory.re,
      operator: 'DB Regio NRW',
      stops: const [
        Stop(name: 'Köln Hbf', planned: TimeOfDay(hour: 8, minute: 4)),
        Stop(name: 'Siegburg/Bonn', planned: TimeOfDay(hour: 8, minute: 25)),
        Stop(name: 'Au (Sieg)', planned: TimeOfDay(hour: 8, minute: 54)),
        Stop(name: 'Siegen Hbf', planned: TimeOfDay(hour: 9, minute: 30)),
      ],
    ),
    Departure(
      id: 're10-0808',
      line: 'RE 10',
      destination: 'Kleve',
      planned: const TimeOfDay(hour: 8, minute: 8),
      platform: '3',
      category: TrainCategory.re,
      operator: 'NordWestBahn',
      stops: const [
        Stop(name: 'Köln Hbf', planned: TimeOfDay(hour: 8, minute: 8)),
        Stop(name: 'Düsseldorf Hbf', planned: TimeOfDay(hour: 8, minute: 34)),
        Stop(name: 'Krefeld Hbf', planned: TimeOfDay(hour: 8, minute: 58)),
        Stop(name: 'Kleve', planned: TimeOfDay(hour: 9, minute: 47)),
      ],
      delay: 6,
    ),
  ];

  static const desks = <String, String>{
    'DB Regio NRW': 'Servicecenter Fahrgastrechte',
    'DB Fernverkehr': 'Servicecenter Fahrgastrechte',
    'National Express': 'Servicecenter Fahrgastrechte',
    'ODEG': 'Servicecenter Fahrgastrechte',
    'eurobahn': 'Servicecenter Fahrgastrechte',
    'NordWestBahn': 'NordWestBahn',
  };

  static String deskFor(String operator) => desks[operator] ?? 'Unbekannt';

  static const deskAddresses = <String, String>{
    'Servicecenter Fahrgastrechte': 'DB Fernverkehr AG · Servicecenter Fahrgastrechte · 60647 Frankfurt am Main\nEUAntragFGR@deutschebahn.com',
    'NordWestBahn': 'NordWestBahn GmbH · Kundenservice · Wilhelm-Bock-Weg 3 · 49080 Osnabrück\nfahrgastrechte@nordwestbahn.de (Beispiel)',
  };

  static final incidents = <Incident>[
    Incident(
      id: 'i-0909',
      date: DateTime(2026, 9, 9),
      line: 'RE 7',
      from: 'Köln Hbf',
      to: 'Münster (Westf) Hbf',
      delayMinutes: 68,
      amount: 1.5,
      ticket: TicketType.deutschlandticket,
      operator: 'National Express',
      desk: 'Servicecenter Fahrgastrechte',
      status: IncidentStatus.gesammelt,
      plannedArrival: const TimeOfDay(hour: 9, minute: 38),
      actualArrival: const TimeOfDay(hour: 10, minute: 46),
    ),
    Incident(
      id: 'i-0902',
      date: DateTime(2026, 9, 2),
      line: 'S 6',
      from: 'Köln Hbf',
      to: 'Düsseldorf Hbf',
      delayMinutes: 63,
      amount: 1.5,
      ticket: TicketType.deutschlandticket,
      operator: 'DB Regio NRW',
      desk: 'Servicecenter Fahrgastrechte',
      status: IncidentStatus.gesammelt,
      plannedArrival: const TimeOfDay(hour: 8, minute: 37),
      actualArrival: const TimeOfDay(hour: 9, minute: 40),
      cancelled: true,
    ),
    Incident(
      id: 'i-0828',
      date: DateTime(2026, 8, 28),
      line: 'RE 1',
      from: 'Köln Hbf',
      to: 'Aachen Hbf',
      delayMinutes: 71,
      amount: 1.5,
      ticket: TicketType.deutschlandticket,
      operator: 'National Express',
      desk: 'Servicecenter Fahrgastrechte',
      status: IncidentStatus.gesammelt,
      plannedArrival: const TimeOfDay(hour: 17, minute: 40),
      actualArrival: const TimeOfDay(hour: 18, minute: 51),
    ),
    Incident(
      id: 'i-0821',
      date: DateTime(2026, 8, 21),
      line: 'RE 10',
      from: 'Köln Hbf',
      to: 'Krefeld Hbf',
      delayMinutes: 64,
      amount: 1.5,
      ticket: TicketType.deutschlandticket,
      operator: 'NordWestBahn',
      desk: 'NordWestBahn',
      status: IncidentStatus.gesammelt,
      plannedArrival: const TimeOfDay(hour: 18, minute: 58),
      actualArrival: const TimeOfDay(hour: 20, minute: 2),
    ),
    Incident(
      id: 'i-0814',
      date: DateTime(2026, 8, 14),
      line: 'ICE 612',
      from: 'Köln Hbf',
      to: 'Frankfurt (Main) Hbf',
      delayMinutes: 124,
      amount: 19.95,
      fare: 39.9,
      ticket: TicketType.einzelfahrkarte,
      operator: 'DB Fernverkehr',
      desk: 'Servicecenter Fahrgastrechte',
      status: IncidentStatus.eingereicht,
      plannedArrival: const TimeOfDay(hour: 19, minute: 5),
      actualArrival: const TimeOfDay(hour: 21, minute: 9),
      bundleId: 'b-0815',
    ),
    Incident(
      id: 'i-0722',
      date: DateTime(2026, 7, 22),
      line: 'RE 7',
      from: 'Köln Hbf',
      to: 'Hamm (Westf) Hbf',
      delayMinutes: 66,
      amount: 1.5,
      ticket: TicketType.deutschlandticket,
      operator: 'National Express',
      desk: 'Servicecenter Fahrgastrechte',
      status: IncidentStatus.eingereicht,
      bundleId: 'b-0801',
    ),
    Incident(
      id: 'i-0715',
      date: DateTime(2026, 7, 15),
      line: 'RB 25',
      from: 'Köln Hbf',
      to: 'Gummersbach',
      delayMinutes: 61,
      amount: 1.5,
      ticket: TicketType.deutschlandticket,
      operator: 'DB Regio NRW',
      desk: 'Servicecenter Fahrgastrechte',
      status: IncidentStatus.eingereicht,
      bundleId: 'b-0801',
    ),
    Incident(
      id: 'i-0703',
      date: DateTime(2026, 7, 3),
      line: 'RE 5',
      from: 'Köln Hbf',
      to: 'Duisburg Hbf',
      delayMinutes: 92,
      amount: 1.5,
      ticket: TicketType.deutschlandticket,
      operator: 'DB Regio NRW',
      desk: 'Servicecenter Fahrgastrechte',
      status: IncidentStatus.eingereicht,
      bundleId: 'b-0801',
    ),
    Incident(
      id: 'i-0612',
      date: DateTime(2026, 6, 12),
      line: 'RE 9',
      from: 'Köln Hbf',
      to: 'Siegen Hbf',
      delayMinutes: 75,
      amount: 1.5,
      ticket: TicketType.deutschlandticket,
      operator: 'DB Regio NRW',
      desk: 'Servicecenter Fahrgastrechte',
      status: IncidentStatus.bestaetigt,
      bundleId: 'b-0620',
    ),
    Incident(
      id: 'i-0605',
      date: DateTime(2026, 6, 5),
      line: 'S 12',
      from: 'Köln Hbf',
      to: 'Hennef (Sieg)',
      delayMinutes: 60,
      amount: 1.5,
      ticket: TicketType.deutschlandticket,
      operator: 'DB Regio NRW',
      desk: 'Servicecenter Fahrgastrechte',
      status: IncidentStatus.bestaetigt,
      bundleId: 'b-0620',
    ),
    Incident(
      id: 'i-0528',
      date: DateTime(2026, 5, 28),
      line: 'RE 1',
      from: 'Köln Hbf',
      to: 'Düsseldorf Hbf',
      delayMinutes: 70,
      amount: 1.5,
      ticket: TicketType.deutschlandticket,
      operator: 'National Express',
      desk: 'Servicecenter Fahrgastrechte',
      status: IncidentStatus.bestaetigt,
      bundleId: 'b-0620',
    ),
    Incident(
      id: 'i-0402',
      date: DateTime(2026, 4, 2),
      line: 'RB 38',
      from: 'Köln Messe/Deutz',
      to: 'Bedburg (Erft)',
      delayMinutes: 62,
      amount: 1.5,
      ticket: TicketType.deutschlandticket,
      operator: 'DB Regio NRW',
      desk: 'Servicecenter Fahrgastrechte',
      status: IncidentStatus.verfallen,
    ),
  ];

  static const ngos = <Ngo>[
    Ngo(
      id: 'bahnhofsmission',
      name: 'Bahnhofsmission Köln',
      tagline: 'Hilft am Gleis, wenn sonst niemand da ist.',
      story: [
        'Die Bahnhofsmission ist rund um die Uhr am Kölner Hauptbahnhof: für Menschen, die gestrandet sind, für Reisende mit Handicap, für alle, die einen Kaffee und ein Gespräch brauchen.',
        'Verspätungen sind ihr Alltag. Wer nachts den letzten Zug verpasst, landet oft hier.',
        'Jede Entschädigung, die du hierher lenkst, bezahlt Decken, warme Getränke und die Nachtschicht.',
      ],
      accountHolder: 'Bahnhofsmission Köln e.V.',
      iban: 'DE12 3456 7890 0000 4711 00',
      confirmedTotal: 12410,
      submittedTotal: 1980,
      donationUrl: 'https://beispiel.bahnhofsmission.de/spenden',
      lastReport: '1. September 2026',
    ),
    Ngo(
      id: 'wald',
      name: 'Wald für morgen e.V.',
      tagline: 'Pflanzt, wo der Wald verschwunden ist.',
      story: [
        'Der Verein forstet Kahlflächen im Sauerland und in der Eifel wieder auf, mit Baumarten, die den nächsten Sommer überstehen.',
        'Ein Euro ist ein Setzling. 68 Minuten Warten sind eine kleine Baumreihe.',
      ],
      accountHolder: 'Wald für morgen e.V.',
      iban: 'DE98 7654 3210 0000 0815 00',
      confirmedTotal: 8730,
      submittedTotal: 2210,
      donationUrl: 'https://beispiel.waldfuermorgen.de/spenden',
      lastReport: '1. September 2026',
    ),
    Ngo(
      id: 'kinderhospiz',
      name: 'Kinderhospiz Rheinland',
      tagline: 'Zeit, die zählt, für Familien, die wenig davon haben.',
      story: [
        'Das Kinderhospiz begleitet Familien mit schwerstkranken Kindern, zu Hause und im Haus in Köln-Ehrenfeld.',
        'Wartezeit bekommt hier eine andere Bedeutung. Deine Verspätung kauft Stunden für Menschen, die sie brauchen.',
      ],
      accountHolder: 'Kinderhospiz Rheinland gGmbH',
      iban: 'DE55 1122 3344 0000 9999 00',
      confirmedTotal: 27140,
      submittedTotal: 1560,
      donationUrl: 'https://beispiel.kinderhospiz-rheinland.de/spenden',
      lastReport: '1. September 2026',
    ),
  ];

  static Ngo ngoById(String id) => ngos.firstWhere((n) => n.id == id, orElse: () => ngos.first);

  static const badges = <VBadge>[
    VBadge(id: 'erste', name: 'Erste Verspätung', rule: 'Erste verspätete Fahrt', earned: true, earnedOn: '14. Mai 2025'),
    VBadge(id: 'sev', name: 'Schienen\u00ADersatzverkehr', rule: 'In einen Ersatzbus eingecheckt', earned: true, earnedOn: '2. Sept. 2026'),
    VBadge(id: 'stellwerk', name: 'Stellwerksstörung', rule: 'Verspätung mit dieser Ursache', earned: true, earnedOn: '9. Sept. 2026'),
    VBadge(id: 'gleis', name: 'Personen im Gleis', rule: 'Verspätung mit dieser Ursache', earned: false),
    VBadge(id: 'gegenzug', name: 'Gegenzug abgewartet', rule: 'Unter 10 Minuten auf eingleisiger Strecke', earned: true, earnedOn: '11. Juni 2026'),
    VBadge(id: 'letzter', name: 'Letzter Zug', rule: 'Check-in nach 23 Uhr', earned: true, earnedOn: '30. Aug. 2026'),
    VBadge(id: 'nacht', name: 'Nachtschicht', rule: 'Ankunft zwischen 0 und 5 Uhr', earned: false),
    VBadge(id: 'stunde', name: 'Volle Stunde', rule: 'Erste Verspätung ab 60 Minuten', earned: true, earnedOn: '28. Mai 2026'),
    VBadge(id: 'bagatell', name: 'Bagatellgrenze geknackt', rule: 'Erstes Bündel über 4 €', earned: true, earnedOn: '20. Juni 2026'),
    VBadge(id: 'abgeschickt', name: 'Abgeschickt', rule: 'Erster Antrag gesendet', earned: true, earnedOn: '20. Juni 2026'),
    VBadge(id: 'bestaetigt', name: 'Bestätigt', rule: 'Erste Antwort der Bahn', earned: true, earnedOn: '18. Juli 2026'),
    VBadge(id: 'deutschland', name: 'Deutschlandreise', rule: 'Check-ins in fünf Bundesländern', earned: false),
    VBadge(id: 'stammgleis', name: 'Stammgleis', rule: '50 Fahrten auf derselben Linie', earned: true, earnedOn: '3. Aug. 2026'),
    VBadge(id: 'geduld', name: 'Geduld ist eine Tugend', rule: '1.000 Geduldspunkte', earned: false),
  ];

  static const pointsTotal = 1372;
  static const pointsThisWeek = 96;
  static const levelName = 'Gleis 7';
  static const nextLevelName = 'Bahnhofsmission';
  static const nextLevelAt = 1500;

  static const boardLine = <BoardEntry>[
    BoardEntry(rank: 1, name: 'Miri aus Hamm', points: 212),
    BoardEntry(rank: 2, name: 'tobi_aus_kalk', points: 174),
    BoardEntry(rank: 3, name: 'Anke W.', points: 151),
    BoardEntry(rank: 4, name: 'Gleiswechsel', points: 133),
    BoardEntry(rank: 5, name: 'Johannes', points: 96, isMe: true),
    BoardEntry(rank: 6, name: 'nachtschicht', points: 88),
    BoardEntry(rank: 7, name: 'Ruhrpott-Rita', points: 71),
    BoardEntry(rank: 8, name: 'Sven aus Unna', points: 64),
    BoardEntry(rank: 9, name: 'Paul & Paula', points: 52),
    BoardEntry(rank: 10, name: 'ICEkalt', points: 47),
  ];

  static const boardCity = <BoardEntry>[
    BoardEntry(rank: 1, name: 'Ehrenfeld-Express', points: 388),
    BoardEntry(rank: 2, name: 'Miri aus Hamm', points: 212),
    BoardEntry(rank: 3, name: 'Kalk-Kalle', points: 190),
    BoardEntry(rank: 4, name: 'tobi_aus_kalk', points: 174),
    BoardEntry(rank: 5, name: 'Anke W.', points: 151),
    BoardEntry(rank: 6, name: 'Südstadt-Sonja', points: 140),
    BoardEntry(rank: 7, name: 'Gleiswechsel', points: 133),
    BoardEntry(rank: 8, name: 'Deutzer Brücke', points: 118),
    BoardEntry(rank: 9, name: 'nachtschicht', points: 88),
    BoardEntry(rank: 10, name: 'Ruhrpott-Rita', points: 71),
    BoardEntry(rank: 14, name: 'Johannes', points: 96, isMe: true),
  ];

  static const boardGermany = <BoardEntry>[
    BoardEntry(rank: 1, name: 'Wartehalle Wanne', points: 1204),
    BoardEntry(rank: 2, name: 'Uelzen-Ulla', points: 987),
    BoardEntry(rank: 3, name: 'Stellwerk Stendal', points: 871),
    BoardEntry(rank: 4, name: 'Ehrenfeld-Express', points: 388),
    BoardEntry(rank: 5, name: 'BOB-Fahrer', points: 355),
    BoardEntry(rank: 6, name: 'Erzgebirge Erik', points: 301),
    BoardEntry(rank: 7, name: 'Miri aus Hamm', points: 212),
    BoardEntry(rank: 8, name: 'S-Bahn Sabine', points: 199),
    BoardEntry(rank: 9, name: 'Kalk-Kalle', points: 190),
    BoardEntry(rank: 10, name: 'tobi_aus_kalk', points: 174),
    BoardEntry(rank: 3021, name: 'Johannes', points: 96, isMe: true),
  ];

  static const teams = <Team>[
    Team(id: 'buero-nord', name: 'Büro Nord', members: 14, minutes: 4812, euros: 96, topMember: 'Anke W.'),
    Team(id: 'wg-ehrenfeld', name: 'WG Ehrenfeld', members: 4, minutes: 1290, euros: 12, topMember: 'Johannes'),
  ];

  static const communityMinutes = 1208311;
  static const communitySubmitted = 61880.0;
  static const communityConfirmed = 48320.0;
  static const communityUsers = 18420;

  static final mails = <RailMail>[
    RailMail(
      id: 'm-0815-out',
      incidentIds: ['i-0814'],
      direction: MailDirection.out,
      from: '$userName <$relayAddress>',
      to: 'EUAntragFGR@deutschebahn.com',
      subject: 'Fahrgastrechte: EU-Antragsformular',
      body:
          'Sehr geehrte Damen und Herren,\n\nanbei mein Antrag auf Entschädigung nach VO (EU) 2021/782 für die Fahrt mit ICE 612 am 14.08.2026 (Köln Hbf – Frankfurt (Main) Hbf), Ankunft 124 Minuten verspätet.\n\nDie Entschädigung bitte ich auf das im Formular angegebene Konto zu überweisen (Kontoinhaber: Bahnhofsmission Köln e.V.).\n\nDiese E-Mail wurde über Verspätomat übermittelt, eine Ausfüll- und Weiterleitungshilfe. Antragsteller ist $userName.\n\nMit freundlichen Grüßen\n$userName',
      date: DateTime(2026, 8, 15, 9, 12),
      attachments: ['EU-Antrag_ICE612_2026-08-14.pdf', 'Ticket_ICE612.png'],
    ),
    RailMail(
      id: 'm-0801-out',
      incidentIds: ['i-0722', 'i-0715', 'i-0703'],
      direction: MailDirection.out,
      from: '$userName <$relayAddress>',
      to: 'EUAntragFGR@deutschebahn.com',
      subject: 'Fahrgastrechte: EU-Antragsformular',
      body:
          'Sehr geehrte Damen und Herren,\n\nanbei mein gesammelter Antrag auf Entschädigung nach VO (EU) 2021/782 (wiederholte Verspätungen, Zeitfahrkarte Deutschlandticket) für drei Fahrten im Juli 2026. Die Einzelfälle sind im Formular unter Punkt 6 aufgeführt.\n\nKontoinhaber: Bahnhofsmission Köln e.V.\n\nDiese E-Mail wurde über Verspätomat übermittelt, eine Ausfüll- und Weiterleitungshilfe. Antragsteller ist $userName.\n\nMit freundlichen Grüßen\n$userName',
      date: DateTime(2026, 8, 1, 18, 40),
      attachments: ['EU-Antrag_Buendel_2026-07.pdf', 'Deutschlandticket_2026-07.png'],
    ),
    RailMail(
      id: 'm-0620-out',
      incidentIds: ['i-0612', 'i-0605', 'i-0528'],
      direction: MailDirection.out,
      from: '$userName <$relayAddress>',
      to: 'EUAntragFGR@deutschebahn.com',
      subject: 'Fahrgastrechte: EU-Antragsformular',
      body: 'Sehr geehrte Damen und Herren,\n\nanbei mein gesammelter Antrag (wiederholte Verspätungen, Deutschlandticket) für drei Fahrten im Mai und Juni 2026.\n\nKontoinhaber: Bahnhofsmission Köln e.V.\n\nMit freundlichen Grüßen\n$userName',
      date: DateTime(2026, 6, 20, 12, 5),
      attachments: ['EU-Antrag_Buendel_2026-06.pdf', 'Deutschlandticket_2026-06.png'],
    ),
    RailMail(
      id: 'm-0718-in',
      incidentIds: ['i-0612', 'i-0605', 'i-0528'],
      direction: MailDirection.inbound,
      from: 'Servicecenter Fahrgastrechte <fahrgastrechte@deutschebahn.com>',
      to: relayAddress,
      subject: 'Ihr Antrag auf Entschädigung – Vorgang 2026-06-4471182',
      body:
          'Sehr geehrter Herr $userName,\n\nvielen Dank für Ihren Antrag. Wir haben die von Ihnen angegebenen Fahrten geprüft.\n\nFür die Fahrten am 28.05.2026 (RE 1), 05.06.2026 (S 12) und 12.06.2026 (RE 9) mit Ihrem Deutschlandticket ergibt sich eine Entschädigung von insgesamt 4,50 EUR (3 × 1,50 EUR).\n\nDer Betrag wird in den nächsten Tagen auf das von Ihnen angegebene Konto überwiesen:\nKontoinhaber: Bahnhofsmission Köln e.V.\nIBAN: DE12 **** **** **** 4711 00\n\nMit freundlichen Grüßen\nIhr Servicecenter Fahrgastrechte',
      date: DateTime(2026, 7, 18, 14, 22),
      amount: 4.5,
      outcome: MailOutcome.accepted,
    ),
  ];

  static final rides = <RideRecord>[
    RideRecord(date: DateTime(2026, 9, 9), line: 'RE 7', from: 'Köln Hbf', to: 'Münster (Westf) Hbf', delay: 68),
    RideRecord(date: DateTime(2026, 9, 8), line: 'RE 7', from: 'Köln Hbf', to: 'Hagen Hbf', delay: 4),
    RideRecord(date: DateTime(2026, 9, 8), line: 'RE 7', from: 'Hagen Hbf', to: 'Köln Hbf', delay: 11),
    RideRecord(date: DateTime(2026, 9, 7), line: 'S 6', from: 'Köln Hbf', to: 'Düsseldorf Hbf', delay: 0),
    RideRecord(date: DateTime(2026, 9, 4), line: 'RE 1', from: 'Köln Hbf', to: 'Aachen Hbf', delay: 9),
    RideRecord(date: DateTime(2026, 9, 3), line: 'RE 5', from: 'Köln Hbf', to: 'Duisburg Hbf', delay: 22),
    RideRecord(date: DateTime(2026, 9, 2), line: 'S 6', from: 'Köln Hbf', to: 'Düsseldorf Hbf', delay: 63, cancelled: true),
    RideRecord(date: DateTime(2026, 9, 1), line: 'RE 7', from: 'Köln Hbf', to: 'Hagen Hbf', delay: 0),
    RideRecord(date: DateTime(2026, 8, 28), line: 'RE 1', from: 'Köln Hbf', to: 'Aachen Hbf', delay: 71),
    RideRecord(date: DateTime(2026, 8, 27), line: 'RB 48', from: 'Köln Hbf', to: 'Solingen Hbf', delay: 3, verified: false),
    RideRecord(date: DateTime(2026, 8, 26), line: 'RE 7', from: 'Köln Hbf', to: 'Hagen Hbf', delay: 17),
    RideRecord(date: DateTime(2026, 8, 25), line: 'RE 7', from: 'Köln Hbf', to: 'Hagen Hbf', delay: 6),
  ];

  static const causes = ['Stellwerksstörung', 'Personen im Gleis', 'Verspätung eines vorausfahrenden Zuges', 'Reparatur an der Strecke', 'Kurzfristiger Personalausfall'];

  static const weekdayNames = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  static const monthNames = ['Jan.', 'Feb.', 'März', 'Apr.', 'Mai', 'Juni', 'Juli', 'Aug.', 'Sept.', 'Okt.', 'Nov.', 'Dez.'];

  /// "Di 09.09."
  static String shortDate(DateTime d) =>
      '${weekdayNames[d.weekday - 1]} ${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.';

  /// "9. September 2026"
  static String longDate(DateTime d) {
    const months = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];
    return '${d.day}. ${months[d.month - 1]} ${d.year}';
  }

  /// "9. Sept."
  static String monthDate(DateTime d) => '${d.day}. ${monthNames[d.month - 1]}';
}
