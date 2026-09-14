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

    return VTabScaffold(
      onRefresh: _load,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The masthead carries the app's own name and the gear. Home is the one tab that wears
          // it: the other three are places inside the app, and this is the front door.
          VAppMasthead(
            onSettings: () => context.push(Routes.einstellungen).then((_) => _load()),
            caption: _nearby.simulated ? 'Standort: Stellwerk · ${_nearby.label ?? ''}' : null,
          ),
          const VGap.l(),
          const VTabHeader(
            title: 'Willkommen',
            subtitle: 'Jede verspätete Minute kann etwas bewegen.',
            narrow: true,
          ),
        ],
      ),
      children: [
        if (_error != null) ...[
          OfflineBanner(stamp: null),
          ErrorLine(message: _error!, onRetry: _load),
        ],

        // The one place a running pause is advertised (docs/24 §3), so it can never be forgotten
        // silently. Tapping it lifts the pause.
        if (session.nudgesSnoozed)
          VCard(
            key: const Key('stumm-bis'),
            padding: const EdgeInsets.all(VSpace.cardTight),
            onTap: session.unsnoozeNudges,
            child: Row(
              children: [
                const Icon(Icons.notifications_off_outlined, size: 18, color: VColors.ink2),
                const SizedBox(width: VSpace.s),
                Expanded(
                  child: Text(
                    me?.settings.snoozedOpenEnded == true
                        ? 'Hinweise aus · aufheben'
                        : 'Stumm bis ${fmtLocal(session.nudgeSnoozeUntil)} · aufheben',
                    style: VText.bodyS,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

        // Wir first (docs/30): the collective minutes are the thing this app is for, and they are
        // true whether or not anybody is travelling right now. The action follows.
        _WirBlock(
          standing: st,
          tick: _minuteTick,
          onTap: () => context.go(Routes.wir),
        ),

        // 1 · Action, sized by the moment. Under way, the ride card (docs/20 §2) opens the sheet;
        // the check-in card waits until the journey is over.
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
        else
          _CheckinCard(onTap: () => runCheckinFlow(context)),

        // Under the card: yesterday's forgotten check-in, only for people who ride most days.
        if (st.next?.kind == 'nachtrag')
          VCard(
            padding: const EdgeInsets.all(VSpace.cardTight),
            onTap: () => context.push(Routes.nachtrag),
            child: Row(
              children: [
                Expanded(
                  child: Text('Gestern vergessen einzuchecken?', style: VText.bodyS),
                ),
                const VChevron(),
              ],
            ),
          ),

        _Momentum(standing: st, onTap: () => context.go(Routes.ich)),

        // What the minutes are for. The mockup puts it at the foot of Home, and it is the one
        // line on this screen that is about somebody other than you.
        VCard(
          child: VCardRow(
            leading: const VIconBadge(icon: Icons.card_giftcard, tone: VBadgeTone.red),
            title: 'Deine Minuten helfen.',
            body: 'Gemeinsam spenden wir an nachhaltige und soziale Projekte.',
            chevron: true,
            onTap: () => context.go(Routes.wir),
          ),
        ),
      ],
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
    return VCard(
      tone: VCardTone.cta,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VCardRow(
            leading: const VIconBadge(icon: Icons.train, tone: VBadgeTone.red),
            eyebrow: 'Einchecken',
            title: 'Fährst du gleich?',
            body: 'Von wo, wohin, welcher Zug. Ab dann zählen wir mit.',
            chevron: true,
            onTap: onTap,
          ),
          const VGap.m(),
          VPrimaryButton(
            key: const Key('einchecken-cta'),
            label: 'Einchecken',
            icon: Icons.crop_free,
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

  /// What the week came to, against what the last one came to.
  ///
  /// The design draws seven bars here. The standing endpoint carries this week and last week, not
  /// a daily series, so the chart shows the two columns the app actually has — a week history at
  /// the resolution we have rather than an empty slot until the API grows one. When a series does
  /// arrive this becomes `VWeekBars(values: series, todayIndex: weekday, labels: [Mo … So])` and
  /// nothing else on the screen has to move.
  @override
  Widget build(BuildContext context) {
    final st = standing;
    final quiet = st.pointsThisWeek == 0;
    final never = quiet && st.pointsLastWeek == 0;
    final diff = st.pointsThisWeek - st.pointsLastWeek;

    final line = never
        ? 'Jede Minute Verspätung wird ein Geduldspunkt.'
        : diff > 0
            ? '${fmtInt(diff)} mehr als letzte Woche'
            : diff < 0
                ? '${fmtInt(-diff)} weniger als letzte Woche'
                : 'Genauso viel wie letzte Woche';

    return VCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VSectionHeader('Deine Woche', linkLabel: 'Alle Wochen', onLink: onTap),
          const VGap.md(),
          VPanel(
            tone: VPanelTone.redFaint,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const VEyebrow('Geduldspunkte diese Woche', size: VEyebrowSize.s),
                      const VGap.xs(),
                      // A FittedBox as a net for a very long figure, not as the size itself: it
                      // only ever shrinks, so the size on screen would otherwise depend on the
                      // number.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          quiet ? '0' : '+${fmtInt(st.pointsThisWeek)}',
                          style: VText.numberM,
                        ),
                      ),
                      const VGap.s(),
                      Text(line, style: VText.bodyS, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: VSpace.s),
                VWeekBars(
                  values: [st.pointsLastWeek, st.pointsThisWeek],
                  todayIndex: 1,
                  labels: const ['Letzte', 'Diese'],
                ),
              ],
            ),
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
    if (c == null) {
      return VBoard(
        onTap: onTap,
        child: const VBoardCaption('Wir haben zusammen gewartet. Zahlen folgen.'),
      );
    }
    final total = c.minutesTotal <= 0 ? 1 : c.minutesTotal;
    return VBoard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VBoardLabel('Minuten haben wir gewartet', icon: Icons.schedule),
          const VGap.s(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              fmtInt(c.minutesTotal + tick),
              style: VText.number.copyWith(color: VColors.inkOnDark),
            ),
          ),
          const VGap.md(),
          VProgressBar(
            value: (c.myMinutes / total).clamp(0.0, 1.0),
            ground: VProgressGround.dark,
          ),
          const VGap.s(),
          VBoardCaption(
            c.myMinutes > 0
                ? '${fmtInt(c.myMinutes)} davon deine'
                : 'Deine ersten Minuten kommen mit der ersten Fahrt.',
          ),
        ],
      ),
    );
  }
}
