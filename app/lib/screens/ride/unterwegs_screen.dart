import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../repo/app_repository.dart';
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../state/ride_monitor.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'angekommen_screen.dart';
import 'ride_widgets.dart';

/// The journey (docs/17), shown inside the ride sheet (docs/19). Glanced at, not read.
///
/// Riding: the current leg with its live delay, the transfer ahead with the
/// connection's live status, then the destination with its planned arrival.
/// Transfer: the confirmation card "RE 5 nach Kleve 10:41 · Gleis 3 · Ich bin drin",
/// with the alternative when the connection was missed.
/// Arrived while the sheet is open: the reveal (the Angekommen body).
///
/// Data comes from the shell's [RideMonitor]; this widget only renders and acts.
class RideSheetBody extends StatelessWidget {
  const RideSheetBody({super.key, required this.monitor});
  final RideMonitor monitor;

  @override
  Widget build(BuildContext context) {
    final session = RepoScope.of(context);
    final m = monitor;
    final journey = m.journey?.journey;
    final live = m.rideLive;

    if (m.arrived) {
      // The journey ended while the sheet was open: the reveal, in place.
      return AngekommenScreen(embedded: true, onDone: () => m.dismiss());
    }
    if (!m.active) {
      return Padding(
        padding: const EdgeInsets.all(VSpace.page),
        child: Text(m.error ?? 'Gerade kein Zug.', style: VText.body.copyWith(color: VColors.ink2)),
      );
    }
    if (live == null && journey == null) {
      return const Padding(padding: EdgeInsets.all(VSpace.page), child: LoadingLine(label: 'Fahrt wird geladen …'));
    }

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
                    m.refresh(quiet: true);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: VDemoControl(label: 'Ankunft +68', icon: Icons.flag_outlined, onTap: () => _simulateArrival(context))),
            ],
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(VSpace.page, 0, VSpace.page, VSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (m.transfer)
            _TransferView(
              live: m.journey!,
              busy: m.busy,
              onConfirm: (leg) => _confirm(context, leg),
              onArrived: () => _finish(context, arrived: true),
              onAbort: () => _finish(context, arrived: false),
            )
          else
            _RidingView(
              journey: journey,
              live: live!,
              stale: m.stale,
              stamp: fmtLocal(m.stamp),
              onWrongTrain: () => _wrongTrain(context, live.ride),
              onAbort: journey == null ? null : () => _finish(context, arrived: false),
            ),
          if (demoControls != null && !m.transfer) ...[const VGap.l(), demoControls],
        ],
      ),
    );
  }

  Future<void> _confirm(BuildContext context, ApiLeg leg) async {
    try {
      await monitor.confirmLeg(leg);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Das ging nicht: ${shortError(e)}')));
    }
  }

  /// "Ich bin da" / "Abbrechen". A legacy ride's arrival result opens the full reveal.
  Future<void> _finish(BuildContext context, {required bool arrived}) async {
    try {
      final result = await monitor.finish(arrived: arrived);
      if (!context.mounted) return;
      if (result != null) {
        monitor.closeSheet();
        context.push(Routes.angekommen, extra: result);
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Das ging nicht: ${shortError(e)}')));
    }
  }

  Future<void> _simulateArrival(BuildContext context) async {
    final repo = RepoScope.read(context).repo;
    try {
      await repo.arrival(const ArrivalRequest(delayMinutes: 68));
      await monitor.refresh(quiet: true);
      // A transfer keeps the sheet on the connection; an arrival switches the body to the reveal.
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ankunft nicht möglich: ${shortError(e)}')));
    }
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
                        await _changeTrain(context, r, d);
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

  Future<void> _changeTrain(BuildContext context, ApiRide r, ApiDeparture d) async {
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
      await monitor.refresh();
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Umbuchen nicht möglich: ${shortError(e)}')));
    }
  }
}

/// The sheet's title line: caption + h2, per state.
(String, String) rideSheetTitle(RideMonitor m) {
  if (m.arrived) {
    return ('Angekommen', m.journey?.journey.destinationStationName ?? m.rideLive?.ride.exitStationName ?? '');
  }
  if (m.transfer) {
    final j = m.journey!.journey;
    final missed = j.missedConnection || (m.journey!.nextLeg ?? j.nextLeg)?.replanned == true;
    return (missed ? 'Anschluss verpasst' : 'Umsteigen', j.transferStationName ?? (m.journey!.nextLeg ?? j.nextLeg)?.fromStationName ?? '');
  }
  final r = m.rideLive?.ride;
  final stops = m.rideLive?.stops ?? const [];
  final headsign = stops.isEmpty ? (r?.exitStationName ?? '') : stops.last.name;
  return ('Unterwegs', r == null ? '' : '${r.line} nach $headsign');
}

/// The current leg, live. With a journey: the transfer ahead and the destination underneath.
/// The line and headsign are the sheet's header, so the body starts with the context line.
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
    final legsAhead = j == null ? const <ApiLeg>[] : j.legs.where((l) => (l.legNo ?? 0) > j.currentLeg).toList();
    final transferName = legsAhead.isEmpty ? null : r.exitStationName;
    final nextLeg = legsAhead.isEmpty ? null : legsAhead.first;
    final connectionAtRisk = nextLeg?.plannedDeparture != null && eta != null && eta.isAfter(nextLeg!.plannedDeparture!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          j == null ? r.operator : '${r.operator} · Zug ${j.currentLeg} von ${j.legs.length} · Ziel ${j.destinationStationName}',
          style: VText.caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const VGap.l(),
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
/// The station is the sheet's header; the body starts with the context line.
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
