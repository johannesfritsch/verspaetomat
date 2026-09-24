import 'package:flutter/material.dart';

import '../../mock/mock_data.dart' show TicketType;
import '../../repo/app_repository.dart';
import '../../repo/repo_scope.dart';
import '../../state/ride_monitor.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'angekommen_screen.dart';
import 'change_train_sheet.dart';
import 'checkin_flow.dart';
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
      return AngekommenScreen(onDone: () => m.dismiss());
    }
    if (!m.active) {
      return Padding(
        padding: const EdgeInsets.all(VSpace.page),
        child: Text(m.error ?? 'Gerade kein Zug.', style: VText.body.copyWith(color: VColors.ink2)),
      );
    }
    if (live == null && journey == null) {
      return const Padding(
        padding: EdgeInsets.all(VSpace.page),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [VSkeletonBoard(), SizedBox(height: VSpace.md), VSkeletonStops(stops: 5)]),
      );
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
      padding: const EdgeInsets.fromLTRB(VSpace.sheet, 0, VSpace.sheet, VSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (m.transfer)
            _TransferView(
              live: m.journey!,
              busy: m.busy,
              onConfirm: (leg) => _confirm(context, leg),
              onMissed: () => _missed(context),
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

  Future<void> _missed(BuildContext context) async {
    try {
      await monitor.missed();
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
        requestArrivalSheet(result: result);
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
    // The same sheet every other train choice uses (docs/29); the journey id is what makes it
    // a Weiterfahrt rather than a new check-in.
    showWelcherZugSheet(
      context,
      from: ApiStation(id: fromId, name: fromName),
      to: ApiStation(id: j.destinationStationId, name: j.destinationStationName),
      continueJourneyId: j.id,
      earliestOnwardArrival: j.earliestOnwardArrival,
      countedMinutes: j.countedCeilingMinutes,
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

/// The drawn header of the change (#57), or null where the plain header stays: riding, arrived,
/// a Weiterfahrt still choosing its train, a transfer with nothing to take.
({String eyebrow, String title, String subtitle, String? track})? transferHero(RideMonitor m) {
  if (m.arrived || !m.transfer) return null;
  final j = m.journey!.journey;
  final next = m.journey!.nextLeg ?? j.nextLeg;
  if (next == null || j.waitingForOwnTrain) return null;
  final where = j.transferStationName ?? next.fromStationName;
  final dep = next.liveDeparture ?? next.plannedDeparture;
  final inMin = dep?.difference(DateTime.now()).inMinutes;
  final missed = j.missedConnection || next.replanned;
  final track = next.platform == null || next.platform!.isEmpty ? null : next.platform;
  if (missed) {
    return (eyebrow: 'Umstieg · $where', title: 'Anschluss verpasst.', subtitle: 'Das ist die nächste Möglichkeit ab hier.', track: track);
  }
  if (inMin != null && inMin < -1) {
    // Gone by the clock, and nobody has said yet whether they are on it.
    return (eyebrow: 'Umstieg · $where', title: 'Bist du im Zug?', subtitle: 'Dein Anschluss ist abgefahren. Sag uns, ob du drin sitzt.', track: track);
  }
  if (inMin != null && inMin <= 5) {
    return (eyebrow: 'Umstieg · $where', title: 'Dein Anschluss fährt jetzt.', subtitle: 'Bist du im richtigen Zug? Sag uns kurz Bescheid.', track: track);
  }
  return (eyebrow: 'Umstieg · $where', title: 'Zeit zum Umsteigen.', subtitle: 'Sag uns Bescheid, sobald du im Zug sitzt.', track: track);
}

/// The platform drawing of #57 with the connection's own track on the sign. The sign in the
/// picture is blank; its place is measured in the image (341 × 440), so the number sits on it
/// at any width.
class TransferArt extends StatelessWidget {
  const TransferArt({super.key, required this.width, this.track});
  final double width;
  final String? track;

  @override
  Widget build(BuildContext context) {
    final h = width * 440 / 341;
    double x(double v) => width * v / 341;
    double y(double v) => h * v / 440;
    return SizedBox(
      width: width,
      height: h,
      child: Stack(
        children: [
          Positioned.fill(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Colors.transparent, Colors.black],
                stops: [0, 0.35],
              ).createShader(rect),
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black, Colors.black, Colors.transparent],
                  stops: [0, 0.75, 1],
                ).createShader(rect),
                child: Image.asset('assets/sheet/umstieg.webp', fit: BoxFit.cover),
              ),
            ),
          ),
          if (track != null)
            Positioned(
              left: x(136),
              top: y(55),
              width: x(122),
              height: y(141),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Gleis', style: VText.bodyS.copyWith(color: VColors.inkOnDark2)),
                    Text(track!, style: VText.number.copyWith(color: VColors.inkOnDark, height: 1.0)),
                  ],
                ),
              ),
            ),
        ],
      ),
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

