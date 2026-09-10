import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../repo/app_repository.dart';
import '../../api/events.dart';
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../state/ride_monitor.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'ride_widgets.dart';
import 'wohin_screen.dart';

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
  ApiGeofence _frequent = ApiGeofence.empty;
  ApiDestinations _destinations = ApiDestinations.empty;
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
      if (e.touchesLocation) _position = null;
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
    final repo = RepoScope.of(context).repo;
    if (!identical(repo, _lastRepo)) {
      _lastRepo = repo;
      _load();
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _ticker?.cancel();
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
    final repo = RepoScope.read(context).repo;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _position ??= await currentPosition(timeout: const Duration(seconds: 3));
      final results = await Future.wait<dynamic>([
        repo.nearbyStations(lat: _position?.lat, lon: _position?.lon),
        _session.loadStanding().catchError((_) => ApiStanding.empty),
        repo.geofence().catchError((_) => ApiGeofence.empty),
      ]);
      if (!mounted) return;
      final nearby = results[0] as ApiNearby;
      // At a station: the destinations from this person's history come with the screen (docs/18).
      final near = _nearestWithin(nearby, 300);
      var dest = ApiDestinations.empty;
      if (near != null) {
        dest = await repo
            .destinations(from: near.id)
            .catchError((_) => ApiDestinations.empty);
      }
      if (!mounted) return;
      setState(() {
        _nearby = nearby;
        _destinations = dest;
        _standing = results[1] as ApiStanding;
        _frequent = results[2] as ApiGeofence;
        _minuteTick = 0;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = shortError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${s.name} bleibt still. Ändern in den Einstellungen.'),
      ),
    );
  }

  void _openStation(ApiStation s) {
    context.push(
      '${Routes.checkin}?station=${Uri.encodeComponent(s.id)}&name=${Uri.encodeComponent(s.name)}',
    );
  }

  /// A destination first: straight to "Welcher Zug?".
  void _toWelcherZug(ApiStation s, ApiDestination d) => context.push(
    welcherZugRoute(
      fromId: s.id,
      fromName: s.name,
      to: d.station,
      lat: s.lat,
      lon: s.lon,
    ),
  );

  /// "Standort erlauben": ask the phone once, then reload. Never a guess.
  Future<void> _locate() async {
    _position = await currentPosition(timeout: const Duration(seconds: 5));
    if (mounted) await _load();
  }

  Future<void> _search() async {
    final s = await showStationSearch(context);
    if (s != null && mounted) _openStation(s);
  }

  @override
  Widget build(BuildContext context) {
    final session = RepoScope.of(context);
    final me = session.me;
    // The ride lives in the shell's monitor (docs/19): the bar and the sheet show it while
    // under way; Home only shows the arrival card once it is over.
    final ride = RideScope.of(context);
    final underWay = ride.active;
    final arrived = ride.arrived && ride.rideLive != null;
    final near = _nearStation;
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
            // Slim header: the Stellwerk caption when a simulated position is active, the small clock.
            Row(
              children: [
                Expanded(
                  child: _nearby.simulated
                      ? Text(
                          'Standort: Stellwerk · ${_nearby.label ?? ''}',
                          style: VText.caption.copyWith(color: VColors.red),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : const SizedBox.shrink(),
                ),
                VIconButton(
                  icon: Icons.settings_outlined,
                  onTap: () =>
                      context.push(Routes.einstellungen).then((_) => _load()),
                ),
              ],
            ),
            if (_error != null) ...[
              const VGap.m(),
              OfflineBanner(stamp: null),
              ErrorLine(message: _error!, onRetry: _load),
            ],
            const VGap.s(),

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
              VSection(near != null ? 'Einchecken' : 'Startbahnhof'),
              const VGap.m(),
              if (near != null)
                _StationCard(
                  station: near,
                  destinations: _destinations,
                  search: RepoScope.read(context).repo.searchStations,
                  onDestination: (d) => _toWelcherZug(near, d),
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

            // Two things, nothing else (docs/19): the week, us.
            const VSection('Deine Woche'),
            _Momentum(standing: st, onTap: () => context.go(Routes.ich)),
            const VGap.l(),
            const VSection('Wir'),
            const VGap.m(),
            _WirBlock(
              standing: st,
              tick: _minuteTick,
              onTap: () => context.go(Routes.wir),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1 · Action
// ---------------------------------------------------------------------------

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
      child: Container(
        padding: const EdgeInsets.all(VSpace.m),
        decoration: BoxDecoration(
          color: VColors.paperElevated,
          border: Border.all(color: VColors.rule),
          borderRadius: BorderRadius.circular(4),
        ),
        child: m.transfer ? _transfer(context) : _riding(context),
      ),
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
    final sorted = [...frequent]
      ..sort((a, b) => b.checkins.compareTo(a.checkins));
    final entries = <(ApiStation, String?)>[];
    for (final f in sorted.take(3)) {
      final isHome =
          f.name == homeStation ||
          (homeStation.isEmpty && identical(f, sorted.first) && f.checkins > 1);
      entries.add((
        ApiStation(id: f.id, name: f.name, lat: f.lat, lon: f.lon),
        isHome ? 'Stammbahnhof' : null,
      ));
    }
    for (final s in nearby.stations) {
      if (entries.length >= 5) break;
      if (entries.any((e) => e.$1.id == s.id || e.$1.name == s.name)) continue;
      entries.add((s, s.distanceM == null ? null : _dist(s.distanceM!)));
    }
    // The same box as the station card, so the idle state reads as "no station yet" rather
    // than as loose chips: one line of context, then the ways in.
    // The box answers one question: where does the journey start? (docs/19 §3)
    final title = !hasPosition
        ? 'Von wo fährst du los?'
        : nearby.stations.isEmpty
        ? 'Kein Bahnhof in der Nähe · von wo fährst du los?'
        : 'Von wo fährst du los?';
    final caption = !hasPosition
        ? 'Wo bist du? Ohne Standort wissen wir nicht, ob du an einem Bahnhof stehst.'
        : 'Stehst du an einem Bahnhof, fragen wir hier direkt nach dem Ziel. Bis dahin:';
    return Container(
      padding: const EdgeInsets.all(VSpace.m),
      decoration: BoxDecoration(
        border: Border.all(color: VColors.rule, width: 1.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: VText.title),
          const SizedBox(height: 2),
          Text(caption, style: VText.caption),
          const VGap.m(),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (s, suffix) in entries)
                ActionChip(
                  onPressed: () => onStation(s),
                  backgroundColor: VColors.paperElevated,
                  side: const BorderSide(color: VColors.rule),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  label: RichText(
                    text: TextSpan(
                      style: VText.bodySStrong,
                      children: [
                        TextSpan(text: 'Ab ${s.name}'),
                        if (suffix != null)
                          TextSpan(text: ' · $suffix', style: VText.caption),
                      ],
                    ),
                  ),
                ),
              ActionChip(
                onPressed: onSearch,
                backgroundColor: VColors.paperElevated,
                side: const BorderSide(color: VColors.rule),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                avatar: const Icon(Icons.search, size: 18, color: VColors.ink),
                label: Text('Suchen', style: VText.bodySStrong),
              ),
            ],
          ),
          if (nearby.none && !hasPosition) ...[
            const VGap.s(),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onLocate,
                child: Text(
                  'Standort erlauben',
                  style: VText.bodySStrong.copyWith(color: VColors.red),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _dist(int m) => m < 1000
      ? '$m m'
      : '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
}

/// At a station: the predicted destinations as one-tap buttons, the next three rail
/// departures underneath as the other way in (docs/17).
class _StationCard extends StatelessWidget {
  const _StationCard({
    required this.station,
    required this.destinations,
    required this.search,
    required this.onDestination,
    required this.onMute,
  });
  final ApiStation station;
  final ApiDestinations destinations;
  final Future<List<ApiStation>> Function(String query) search;
  final ValueChanged<ApiDestination> onDestination;
  final VoidCallback onMute;

  @override
  Widget build(BuildContext context) {
    // Only places this person has been to before (docs/18); the home station comes first when away.
    final history = destinations.predicted
        .where((p) => p.stationId != station.id)
        .take(4)
        .toList();
    return Container(
      padding: const EdgeInsets.all(VSpace.m),
      decoration: BoxDecoration(
        border: Border.all(color: VColors.ink, width: 1.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: () => _muteSheet(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('STARTBAHNHOF', style: VText.eyebrow),
                const SizedBox(height: 2),
                Text(
                  'Ab ${station.name}',
                  style: VText.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  station.distanceM == null
                      ? 'Du bist hier'
                      : 'Du bist hier · ${station.distanceM} m',
                  style: VText.caption,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final d in history) ...[
            DestinationButton(
              destination: d,
              primary: identical(d, history.first),
              onTap: () => onDestination(d),
            ),
            const SizedBox(height: 8),
          ],
          _WohinField(
            search: search,
            exclude: station.id,
            onPick: (s) => onDestination(
              ApiDestination(stationId: s.id, stationName: s.name),
            ),
          ),
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
            VSheetHeader(
              title: 'Diesen Bahnhof nie?',
              subtitle:
                  '${station.name} stumm schalten: kein Hinweis mehr, wenn du hier stehst. Einchecken geht weiter.',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
              child: Row(
                children: [
                  Expanded(
                    child: VOutlineButton(
                      label: 'Stumm schalten',
                      onTap: () => Navigator.of(ctx).pop(true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: VGhostButton(
                      label: 'Abbrechen',
                      onTap: () => Navigator.of(ctx).pop(false),
                    ),
                  ),
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
    return Container(
      padding: const EdgeInsets.all(VSpace.m),
      decoration: BoxDecoration(
        border: Border.all(color: VColors.rule),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ANGEKOMMEN', style: VText.eyebrow),
          const SizedBox(height: 10),
          Row(
            children: [
              VDelay(
                delay,
                size: VDelaySize.large,
                cancelled: j?.cancelled ?? r.cancelled,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  '$where\n$points Geduldspunkte${j?.missedConnection == true ? ' · Anschluss verpasst' : ''}',
                  style: VText.bodyS.copyWith(color: VColors.ink2),
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
              Text(
                st.pointsLastWeek > 0
                    ? 'Letzte Woche ${fmtInt(st.pointsLastWeek)} Geduldspunkte'
                    : 'Jede Minute Verspätung wird ein Geduldspunkt.',
                style: VText.caption,
              ),
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
                lvl.pointsToNext > 0
                    ? '${lvl.name} · ${fmtInt(lvl.pointsToNext)} bis „${lvl.nextName}“'
                    : '${lvl.name} · höchste Stufe erreicht',
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.all(VSpace.m),
        decoration: BoxDecoration(
          color: VColors.paperElevated,
          border: Border.all(color: VColors.rule),
          borderRadius: BorderRadius.circular(4),
        ),
        child: c == null
            ? Text('Wir haben zusammen gewartet. Zahlen folgen.', style: VText.caption)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      fmtInt(c.minutesTotal + tick),
                      style: VText.display.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('Minuten haben wir gewartet', style: VText.caption),
                  const SizedBox(height: 12),
                  // The share is tiny; the filled part keeps a visible minimum.
                  LayoutBuilder(
                    builder: (context, box) {
                      final total = c.minutesTotal <= 0 ? 1 : c.minutesTotal;
                      final share = (c.myMinutes / total).clamp(0.0, 1.0);
                      final filled = (box.maxWidth * share).clamp(c.myMinutes > 0 ? 6.0 : 0.0, box.maxWidth);
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
                    c.myMinutes > 0 ? '${fmtInt(c.myMinutes)} davon deine' : 'Deine ersten Minuten kommen mit der ersten Fahrt.',
                    style: VText.caption,
                  ),
                ],
              ),
      ),
    );
  }
}

/// "Wohin?": types a station name, suggests up to four, one tap picks. Always present on
/// the card, the only way in when there is no history yet (docs/18).
class _WohinField extends StatefulWidget {
  const _WohinField({
    required this.search,
    required this.exclude,
    required this.onPick,
  });
  final Future<List<ApiStation>> Function(String query) search;
  final String exclude;
  final ValueChanged<ApiStation> onPick;

  @override
  State<_WohinField> createState() => _WohinFieldState();
}

class _WohinFieldState extends State<_WohinField> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<ApiStation> _hits = const [];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _hits = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () => _run(q.trim()));
  }

  Future<void> _run(String q) async {
    setState(() => _searching = true);
    try {
      final hits = await widget.search(q);
      if (!mounted || _controller.text.trim() != q) return;
      setState(
        () =>
            _hits = hits.where((s) => s.id != widget.exclude).take(4).toList(),
      );
    } catch (_) {
      if (mounted) setState(() => _hits = const []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Wohin?',
            prefixIcon: const Icon(Icons.search, size: 20, color: VColors.ink2),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: VColors.ink2,
                      ),
                    ),
                  )
                : null,
          ),
        ),
        for (final s in _hits)
          InkWell(
            onTap: () => widget.onPick(s),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.place_outlined,
                        size: 20,
                        color: VColors.ink2,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          s.name,
                          style: VText.bodySStrong,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward,
                        size: 18,
                        color: VColors.ink,
                      ),
                    ],
                  ),
                ),
                const VRule.soft(),
              ],
            ),
          ),
      ],
    );
  }
}
