import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../mock/mock_data.dart' show TicketType, TicketTypeX;
import '../../repo/app_repository.dart';
import '../../repo/repo_scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'angekommen_screen.dart' show ArrivalArt;
import 'ride_widgets.dart';
import '../community/community_widgets.dart' show SwitchRow;
import '../tickets/tickets.dart';

// The full screen that used to live here is gone: every train choice is a sheet now
// (docs/29). `WelcherZugList` below is the shared body it always was.

/// Step 3's body (#67): „Früher" and the day on top, the connections in the middle, and Zurück and
/// Weiter floating at the foot so they are there however far the list is scrolled. Weiter opens
/// the ticket sheet, and „Jetzt einchecken" there starts the journey. A Weiterfahrt has its ticket
/// already, so Weiter confirms the train directly.
class WelcherZugList extends StatefulWidget {
  const WelcherZugList({
    super.key,
    required this.fromStationId,
    required this.fromStationName,
    required this.toStationId,
    required this.toStationName,
    required this.onStarted,
    required this.onBack,
    this.fromLat,
    this.fromLon,
    this.firstTripId,
    this.continueJourneyId,
    this.earliestOnwardArrival,
    this.countedMinutes,
  });
  final String fromStationId;
  final String fromStationName;
  final String toStationId;
  final String toStationName;
  final double? fromLat;
  final double? fromLon;
  final String? firstTripId;
  final String? continueJourneyId;
  final DateTime? earliestOnwardArrival;
  final int? countedMinutes;

  /// The journey is running: the sheet closes itself and everything under it.
  final VoidCallback onStarted;

  /// „Zurück": the step before.
  final VoidCallback onBack;

  @override
  State<WelcherZugList> createState() => _WelcherZugListState();
}

class _WelcherZugListState extends State<WelcherZugList> {
  List<ApiItinerary> _itineraries = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  /// „Früher" (#67): where the last page back started, whether it is loading, and whether there is
  /// nothing further back that is still under way.
  DateTime? _cursor;
  bool _loadingEarlier = false;
  bool _noEarlier = false;

  /// The connections „Früher" brought in. They left longer ago than the half hour the first page
  /// looks back, and they are still „schon weg" (see [_hasLeft]).
  final Set<String> _earlierKeys = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  static DateTime? _dep(ApiItinerary it) => it.first.liveDeparture ?? it.plannedDeparture;
  static DateTime? _arr(ApiItinerary it) => it.liveArrival ?? it.plannedArrival;
  static String _key(ApiItinerary it) => it.legs.map((l) => '${l.tripId}@${l.plannedDeparture?.toIso8601String()}').join('|');

  /// One list, in the order a board has them (issue #9): the train that left twelve minutes ago
  /// stands above the next one, because that is where it belongs in time.
  static List<ApiItinerary> _sorted(Iterable<ApiItinerary> its) => [...its]..sort((a, b) {
      final da = _dep(a), db = _dep(b);
      if (da == null || db == null) return 0;
      return da.compareTo(db);
    });

