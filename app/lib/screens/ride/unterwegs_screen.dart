import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../mock/mock_data.dart' show TicketType;
import '../../repo/app_repository.dart';
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../state/ride_monitor.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'angekommen_screen.dart';
import 'change_train_sheet.dart';
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
              onAbort: () => showAbortSheet(context, m),
              onPickTrain: () => _pickOwnTrain(context, m.journey!.journey),
            )
          else
            _RidingView(
              journey: journey,
              live: live!,
              stale: m.stale,
              stamp: fmtLocal(m.stamp),
              onWrongTrain: () => _wrongTrain(context, live.ride),
              onAbort: journey == null ? null : () => showAbortSheet(context, m),
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

  /// Weiterfahrt (docs/21 §2): pick the train yourself, from where you stand, same destination.
  void _pickOwnTrain(BuildContext context, ApiJourney j) {
    final fromName = j.transferStationName ?? j.originStationName;
    final fromId = j.legs.isEmpty ? j.originStationId : (j.currentLegInfo?.toStationId ?? j.originStationId);
    monitor.closeSheet();
    final earliest = j.earliestOnwardArrival;
    final counted = j.countedCeilingMinutes;
    context.push(
      '${Routes.welcherZug}?from=${Uri.encodeComponent(fromId)}&fromName=${Uri.encodeComponent(fromName)}'
      '&to=${Uri.encodeComponent(j.destinationStationId)}&toName=${Uri.encodeComponent(j.destinationStationName)}'
      '&continue=${Uri.encodeComponent(j.id)}'
      '${earliest == null ? '' : '&earliest=${Uri.encodeComponent(earliest.toIso8601String())}'}'
      '${counted == null ? '' : '&counted=$counted'}',
    );
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
  /// "Zug wechseln" (docs/24 §2): the Welcher-Zug sheet from the current position to the
  /// unchanged destination. Changing the destination is an abort plus a new check-in, and the
  /// sheet says so.
  Future<void> _wrongTrain(BuildContext context, ApiRide r) async {
    final j = monitor.journey?.journey;
    final stops = monitor.journey?.stops ?? const <ApiStop>[];
    // Where they can actually board: the next stop the train still reaches, else where this
    // leg began — never the exit stop, which on a direct journey is the destination itself.
    final here = stops.isEmpty
        ? null
        : stops[(r.passedStops + fromIndex(stops, r.fromStationId, r.fromStationName)).clamp(0, stops.length - 1)];
    final fromId = here?.stationId ?? r.fromStationId;
    final fromName = here?.name ?? r.fromStationName;
    final toId = j?.destinationStationId ?? r.exitStationId;
    final toName = j?.destinationStationName ?? r.exitStationName;
    if (!context.mounted) return;
    await showChangeTrainSheet(
      context,
      monitor: monitor,
      fromStationId: fromId,
      fromStationName: fromName,
      toStationId: toId,
      toStationName: toName,
    );
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
    final caption = j.waitingForOwnTrain
        ? 'Weiterfahrt'
        : missed
            ? 'Anschluss verpasst'
            : 'Umsteigen';
    return (caption, j.transferStationName ?? (m.journey!.nextLeg ?? j.nextLeg)?.fromStationName ?? '');
  }
  final r = m.rideLive?.ride;
  final stops = m.rideLive?.stops ?? const [];
  final headsign = stops.isEmpty ? (r?.exitStationName ?? '') : stops.last.name;
  return ('Unterwegs', r == null ? '' : '${r.line} nach $headsign');
}

/// The stops of the train after the change (docs/26 §4).
///
/// `ApiLeg` carries only its endpoints, so the stops come from the trip itself. While that is
/// in flight — or when the feed has nothing — the endpoints alone still say where the passenger
/// gets on and off, which is the part that matters.
class _NextLegStops extends StatefulWidget {
  const _NextLegStops({required this.leg});
  final ApiLeg leg;

  @override
  State<_NextLegStops> createState() => _NextLegStopsState();
}

class _NextLegStopsState extends State<_NextLegStops> {
  List<ApiStop> _stops = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant _NextLegStops old) {
    super.didUpdateWidget(old);
    if (old.leg.tripId != widget.leg.tripId) _load();
  }

  Future<void> _load() async {
    try {
      final trip = await RepoScope.read(context).repo.trip(widget.leg.tripId);
      if (mounted) setState(() => _stops = trip.stops);
    } catch (_) {
      // The endpoints below are enough; a missing feed is not worth an error here.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.leg;
    if (_stops.isEmpty) {
      if (_loading) return const LoadingLine(label: 'Halte werden geladen …');
      return Text('Halte folgen, sobald der Zug im Feed ist.', style: VText.caption);
    }
    final from = fromIndex(_stops, l.fromStationId, l.fromStationName);
    final to = fromIndex(_stops, l.toStationId, l.toStationName);
    return StopLine(
      stops: _stops,
      from: from,
      to: to,
      // Nothing of this train has been ridden yet, so no stop is behind us.
      passed: from - 1,
      exitIndex: to,
      compact: true,
      labels: {from: 'Umstieg', to: 'Ziel'},
    );
  }
}

/// The current leg, live. With a journey: the transfer ahead and the destination underneath.
/// The line and headsign are the sheet's header, so the body starts with the context line.
class _RidingView extends StatelessWidget {
  const _RidingView({required this.journey, required this.live, required this.stale, required this.stamp, required this.onWrongTrain, this.onAbort});
  final ApiJourney? journey;
  final ApiRideLive live;
  final bool stale;
  final String stamp;
  /// "Zug wechseln" (docs/24 §2): another train to the same destination, from where the
  /// passenger is now. What that means — a swapped leg or an ended one — is worked out, not asked.
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
          child: VDelay(j?.cappedDelay(delay) ?? delay, size: VDelaySize.display, cancelled: r.cancelled),
        ),
        if (j?.countedCeilingMinutes != null && delay > j!.countedCeilingMinutes!) ...[
          const SizedBox(height: 6),
          Text('Mehr zählt nicht: die Zeit nach dem frühesten Zug ab ${j.transferStationName ?? 'dem Halt'} ist deine.', style: VText.caption),
        ],
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
          Builder(builder: (context) {
            // docs/26 §4: the journey starts where the passenger got on. Stops the train called
            // at before that are not theirs and only push the useful part off the screen.
            final boarded = fromIndex(stops, r.fromStationId, r.fromStationName);
            return StopLine(
              stops: stops,
              from: boarded,
              // The train runs on past the exit; the passenger does not (docs/26 §4).
              to: exitIndex < 0 ? null : exitIndex,
              passed: r.passedStops - 1 + boarded,
              exitIndex: exitIndex < 0 ? null : exitIndex,
              compact: true,
              labels: {
                boarded: 'Zustieg',
                if (exitIndex >= 0) exitIndex: nextLeg != null ? 'Umstieg' : 'Ziel',
              },
            );
          }),
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
          const VGap.m(),
          // The second train's stops, so the whole journey reads as one line down the page
          // rather than stopping at the change (docs/26 §4).
          _NextLegStops(leg: nextLeg),
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
            Expanded(child: VGhostButton(label: 'Zug wechseln', color: VColors.ink2, onTap: onWrongTrain)),
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
  const _TransferView({required this.live, required this.busy, required this.onConfirm, required this.onArrived, required this.onAbort, required this.onPickTrain});
  final ApiJourneyLive live;
  final bool busy;
  final ValueChanged<ApiLeg> onConfirm;
  final VoidCallback onArrived;
  final VoidCallback onAbort;
  final VoidCallback onPickTrain;

  @override
  Widget build(BuildContext context) {
    final j = live.journey;
    final next = live.nextLeg ?? j.nextLeg;
    final ownTrain = j.waitingForOwnTrain;
    // A Weiterfahrt is a choice, not a miss: it never gets the red "next possibility" styling.
    final missed = !ownTrain && (j.missedConnection || next?.replanned == true);
    final done = live.ride;
    final where = j.transferStationName ?? next?.fromStationName ?? done?.exitStationName ?? '';
    final legDelay = done?.finalDelayMinutes ?? 0;
    // What the railway caused, and therefore the most this journey can still be worth
    // (docs/21 §2). Zero is not a warning, it is noise: then we say nothing about the cap.
    final raw = j.countedCeilingMinutes;
    final ceiling = (raw != null && raw >= 1) ? raw : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ownTrain
              ? 'Du fährst weiter nach ${j.destinationStationName}. Es zählt die Verspätung bis zum frühesten Zug ab hier — eine längere Pause ist deine Zeit.'
              : done == null
                  ? 'Weiter nach ${j.destinationStationName}.'
                  : '${done.line} war ${legDelay > 0 ? '+$legDelay' : 'pünktlich'}${missed ? ' · der geplante Anschluss ist weg' : ''}. Weiter nach ${j.destinationStationName}.',
          style: VText.body.copyWith(color: VColors.ink2),
        ),
        const VGap.l(),
        if (ownTrain && next == null) ...[
          Container(
            padding: const EdgeInsets.all(VSpace.m),
            decoration: BoxDecoration(
              border: Border.all(color: VColors.ink, width: 1.5),
              borderRadius: BorderRadius.circular(4),
              color: VColors.paperElevated,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('WEITERFAHRT', style: VText.eyebrow),
                const SizedBox(height: 8),
                Text('Wähl den Zug, mit dem du weiterfährst.', style: VText.title),
                const SizedBox(height: 4),
                Text('Ab ${where.isEmpty ? 'hier' : where} nach ${j.destinationStationName}.', style: VText.caption),
                const SizedBox(height: 14),
                VPrimaryButton(label: 'Zug wählen', icon: Icons.train_outlined, onTap: busy ? null : onPickTrain),
              ],
            ),
          ),
        ] else if (next == null) ...[
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
                if (ownTrain && ceiling != null) ...[
                  const SizedBox(height: 10),
                  const VRule(),
                  const SizedBox(height: 8),
                  Text(
                    'Frühester Zug ab hier: ${next.line}, an ${fmtLocal(next.liveArrival ?? next.plannedArrival)} · ${fmtMinutes(ceiling)} ${ceiling == 1 ? 'zählt' : 'zählen'}.',
                    style: VText.captionInk,
                  ),
                ],
                const SizedBox(height: 14),
                VPrimaryButton(label: busy ? 'Einen Moment …' : 'Ich bin drin', icon: Icons.check, onTap: busy ? null : () => onConfirm(next)),
                if (ownTrain) ...[
                  const SizedBox(height: 4),
                  VGhostButton(label: 'Anderen Zug wählen', color: VColors.ink2, onTap: busy ? null : onPickTrain),
                ],
              ],
            ),
          ),
        const VGap.m(),
        Text(
          ownTrain
              ? (ceiling == null
                  ? 'Es zählt die Verspätung bis zum frühesten Zug, mit dem du ab hier weiterkommst.'
                  : 'Nimmst du einen späteren Zug, zählt deine Pause nicht mit — es bleiben ${fmtMinutes(ceiling)}.')
              : missed
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

// ---------------------------------------------------------------------------
// Abbrechen (docs/21 §1)
// ---------------------------------------------------------------------------

/// "Abbrechen" never ends a journey without asking why. Three answers, each with its
/// consequence written next to it, because only one of them keeps the claim alive.
Future<void> showAbortSheet(BuildContext context, RideMonitor monitor) {
  return showVSheet(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.only(bottom: VSpace.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VSheetHeader(title: 'Fahrt beenden?', subtitle: 'Was ist passiert?'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VGap.s(),
                VChoiceCard(
                  key: const Key('abort-weiterfahrt'),
                  title: 'Ich fahre weiter',
                  subtitle: 'Es zählt die Verspätung bis zum frühesten Zug ab hier. Eine längere Pause zählt nicht mit.',
                  selected: true,
                  trailing: const Icon(Icons.chevron_right, size: 22, color: VColors.ink2),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _abortAction(context, monitor, () => monitor.replan());
                  },
                ),
                const VGap.s(),
                VChoiceCard(
                  key: const Key('abort-aufgegeben'),
                  title: 'Ich gebe auf',
                  subtitle: 'Zu viel Verspätung, ich fahre nicht mehr. Die Wartezeit zählt für deine Geduldspunkte, ein Anspruch entsteht nicht.',
                  selected: false,
                  trailing: const Icon(Icons.chevron_right, size: 22, color: VColors.ink2),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final ticket = RepoScope.read(context).me?.settings.ticket;
                    await _abortAction(context, monitor, () => monitor.finish(arrived: false, reason: 'aufgegeben'));
                    if (context.mounted) await showGaveUpSheet(context, ticket, monitor.lastAbandonPoints);
                  },
                ),
                const VGap.s(),
                VChoiceCard(
                  key: const Key('abort-nicht-gefahren'),
                  title: 'Ich bin gar nicht mitgefahren',
                  subtitle: 'War ein Versehen. Die Fahrt zählt nirgends mit.',
                  selected: false,
                  trailing: const Icon(Icons.chevron_right, size: 22, color: VColors.ink2),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _abortAction(context, monitor, () => monitor.finish(arrived: false, reason: 'nicht_gefahren'));
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fahrt verworfen.')));
                  },
                ),
                const VGap.m(),
                VGhostButton(label: 'Zurück', color: VColors.ink2, onTap: () => Navigator.of(ctx).pop()),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> _abortAction(BuildContext context, RideMonitor monitor, Future<void> Function() run) async {
  try {
    await run();
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Das ging nicht: ${shortError(e)}')));
  }
}

/// After "Ich gebe auf": the right the passenger has instead, which almost nobody knows.
/// Art. 18 VO (EU) 2021/782 — the fare back, not the compensation (docs/02, docs/21 §0).
Future<void> showGaveUpSheet(BuildContext context, TicketType? ticket, [int points = 0]) {
  final single = ticket == TicketType.einzelfahrkarte;
  return showVSheet(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.only(bottom: VSpace.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VSheetHeader(
            title: 'Aufgegeben',
            subtitle: points > 0 ? '+$points Geduldspunkte für die Wartezeit.' : 'Keine Wartezeit, keine Geduldspunkte.',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VGap.s(),
                Text('Ein Anspruch entsteht nicht — die Entschädigung hängt an der Ankunft.', style: VText.bodyS.copyWith(color: VColors.ink2)),
                const VGap.m(),
                Text('Dafür hast du ein anderes Recht.', style: VText.bodyStrong),
                const SizedBox(height: 6),
                Text(
                  'Ab 60 Minuten erwarteter Verspätung darfst du die Fahrt abbrechen und den Fahrpreis zurückverlangen (Art. 18 der EU-Fahrgastrechte).',
                  style: VText.bodyS,
                ),
                const SizedBox(height: 8),
                Text(
                  single
                      ? 'Mit Einzelfahrkarte holst du dir das Geld am Schalter oder über das Fahrgastrechte-Formular der Bahn. Das ist meist mehr als die Entschädigung gewesen wäre.'
                      : 'Mit dem Deutschlandticket gibt es für die einzelne Fahrt nichts zurück — das Ticket läuft ja weiter.',
                  style: VText.bodyS.copyWith(color: VColors.ink2),
                ),
                const VGap.m(),
                const VRule.red(),
                const VGap.m(),
                Text('Fährst du doch noch?', style: VText.bodyStrong),
                const SizedBox(height: 6),
                Text('Dann check wieder ein. Es zählt dann die Verspätung bis zum frühesten Zug ab hier, nicht die Pause.', style: VText.bodyS),
                const VGap.m(),
                VOutlineButton(label: 'Verstanden', onTap: () => Navigator.of(ctx).pop()),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
