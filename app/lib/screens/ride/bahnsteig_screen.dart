import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../repo/app_repository.dart';
import '../../api/events.dart';
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../state/nearby_monitor.dart';
import '../../state/ride_monitor.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'checkin_flow.dart';
import '../community/community_widgets.dart';
import 'ride_widgets.dart';

/// Home, second version (docs/16). Six blocks, everything above the fold: the action
/// for this moment, momentum, the money countdown, standing, the community with my
/// share, and at most one "next thing".
class BahnsteigScreen extends StatefulWidget {
  const BahnsteigScreen({super.key});

  @override
  State<BahnsteigScreen> createState() => _BahnsteigScreenState();
}

class _BahnsteigScreenState extends State<BahnsteigScreen> {
  StreamSubscription<AppEvent>? _eventSub;

  /// Where the passenger is and which stations are around them: one live source for Home,
  /// the check-in and the away box (docs/24 §0). This screen no longer holds a fix.
  NearbyMonitor? _near;
  ApiStanding _standing = ApiStanding.empty;
  bool _loading = true;
  String? _error;
  Timer? _ticker;
  int _minuteTick = 0;
  AppRepository? _lastRepo;
  String? _lastMeStamp;
  late final Session _session;

  @override
  void initState() {
    super.initState();
    final session = RepoScope.read(context);
    _session = session;
    _eventSub = session.events.listen((e) {
      if (!mounted) return;
      // The monitor listens for the location itself; this is the rest of the screen.
      if (e.touchesLocation || e.touchesRide || e.touchesLedger) _load();
    });
    session.addListener(_onSession);
    _ticker = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && _standing.community != null) {
        setState(() => _minuteTick += 1 + DateTime.now().second % 3);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final near = NearbyScope.of(context);
    if (!identical(near, _near)) {
      _near?.removeListener(_onNearby);
      _near = near..addListener(_onNearby);
    }
    final repo = RepoScope.of(context).repo;
    if (!identical(repo, _lastRepo)) {
      _lastRepo = repo;
      _load();
    }
  }