  Future<void> _load() async {
    final repo = RepoScope.read(context).repo;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plan = await repo.planJourney(from: widget.fromStationId, to: widget.toStationId, firstTrip: widget.firstTripId);
      if (mounted) setState(() => _itineraries = _sorted(plan.itineraries));
    } catch (e) {
      if (mounted) setState(() => _error = shortError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// One page back: an hour before the earliest train on the list, or before the last page if
  /// that one brought nothing new. A train that has already arrived is left out — nobody is
  /// sitting in it — and when a page brings only those, there is nothing further back to show.
  Future<void> _earlier() async {
    final repo = RepoScope.read(context).repo;
    final shown = _itineraries.map(_dep).whereType<DateTime>();
    var from = shown.isEmpty ? DateTime.now() : shown.reduce((a, b) => a.isBefore(b) ? a : b);
    if (_cursor != null && _cursor!.isBefore(from)) from = _cursor!;
    from = from.subtract(const Duration(hours: 1));
    setState(() => _loadingEarlier = true);
    try {
      final plan = await repo.planJourney(from: widget.fromStationId, to: widget.toStationId, time: from);
      if (!mounted) return;
      final known = {for (final it in _itineraries) _key(it)};
      final now = DateTime.now();
      final fresh = plan.itineraries.where((it) {
        final a = _arr(it);
        return !known.contains(_key(it)) && (a == null || a.isAfter(now));
      }).toList();
      setState(() {
        _cursor = from;
        if (fresh.isEmpty) {
          _noEarlier = true;
        } else {
          _earlierKeys.addAll(fresh.map(_key));
          _itineraries = _sorted([..._itineraries, ...fresh]);
        }
      });
      if (fresh.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Davor fährt keine Verbindung mehr, die noch unterwegs ist.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Frühere Verbindungen nicht geladen: ${shortError(e)}')));
    } finally {
      if (mounted) setState(() => _loadingEarlier = false);
    }
  }

  /// Weiter. A check-in asks for the ticket first; a Weiterfahrt has one.
  Future<void> _next(ApiItinerary it) async {
    if (widget.continueJourneyId != null) {
      await _start(it, null);
      return;
    }
    final started = await showTicketChoiceSheet(context, itinerary: it, fromStationName: widget.fromStationName, onCheckin: (choice, legacy) => _start(it, legacy, choice: choice, rethrowErrors: true));
    if (started == true && mounted) widget.onStarted();
  }

  Future<void> _start(ApiItinerary it, TicketType? ticket, {JourneyTicketChoice? choice, bool rethrowErrors = false}) async {
    final session = RepoScope.read(context);
    setState(() => _sending = true);
    try {
      HapticFeedback.mediumImpact();
      final continuing = widget.continueJourneyId;
      if (continuing != null) {
        await session.repo.confirmLeg(continuing, it.legs.first.tripId);
        if (mounted) widget.onStarted();
        return;
      }
      final loc = await currentPosition(timeout: const Duration(seconds: 2), ask: true);
      await session.repo.startJourney(StartJourneyRequest(
        fromStationId: widget.fromStationId,
        fromStationName: widget.fromStationName,
        toStationId: widget.toStationId,
        toStationName: widget.toStationName,
        legs: it.legs,
        ticket: ticket,
        tickets: choice == null ? null : [choice],
        location: loc,
        fromLat: widget.fromLat,
        fromLon: widget.fromLon,
      ));
    } catch (e) {
      if (mounted) setState(() => _sending = false);
      if (rethrowErrors) rethrow;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Check-in nicht möglich: ${shortError(e)}')));
    }
  }

  DateTime get _now => DateTime.now();

  /// The backend plans from half an hour back (issue #9, `PLAN_LOOKBACK_MIN`), and this window is
  /// that one plus a little slack. Anything older than it is not „just left" — it is a timetable
  /// the app happens to be holding (the Demo fixture keeps fixed morning departures all day) and
  /// it stays in the ordinary list rather than claiming you could still be on it. What „Früher"
  /// brought in is the exception: it was asked for because it left.
  static const _justLeft = Duration(minutes: 35);

  bool _hasLeft(ApiItinerary it) {
    // The leg's own live departure when there is one: a train ten minutes late has not left yet.
    final d = _dep(it);
    if (d == null || !d.isBefore(_now)) return false;
    return _earlierKeys.contains(_key(it)) || _now.difference(d) <= _justLeft;
  }

  /// True when this itinerary arrives after the earliest onward connection (docs/21 §2).
  bool _later(ApiItinerary it) {
    final e = widget.earliestOnwardArrival;
    final a = _arr(it);
    return e != null && a != null && a.isAfter(e);
  }

  /// Which connection is ticked. The design picks first and confirms with „Weiter".
  ApiItinerary? _chosen;

  static int? _delta(DateTime? planned, DateTime? live) => planned == null || live == null ? null : live.difference(planned).inMinutes;

  /// „Heute, 27. September": the day of the first train on the list.
  static String _day(DateTime d) {
    const months = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];
    const days = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];
    final l = d.toLocal();
    final today = DateTime.now();
    final diff = DateTime(l.year, l.month, l.day).difference(DateTime(today.year, today.month, today.day)).inDays;
    final name = switch (diff) { 0 => 'Heute', -1 => 'Gestern', 1 => 'Morgen', _ => days[l.weekday - 1] };
    return '$name, ${l.day}. ${months[l.month - 1]}';
  }

  Widget _card(ApiItinerary it) {
    final first = it.legs.isEmpty ? null : it.legs.first;
    final last = it.legs.isEmpty ? null : it.legs.last;
    final plannedDep = first?.plannedDeparture ?? it.plannedDeparture;
    final liveDep = first?.liveDeparture;
    final plannedArr = last?.plannedArrival ?? it.plannedArrival;
    final liveArr = last?.liveArrival ?? it.liveArrival;
    final arrDelta = _delta(plannedArr, liveArr);
    String? track(String? t) => t == null || t.trim().isEmpty ? null : 'Gl. ${t.trim()}';
    return ItineraryTile(
      itinerary: it,
      child: VConnectionCard(
        departTime: fmtLocal(plannedDep),
        departDelta: _delta(plannedDep, liveDep),
        departLive: fmtLocal(liveDep),
        departStation: first?.fromStationName ?? widget.fromStationName,
        departPlatform: track(first?.platform),
        arriveTime: fmtLocal(plannedArr),
        arriveDelta: arrDelta,
        arriveLive: fmtLocal(liveArr),
        arriveStation: widget.toStationName,
        arrivePlatform: track(last?.arrivalPlatform),
        duration: it.durationMin == null ? '—' : fmtMinutes(it.durationMin!),
        line: first?.line ?? '',
        cls: vLineClassOf(first?.line ?? ''),
        selected: identical(_chosen, it),
        onTap: _sending ? () {} : () => setState(() => _chosen = it),
        tags: [
          if (it.direct)
            const VConnectionTag('Direkt', icon: Icons.trending_flat, tone: VConnectionTone.good)
          else
            VConnectionTag('${it.transfers}× umsteigen in ${it.transferStations.join(', ')}', icon: Icons.swap_horiz),
          // Only when the feed has said so: without a live time „Pünktlich" would be a guess. A
          // late train says it in its times, so it needs no tag of its own.
          if (arrDelta != null && arrDelta <= 0) const VConnectionTag('Pünktlich', icon: Icons.schedule, tone: VConnectionTone.good),
          // No occupancy tag. Nothing in the app or the backend knows how full a train is.
          if (_hasLeft(it)) const VConnectionTag('schon weg', icon: Icons.history),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firstDep = _itineraries.map(_dep).whereType<DateTime>().firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // „Früher" and the day, above the list and not in it: the way back is always in reach.
        Padding(
          padding: const EdgeInsets.fromLTRB(VSpace.sheet, VSpace.s, VSpace.sheet, VSpace.s),
          child: Row(
            children: [
              _Pill(
                key: const Key('zug-frueher'),
                icon: Icons.chevron_left,
                label: _loadingEarlier ? 'Lädt …' : 'Früher',
                onTap: _loading || _loadingEarlier || _noEarlier || _error != null ? null : _earlier,
              ),
              const SizedBox(width: VSpace.s),
              Expanded(
                child: Container(
                  height: VControl.button,
                  padding: const EdgeInsets.symmetric(horizontal: VSpace.md),
                  decoration: BoxDecoration(color: VColors.greyFill, borderRadius: BorderRadius.circular(VRadius.button)),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 18, color: VColors.ink2),
                      const SizedBox(width: VSpace.s),
                      Expanded(
                        child: Text(_day(firstDep ?? DateTime.now()), style: VText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              ListView(
                // Room under the last card for the buttons that float over it.
                padding: const EdgeInsets.fromLTRB(VSpace.sheet, VSpace.xs, VSpace.sheet, 120),
                children: [
                  if (_loading) ...const [VSkeletonCard(trailing: true), SizedBox(height: VSpace.s), VSkeletonCard(trailing: true)],
                  if (_error != null) ...[const OfflineBanner(), ErrorLine(message: 'Keine Verbindung geplant. $_error', onRetry: _load)],
                  if (!_loading && _error == null && _itineraries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: VSpace.l),
                      child: Text('Gerade keine Verbindung in Sicht. Versuch es gleich noch mal oder nimm ein anderes Ziel.', style: VText.bodyS.copyWith(color: VColors.ink2)),
                    ),
                  if (widget.continueJourneyId != null && _itineraries.isNotEmpty) ...[
                    Text('Deine Fahrt läuft weiter. Die Verspätung zählt am Ziel.', style: VText.bodyS),
                    const VGap.s(),
                  ],
                  for (final it in _itineraries) ...[
                    _card(it),
                    // A later train than the earliest one: the extra wait is the passenger's, not the railway's.
                    if (_later(it))
                      Padding(
                        padding: const EdgeInsets.only(left: VSpace.xs, top: VSpace.xs),
                        child: Text('Deine Pause zählt nicht mit — es bleiben ${fmtMinutes(widget.countedMinutes ?? 0)}.', style: VText.caption),
                      ),
                    const VGap.s(),
                  ],
                ],
              ),
              // Zurück and Weiter, floating: on paper, with the list fading out under them.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: EdgeInsets.fromLTRB(VSpace.sheet, VSpace.l, VSpace.sheet, VSpace.m + MediaQuery.paddingOf(context).bottom),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [VColors.paperElevated.withAlpha(0), VColors.paperElevated, VColors.paperElevated],
                      stops: const [0, 0.35, 1],
                    ),
                  ),
                  child: Row(
                    children: [
                      // Grey, like „Schließen" on the other sheets: going back is not the thing
                      // this step is for, and an ink outline beside the red button read louder
                      // than it.
                      Expanded(child: VTintButton(label: 'Zurück', icon: Icons.arrow_back, tone: VTintTone.neutral, onTap: _sending ? null : widget.onBack)),
                      const SizedBox(width: VSpace.s),
                      Expanded(
                        // No arrow at half the width: it ran into the label.
                        child: VPrimaryButton(
                          label: 'Weiter',
                          busy: _sending,
                          onTap: _chosen == null || _sending ? null : () => _next(_chosen!),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A quiet grey button the height of the day beside it.
class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null ? VColors.ink3 : VColors.ink;
    return Material(
      color: VColors.greyFill,
      borderRadius: BorderRadius.circular(VRadius.button),
      child: InkWell(
        borderRadius: BorderRadius.circular(VRadius.button),
        onTap: onTap,
        child: SizedBox(
          height: VControl.button,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(VSpace.s, 0, VSpace.md, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(width: VSpace.xs),
                Text(label, style: VText.bodyStrong.copyWith(color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// „Fahrkarte auswählen" (#67, #66): after Weiter, before the journey starts. The platform drawing
/// with the station you are leaving from on its sign, the connection in one line, the passenger's
/// own tickets (the one used last first), a single ticket for this ride, and „Andere Fahrkarte".
/// The sentence under the choice is the catalogue's, so what the app says a ticket brings is what
/// the server will count.
///
/// A ticket that does not cover a train of this connection is greyed out with the reason: the
/// Deutschlandticket does not cover an ICE, so whoever sits in one holds another ticket.
///
/// On a first ride there are no tickets yet: the common ones are offered to add right here. And a
/// server from before tickets gets the three types it knows.
///
/// Returns true when the journey started; the caller then closes the check-in and goes home.
Future<bool?> showTicketChoiceSheet(
  BuildContext context, {
  required ApiItinerary itinerary,
  required String fromStationName,
  required Future<void> Function(JourneyTicketChoice? choice, TicketType legacy) onCheckin,
}) {
  return showVSheet<bool>(
    context,
    builder: (ctx) => _TicketChoice(itinerary: itinerary, fromStationName: fromStationName, onCheckin: onCheckin),
  );
}

/// What is chosen: a ticket the passenger has, a new one of a product, or the single ticket.
class _Pick {
  const _Pick.ticket(String this.ticketId) : product = null, single = false;
  const _Pick.product(String this.product) : ticketId = null, single = false;
  const _Pick.single() : ticketId = null, product = null, single = true;
  final String? ticketId;
  final String? product;
  final bool single;

  @override
  bool operator ==(Object other) => other is _Pick && other.ticketId == ticketId && other.product == product && other.single == single;

  @override
  int get hashCode => Object.hash(ticketId, product, single);
}

class _TicketChoice extends StatefulWidget {
  const _TicketChoice({required this.itinerary, required this.fromStationName, required this.onCheckin});
  final ApiItinerary itinerary;
  final String fromStationName;
  final Future<void> Function(JourneyTicketChoice? choice, TicketType legacy) onCheckin;

  @override
  State<_TicketChoice> createState() => _TicketChoiceState();
}

class _TicketChoiceState extends State<_TicketChoice> {
  TicketBook? _book;
  bool _legacyOnly = false;
  _Pick? _pick;
  TicketType? _legacy;
  final _price = TextEditingController();
  bool _first = false;
  bool _busy = false;
  String? _error;

  bool get _longDistance => widget.itinerary.legs.any((l) => l.category == ApiCategory.fern);

  /// The single ticket's product: DB's for a long-distance journey, the Deutschlandtarif's for a
  /// regional one.
  String get _singleProduct => _longDistance ? 'einzel_db' : 'einzel_nah';

  /// The first ride's shortcuts: the families that are one product each.
  static const _quick = ['deutschlandticket', 'bahncard100', 'streckenzeitkarte', 'laender_ticket'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  Future<void> _load({String? select}) async {
    try {
      final b = await TicketBook.load(context);
      if (!mounted) return;
      setState(() {
        _book = b;
        if (select != null) {
          _pick = _Pick.ticket(select);
        } else {
          _pick ??= b.tickets.where((t) => _covers(b.fares.byId(t.product))).map((t) => _Pick.ticket(t.id)).firstOrNull;
        }
      });
    } catch (_) {
      // A server from before tickets (#66): the three types it knows.
      if (!mounted) return;
      final current = RepoScope.read(context).me?.settings.ticket;
      setState(() {
        _legacyOnly = true;
        if (current != null && _legacyAllowed(current)) _legacy = current;
      });
    }
  }

  bool _covers(ApiFare? fare) => fare == null || !_longDistance || fare.validLongDistance;

  bool _legacyAllowed(TicketType t) => !(t == TicketType.deutschlandticket && _longDistance);

  static IconData _legacyIcon(TicketType t) => switch (t) {
    TicketType.deutschlandticket => Icons.confirmation_number,
    TicketType.zeitkarte => Icons.badge_outlined,
    TicketType.einzelfahrkarte => Icons.receipt_long_outlined,
  };

  String _legacyHint(TicketType t) => switch (t) {
    TicketType.deutschlandticket => _longDistance ? 'Gilt nicht im Fernverkehr.' : 'Nah- und Regionalverkehr.',
    TicketType.zeitkarte => 'BahnCard 100, Monats- oder Jahreskarte.',
    TicketType.einzelfahrkarte => 'Für genau diese Fahrt gekauft.',
  };

  ApiFare? get _pickedFare {
    final b = _book;
    final p = _pick;
    if (b == null || p == null) return null;
    if (p.single) return b.fares.byId(_singleProduct);
    if (p.product != null) return b.fares.byId(p.product!);
    final t = b.tickets.where((t) => t.id == p.ticketId).firstOrNull;
    return t == null ? null : b.fares.byId(t.product);
  }

  Future<void> _addOther() async {
    final t = await addTicket(context);
    if (t != null && mounted) await _load(select: t.id);
  }

  Future<void> _checkin() async {
    JourneyTicketChoice? choice;
    TicketType legacy;
    if (_legacyOnly) {
      if (_legacy == null) return;
      legacy = _legacy!;
    } else {
      final p = _pick;
      final fare = _pickedFare;
      if (p == null) return;
      if (p.single && _price.text.trim().isNotEmpty && parseEuro(_price.text) == null) {
        setState(() => _error = 'Der Fahrpreis ist keine Zahl.');
        return;
      }
      choice = p.ticketId != null
          ? JourneyTicketChoice.existing(p.ticketId!)
          : JourneyTicketChoice.adding(TicketInput(product: p.single ? _singleProduct : p.product!, firstClass: p.single && _first, priceCents: p.single ? parseEuro(_price.text) : null));
      legacy = fare?.ticket ?? TicketType.deutschlandticket;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onCheckin(choice, legacy);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Check-in nicht möglich: ${shortError(e)}';
        });
      }
    }
  }

  List<Widget> _options() {
    if (_legacyOnly) {
      return [
        for (final t in TicketType.values) ...[
          _TicketOption(
            key: Key('ticket-${t.name}'),
            icon: _legacyIcon(t),
            title: t.label,
            hint: _legacyHint(t),
            selected: _legacy == t,
            enabled: _legacyAllowed(t) && !_busy,
            onTap: () => setState(() => _legacy = t),
          ),
          const VGap.s(),
        ],
      ];
    }
    final b = _book;
    if (b == null) return const [VSkeletonCard(), VGap.s()];
    final seen = <String>{};
    final out = <Widget>[];
    void option({required Key key, required IconData icon, required String title, required String hint, required _Pick pick, required bool enabled}) {
      out
        ..add(_TicketOption(key: key, icon: icon, title: title, hint: hint, selected: _pick == pick, enabled: enabled && !_busy, onTap: () => setState(() => _pick = pick)))
        ..add(const VGap.s());
    }

    for (final t in b.tickets) {
      final fare = b.fares.byId(t.product);
      final covers = _covers(fare);
      // The first ticket of a product carries the product's key: the E2E picks by product.
      final key = seen.add(t.product) ? Key('ticket-${t.product}') : Key('ticket-${t.id}');
      option(
        key: key,
        icon: TicketFamily.of(t.family).icon,
        title: t.name,
        hint: covers ? (ticketMissing(t, fare) ?? (fare?.validLongDistance == false ? 'Nah- und Regionalverkehr.' : (t.firstClass ? '1. Klasse.' : '2. Klasse.'))) : 'Gilt nicht im Fernverkehr.',
        pick: _Pick.ticket(t.id),
        enabled: covers,
      );
    }
    // The shortcuts: on a first ride, and whenever none of the passenger's tickets covers this
    // connection (a D-Ticket holder boarding an ICE holds another ticket for it).
    final covered = b.tickets.any((t) => _covers(b.fares.byId(t.product)));
    if (b.tickets.isEmpty || !covered) {
      for (final id in _quick) {
        final fare = b.fares.inFamily(id).firstOrNull;
        if (fare == null || b.tickets.any((t) => t.product == fare.id)) continue;
        final covers = _covers(fare);
        option(
          key: Key('ticket-${fare.id}'),
          icon: TicketFamily.of(id).icon,
          title: fare.name,
          hint: covers ? (fare.validLongDistance ? 'Nah- und Fernverkehr.' : 'Nah- und Regionalverkehr.') : 'Gilt nicht im Fernverkehr.',
          pick: _Pick.product(fare.id),
          enabled: covers,
        );
      }
    }
    option(key: const Key('ticket-single'), icon: Icons.receipt_long_outlined, title: 'Einzelfahrkarte', hint: 'Für genau diese Fahrt gekauft.', pick: const _Pick.single(), enabled: true);
    if (_pick?.single ?? false) {
      out
        ..add(
          VCard(
            padding: const EdgeInsets.symmetric(horizontal: VSpace.cardTight),
            child: Column(
              children: [
                TicketField(
                  key: const Key('ticket-single-preis'),
                  label: 'Fahrpreis',
                  hint: 'Kannst du auch später eintragen',
                  controller: _price,
                  keyboard: const TextInputType.numberWithOptions(decimal: true),
                  suffix: '€',
                ),
                const VDivider(),
                SwitchRow(title: '1. Klasse', value: _first, divider: false, onChanged: (v) => setState(() => _first = v)),
              ],
            ),
          ),
        )
        ..add(const VGap.s());
    }
    out
      ..add(VGhostButton(key: const Key('ticket-add'), label: 'Andere Fahrkarte', icon: Icons.add, onTap: _busy ? null : _addOther))
      ..add(const VGap.s());
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.itinerary;
    final first = it.legs.isEmpty ? null : it.legs.first;
    final last = it.legs.isEmpty ? null : it.legs.last;
    final dep = first?.liveDeparture ?? first?.plannedDeparture ?? it.plannedDeparture;
    final arr = last?.liveArrival ?? last?.plannedArrival ?? it.liveArrival ?? it.plannedArrival;
    final lines = it.legs.map((l) => l.line).where((l) => l.isNotEmpty).join(' · ');
    final fare = _legacyOnly ? null : _pickedFare;
    final ready = _legacyOnly ? _legacy != null : _pick != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: VSpace.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: VSpace.l),
                child: ArrivalArt(station: widget.fromStationName, widthFactor: 1),
              ),
              const Positioned(left: 0, right: 0, top: 0, child: VSheetHeader()),
              Positioned(
                right: VSpace.sheet,
                top: VSpace.l,
                child: VCircleIconButton(icon: Icons.close, onTap: _busy ? () {} : () => Navigator.of(context).pop()),
              ),
            ],
          ),
          // No scroll view of its own: showVSheet already scrolls a sheet taller than the screen.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: VSpace.sheet),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Fahrkarte auswählen', style: VText.h2),
                const VGap.xs(),
                Text('Für die Verbindung ${fmtLocal(dep)} → ${fmtLocal(arr)}${lines.isEmpty ? '' : ' ($lines)'}', style: VText.body.copyWith(color: VColors.ink2)),
                const VGap.m(),
                ..._options(),
                if (fare != null) ...[
                  Text(
                    fare.ruleLine,
                    key: const Key('ticket-regel'),
                    style: VText.bodyS.copyWith(color: VColors.ink2),
                  ),
                  if (fare.caveat != null) ...[const SizedBox(height: 2), Text(fare.caveat!, style: VText.bodyS.copyWith(color: VColors.ink3))],
                  const VGap.s(),
                ],
                if (_error != null) ...[Text(_error!, style: VText.bodyS.copyWith(color: VColors.red)), const VGap.s()],
                const VGap.s(),
                VPrimaryButton(label: 'Jetzt einchecken', trailingIcon: Icons.arrow_forward, busy: _busy, onTap: !ready || _busy ? null : _checkin),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One ticket: its mark, its name, what it covers, and the same select mark the connection cards
/// carry. Greyed out and inert when it cannot be the ticket for this connection.
class _TicketOption extends StatelessWidget {
  const _TicketOption({super.key, required this.icon, required this.title, required this.hint, required this.selected, required this.enabled, required this.onTap});
  final IconData icon;
  final String title;
  final String hint;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(VRadius.md);
    return Opacity(
      opacity: enabled || selected ? 1 : 0.45,
      child: Material(
        color: selected ? VColors.redTintFaint : VColors.paperElevated,
        borderRadius: shape,
        child: InkWell(
          borderRadius: shape,
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.all(VSpace.cardTight),
            decoration: BoxDecoration(
              borderRadius: shape,
              border: Border.all(color: selected ? VColors.red : VColors.hairline, width: selected ? VControl.hairline * 2 : VControl.hairline),
            ),
            child: Row(
              children: [
                VIconBadge(icon: icon, tone: selected ? VBadgeTone.red : VBadgeTone.neutral, size: VControl.badgeSmall, iconColor: selected ? null : VColors.ink2),
                const SizedBox(width: VSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: VText.bodyStrong),
                      const SizedBox(height: 2),
                      Text(hint, style: VText.bodyS),
                    ],
                  ),
                ),
                const SizedBox(width: VSpace.s),
                Container(
                  width: VControl.badgeIcon,
                  height: VControl.badgeIcon,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? VColors.red : null,
                    border: selected ? null : Border.all(color: VColors.disabledInk, width: VControl.hairline * 3),
                  ),
                  child: selected ? const Icon(Icons.check, size: VControl.chevronSmall, color: VColors.inkOnDark) : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The itinerary a connection card stands for, hung on the card without drawing anything.
///
/// [VConnectionCard] is a design widget: it takes times, names and tags, and knows nothing about a
/// journey. The walk-through test has to pick a particular connection — direct or with exactly one
/// transfer, an operator the claims directory knows, one that has not left yet — and until this
/// tile existed it read that off `ItineraryRow`, which this list stopped using in the redesign
/// (#26). One stale finder took three E2E scenarios down with it, so the handle is worth its four
/// lines.
class ItineraryTile extends StatelessWidget {
  const ItineraryTile({super.key, required this.itinerary, required this.child});
  final ApiItinerary itinerary;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// One itinerary in board style: the first leg as a departure row, the transfers as a chip line.
class ItineraryRow extends StatelessWidget {
  const ItineraryRow({super.key, required this.itinerary, required this.onTap, this.departed = false});
  final ApiItinerary itinerary;
  final VoidCallback? onTap;

  /// This train has left. The row keeps its live delay — it is the same train, still running —
  /// and says how long ago it went instead of pretending it is next (issue #9).
  final bool departed;

  static String _ago(DateTime? when) {
    if (when == null) return '';
    final m = DateTime.now().difference(when).inMinutes;
    if (m < 1) return 'gerade';
    if (m < 60) return 'vor $m Min';
    return 'vor ${(m / 60).round()} Std';
  }

  @override
  Widget build(BuildContext context) {
    final it = itinerary;
    final first = it.first;
    final d = first.toDeparture();
    final delay = d.delayMinutes;
    final meta = [if (first.platform != null && first.platform!.isNotEmpty) 'Gl. ${first.platform}', first.operator].where((s) => s.isNotEmpty).join(' · ');
    final arrival = it.liveArrival ?? it.plannedArrival;
    final late = it.liveArrival != null && it.plannedArrival != null && it.liveArrival!.isAfter(it.plannedArrival!);
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 52,
                      child: Text(
                        fmtLocal(d.scheduledDeparture),
                        style: VText.mono.copyWith(
                          color: d.cancelled || departed ? VColors.ink3 : VColors.ink,
                          decoration: d.cancelled ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    LineBadgeColumn(child: LineBadge(d.line, cancelled: d.cancelled)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.destination, style: VText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(meta, style: VText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (departed && !d.cancelled)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(_ago(d.scheduledDeparture), style: VText.caption),
                      ),
                    if (d.cancelled)
                      const VChip('Ausfall', tone: VTone.red)
                    else if (delay > 0)
                      VDelay(delay, size: VDelaySize.small)
                    else
                      Text('pünktlich', style: VText.caption.copyWith(color: VColors.green)),
                    const SizedBox(width: 4),
                    // One row, one tap: the chevron says so.
                    const Icon(Icons.chevron_right, size: 22, color: VColors.ink2),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 62),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (it.direct)
                        const VChip('direkt', tone: VTone.green)
                      else
                        VChip('${it.transfers}× umsteigen in ${it.transferStations.join(', ')}', tone: VTone.ink),
                      if (it.preferred) const VChip('nächste Verbindung', tone: VTone.neutral),
                      Text(
                        'an ${fmtLocal(arrival)}${it.durationMin != null ? ' · ${it.durationMin} min' : ''}',
                        style: VText.caption.copyWith(color: late ? VColors.red : VColors.ink2),
                      ),
                    ],
                  ),
                ),
                if (!it.direct) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 62),
                    child: Text(
                      [for (final l in it.legs.skip(1)) '${l.line} ab ${l.fromStationName} ${fmtLocal(l.plannedDeparture)}'].join(' · '),
                      style: VText.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const VRule(),
        ],
      ),
    );
  }
}
