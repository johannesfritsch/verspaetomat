import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../repo/app_repository.dart';
import '../../api/events.dart';
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'ride_widgets.dart';

/// The journey (docs/17). Glanced at, not read. The number is the whole screen.
///
/// Riding: the current leg with its live delay, the transfer ahead with the
/// connection's live status, then the destination with its planned arrival.
/// Transfer: the confirmation card "RE 5 nach Kleve 10:41 · Gleis 3 · Ich bin drin",
/// with the alternative when the connection was missed.
class UnterwegsScreen extends StatefulWidget {
  const UnterwegsScreen({super.key});

  @override
  State<UnterwegsScreen> createState() => _UnterwegsScreenState();
}

class _UnterwegsScreenState extends State<UnterwegsScreen> {
  StreamSubscription<AppEvent>? _eventSub;
  ApiJourneyLive? _journey;
  ApiRideLive? _live;
  bool _loading = true;
  bool _busy = false;
  bool _stale = false;
  DateTime? _stamp;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _eventSub = RepoScope.read(context).events.listen((e) {
      if (mounted && e.touchesRide) _load(quiet: true);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  bool get _riding => _journey?.journey.riding == true || (_journey == null && _live?.ride.status == ApiRideStatus.riding);
  bool get _transfer => _journey?.journey.inTransfer == true;

  Future<void> _load({bool quiet = false}) async {
    final repo = RepoScope.read(context).repo;
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final journey = await repo.currentJourney().catchError((_) => null);
      // Older backends and legacy single-leg rides: the ride view still works.
      final live = journey?.asRideLive ?? await repo.currentRide();
      if (!mounted) return;
      final wasOpen = _riding || _transfer;
      setState(() {
        _journey = journey;
        _live = live;
        _stale = false;
        _stamp = DateTime.now();
        _error = null;
      });
      // The journey ended while we were watching: the reveal, once.
      final arrivedNow = journey?.journey.arrived ?? (live != null && live.ride.status == ApiRideStatus.arrived);
      if (wasOpen && arrivedNow && !_transfer && mounted) {
        context.go(Routes.angekommen);
        return;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _stale = true;
          if (_live == null && _journey == null) _error = shortError(e);
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
      _poll?.cancel();
      if (mounted && (_riding || _transfer)) {
        _poll = Timer(const Duration(seconds: 20), () => _load(quiet: true));
      }
    }
  }

  Future<void> _confirm(ApiLeg leg) async {
    final j = _journey;
    if (j == null) return;
    setState(() => _busy = true);
    try {
      await RepoScope.read(context).repo.confirmLeg(j.journey.id, leg.tripId);
      await _load(quiet: true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Das ging nicht: ${shortError(e)}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "Ich bin da" / "Abbrechen" on a journey; the plain arrival call on a legacy ride.
  Future<void> _finish({required bool arrived}) async {
    final repo = RepoScope.read(context).repo;
    setState(() => _busy = true);
    try {
      final j = _journey;
      if (j != null) {
        await repo.finishJourney(j.journey.id, arrived: arrived);
        if (!mounted) return;
        if (arrived) {
          context.go(Routes.angekommen);
        } else {
          context.go(Routes.bahnsteig);
        }
      } else {
        final result = await repo.arrival(const ArrivalRequest());
        if (mounted) context.go(Routes.angekommen, extra: result);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Das ging nicht: ${shortError(e)}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _simulateArrival() async {
    final repo = RepoScope.read(context).repo;
    try {
      final result = await repo.arrival(const ArrivalRequest(delayMinutes: 68));
      await _load(quiet: true);
      if (!mounted) return;
      if (_transfer) return; // the transfer card is the next thing to see
      context.go(Routes.angekommen, extra: result);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ankunft nicht möglich: ${shortError(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = RepoScope.of(context);
    final journey = _journey?.journey;
    final live = _live;

    if (!_loading && !_riding && !_transfer) {
      final arrived = journey?.arrived ?? (live?.ride.status == ApiRideStatus.arrived);
      return _NotRiding(error: _error, onRetry: _load, arrived: arrived);
    }
    if (live == null && journey == null) {
      return VScreen(title: 'Unterwegs', child: const LoadingLine(label: 'Fahrt wird geladen …'));
    }

    final stamp = fmtLocal(_stamp);
    final demoControls = session.isLocal
        ? null
        : Row(
            children: [
              Expanded(
                child: VDemoControl(
                  label: 'Nächster Halt',
                  icon: Icons.skip_next_outlined,
                  onTap: () {
                    session.demo.tickRide();
                    _load(quiet: true);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: VDemoControl(label: 'Ankunft +68', icon: Icons.flag_outlined, onTap: _simulateArrival)),
            ],
          );

    return VScreen(
      scroll: true,
      trailing: VIconButton(icon: Icons.close, onTap: () => context.go(Routes.bahnsteig)),
      showBack: false,
      // Demo mode fakes the world from here. In local mode the Stellwerk on the backend does.
      bottom: _transfer ? null : demoControls,
      child: _transfer
          ? _TransferView(live: _journey!, busy: _busy, onConfirm: _confirm, onArrived: () => _finish(arrived: true), onAbort: () => _finish(arrived: false))
          : _RidingView(journey: journey, live: live!, stale: _stale, stamp: stamp, onWrongTrain: () => _wrongTrain(context, live.ride), onAbort: journey == null ? null : () => _finish(arrived: false)),
    );
  }

  /// E2: pick another departure from the same station.
  Future<void> _wrongTrain(BuildContext context, ApiRide r) async {
    final repo = RepoScope.read(context).repo;
    List<ApiDeparture> others = const [];
    String? error;
    try {
      others = (await repo.departures(r.fromStationId)).where((d) => d.tripId != r.tripId && !d.cancelled).toList();
    } catch (e) {
      error = shortError(e);
    }
    if (!context.mounted) return;
    showVSheet(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(bottom: VSpace.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const VSheetHeader(title: 'Welcher Zug dann?', subtitle: 'Abfahrten am Startbahnhof. Punkte bleiben.'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
              child: Column(
                children: [
                  if (error != null) ErrorLine(message: error),
                  for (final d in others.take(6))
                    DepartureRow(
                      departure: d,
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        await _changeTrain(r, d);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeTrain(ApiRide r, ApiDeparture d) async {
    final repo = RepoScope.read(context).repo;
    try {
      final trip = await repo.trip(d.tripId);
      final exitIdx = fromIndex(trip.stops, r.exitStationId, r.exitStationName);
      final exit = trip.stops.isEmpty ? null : trip.stops[exitIdx];
      await repo.checkIn(CheckInRequest(
        tripId: d.tripId,
        fromStationId: r.fromStationId,
        fromStationName: r.fromStationName,
        exitStationId: exit?.stationId ?? r.exitStationId,
        exitStationName: exit?.name ?? r.exitStationName,
      ));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Umbuchen nicht möglich: ${shortError(e)}')));
    }
  }
}

/// The current leg, live. With a journey: the transfer ahead and the destination underneath.
class _RidingView extends StatelessWidget {
  const _RidingView({required this.journey, required this.live, required this.stale, required this.stamp, required this.onWrongTrain, this.onAbort});
  final ApiJourney? journey;
  final ApiRideLive live;
  final bool stale;
  final String stamp;
  final VoidCallback onWrongTrain;
  final VoidCallback? onAbort;

  @override
  Widget build(BuildContext context) {
    final r = live.ride;
    final stops = live.stops;
    final j = journey;
    final exitIndex = stops.isEmpty ? -1 : fromIndex(stops, r.exitStationId, r.exitStationName);
    final delay = r.liveDelayMinutes;
    final planned = r.plannedArrival ?? (exitIndex >= 0 ? plannedAt(stops[exitIndex]) : null);
    final eta = live.eta ?? planned?.add(Duration(minutes: delay));
    final headsign = stops.isEmpty ? r.exitStationName : stops.last.name;
    final legsAhead = j == null ? const <ApiLeg>[] : j.legs.where((l) => (l.legNo ?? 0) > j.currentLeg).toList();
    final transferName = legsAhead.isEmpty ? null : r.exitStationName;
    final nextLeg = legsAhead.isEmpty ? null : legsAhead.first;
    final connectionAtRisk = nextLeg?.plannedDeparture != null && eta != null && eta.isAfter(nextLeg!.plannedDeparture!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            LineBadge(r.line, large: true),
            const SizedBox(width: 12),
            Expanded(child: Text('nach $headsign', style: VText.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          j == null ? r.operator : '${r.operator} · Zug ${j.currentLeg} von ${j.legs.length} · Ziel ${j.destinationStationName}',
          style: VText.caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const VGap.xl(),
        Opacity(
          opacity: stale ? 0.45 : 1,
          child: VDelay(delay, size: VDelaySize.display, cancelled: r.cancelled),
        ),
        const VGap.m(),
        Text(
          delay > 0
              ? '${transferName != null ? 'Umstieg' : 'Ankunft'} ${r.exitStationName} ${fmtLocal(eta)} statt ${fmtLocal(planned)}'
              : '${transferName != null ? 'Umstieg' : 'Ankunft'} ${r.exitStationName} ${fmtLocal(planned)}',
          style: VText.body,
        ),
        if (r.cause != null) Text(r.cause!, style: VText.caption),
        const VGap.l(),
        const VRule.red(),
        const VGap.m(),
        if (stops.isEmpty)
          Text('Halte folgen, sobald der Zug im Feed ist.', style: VText.caption)
        else
          StopLine(
            stops: stops,
            passed: r.passedStops - 1 + fromIndex(stops, r.fromStationId, r.fromStationName),
            exitIndex: exitIndex < 0 ? null : exitIndex,
            compact: true,
          ),
        if (nextLeg != null) ...[
          const VGap.l(),
          const VRule(),
          const VGap.m(),
          Text('DANACH', style: VText.eyebrow),
          const SizedBox(height: 8),
          Row(
            children: [
              LineBadge(nextLeg.line, cancelled: nextLeg.cancelled),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('nach ${nextLeg.headsign.isNotEmpty ? nextLeg.headsign : nextLeg.toStationName}', style: VText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      'ab ${nextLeg.fromStationName} ${fmtLocal(nextLeg.liveDeparture ?? nextLeg.plannedDeparture)}${nextLeg.platform != null && nextLeg.platform!.isNotEmpty ? ' · Gl. ${nextLeg.platform}' : ''}',
                      style: VText.caption,
                    ),
                  ],
                ),
              ),
              if (nextLeg.cancelled)
                const VChip('Ausfall', tone: VTone.red)
              else if (connectionAtRisk)
                const VChip('knapp', tone: VTone.red)
              else if (nextLeg.delayMin > 0)
                VDelay(nextLeg.delayMin, size: VDelaySize.small),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            connectionAtRisk ? 'Der Anschluss wird knapp. Wir planen um, sobald du da bist.' : 'Am Umstieg fragen wir einmal: bist du drin?',
            style: VText.caption,
          ),
        ],
        if (j != null) ...[
          const VGap.m(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text('Ziel ${j.destinationStationName}', style: VText.bodyS)),
              Text('an ${fmtLocal(j.plannedArrival)}', style: VText.mono),
            ],
          ),
        ],
        const VGap.l(),
        const VRule(),
        const VGap.m(),
        Text(
          stale ? 'Letzter Stand $stamp · Verbindung fehlt.' : 'Stand $stamp · Wir folgen dem Zug, nicht dir.',
          style: VText.caption,
        ),
        if (delay >= 60) ...[
          const VGap.xs(),
          Text('Ab hier entsteht ein Anspruch.', style: VText.captionInk),
        ],
        const VGap.l(),
        Row(
          children: [
            Expanded(child: VGhostButton(label: 'Falscher Zug?', color: VColors.ink2, onTap: onWrongTrain)),
            if (onAbort != null) Expanded(child: VGhostButton(label: 'Abbrechen', color: VColors.ink2, onTap: onAbort)),
          ],
        ),
      ],
    );
  }
}

/// Between two legs: confirm the connection with one tap, or the alternative after a miss.
class _TransferView extends StatelessWidget {
  const _TransferView({required this.live, required this.busy, required this.onConfirm, required this.onArrived, required this.onAbort});
  final ApiJourneyLive live;
  final bool busy;
  final ValueChanged<ApiLeg> onConfirm;
  final VoidCallback onArrived;
  final VoidCallback onAbort;

  @override
  Widget build(BuildContext context) {
    final j = live.journey;
    final next = live.nextLeg ?? j.nextLeg;
    final missed = j.missedConnection || next?.replanned == true;
    final done = live.ride;
    final where = j.transferStationName ?? next?.fromStationName ?? done?.exitStationName ?? '';
    final legDelay = done?.finalDelayMinutes ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(missed ? 'Anschluss verpasst' : 'Umsteigen', style: VText.eyebrow.copyWith(color: missed ? VColors.red : VColors.ink2)),
        const SizedBox(height: 4),
        Text(where, style: VText.h2),
        const SizedBox(height: 4),
        Text(
          done == null
              ? 'Weiter nach ${j.destinationStationName}.'
              : '${done.line} war ${legDelay > 0 ? '+$legDelay' : 'pünktlich'}${missed ? ' · der geplante Anschluss ist weg' : ''}. Weiter nach ${j.destinationStationName}.',
          style: VText.body.copyWith(color: VColors.ink2),
        ),
        const VGap.l(),
        if (next == null) ...[
          Text('Keine Verbindung gefunden.', style: VText.bodyStrong),
          const SizedBox(height: 4),
          Text('Sag uns, wenn du angekommen bist. Die Verspätung bis hierher zählt.', style: VText.caption),
        ] else
          Container(
            padding: const EdgeInsets.all(VSpace.m),
            decoration: BoxDecoration(
              border: Border.all(color: missed ? VColors.red : VColors.ink, width: 1.5),
              borderRadius: BorderRadius.circular(4),
              color: VColors.paperElevated,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (missed) ...[
                  Text('NÄCHSTE MÖGLICHKEIT', style: VText.eyebrow.copyWith(color: VColors.red)),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    LineBadge(next.line, large: true, cancelled: next.cancelled),
                    const SizedBox(width: 12),
                    Expanded(child: Text('nach ${next.headsign.isNotEmpty ? next.headsign : next.toStationName}', style: VText.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (next.delayMin > 0) VDelay(next.delayMin, size: VDelaySize.medium),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(fmtLocal(next.liveDeparture ?? next.plannedDeparture), style: VText.numberM),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        [
                          if (next.platform != null && next.platform!.isNotEmpty) 'Gleis ${next.platform}',
                          'an ${next.toStationName} ${fmtLocal(next.liveArrival ?? next.plannedArrival)}',
                        ].join(' · '),
                        style: VText.caption,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                VPrimaryButton(label: busy ? 'Einen Moment …' : 'Ich bin drin', icon: Icons.check, onTap: busy ? null : () => onConfirm(next)),
              ],
            ),
          ),
        const VGap.m(),
        Text(
          missed
              ? 'Die Verspätung zählt am Ziel, nicht pro Zug. Ein verpasster Anschluss ist ein gültiger Antragsgrund.'
              : 'Ein bestätigter Zug ist ein Beleg. Ein vermuteter nicht. Deshalb die eine Frage.',
          style: VText.caption,
        ),
        const VGap.xl(),
        const VRule(),
        const VGap.m(),
        Row(
          children: [
            Expanded(child: VOutlineButton(label: 'Ich bin da', onTap: busy ? null : onArrived)),
            const SizedBox(width: 10),
            Expanded(child: VGhostButton(label: 'Abbrechen', color: VColors.ink2, onTap: busy ? null : onAbort)),
          ],
        ),
        const VGap.xs(),
        Text('„Ich bin da“ beendet die Fahrt hier, mit der Verspätung bis ${where.isEmpty ? 'hierher' : where}.', style: VText.caption),
      ],
    );
  }
}

/// Calm empty state so the screen is always demonstrable.
class _NotRiding extends StatelessWidget {
  const _NotRiding({this.error, required this.onRetry, this.arrived = false});
  final String? error;
  final VoidCallback onRetry;
  final bool arrived;

  @override
  Widget build(BuildContext context) {
    final isLocal = RepoScope.of(context).isLocal;
    return VScreen(
      title: 'Unterwegs',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VGap.xl(),
          const Center(child: VStationClock(size: 96, animated: true)),
          const VGap.l(),
          Text(arrived ? 'Angekommen.' : 'Gerade kein Zug.', style: VText.h2),
          const VGap.s(),
          Text(
            arrived ? 'Die letzte Fahrt ist abgeschlossen. Schau sie dir an.' : 'Sag am Bahnsteig, wohin du willst, dann siehst du hier die Fahrt.',
            style: VText.body.copyWith(color: VColors.ink2),
          ),
          if (error != null) ErrorLine(message: error!, onRetry: onRetry),
          const VGap.xl(),
          if (arrived)
            VPrimaryButton(label: 'Ankunft ansehen', onTap: () => context.go(Routes.angekommen))
          else if (isLocal)
            VGhostButton(label: 'Zum Bahnsteig', onTap: () => context.go(Routes.bahnsteig))
          else
            VDemoControl(label: 'Nächsten Regio einchecken', icon: Icons.train_outlined, onTap: () => demoCheckIn(context)),
        ],
      ),
    );
  }
}