  /// Only the Stellwerk caption depends on the monitor here; which station we stand at is the
  /// check-in's business now (docs/30).
  void _onNearby() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _ticker?.cancel();
    _near?.removeListener(_onNearby);
    _session.removeListener(_onSession);
    super.dispose();
  }

  /// The account changed (points after an arrival, a new NGO, a nickname): the numbers follow.
  void _onSession() {
    if (!mounted) return;
    final me = _session.me;
    final stamp = me == null
        ? null
        : '${me.id}:${me.pointsTotal}:${me.pointsThisWeek}:${me.settings.ngoId}:${me.settings.showOnBoards}';
    if (stamp != _lastMeStamp) {
      _lastMeStamp = stamp;
      _loadStanding();
    }
  }

  Future<void> _loadStanding() async {
    try {
      final st = await _session.loadStanding();
      if (mounted) setState(() => _standing = st);
    } catch (_) {
      // keep the last numbers
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Home carries no stations any more (docs/30): the numbers are all it loads.
      final st = await _session.loadStanding().catchError((_) => ApiStanding.empty);
      if (!mounted) return;
      setState(() {
        _standing = st;
        _minuteTick = 0;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = shortError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  ApiNearby get _nearby => _near?.nearby ?? const ApiNearby(stations: [], source: 'none');

  @override
  Widget build(BuildContext context) {
    final session = RepoScope.of(context);
    final me = session.me;
    // The ride lives in the shell's monitor (docs/19): the bar and the sheet show it while
    // under way; Home only shows the arrival card once it is over.
    final ride = RideScope.of(context);
    final underWay = ride.active;
    final arrived = ride.arrived && ride.rideLive != null;
    final st = _standing;

    return VScreen(
      showBack: false,
      padding: const EdgeInsets.fromLTRB(
        VSpace.page,
        VSpace.s,
        VSpace.page,
        VSpace.l,
      ),
      child: RefreshIndicator(
        onRefresh: _load,
        color: VColors.ink,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The same header as the other tabs (issue #14): a title, a quiet line under it, the
            // settings button. Home had only the button, which made it the one screen without a
            // name. The Stellwerk line keeps its place as the caption, because that is what it
            // is — a note about where the app thinks it is.
            TabHeader(
              title: 'Willkommen',
              caption: _nearby.simulated ? 'Standort: Stellwerk · ${_nearby.label ?? ''}' : null,
              onSettings: () => context.push(Routes.einstellungen).then((_) => _load()),
            ),
            const VGap.m(),
            if (_error != null) ...[
              const VGap.m(),
              OfflineBanner(stamp: null),
              ErrorLine(message: _error!, onRetry: _load),
            ],
            // The one place a running pause is advertised (docs/24 §3), so it can never be
            // forgotten silently. Tapping it lifts the pause.
            if (session.nudgesSnoozed)
              InkWell(
                key: const Key('stumm-bis'),
                onTap: session.unsnoozeNudges,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.notifications_off_outlined, size: 15, color: VColors.ink2),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          me?.settings.snoozedOpenEnded == true
                              ? 'Hinweise aus · aufheben'
                              : 'Stumm bis ${fmtLocal(session.nudgeSnoozeUntil)} · aufheben',
                          style: VText.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const VGap.s(),

            // Wir first (docs/30): the collective minutes are the thing this app is for, and
            // they are true whether or not anybody is travelling right now. The action follows.
            const VSection('Wir'),
            const VGap.m(),
            _WirBlock(
              standing: st,
              tick: _minuteTick,
              onTap: () => context.go(Routes.wir),
            ),
            const VGap.l(),

            // 1 · Action, sized by the moment. Under way, the ride card (docs/20 §2) opens the
            // sheet; the check-in card waits until the journey is over.
            if (_loading && ride.loading)
              const LoadingLine(label: 'Bahnsteig wird geladen …')
            else if (underWay)
              _RideCard(monitor: ride)
            else if (arrived)
              _ArrivedBlock(
                live: ride.rideLive!,
                journey: ride.journey?.journey,
                onDismiss: () => ride.dismiss().then((_) => _load()),
              )
            else ...[
              const VSection('Einchecken'),
              const VGap.m(),
              _CheckinCard(onTap: () => runCheckinFlow(context)),
            ],
            // Under the card: yesterday's forgotten check-in, only for people who ride most days.
            if (st.next?.kind == 'nachtrag') ...[
              const VGap.s(),
              InkWell(
                onTap: () => context.push(Routes.nachtrag),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'Gestern vergessen einzuchecken?',
                    style: VText.caption.copyWith(
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ],
            const VGap.l(),

            const VSection('Deine Woche'),
            const VGap.m(),
            _Momentum(standing: st, onTap: () => context.go(Routes.ich)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1 · Action
// ---------------------------------------------------------------------------

/// Idle: one square of paper and one button (docs/30). Home used to name the station it thought
/// you were at and offer your usual destinations on it — two proposals in two places, because
/// the check-in's own first step asks the same question. It asks it alone now: Home says only
/// that a journey can start here, and every way in runs the same three sheets.
class _CheckinCard extends StatelessWidget {
  const _CheckinCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return VFahrkarte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Fährst du gleich?', style: VText.title),
          const SizedBox(height: 2),
          Text('Von wo, wohin, welcher Zug. Ab dann zählen wir mit.', style: VText.caption),
          const VGap.m(),
          VPrimaryButton(
            key: const Key('einchecken-cta'),
            label: 'Einchecken',
            icon: Icons.train,
            onTap: onTap,
          ),
        ],
      ),
    );
  }
}

/// Under way (docs/20 §2): the train you are on, the next stop, the destination; in a
/// transfer the next train with "Ich bin drin". Tapping the card opens the ride sheet.
class _RideCard extends StatelessWidget {
  const _RideCard({required this.monitor});
  final RideMonitor monitor;

  @override
  Widget build(BuildContext context) {
    final m = monitor;
    return InkWell(
      key: const Key('home-ride-card'),
      onTap: m.openSheet,
      child: VFahrkarte(child: m.transfer ? _transfer(context) : _riding(context)),
    );
  }

  Widget _riding(BuildContext context) {
    final live = monitor.rideLive;
    final r = live?.ride;
    if (r == null) return const SizedBox.shrink();
    final stops = live!.stops;
    final j = monitor.journey?.journey;
    final headsign = stops.isEmpty ? r.exitStationName : stops.last.name;
    final nextIdx = (r.passedStops + fromIndex(stops, r.fromStationId, r.fromStationName)).clamp(0, stops.isEmpty ? 0 : stops.length - 1);
    final next = stops.isEmpty ? null : stops[nextIdx];
    // Capped at what the railway caused when the journey was interrupted (docs/21 §2).
    final delay = j?.cappedDelay(r.liveDelayMinutes) ?? r.liveDelayMinutes;
    final dest = j?.destinationStationName ?? r.exitStationName;
    final destAt = j?.plannedArrival ?? r.plannedArrival;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('UNTERWEGS', style: VText.eyebrow),
        const SizedBox(height: 10),
        Row(
          children: [
            LineBadge(r.line, large: true, cancelled: r.cancelled),
            const SizedBox(width: 12),
            Expanded(
              child: Text('${r.line} nach $headsign', style: VText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            if (r.cancelled)
              const VChip('Ausfall', tone: VTone.red)
            else if (delay > 0)
              VDelay(delay, size: VDelaySize.medium)
            else
              Text('pünktlich', style: VText.bodySStrong.copyWith(color: VColors.green)),
          ],
        ),
        const SizedBox(height: 12),
        if (next != null) VKeyValue('Nächster Halt', '${next.name} ${fmtLocal(plannedAt(next)?.add(Duration(minutes: delay)))}', strong: true),
        if (next != null) const VRule.soft(),
        VKeyValue('Ziel', '$dest an ${fmtLocal(destAt?.add(Duration(minutes: delay)))}', strong: true),
        const SizedBox(height: 8),
        Text('Tippen für Details', style: VText.caption),
      ],
    );
  }

  Widget _transfer(BuildContext context) {
    final jl = monitor.journey!;
    final j = jl.journey;
    final next = jl.nextLeg ?? j.nextLeg;
    final missed = j.missedConnection || next?.replanned == true;
    final where = j.transferStationName ?? next?.fromStationName ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('UMSTEIGEN', style: VText.eyebrow),
        const SizedBox(height: 6),
        Text(where, style: VText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 10),
        if (next == null)
          Text('Keine Verbindung gefunden.', style: VText.bodyStrong)
        else ...[
          Row(
            children: [
              LineBadge(next.line, cancelled: next.cancelled),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${next.line} nach ${next.headsign.isNotEmpty ? next.headsign : next.toStationName}',
                      style: VText.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        fmtLocal(next.liveDeparture ?? next.plannedDeparture),
                        if (next.platform != null && next.platform!.isNotEmpty) 'Gleis ${next.platform}',
                      ].join(' · '),
                      style: VText.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (missed) ...[
            const SizedBox(height: 4),
            Text('Anschluss verpasst · nächste Möglichkeit', style: VText.caption.copyWith(color: VColors.red)),
          ],
          const SizedBox(height: 12),
          VPrimaryButton(
            label: monitor.busy ? 'Einen Moment …' : 'Ich bin drin',
            icon: Icons.check,
            onTap: monitor.busy ? null : () => monitor.confirmLeg(next),
          ),
        ],
        const SizedBox(height: 8),
        Text('Tippen für Details', style: VText.caption),
      ],
    );
  }
}

/// The journey is over and unacknowledged (docs/20 §2): the delay, where it ended, what the
/// waiting was worth, and the two ways out — ansehen or fertig.
class _ArrivedBlock extends StatelessWidget {
  const _ArrivedBlock({
    required this.live,
    this.journey,
    required this.onDismiss,
  });
  final ApiRideLive live;
  final ApiJourney? journey;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final r = live.ride;
    final j = journey;
    final delay = j?.finalDelayMin ?? r.finalDelayMinutes ?? 0;
    final where = j?.destinationStationName ?? r.exitStationName;
    final points = j?.points ?? r.points;
    final cancelled = j?.cancelled ?? r.cancelled;
    // Two lines beside the figure: where it ended, and what the waiting was worth. Next to a
    // green nought „0 Geduldspunkte" would only say the same thing twice.
    final worth = delay > 0 || cancelled ? '$points Geduldspunkte' : 'pünktlich, keine Punkte';
    final note = j?.missedConnection == true ? '$worth · Anschluss verpasst' : worth;
    // One journey, over: the Fahrkarte, punched (app/STYLE.md).
    return VFahrkarte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ANGEKOMMEN', style: VText.eyebrow),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              VDelay(delay, size: VDelaySize.large, cancelled: cancelled),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(where, style: VText.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(note, style: VText.bodyS.copyWith(color: VColors.ink2)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: VOutlineButton(
                  label: 'Ansehen',
                  onTap: () => context.push(Routes.angekommen),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: VGhostButton(label: 'Fertig', onTap: onDismiss),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2 · Momentum
// ---------------------------------------------------------------------------

class _Momentum extends StatelessWidget {
  const _Momentum({required this.standing, required this.onTap});
  final ApiStanding standing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final st = standing;
    final quiet = st.pointsThisWeek == 0;
    // The same box as Wir (docs/30): elevated paper, a hairline border, the big number on top
    // and one quiet line under it. Two blocks that say the same kind of thing should look the
    // same; this one used to be bare text next to a bordered box.
    return VTafel(
      onTap: onTap,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // `VText.number`, not `display`: with `display` (168 px) inside a FittedBox that only
            // ever shrinks, the size on screen depended on the number itself — 1.208.473 came out
            // at about 65 px while +60 stayed huge. Two boxes above each other share one size
            // (app/STYLE.md), which is what the Wir screen has always done. The FittedBox stays
            // as a net for very long numbers.
            const VTafelLabel('Geduldspunkte diese Woche'),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: VTafelZahl(quiet ? '0' : '+${fmtInt(st.pointsThisWeek)}'),
            ),
            const SizedBox(height: 10),
            Container(height: 1, color: VColors.red),
            const SizedBox(height: 12),
            // Last week as the bar, so the two numbers can be compared at a glance rather than
            // read. A quiet week shows an empty track, which is the honest picture of it.
            LayoutBuilder(
              builder: (context, box) {
                final last = st.pointsLastWeek;
                final most = [st.pointsThisWeek, last, 1].reduce((a, b) => a > b ? a : b);
                final share = (st.pointsThisWeek / most).clamp(0.0, 1.0);
                final filled = (box.maxWidth * share).clamp(st.pointsThisWeek > 0 ? 6.0 : 0.0, box.maxWidth);
                return Stack(
                  children: [
                    Container(height: 6, decoration: BoxDecoration(color: VColors.ruleSoft, borderRadius: BorderRadius.circular(3))),
                    Container(height: 6, width: filled, decoration: BoxDecoration(color: VColors.red, borderRadius: BorderRadius.circular(3))),
                  ],
                );
              },
            ),
            const SizedBox(height: 6),
            Text(
              st.pointsLastWeek > 0
                  ? '${fmtInt(st.pointsLastWeek)} letzte Woche'
                  : 'Jede Minute Verspätung wird ein Geduldspunkt.',
              style: VText.caption,
            ),
          ],
        ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3 · Wir: the community's minutes, big and ticking, with the customer's share as a bar
// ---------------------------------------------------------------------------

class _WirBlock extends StatelessWidget {
  const _WirBlock({required this.standing, required this.tick, required this.onTap});
  final ApiStanding standing;
  final int tick;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = standing.community;
    const look = VTafelLook.anzeige;
    return VTafel(
      look: look,
      onTap: onTap,
      child: c == null
            ? const VTafelCaption('Wir haben zusammen gewartet. Zahlen folgen.', look: look)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const VTafelLabel('Minuten haben wir gewartet', look: look),
                  const SizedBox(height: 10),
                  // The same size as „Deine Woche" below it and as the Wir screen.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: VTafelZahl(fmtInt(c.minutesTotal + tick), look: look),
                  ),
                  const SizedBox(height: 10),
                  Container(height: 1, color: VColors.red),
                  const SizedBox(height: 12),
                  // The share is tiny; the filled part keeps a visible minimum.
                  LayoutBuilder(
                    builder: (context, box) {
                      final total = c.minutesTotal <= 0 ? 1 : c.minutesTotal;
                      final share = (c.myMinutes / total).clamp(0.0, 1.0);
                      final filled = (box.maxWidth * share).clamp(c.myMinutes > 0 ? 6.0 : 0.0, box.maxWidth);
                      return Stack(
                        children: [
                          Container(height: 6, decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(3))),
                          Container(height: 6, width: filled, decoration: BoxDecoration(color: VColors.red, borderRadius: BorderRadius.circular(3))),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  VTafelCaption(
                    c.myMinutes > 0 ? '${fmtInt(c.myMinutes)} davon deine' : 'Deine ersten Minuten kommen mit der ersten Fahrt.',
                    look: look,
                  ),
                ],
              ),
    );
  }
}