String? _track(String? t) => t == null || t.trim().isEmpty ? null : t.trim();

String _minutes(int n) => '$n ${n == 1 ? 'Minute' : 'Minuten'}';

/// The drawn header while riding (#62): what the moment is about, in one line. Just boarded, a
/// change coming up, a connection at risk, the destination close, a delay that has become a
/// claim — or, with nothing to say, the delay itself. Null where the plain header stays.
///
/// Every sentence is made from what the feed says about this ride; nothing here is predicted.
({String eyebrow, String title, String subtitle, String? track})? ridingHero(RideMonitor m) {
  if (m.arrived || m.transfer || m.overdue) return null;
  final live = m.rideLive;
  if (live == null) return null;
  final r = live.ride;
  final stops = live.stops;
  final j = m.journey?.journey;
  final now = DateTime.now();
  final exitIndex = stops.isEmpty ? -1 : fromIndex(stops, r.exitStationId, r.exitStationName);
  final boarded = stops.isEmpty ? -1 : fromIndex(stops, r.fromStationId, r.fromStationName);
  final planned = r.plannedArrival ?? (exitIndex >= 0 ? plannedAt(stops[exitIndex]) : null);
  final eta = live.eta ?? planned?.add(Duration(minutes: r.liveDelayMinutes));
  final delay = j?.cappedDelay(r.liveDelayMinutes) ?? r.liveDelayMinutes;
  final next = _legsAhead(j).firstOrNull;
  final exit = r.exitStationName;
  // Past the forecast and not yet arrived says nothing about how soon; it is not "soon".
  final toExitRaw = eta?.difference(now).inMinutes;
  final toExit = toExitRaw == null || toExitRaw < 0 ? null : toExitRaw;
  final info = j?.currentLegInfo;
  final claimFrom = m.journey?.claimFromMinute ?? 60;

  if (r.cancelled) {
    return (
      eyebrow: 'Unterwegs · ${r.line}',
      title: 'Dein Zug fällt aus.',
      subtitle: 'Unten kannst du einen anderen Zug zum selben Ziel wählen.',
      track: null,
    );
  }

  if (next != null && toExit != null && toExit <= 10) {
    final nextDep = next.liveDeparture ?? next.plannedDeparture;
    final gap = nextDep == null || eta == null ? null : nextDep.difference(eta).inMinutes;
    final from = _track(info?.arrivalPlatform), to = _track(next.platform);
    if (gap != null && gap <= 0) {
      return (eyebrow: 'Umstieg · $exit', title: 'Der Anschluss wird knapp.', subtitle: 'Wir planen um, sobald du in $exit bist.', track: to);
    }
    final time = gap == null ? '' : '${_minutes(gap)} Zeit';
    return (
      eyebrow: 'Umstieg · $exit',
      title: toExit <= 1 ? 'Jetzt umsteigen.' : 'Umstieg in ${_minutes(toExit)}.',
      subtitle: from != null && to != null
          ? 'Von Gleis $from zu Gleis $to${time.isEmpty ? '' : ', $time'}.'
          : '${next.line} nach ${next.headsign.isNotEmpty ? next.headsign : next.toStationName}${time.isEmpty ? '' : ', $time'}.',
      track: to,
    );
  }

  // A claim outranks the welcome: someone boarding an hour late checked in for this line.
  if (delay >= claimFrom) {
    return (
      eyebrow: 'Unterwegs · ${r.line}',
      title: '+${_minutes(delay)}.',
      subtitle: 'Ab hier entsteht ein Anspruch.',
      track: _track(next?.platform) ?? _track(info?.arrivalPlatform),
    );
  }

  // Just boarded: the train is still at the platform or left in the last five minutes.
  final boardDep = boarded < 0 ? null : (liveAt(stops[boarded]) ?? plannedAt(stops[boarded]));
  if (boardDep != null && now.isBefore(boardDep.add(const Duration(minutes: 5)))) {
    return (
      eyebrow: 'Eingestiegen · ${r.line}',
      title: 'Gute Fahrt.',
      subtitle: next != null
          ? 'In $exit steigst du um, um ${fmtLocal(eta)}. Bis dahin passen wir auf.'
          : 'Ankunft in $exit um ${fmtLocal(eta)}. Bis dahin passen wir auf.',
      track: _track(info?.platform),
    );
  }

  if (next == null && toExit != null && toExit <= 10) {
    final arr = _track(info?.arrivalPlatform);
    return (
      eyebrow: 'Ankunft · $exit',
      title: toExit <= 1 ? 'Gleich da.' : 'Noch ${_minutes(toExit)}.',
      subtitle: 'Ankunft um ${fmtLocal(eta)}${arr == null ? '' : ' auf Gleis $arr'}.',
      track: arr,
    );
  }

  final late = delay > 0 && planned != null ? ' statt ${fmtLocal(planned)}' : '';
  return (
    eyebrow: j != null && j.legs.length > 1 ? 'Unterwegs · Zug ${j.currentLeg} von ${j.legs.length}' : 'Unterwegs · ${r.line}',
    title: delay > 0 ? '+${_minutes(delay)}.' : 'Pünktlich unterwegs.',
    subtitle: next != null ? 'Umstieg in $exit um ${fmtLocal(eta)}$late.' : 'Ankunft in $exit um ${fmtLocal(eta)}$late.',
    track: _track(next?.platform) ?? _track(info?.arrivalPlatform),
  );
}

