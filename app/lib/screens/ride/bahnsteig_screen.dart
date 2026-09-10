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
  ApiLocation? _position;
  ApiNearby _nearby = const ApiNearby(stations: [], source: 'none');
  List<ApiDeparture> _nearDepartures = const [];
  ApiGeofence _frequent = ApiGeofence.empty;
  ApiRideLive? _live;
  ApiStanding _standing = ApiStanding.empty;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Timer? _poll;
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
      if (e.touchesLocation) _position = null;
      if (e.touchesLocation || e.touchesRide || e.touchesLedger) _load();
    });
    session.addListener(_onSession);
    _ticker = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && _standing.community != null) setState(() => _minuteTick += 1 + DateTime.now().second % 3);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = RepoScope.of(context).repo;
    if (!identical(repo, _lastRepo)) {
      _lastRepo = repo;
      _load();
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _poll?.cancel();
    _ticker?.cancel();
    _session.removeListener(_onSession);
    super.dispose();
  }

  /// The account changed (points after an arrival, a new NGO, a nickname): the numbers follow.
  void _onSession() {
    if (!mounted) return;
    final me = _session.me;
    final stamp = me == null ? null : '${me.id}:${me.pointsTotal}:${me.pointsThisWeek}:${me.settings.ngoId}:${me.settings.showOnBoards}';
    if (stamp != _lastMeStamp) {
      _lastMeStamp = stamp;
      _loadStanding();
    }
  }

  Future<void> _loadStanding() async {
    try {
      final st = await RepoScope.read(context).repo.standing();
      if (mounted) setState(() => _standing = st);
    } catch (_) {
      // keep the last numbers
    }
  }

  Future<void> _load() async {
    final repo = RepoScope.read(context).repo;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _position ??= await currentPosition(timeout: const Duration(seconds: 3));
      final results = await Future.wait<dynamic>([
        repo.nearbyStations(lat: _position?.lat, lon: _position?.lon),
        repo.currentRide(),
        repo.standing().catchError((_) => ApiStanding.empty),
        repo.geofence().catchError((_) => ApiGeofence.empty),
      ]);
      if (!mounted) return;
      final nearby = results[0] as ApiNearby;
      // At a station: the next departures come with the screen, no second tap.
      final near = _nearestWithin(nearby, 300);
      List<ApiDeparture> deps = const [];
      if (near != null) {
        try {
          deps = await repo.departures(near.id);
        } catch (_) {
          deps = const [];
        }
      }
      if (!mounted) return;
      setState(() {
        _nearby = nearby;
        _nearDepartures = deps;
        _live = results[1] as ApiRideLive?;
        _standing = results[2] as ApiStanding;
        _frequent = results[3] as ApiGeofence;
        _minuteTick = 0;
        _error = null;
      });
      _schedulePoll();
    } catch (e) {
      if (mounted) setState(() => _error = shortError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _schedulePoll() {
    _poll?.cancel();
    if (_live?.ride.status == ApiRideStatus.riding) {
      _poll = Timer(const Duration(seconds: 20), _refreshRide);
    }
  }

  Future<void> _refreshRide() async {
    try {
      final live = await RepoScope.read(context).repo.currentRide();
      if (!mounted) return;
      final wasRiding = _live?.ride.status == ApiRideStatus.riding;
      setState(() => _live = live);
      // The ride ended while the customer was on the Bahnsteig: the reveal, once.
      if (wasRiding && live != null && live.ride.status == ApiRideStatus.arrived) {
        context.push(Routes.angekommen);
      }
    } catch (_) {
      // keep the last state
    }
    if (mounted) _schedulePoll();
  }

  Future<void> _dismiss() async {
    try {
      await RepoScope.read(context).repo.dismissRide();
    } catch (_) {}
    if (mounted) _load();
  }

  static ApiStation? _nearestWithin(ApiNearby nearby, int metres) {
    // Needs a position: the phone's, or a Stellwerk override. Never a guess.
    if (nearby.none || nearby.stations.isEmpty) return null;
    final s = nearby.stations.first;
    final d = s.distanceM;
    return d != null && d <= metres ? s : null;
  }

  ApiStation? get _nearStation => _nearestWithin(_nearby, 300);

  Future<void> _muteStation(ApiStation s) async {
    final session = RepoScope.read(context);
    await session.muteStation(ApiMutedStation(id: s.id, name: s.name));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.name} bleibt still. Ändern in den Einstellungen.')));
  }

  /// The same path Konto takes: draft for the ready desk, then the five steps.
  Future<void> _prepareClaim(String desk) async {
    final session = RepoScope.read(context);
    setState(() => _busy = true);
    try {
      final draft = await session.repo.draftClaim(desk: desk);
      if (!mounted) return;
      await context.push('${Routes.antrag}?id=${draft.claim.id}&desk=${Uri.encodeComponent(desk)}', extra: draft);
      if (mounted) _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Antrag nicht möglich: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openStation(ApiStation s) {
    context.push('${Routes.checkin}?station=${Uri.encodeComponent(s.id)}&name=${Uri.encodeComponent(s.name)}');
  }

  /// Straight to "Wo steigst du aus?", the way the Einchecken screen does it.
  void _toExit(ApiStation s, ApiDeparture d) {
    final coords = s.lat != 0 || s.lon != 0 ? '&lat=${s.lat}&lon=${s.lon}' : '';
    context.push('${Routes.exitStop}?departure=${Uri.encodeComponent(d.tripId)}&station=${Uri.encodeComponent(s.id)}&name=${Uri.encodeComponent(s.name)}$coords');
  }

  /// "Standort erlauben": ask the phone once, then reload. Never a guess.
  Future<void> _locate() async {
    _position = await currentPosition(timeout: const Duration(seconds: 5));
    if (mounted) await _load();
  }

  Future<void> _search() async {
    final s = await showStationSearch(context);
    if (s != null && mounted) _openStation(s);
  }

  void _openNext(ApiStandingNext n) {
    switch (n.kind) {
      case 'mail':
        context.push(Routes.antwort);
      case 'deadline':
        context.go(Routes.konto);
      case 'nachtrag':
        context.push(Routes.nachtrag);
      case 'badge':
        context.go(Routes.ich);
      default:
        context.go(Routes.konto);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = RepoScope.of(context);
    final me = session.me;
    final riding = _live?.ride.status == ApiRideStatus.riding;
    final arrived = _live != null && _live!.ride.status == ApiRideStatus.arrived;
    final near = _nearStation;
    final st = _standing;

    return VScreen(
      showBack: false,
      padding: const EdgeInsets.fromLTRB(VSpace.page, VSpace.s, VSpace.page, VSpace.l),
      child: RefreshIndicator(
        onRefresh: _load,
        color: VColors.ink,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Slim header: the Stellwerk caption when a simulated position is active, the small clock.
            Row(
              children: [
                Expanded(
                  child: _nearby.simulated
                      ? Text('Standort: Stellwerk · ${_nearby.label ?? ''}', style: VText.caption.copyWith(color: VColors.red), maxLines: 1, overflow: TextOverflow.ellipsis)
                      : const SizedBox.shrink(),
                ),
                const VStationClock(size: 32),
              ],
            ),
            if (_error != null) ...[const VGap.m(), OfflineBanner(stamp: null), ErrorLine(message: _error!, onRetry: _load)],
            const VGap.s(),

            // 1 · Action, sized by the moment.
            if (_loading && _live == null)
              const LoadingLine(label: 'Bahnsteig wird geladen …')
            else if (riding)
              _RidingBlock(live: _live!)
            else if (arrived)
              _ArrivedBlock(live: _live!, onDismiss: _dismiss)
            else ...[
              const VSection('Einchecken'),
              const VGap.m(),
              if (near != null)
                _StationCard(
                  station: near,
                  departures: _nearDepartures,
                  onDeparture: (d) => _toExit(near, d),
                  onAll: () => _openStation(near),
                  onMute: () => _muteStation(near),
                )
              else
                _StationRow(
                  nearby: _nearby,
                  frequent: _frequent.stations,
                  homeStation: me?.homeStation ?? '',
                  hasPosition: _position != null,
                  onStation: _openStation,
                  onSearch: _search,
                  onLocate: _locate,
                ),
            ],
            const VGap.m(),

            // 2 · Momentum.
            _Momentum(standing: st, onTap: () => context.go(Routes.ich)),
            const VRule(),

            // 3 · Money countdown.
            _Money(standing: st, busy: _busy, onOpen: () => context.go(Routes.konto), onClaim: st.money?.readyDesk == null ? null : () => _prepareClaim(st.money!.readyDesk!)),
            const VRule(),

            // 4 · Standing.
            if (st.board != null) ...[
              _Standing(board: st.board!, onTap: () => context.go(Routes.wir)),
              const VRule(),
            ],

            // 5 · Community with my share.
            _Community(standing: st, tick: _minuteTick, onTap: () => context.go(Routes.wir)),

            // 6 · The one next thing.
            if (st.next != null) ...[
              const VGap.l(),
              _NextThing(next: st.next!, onTap: () => _openNext(st.next!)),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1 · Action
// ---------------------------------------------------------------------------

/// Away from a station: the home station, the frequent ones, nearby ones if any, search.
class _StationRow extends StatelessWidget {
  const _StationRow({
    required this.nearby,
    required this.frequent,
    required this.homeStation,
    required this.hasPosition,
    required this.onStation,
    required this.onSearch,
    required this.onLocate,
  });
  final ApiNearby nearby;
  final List<ApiGeofenceStation> frequent;
  final String homeStation;
  final bool hasPosition;
  final ValueChanged<ApiStation> onStation;
  final VoidCallback onSearch;
  final VoidCallback onLocate;

  @override
  Widget build(BuildContext context) {
    // Frequent first (most check-ins), then nearby ones not already listed, at most five.
    final sorted = [...frequent]..sort((a, b) => b.checkins.compareTo(a.checkins));
    final entries = <(ApiStation, String?)>[];
    for (final f in sorted.take(3)) {
      final isHome = f.name == homeStation || (homeStation.isEmpty && identical(f, sorted.first) && f.checkins > 1);
      entries.add((ApiStation(id: f.id, name: f.name, lat: f.lat, lon: f.lon), isHome ? 'Stammbahnhof' : null));
    }
    for (final s in nearby.stations) {
      if (entries.length >= 5) break;
      if (entries.any((e) => e.$1.id == s.id || e.$1.name == s.name)) continue;
      entries.add((s, s.distanceM == null ? null : _dist(s.distanceM!)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (s, suffix) in entries)
              ActionChip(
                onPressed: () => onStation(s),
                backgroundColor: VColors.paperElevated,
                side: const BorderSide(color: VColors.rule),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                label: RichText(
                  text: TextSpan(
                    style: VText.bodySStrong,
                    children: [
                      TextSpan(text: s.name),
                      if (suffix != null) TextSpan(text: ' · $suffix', style: VText.caption),
                    ],
                  ),
                ),
              ),
            ActionChip(
              onPressed: onSearch,
              backgroundColor: VColors.paperElevated,
              side: const BorderSide(color: VColors.rule),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              avatar: const Icon(Icons.search, size: 18, color: VColors.ink),
              label: Text('Suchen', style: VText.bodySStrong),
            ),
          ],
        ),
        if (nearby.none && !hasPosition) ...[
          const VGap.s(),
          Row(
            children: [
              Expanded(child: Text('Ohne Standort zeigen wir keinen Bahnhof in der Nähe.', style: VText.caption)),
              TextButton(onPressed: onLocate, child: Text('Standort erlauben', style: VText.bodySStrong.copyWith(color: VColors.red))),
            ],
          ),
        ],
      ],
    );
  }

  static String _dist(int m) => m < 1000 ? '$m m' : '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
}

/// At a station: the next three rail departures inline, one tap to the exit stop.
class _StationCard extends StatelessWidget {
  const _StationCard({required this.station, required this.departures, required this.onDeparture, required this.onAll, required this.onMute});
  final ApiStation station;
  final List<ApiDeparture> departures;
  final ValueChanged<ApiDeparture> onDeparture;
  final VoidCallback onAll;
  final VoidCallback onMute;

  @override
  Widget build(BuildContext context) {
    final next = departures.where((d) => !d.cancelled && d.category != ApiCategory.other && d.category != ApiCategory.bus).take(3).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(VSpace.m, VSpace.m, VSpace.m, 0),
      decoration: BoxDecoration(border: Border.all(color: VColors.ink, width: 1.5), borderRadius: BorderRadius.circular(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: () => _muteSheet(context),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(station.name, style: VText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        station.distanceM == null ? 'Du bist hier · halten: nie hier erinnern' : 'Du bist hier · ${station.distanceM} m',
                        style: VText.caption,
                      ),
                    ],
                  ),
                ),
                ActionChip(
                  onPressed: onAll,
                  backgroundColor: VColors.paperElevated,
                  side: const BorderSide(color: VColors.rule),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  label: Text('Alle Abfahrten', style: VText.bodySStrong),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          if (next.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Gerade keine Abfahrt in Sicht. Alle Abfahrten zeigen auch Busse und Bahnen.', style: VText.caption),
            )
          else
            for (final d in next) DepartureRow(departure: d, onTap: () => onDeparture(d)),
        ],
      ),
    );
  }

  Future<void> _muteSheet(BuildContext context) async {
    final yes = await showVSheet<bool>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(bottom: VSpace.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VSheetHeader(title: 'Diesen Bahnhof nie?', subtitle: '${station.name} stumm schalten: kein Hinweis mehr, wenn du hier stehst. Einchecken geht weiter.'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
              child: Row(
                children: [
                  Expanded(child: VOutlineButton(label: 'Stumm schalten', onTap: () => Navigator.of(ctx).pop(true))),
                  const SizedBox(width: 10),
                  Expanded(child: VGhostButton(label: 'Abbrechen', onTap: () => Navigator.of(ctx).pop(false))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (yes == true) onMute();
  }
}

class _RidingBlock extends StatelessWidget {
  const _RidingBlock({required this.live});
  final ApiRideLive live;

  @override
  Widget build(BuildContext context) {
    final r = live.ride;
    final stops = live.stops;
    final nextName = stops.isEmpty ? null : stops[(r.passedStops + 1).clamp(0, stops.length - 1)].name;
    return InkWell(
      onTap: () => context.push(Routes.unterwegs),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.all(VSpace.m),
        decoration: BoxDecoration(border: Border.all(color: VColors.ink, width: 1.5), borderRadius: BorderRadius.circular(4)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('UNTERWEGS', style: VText.eyebrow),
            const SizedBox(height: 10),
            Row(
              children: [
                LineBadge(r.line, large: true),
                const SizedBox(width: 12),
                Expanded(child: Text('nach ${r.exitStationName}', style: VText.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                VDelay(r.liveDelayMinutes, size: VDelaySize.medium, cancelled: r.cancelled),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              [if (nextName != null) 'Nächster Halt $nextName', 'Ausstieg ${r.exitStationName}', if (live.eta != null) 'an ${fmtLocal(live.eta)}'].join(' · '),
              style: VText.caption,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: VOutlineButton(label: 'Zur Fahrt', onTap: () => context.push(Routes.unterwegs))),
                const SizedBox(width: 10),
                Expanded(child: VGhostButton(label: 'Zug wechseln', onTap: () => context.push(Routes.unterwegs))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ArrivedBlock extends StatelessWidget {
  const _ArrivedBlock({required this.live, required this.onDismiss});
  final ApiRideLive live;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final r = live.ride;
    final delay = r.finalDelayMinutes ?? 0;
    return Container(
      padding: const EdgeInsets.all(VSpace.m),
      decoration: BoxDecoration(border: Border.all(color: VColors.rule), borderRadius: BorderRadius.circular(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ANGEKOMMEN', style: VText.eyebrow),
          const SizedBox(height: 10),
          Row(
            children: [
              VDelay(delay, size: VDelaySize.large, cancelled: r.cancelled),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  '${r.exitStationName}\n${r.points} Geduldspunkte',
                  style: VText.bodyS.copyWith(color: VColors.ink2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: VOutlineButton(label: 'Ansehen', onTap: () => context.push(Routes.angekommen))),
              const SizedBox(width: 10),
              Expanded(child: VGhostButton(label: 'Fertig', onTap: onDismiss)),
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
    final lvl = st.level;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: VSpace.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (quiet) ...[
              Text('Diese Woche noch keine Fahrt', style: VText.title),
              const SizedBox(height: 2),
              Text(st.pointsLastWeek > 0 ? 'Letzte Woche ${fmtInt(st.pointsLastWeek)} Geduldspunkte' : 'Jede Minute Verspätung wird ein Geduldspunkt.', style: VText.caption),
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('+${fmtInt(st.pointsThisWeek)}', style: VText.numberM),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Geduldspunkte diese Woche · letzte Woche ${fmtInt(st.pointsLastWeek)}',
                      style: VText.caption,
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ],
            if (lvl != null) ...[
              const SizedBox(height: 10),
              VProgress(confirmed: lvl.progress),
              const SizedBox(height: 6),
              Text(
                lvl.pointsToNext > 0 ? '${lvl.name} · ${fmtInt(lvl.pointsToNext)} bis „${lvl.nextName}“' : '${lvl.name} · höchste Stufe erreicht',
                style: VText.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3 · Money countdown
// ---------------------------------------------------------------------------

class _Money extends StatelessWidget {
  const _Money({required this.standing, required this.busy, required this.onOpen, this.onClaim});
  final ApiStanding standing;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback? onClaim;

  @override
  Widget build(BuildContext context) {
    final m = standing.money;
    if (m == null) {
      return InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: VSpace.m),
          child: Text('Noch keine Verspätung ab 60 Minuten. Die erste zählt 1,50 €.', style: VText.caption),
        ),
      );
    }
    if (m.ready && onClaim != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: VSpace.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VPrimaryButton(label: busy ? 'Einen Moment …' : '${fmtEuro(m.openCents / 100)} beantragen', icon: Icons.edit_outlined, onTap: busy ? null : onClaim),
            const SizedBox(height: 6),
            Text('Bündel bereit · geht an ${m.ngoName}', style: VText.caption),
          ],
        ),
      );
    }
    final first = m.openCents == 0;
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: VSpace.m),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(fmtEuro(m.missingCents / 100), style: VText.numberM),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                first ? 'bis zum ersten Antrag · jede Verspätung ab 60 Minuten zählt' : 'bis zum Antrag · ${fmtEuro(m.openCents / 100)} gesammelt für ${m.ngoName}',
                style: VText.caption,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4 · Standing
// ---------------------------------------------------------------------------

class _Standing extends StatelessWidget {
  const _Standing({required this.board, required this.onTap});
  final ApiStandingBoard board;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = board;
    final where = b.scope == 'city' ? 'in ${b.key}' : 'auf der ${b.key}';
    final gap = b.gapToNext;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: VSpace.m),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('Platz ${b.rank}', style: VText.numberM),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                gap == null || b.rank <= 1
                    ? '$where diese Woche · ganz oben, von ${b.size}'
                    : '$where diese Woche · ${fmtInt(gap)} ${gap == 1 ? 'Punkt' : 'Punkte'} bis Platz ${b.rank - 1}',
                style: VText.caption,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5 · Community with my share
// ---------------------------------------------------------------------------

class _Community extends StatelessWidget {
  const _Community({required this.standing, required this.tick, required this.onTap});
  final ApiStanding standing;
  final int tick;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = standing.community;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: VSpace.m),
        child: c == null
            ? Text('Wir haben zusammen gewartet. Zahlen folgen.', style: VText.caption)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: VText.body.copyWith(color: VColors.ink2),
                      children: [
                        TextSpan(
                          text: '${fmtInt(c.minutesTotal + tick)} Minuten',
                          style: VText.bodyStrong.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                        const TextSpan(text: ' haben wir gewartet'),
                        if (c.myMinutes > 0) TextSpan(text: ' · ${fmtInt(c.myMinutes)} davon deine'),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    c.myConfirmedCents > 0
                        ? '${fmtEuroWhole(c.confirmedCents / 100)} an Vereine bestätigt · ${fmtEuro(c.myConfirmedCents / 100)} durch dich'
                        : '${fmtEuroWhole(c.confirmedCents / 100)} an Vereine bestätigt',
                    style: VText.caption,
                  ),
                ],
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 6 · The one next thing
// ---------------------------------------------------------------------------

class _NextThing extends StatelessWidget {
  const _NextThing({required this.next, required this.onTap});
  final ApiStandingNext next;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = switch (next.kind) {
      'mail' => Icons.mail_outline,
      'deadline' => Icons.schedule,
      'nachtrag' => Icons.history,
      'badge' => Icons.workspace_premium_outlined,
      _ => Icons.arrow_forward,
    };
    final urgent = next.kind == 'deadline' && (next.daysLeft ?? 99) <= 7;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.all(VSpace.m),
        decoration: BoxDecoration(
          color: urgent ? VColors.redSoft : VColors.paperElevated,
          border: Border.all(color: urgent ? VColors.red : VColors.rule),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: urgent ? VColors.red : VColors.ink),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(next.title.toUpperCase(), style: VText.eyebrow.copyWith(color: urgent ? VColors.red : VColors.ink2)),
                  const SizedBox(height: 2),
                  Text(next.body, style: VText.bodySStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: VColors.ink3),
          ],
        ),
      ),
    );
  }
}
