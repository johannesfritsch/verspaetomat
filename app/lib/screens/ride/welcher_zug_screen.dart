import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../mock/mock_data.dart' show TicketTypeX;
import '../../repo/app_repository.dart';
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'ride_widgets.dart';

/// "Welcher Zug?" (docs/17) as a full screen: still the target of a deep link and of the
/// Weiterfahrt from the ride sheet. The check-in flow shows [WelcherZugList] in a sheet
/// instead (docs/24 §1), so a wrong choice above is one swipe away.
class WelcherZugScreen extends StatelessWidget {
  const WelcherZugScreen({
    super.key,
    required this.fromStationId,
    required this.fromStationName,
    required this.toStationId,
    required this.toStationName,
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

  /// Weiterfahrt (docs/21 §2): confirm this train as the next leg of a journey that is
  /// already running, instead of starting a new one. The planned arrival stays.
  final String? continueJourneyId;

  /// The arrival of the earliest onward connection, and the minutes it is worth. Anything
  /// later is the passenger's own pause and adds nothing to the claim.
  final DateTime? earliestOnwardArrival;
  final int? countedMinutes;

  @override
  Widget build(BuildContext context) {
    return VScreen(
      eyebrow: '$fromStationName → $toStationName',
      title: 'Welcher Zug?',
      child: WelcherZugList(
        fromStationId: fromStationId,
        fromStationName: fromStationName,
        toStationId: toStationId,
        toStationName: toStationName,
        fromLat: fromLat,
        fromLon: fromLon,
        firstTripId: firstTripId,
        continueJourneyId: continueJourneyId,
        earliestOnwardArrival: earliestOnwardArrival,
        countedMinutes: countedMinutes,
        onStarted: () => context.go(Routes.unterwegs),
      ),
    );
  }
}

/// The itineraries themselves: the list, the ticket row and the tap that starts the journey.
/// Shared by [WelcherZugScreen] and the check-in sheet (docs/24 §1).
class WelcherZugList extends StatefulWidget {
  const WelcherZugList({
    super.key,
    required this.fromStationId,
    required this.fromStationName,
    required this.toStationId,
    required this.toStationName,
    required this.onStarted,
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

  /// The journey is running: the screen navigates, the sheet closes itself first.
  final VoidCallback onStarted;

  @override
  State<WelcherZugList> createState() => _WelcherZugListState();
}

class _WelcherZugListState extends State<WelcherZugList> {
  List<ApiItinerary> _itineraries = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repo = RepoScope.read(context).repo;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plan = await repo.planJourney(from: widget.fromStationId, to: widget.toStationId, firstTrip: widget.firstTripId);
      final list = [...plan.itineraries]..sort((a, b) {
          if (a.preferred != b.preferred) return a.preferred ? -1 : 1;
          final da = a.plannedDeparture, db = b.plannedDeparture;
          if (da == null || db == null) return 0;
          return da.compareTo(db);
        });
      if (mounted) setState(() => _itineraries = list);
    } catch (e) {
      if (mounted) setState(() => _error = shortError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _start(ApiItinerary it) async {
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
      final loc = await currentPosition(timeout: const Duration(seconds: 2));
      await session.repo.startJourney(StartJourneyRequest(
        fromStationId: widget.fromStationId,
        fromStationName: widget.fromStationName,
        toStationId: widget.toStationId,
        toStationName: widget.toStationName,
        legs: it.legs,
        location: loc,
        fromLat: widget.fromLat,
        fromLon: widget.fromLon,
      ));
      if (mounted) widget.onStarted();
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Check-in nicht möglich: ${shortError(e)}')));
      }
    }
  }

  /// True when this itinerary arrives after the earliest onward connection (docs/21 §2).
  bool _later(ApiItinerary it) {
    final e = widget.earliestOnwardArrival;
    final a = it.liveArrival ?? it.plannedArrival;
    return e != null && a != null && a.isAfter(e);
  }

  @override
  Widget build(BuildContext context) {
    final session = RepoScope.of(context);
    final ticket = session.me?.settings.ticket;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const VGap.s(),
        if (_loading) const LoadingLine(label: 'Verbindungen werden geladen …'),
        if (_error != null) ...[const OfflineBanner(), ErrorLine(message: 'Keine Verbindung geplant. $_error', onRetry: _load)],
        if (!_loading && _error == null && _itineraries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: VSpace.l),
            child: Text('Gerade keine Verbindung in Sicht. Versuch es gleich noch mal oder nimm ein anderes Ziel.', style: VText.bodyS.copyWith(color: VColors.ink2)),
          ),
        if (_itineraries.isNotEmpty) ...[
          Text(widget.continueJourneyId != null ? 'Tipp auf den Zug, mit dem du weiterfährst.' : 'Tipp auf den Zug, in dem du sitzt.', style: VText.bodyStrong),
          const SizedBox(height: 2),
          Text(
            widget.continueJourneyId != null ? 'Deine Fahrt läuft weiter. Die Verspätung zählt am Ziel.' : 'Umstiege folgen später von selbst.',
            style: VText.caption,
          ),
        ],
        const VGap.m(),
        for (final it in _itineraries) ...[
          ItineraryRow(itinerary: it, onTap: _sending ? null : () => _start(it)),
          // A later train than the earliest one: the extra wait is the passenger's, not the railway's.
          if (_later(it)) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: VSpace.s),
              child: Text('Deine Pause zählt nicht mit — es bleiben ${fmtMinutes(widget.countedMinutes ?? 0)}.', style: VText.caption),
            ),
          ],
        ],
        if (_sending) const LoadingLine(label: 'Einchecken …'),
        // The ticket belongs to the claim, not to the train: quiet, and always reachable.
        InkWell(
          onTap: () => showTicketSheet(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.confirmation_number_outlined, size: 20, color: VColors.ink2),
                const SizedBox(width: 10),
                Expanded(child: Text(ticket?.label ?? 'Ticket wählen', style: VText.bodySStrong)),
                const Icon(Icons.expand_more, size: 20, color: VColors.ink2),
              ],
            ),
          ),
        ),
        const VGap.l(),
      ],
    );
  }
}

/// One itinerary in board style: the first leg as a departure row, the transfers as a chip line.
class ItineraryRow extends StatelessWidget {
  const ItineraryRow({super.key, required this.itinerary, required this.onTap});
  final ApiItinerary itinerary;
  final VoidCallback? onTap;

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
                      child: Text(fmtLocal(d.scheduledDeparture), style: VText.mono.copyWith(color: d.cancelled ? VColors.ink3 : VColors.ink, decoration: d.cancelled ? TextDecoration.lineThrough : null)),
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