/// The legs still to come after the one being ridden, in order.
List<ApiLeg> _legsAhead(ApiJourney? j) {
  if (j == null) return const [];
  final ahead = j.legs.where((l) => (l.legNo ?? 0) > j.currentLeg).toList()..sort((a, b) => (a.legNo ?? 0).compareTo(b.legNo ?? 0));
  return ahead;
}

/// The current leg, live, then every leg still ahead, with the change between them (#62).
/// The situation — and the delay that matters — is the sheet's header, so the body is the plan:
/// one card per train, where you get on and off and on which track, the stops in between folded.
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
    final ahead = _legsAhead(j);
    final info = j?.currentLegInfo;
    final shown = j?.cappedDelay(delay) ?? delay;

    final boarded = stops.isEmpty ? 0 : fromIndex(stops, r.fromStationId, r.fromStationName);
    final exit = exitIndex < 0 ? null : exitIndex;
    final current = stops.isEmpty
        ? const <VStop>[]
        : vStopsOf(
            stops,
            from: boarded,
            // The train runs on past the exit; the passenger does not (docs/26 §4).
            to: exit,
            passed: r.passedStops - 1 + boarded,
            boldIndex: exit,
            // The two stops you have to do something at: get on, get off.
            halos: {boarded, if (exit != null) exit},
            labels: {
              boarded: 'Zustieg',
              if (exit != null) exit: ahead.isNotEmpty ? 'Umstieg' : 'Ziel',
            },
            operatorName: r.operator,
            tracks: {boarded: info?.platform, if (exit != null) exit: info?.arrivalPlatform},
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Opacity(
          opacity: stale ? 0.45 : 1,
          child: _LegShell(
            key: ValueKey(r.tripId),
            live: true,
            line: r.line,
            headsign: stops.isEmpty ? r.exitStationName : stops.last.name,
            cancelled: r.cancelled,
            status: r.cancelled
                ? const VPill('Ausfall', tone: VPillTone.red)
                : shown > 0
                    ? VDelayPill(shown)
                    : const VPill('pünktlich', tone: VPillTone.green),
            note: r.cause,
            stops: current,
            empty: 'Halte folgen, sobald der Zug im Feed ist.',
          ),
        ),
        for (var i = 0; i < ahead.length; i++) ...[
          _ChangeGap(
            station: ahead[i].fromStationName,
            arrive: i == 0 ? eta : (ahead[i - 1].liveArrival ?? ahead[i - 1].plannedArrival),
            leg: ahead[i],
          ),
          // Keyed by trip: when a leg is confirmed the list shifts, and a fold opened on one
          // train must not open the next.
          _AheadLeg(key: ValueKey(ahead[i].tripId), leg: ahead[i], last: i == ahead.length - 1),
        ],
        if (j?.countedCeilingMinutes != null && delay > j!.countedCeilingMinutes!) ...[
          const VGap.m(),
          Text('Mehr zählt nicht: die Zeit nach dem frühesten Zug ab ${j.transferStationName ?? 'dem Halt'} ist deine.', style: VText.bodyS),
        ],
        const VGap.m(),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Action(
                  key: const Key('ride-wrong-train'),
                  icon: Icons.swap_horiz,
                  red: true,
                  title: 'Zug wechseln',
                  body: 'Anderer Zug, gleiches Ziel.',
                  onTap: onWrongTrain,
                ),
              ),
              if (onAbort != null) ...[
                const SizedBox(width: VSpace.s),
                Expanded(
                  child: _Action(
                    key: const Key('ride-abort'),
                    icon: Icons.close,
                    red: false,
                    title: 'Fahrt beenden',
                    body: 'Wir fragen kurz, was passiert ist.',
                    onTap: onAbort,
                  ),
                ),
              ],
            ],
          ),
        ),
        const VGap.m(),
        Text(
          stale ? 'Letzter Stand $stamp · Verbindung fehlt.' : 'Stand $stamp · Wir folgen dem Zug, nicht dir.',
          style: VText.caption,
        ),
      ],
    );
  }
}

/// One train of the journey on a card (#62): line, direction and status on top, then where you
/// get on and off. The stops in between are folded behind one quiet row — the glance is the two
/// ends; the list is there for whoever wants to count.
///
/// The train you are on is tinted with the red line; a train still ahead is a white card with the
/// ink line, so two live journeys never stand on one screen.
class _LegShell extends StatefulWidget {
  const _LegShell({super.key, required this.live, required this.line, required this.headsign, required this.cancelled, required this.status, required this.stops, this.note, this.empty});
  final bool live;
  final String line;
  final String headsign;
  final bool cancelled;
  final Widget? status;
  final List<VStop> stops;
  final String? note;

  /// Said instead of the stops when there are none.
  final String? empty;

  @override
  State<_LegShell> createState() => _LegShellState();
}

class _LegShellState extends State<_LegShell> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final between = w.stops.length - 2;
    final shown = _open || between <= 0 ? w.stops : [w.stops.first, w.stops.last];
    return VCard(
      tone: w.live ? VCardTone.tint : VCardTone.raised,
      padding: const EdgeInsets.all(VSpace.cardTight),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LineBadge(w.line, large: w.live, cancelled: w.cancelled),
              const SizedBox(width: VSpace.s),
              Expanded(child: Text('nach ${w.headsign}', style: VText.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (w.status != null) ...[const SizedBox(width: VSpace.s), w.status!],
            ],
          ),
          if (w.note != null && w.note!.isNotEmpty) ...[
            const VGap.s(),
            Text(w.note!, style: VText.bodyS),
          ],
          if (w.stops.isEmpty && w.empty != null) ...[
            const VGap.s(),
            Text(w.empty!, style: VText.bodyS),
          ] else
            VStopTimeline(stops: shown, tone: w.live ? VTimelineTone.live : VTimelineTone.quiet),
          if (between > 0)
            InkWell(
              onTap: () => setState(() => _open = !_open),
              borderRadius: BorderRadius.circular(VRadius.sm),
              child: Padding(
                // Under the names, not under the spine.
                padding: const EdgeInsets.fromLTRB(40, VSpace.xs, 0, VSpace.xs),
                child: Row(
                  children: [
                    Text(
                      _open ? 'Halte dazwischen ausblenden' : '$between ${between == 1 ? 'Halt' : 'Halte'} dazwischen',
                      style: VText.bodySStrong.copyWith(color: VColors.ink2),
                    ),
                    const SizedBox(width: VSpace.xs),
                    Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18, color: VColors.ink2),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A train still ahead (docs/26 §4). `ApiLeg` carries only its endpoints, so the stops come from
/// the trip itself; while that is in flight — or when the feed has nothing — the two ends alone
/// still say where the passenger gets on and off, which is the part that matters.
class _AheadLeg extends StatefulWidget {
  const _AheadLeg({super.key, required this.leg, required this.last});
  final ApiLeg leg;

  /// The journey ends where this leg does.
  final bool last;

  @override
  State<_AheadLeg> createState() => _AheadLegState();
}

class _AheadLegState extends State<_AheadLeg> {
  List<ApiStop> _stops = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant _AheadLeg old) {
    super.didUpdateWidget(old);
    if (old.leg.tripId != widget.leg.tripId) _load();
  }

  Future<void> _load() async {
    try {
      final trip = await RepoScope.read(context).repo.trip(widget.leg.tripId);
      if (mounted) setState(() => _stops = trip.stops);
    } catch (_) {
      // The endpoints are enough; a missing feed is not worth an error here.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.leg;
    final endTag = widget.last ? 'Ziel' : 'Umstieg';
    final from = _stops.isEmpty ? -1 : fromIndex(_stops, l.fromStationId, l.fromStationName);
    final to = _stops.isEmpty ? -1 : fromIndex(_stops, l.toStationId, l.toStationName);
    final List<VStop> stops = from >= 0 && to > from
        ? vStopsOf(
            _stops,
            from: from,
            to: to,
            // Nothing of this train has been ridden yet, so no stop is behind us.
            passed: from - 1,
            labels: {from: 'Umstieg', to: endTag},
            operatorName: l.operator,
            tracks: {from: l.platform, to: l.arrivalPlatform},
          )
        : [
            VStop(station: l.fromStationName, time: fmtLocal(l.liveDeparture ?? l.plannedDeparture), tag: 'Umstieg', track: _track(l.platform)),
            VStop(station: l.toStationName, time: fmtLocal(l.liveArrival ?? l.plannedArrival), tag: endTag, track: _track(l.arrivalPlatform)),
          ];
    return _LegShell(
      live: false,
      line: l.line,
      headsign: l.headsign.isNotEmpty ? l.headsign : l.toStationName,
      cancelled: l.cancelled,
      status: l.cancelled
          ? const VPill('Ausfall', tone: VPillTone.red)
          : l.delayMin > 0
              ? VDelayPill(l.delayMin)
              // On time only when the feed has said so; no live time is no claim.
              : l.liveDeparture != null
                  ? const VPill('pünktlich', tone: VPillTone.green)
                  : null,
      stops: stops,
    );
  }
}

/// The change between two trains (#62): the walk, and how long there is for it — from the
/// forecast arrival to the connection's departure. At zero or below it says so in red; at the change
/// itself the sheet asks once whether you made it.
class _ChangeGap extends StatelessWidget {
  const _ChangeGap({required this.station, required this.arrive, required this.leg});
  final String station;
  final DateTime? arrive;
  final ApiLeg leg;

  @override
  Widget build(BuildContext context) {
    final dep = leg.liveDeparture ?? leg.plannedDeparture;
    final gap = arrive == null || dep == null ? null : dep.difference(arrive!).inMinutes;
    final tight = gap != null && gap <= 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: VSpace.s),
      child: Row(
        children: [
          // The dotted path from one spine to the next, on the spines' axis.
          SizedBox(
            width: VSpace.cardTight * 2 + 28,
            child: Column(
              children: [
                for (var i = 0; i < 5; i++)
                  Container(
                    width: 3,
                    height: 3,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    decoration: const BoxDecoration(color: VColors.ink3, shape: BoxShape.circle),
                  ),
              ],
            ),
          ),
          Icon(Icons.directions_walk, size: 22, color: tight ? VColors.red : VColors.ink2),
          const SizedBox(width: VSpace.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Umstieg in $station', style: VText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  gap == null
                      ? 'Umstiegszeit folgt'
                      : tight
                          ? 'Wird knapp. Wir planen um, sobald du da bist.'
                          : '${_minutes(gap)} zum Umsteigen',
                  style: VText.bodyStrong.copyWith(color: tight ? VColors.red : VColors.ink),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the two things you can do on a moving train, as a tile: a mark, what it is, what it
/// does. Two side by side, so neither reads as the thing you are expected to press.
class _Action extends StatelessWidget {
  const _Action({super.key, required this.icon, required this.red, required this.title, required this.body, required this.onTap});
  final IconData icon;
  final bool red;
  final String title;
  final String body;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: red ? VColors.redTintSoft : VColors.greyFill,
      borderRadius: BorderRadius.circular(VRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(VRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(VSpace.cardTight),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VIconBadge(icon: icon, tone: red ? VBadgeTone.red : VBadgeTone.neutral, size: VControl.badgeSmall, iconColor: red ? null : VColors.ink2),
              const VGap.s(),
              Text(title, style: VText.bodyStrong.copyWith(color: red ? VColors.red : VColors.ink)),
              const SizedBox(height: 2),
              Text(body, style: VText.bodyS.copyWith(color: VColors.ink2)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Between two legs. With a connection to take (#57): the train on a card — line, destination,
/// how soon, both ends, the track — and the three answers there are, each with what it does.
/// A Weiterfahrt still waiting for a train, and a transfer with no connection at all, keep the
/// plain view below.
class _TransferView extends StatelessWidget {
  const _TransferView({required this.live, required this.busy, required this.onConfirm, required this.onMissed, required this.onArrived, required this.onAbort, required this.onPickTrain});
  final ApiJourneyLive live;
  final bool busy;
  final ValueChanged<ApiLeg> onConfirm;
  final VoidCallback onMissed;
  final VoidCallback onArrived;
  final VoidCallback onAbort;
  final VoidCallback onPickTrain;

  @override
  Widget build(BuildContext context) {
    final j = live.journey;
    final next = live.nextLeg ?? j.nextLeg;
    if (next == null || j.waitingForOwnTrain) {
      return _TransferViewPlain(live: live, busy: busy, onConfirm: onConfirm, onArrived: onArrived, onAbort: onAbort, onPickTrain: onPickTrain);
    }
    final missed = j.missedConnection || next.replanned;
    final done = live.ride;
    final where = j.transferStationName ?? next.fromStationName;
    final legDelay = done?.finalDelayMinutes ?? 0;
    // #56: the track you got off on, next to the one you get on at.
    final arrivedOn = j.currentLegInfo?.arrivalPlatform;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (done != null) ...[
          Text(
            '${done.line} war ${legDelay > 0 ? '+$legDelay' : 'pünktlich'}${missed ? ' · der geplante Anschluss ist weg' : ''}. Weiter nach ${j.destinationStationName}.',
            style: VText.bodyS.copyWith(color: VColors.ink2),
          ),
          const VGap.m(),
        ],
        ConnectionCard(leg: next, arrivedOn: arrivedOn, missed: missed),
        const VGap.m(),
        _Answer(
          key: const Key('transfer-in-train'),
          icon: Icons.train,
          tone: _AnswerTone.red,
          title: 'Ich bin im Zug',
          body: 'Super! Wir zählen ab jetzt weiter für diese Fahrt.',
          onTap: busy ? null : () => onConfirm(next),
        ),
        const VGap.s(),
        _Answer(
          key: const Key('transfer-missed'),
          icon: Icons.directions_run,
          tone: _AnswerTone.grey,
          title: 'Leider verpasst',
          body: 'Ich war am Gleis, habe es aber nicht geschafft. Wir suchen die nächste Verbindung ab $where.',
          onTap: busy ? null : onMissed,
        ),
        const VGap.s(),
        _Answer(
          key: const Key('transfer-end'),
          icon: Icons.close,
          tone: _AnswerTone.grey,
          title: 'Fahrt hier abbrechen',
          body: 'Ich beende die Fahrt in $where. Die Verspätung bis hier zählt.',
          onTap: busy ? null : onArrived,
        ),
        const VGap.m(),
        if (missed) ...[
          Text('Die Verspätung zählt am Ziel, nicht pro Zug. Ein verpasster Anschluss ist ein gültiger Antragsgrund.', style: VText.caption),
          const VGap.s(),
        ],
        Center(child: VGhostButton(label: 'Anders beenden …', color: VColors.ink2, onTap: busy ? null : onAbort)),
      ],
    );
  }
}

/// The connection on a card (#57): line and destination, how soon, both ends on a line, then
/// the track, the time left and the kind of train. Also used where the next train is shown
/// while still riding.
class ConnectionCard extends StatelessWidget {
  const ConnectionCard({super.key, required this.leg, this.arrivedOn, this.missed = false});
  final ApiLeg leg;

  /// The track the passenger arrives on at the change (#56), when known.
  final String? arrivedOn;
  final bool missed;

  static String kindOf(ApiCategory c) => switch (c) {
        ApiCategory.s => 'S-Bahn',
        ApiCategory.rb => 'Regionalbahn',
        ApiCategory.re => 'Regional-Express',
        ApiCategory.fern => 'Fernverkehr',
        ApiCategory.bus => 'Bus',
        ApiCategory.other => 'Zug',
      };

  @override
  Widget build(BuildContext context) {
    final dep = leg.liveDeparture ?? leg.plannedDeparture;
    final arr = leg.liveArrival ?? leg.plannedArrival;
    final inMin = dep?.difference(DateTime.now()).inMinutes;
    final track = leg.platform == null || leg.platform!.isEmpty ? '–' : leg.platform!;
    final Widget status = leg.cancelled
        ? const VPill('Ausfall', tone: VPillTone.red)
        : leg.delayMin > 0
            ? VDelayPill(leg.delayMin)
            : inMin == null
                ? const SizedBox.shrink()
                : inMin > 0
                    ? VPill('in $inMin ${inMin == 1 ? 'Minute' : 'Minuten'}', tone: VPillTone.green)
                    : inMin >= -1
                        ? const VPill('jetzt', tone: VPillTone.green)
                        : const VPill('abgefahren', tone: VPillTone.neutral);
    return VCard(
      padding: const EdgeInsets.all(VSpace.cardTight),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (missed) ...[
            Text('NÄCHSTE MÖGLICHKEIT', style: VText.eyebrow.copyWith(color: VColors.red)),
            const VGap.s(),
          ],
          Row(
            children: [
              LineBadge(leg.line, large: true, cancelled: leg.cancelled),
              const SizedBox(width: VSpace.s),
              Expanded(
                child: Text('nach ${leg.headsign.isNotEmpty ? leg.headsign : leg.toStationName}', style: VText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: VSpace.s),
              status,
            ],
          ),
          const VGap.m(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(fmtLocal(dep), style: VText.numberS),
                  Text(leg.fromStationName, style: VText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              const Expanded(flex: 4, child: Padding(padding: EdgeInsets.only(top: 10), child: _RunLine())),
              Expanded(
                flex: 5,
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(fmtLocal(arr), style: VText.numberS),
                  Text(leg.toStationName, style: VText.caption, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right),
                ]),
              ),
            ],
          ),
          const VGap.m(),
          const VRule(),
          const VGap.m(),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(child: _Fact(label: 'Gleis', value: track, sub: arrivedOn == null || arrivedOn!.isEmpty ? null : 'Ankunft auf $arrivedOn')),
                const VerticalDivider(width: VSpace.m, thickness: 1, color: VColors.rule),
                Expanded(
                  child: _Fact(
                    label: 'Abfahrt in',
                    value: inMin == null || inMin < -1 ? '–' : (inMin <= 0 ? 'jetzt' : '$inMin Min'),
                    sub: fmtLocal(dep),
                  ),
                ),
                const VerticalDivider(width: VSpace.m, thickness: 1, color: VColors.rule),
                Expanded(child: _Fact(label: 'Zugtyp', value: leg.line, sub: kindOf(leg.category))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The small train on its way from one end to the other.
class _RunLine extends StatelessWidget {
  const _RunLine();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.train, size: 16, color: VColors.red),
        const SizedBox(width: 4),
        Expanded(child: Container(height: 2, color: VColors.rule)),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: VColors.ink3, width: 1.5)),
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.sub});
  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: VText.caption),
        const SizedBox(height: 2),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: VText.title)),
        if (sub != null) Text(sub!, style: VText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

enum _AnswerTone { red, grey }

/// One answer at the change: a mark, what it is, what it does, and the chevron that says so.
class _Answer extends StatelessWidget {
  const _Answer({super.key, required this.icon, required this.tone, required this.title, required this.body, required this.onTap});
  final IconData icon;
  final _AnswerTone tone;
  final String title;
  final String body;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final red = tone == _AnswerTone.red;
    return Material(
      color: red ? VColors.redTintSoft : VColors.greyFill,
      borderRadius: BorderRadius.circular(VRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(VRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(VSpace.cardTight),
          child: Row(
            children: [
              VIconBadge(icon: icon, tone: red ? VBadgeTone.red : VBadgeTone.neutral, size: VControl.badgeSmall, iconColor: red ? null : VColors.ink2),
              const SizedBox(width: VSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: VText.bodyStrong.copyWith(color: red ? VColors.red : VColors.ink)),
                    const SizedBox(height: 2),
                    Text(body, style: VText.bodyS.copyWith(color: VColors.ink2)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: red ? VColors.red : VColors.ink2),
            ],
          ),
        ),
      ),
    );
  }
}

/// Between two legs: confirm the connection with one tap, or the alternative after a miss.
/// The station is the sheet's header; the body starts with the context line.
class _TransferViewPlain extends StatelessWidget {
  const _TransferViewPlain({required this.live, required this.busy, required this.onConfirm, required this.onArrived, required this.onAbort, required this.onPickTrain});
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
