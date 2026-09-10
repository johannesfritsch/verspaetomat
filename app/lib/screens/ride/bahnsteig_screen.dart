import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../mock/mock_data.dart' show Mock;
import '../../repo/app_repository.dart';
import '../../api/events.dart';
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import '../claims/claims_widgets.dart' show fmtCents;
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
  ApiRideLive? _live;
  ApiJourneyLive? _journey;
  ApiDestinations _destinations = ApiDestinations.empty;
  List<ApiClaim> _claims = const [];
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
    _poll?.cancel();
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
        repo.currentRide(),
        _session.loadStanding().catchError((_) => ApiStanding.empty),
        repo.geofence().catchError((_) => ApiGeofence.empty),
        repo.currentJourney().catchError((_) => null),
        repo.claims().catchError((_) => const <ApiClaim>[]),
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
        _live = results[1] as ApiRideLive?;
        _journey = results[4] as ApiJourneyLive?;
        _standing = results[2] as ApiStanding;
        _frequent = results[3] as ApiGeofence;
        _claims = results[5] as List<ApiClaim>;
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
    if (_live?.ride.status == ApiRideStatus.riding ||
        _journey?.journey.inTransfer == true) {
      _poll = Timer(const Duration(seconds: 20), _refreshRide);
    }
  }

  Future<void> _refreshRide() async {
    try {
      final repo = RepoScope.read(context).repo;
      final live = await repo.currentRide();
      final journey = await repo.currentJourney().catchError((_) => null);
      if (!mounted) return;
      final wasRiding = _live?.ride.status == ApiRideStatus.riding;
      setState(() {
        _live = live;
        _journey = journey;
      });
      // The journey ended while the customer was on the Bahnsteig: the reveal, once.
      final journeyArrived =
          journey?.journey.arrived ??
          (live != null && live.ride.status == ApiRideStatus.arrived);
      if (wasRiding && journeyArrived && journey?.journey.inTransfer != true) {
        context.push(Routes.angekommen);
      }
    } catch (_) {
      // keep the last state
    }
    if (mounted) _schedulePoll();
  }

  /// "Ich bin drin": the proposed next leg becomes the ride.
  Future<void> _confirmLeg(ApiJourneyLive j, ApiLeg leg) async {
    setState(() => _busy = true);
    try {
      await RepoScope.read(context).repo.confirmLeg(j.journey.id, leg.tripId);
      if (mounted) context.push(Routes.unterwegs);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Das ging nicht: ${shortError(e)}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _load();
      }
    }
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${s.name} bleibt still. Ändern in den Einstellungen.'),
      ),
    );
  }

  /// The same path Konto takes: draft for the ready desk, then the five steps.
  Future<void> _prepareClaim(String desk) async {
    final session = RepoScope.read(context);
    setState(() => _busy = true);
    try {
      final draft = await session.repo.draftClaim(desk: desk);
      if (!mounted) return;
      await context.push(
        '${Routes.antrag}?id=${draft.claim.id}&desk=${Uri.encodeComponent(desk)}',
        extra: draft,
      );
      if (mounted) _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Antrag nicht möglich: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    final journey = _journey;
    final transfer = journey?.journey.inTransfer == true;
    final riding =
        !transfer &&
        (journey?.journey.riding == true ||
            _live?.ride.status == ApiRideStatus.riding);
    final arrived =
        !transfer &&
        !riding &&
        (journey?.journey.arrived == true ||
            (_live != null && _live!.ride.status == ApiRideStatus.arrived));
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
                const VStationClock(size: 32),
                const SizedBox(width: 4),
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

            // 1 · Action, sized by the moment.
            if (_loading && _live == null && journey == null)
              const LoadingLine(label: 'Bahnsteig wird geladen …')
            else if (transfer)
              _TransferBlock(
                live: journey!,
                busy: _busy,
                onConfirm: (leg) => _confirmLeg(journey, leg),
              )
            else if (riding && (_live != null || journey?.asRideLive != null))
              _RidingBlock(
                live: _live ?? journey!.asRideLive!,
                journey: journey?.journey,
              )
            else if (arrived && (_live != null || journey?.asRideLive != null))
              _ArrivedBlock(
                live: _live ?? journey!.asRideLive!,
                journey: journey?.journey,
                onDismiss: _dismiss,
              )
            else ...[
              const VSection('Einchecken'),
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

            // Three things, nothing else (docs/18): the week, the claims, us.
            const VSection('Deine Woche'),
            _Momentum(standing: st, onTap: () => context.go(Routes.ich)),
            const VGap.l(),
            const VSection('Deine Anträge'),
            _CycleStrip(
              standing: st,
              claims: _claims,
              busy: _busy,
              onOpen: () => context.go(Routes.antraege),
              onClaim: st.money?.readyDesk == null
                  ? null
                  : () => _prepareClaim(st.money!.readyDesk!),
            ),
            const VGap.l(),
            const VSection('Wir'),
            _Community(
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
    final title = !hasPosition
        ? 'Wo bist du?'
        : nearby.stations.isEmpty
        ? 'Kein Bahnhof in der Nähe'
        : 'Nicht am Bahnhof';
    final caption = !hasPosition
        ? 'Ohne Standort wissen wir nicht, ob du an einem Bahnhof stehst.'
        : 'Stehst du an einem Bahnhof, zeigen wir hier die Abfahrten. Bis dahin:';
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
                        TextSpan(text: s.name),
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
                Text(
                  station.name,
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

class _RidingBlock extends StatelessWidget {
  const _RidingBlock({required this.live, this.journey});
  final ApiRideLive live;
  final ApiJourney? journey;

  @override
  Widget build(BuildContext context) {
    final r = live.ride;
    final stops = live.stops;
    final nextName = stops.isEmpty
        ? null
        : stops[(r.passedStops + 1).clamp(0, stops.length - 1)].name;
    final j = journey;
    final dest = j?.destinationStationName ?? r.exitStationName;
    final transferAhead = j != null && j.currentLeg < j.legs.length
        ? j.legs[(j.currentLeg - 1).clamp(0, j.legs.length - 1)].toStationName
        : null;
    return InkWell(
      onTap: () => context.push(Routes.unterwegs),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.all(VSpace.m),
        decoration: BoxDecoration(
          border: Border.all(color: VColors.ink, width: 1.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('UNTERWEGS', style: VText.eyebrow),
            const SizedBox(height: 10),
            Row(
              children: [
                LineBadge(r.line, large: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'nach $dest',
                    style: VText.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                VDelay(
                  r.liveDelayMinutes,
                  size: VDelaySize.medium,
                  cancelled: r.cancelled,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              [
                if (nextName != null) 'Nächster Halt $nextName',
                if (transferAhead != null)
                  'Umstieg $transferAhead'
                else
                  'Ausstieg ${r.exitStationName}',
                if (live.eta != null) 'an ${fmtLocal(live.eta)}',
              ].join(' · '),
              style: VText.caption,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: VOutlineButton(
                    label: 'Zur Fahrt',
                    onTap: () => context.push(Routes.unterwegs),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: VGhostButton(
                    label: 'Zug wechseln',
                    onTap: () => context.push(Routes.unterwegs),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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

/// Between two legs: the connection to confirm with one tap ("Ich bin drin").
class _TransferBlock extends StatelessWidget {
  const _TransferBlock({
    required this.live,
    required this.busy,
    required this.onConfirm,
  });
  final ApiJourneyLive live;
  final bool busy;
  final ValueChanged<ApiLeg> onConfirm;

  @override
  Widget build(BuildContext context) {
    final j = live.journey;
    final next = live.nextLeg ?? j.nextLeg;
    final missed = j.missedConnection || next?.replanned == true;
    return Container(
      padding: const EdgeInsets.all(VSpace.m),
      decoration: BoxDecoration(
        border: Border.all(
          color: missed ? VColors.red : VColors.ink,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(4),
        color: missed ? VColors.redSoft : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            missed ? 'ANSCHLUSS VERPASST' : 'UMSTEIGEN',
            style: VText.eyebrow.copyWith(
              color: missed ? VColors.red : VColors.ink2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${j.transferStationName ?? next?.fromStationName ?? ''} · weiter nach ${j.destinationStationName}',
            style: VText.caption,
          ),
          const SizedBox(height: 10),
          if (next == null)
            Text(
              'Keine Verbindung gefunden. Sag uns, wenn du da bist.',
              style: VText.bodyS,
            )
          else ...[
            Row(
              children: [
                LineBadge(next.line, large: true, cancelled: next.cancelled),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'nach ${next.headsign.isNotEmpty ? next.headsign : next.toStationName}',
                        style: VText.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        [
                          fmtLocal(next.liveDeparture ?? next.plannedDeparture),
                          if (next.platform != null &&
                              next.platform!.isNotEmpty)
                            'Gl. ${next.platform}',
                          if (missed) 'nächste Möglichkeit',
                        ].join(' · '),
                        style: VText.caption,
                      ),
                    ],
                  ),
                ),
                if (next.delayMin > 0)
                  VDelay(next.delayMin, size: VDelaySize.small),
              ],
            ),
            const SizedBox(height: 12),
            VPrimaryButton(
              label: busy ? 'Einen Moment …' : 'Ich bin drin',
              icon: Icons.check,
              onTap: busy ? null : () => onConfirm(next),
            ),
          ],
          const SizedBox(height: 8),
          VGhostButton(
            label: 'Zur Fahrt',
            onTap: () => context.push(Routes.unterwegs),
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
// 3 · The claim cycle (decided 10 September 2026)
// ---------------------------------------------------------------------------

enum _Stage { collecting, ready, submitted, answered }

/// Four steps, the current one in ink, one line beneath it. A ready bundle keeps
/// its button even while another claim is out or was just answered.
class _CycleStrip extends StatelessWidget {
  const _CycleStrip({
    required this.standing,
    required this.claims,
    required this.busy,
    required this.onOpen,
    this.onClaim,
  });
  final ApiStanding standing;
  final List<ApiClaim> claims;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback? onClaim;

  static const _labels = [
    'Sammeln',
    'Antrag bereit',
    'Eingereicht',
    'Bestätigt',
  ];

  @override
  Widget build(BuildContext context) {
    final m = standing.money;
    final now = DateTime.now();
    final out =
        claims
            .where(
              (c) =>
                  c.status == ApiClaimStatus.sent ||
                  c.status == ApiClaimStatus.question,
            )
            .toList()
          ..sort(
            (a, b) =>
                (b.sentAt ?? DateTime(0)).compareTo(a.sentAt ?? DateTime(0)),
          );
    final closed =
        claims
            .where(
              (c) =>
                  (c.status == ApiClaimStatus.accepted ||
                      c.status == ApiClaimStatus.rejected) &&
                  c.sentAt != null &&
                  now.difference(c.sentAt!).inDays <= 60,
            )
            .toList()
          ..sort(
            (a, b) =>
                (b.sentAt ?? DateTime(0)).compareTo(a.sentAt ?? DateTime(0)),
          );
    final recentClosed = closed
        .where(
          (c) =>
              _closedAt(c) != null &&
              now.difference(_closedAt(c)!).inDays <= 14,
        )
        .firstOrNull;
    final ready = m != null && m.ready && onClaim != null;

    final _Stage stage;
    if (out.isNotEmpty) {
      stage = _Stage.submitted;
    } else if (recentClosed != null) {
      stage = _Stage.answered;
    } else if (ready) {
      stage = _Stage.ready;
    } else {
      stage = _Stage.collecting;
    }
    final active = stage.index;
    final answeredLabel = recentClosed?.status == ApiClaimStatus.rejected
        ? 'Abgelehnt'
        : 'Bestätigt';

    String line;
    switch (stage) {
      case _Stage.collecting:
        line = m == null || m.openCents == 0
            ? 'Noch keine Verspätung ab 60 Minuten. Die erste zählt 1,50 €.'
            : 'Noch ${fmtEuro(m.missingCents / 100)} bis zum Antrag · ${fmtEuro(m.openCents / 100)} gesammelt für ${m.ngoName}';
      case _Stage.ready:
        line = 'Bündel bereit · geht an ${m!.ngoName}';
      case _Stage.submitted:
        final c = out.first;
        line = c.status == ApiClaimStatus.question
            ? 'Rückfrage der Bahn · bitte antworten'
            : c.expectedReplyBy != null
            ? 'Antwort bis ${Mock.shortDate(c.expectedReplyBy!.toLocal())} · ${fmtCents(c.amountClaimedCents)} unterwegs'
            : '${fmtCents(c.amountClaimedCents)} unterwegs · Antwort in etwa 4 Wochen';
      case _Stage.answered:
        final c = recentClosed!;
        line = c.status == ApiClaimStatus.rejected
            ? 'Abgelehnt · Widerspruch möglich'
            : '${fmtCents(c.amountConfirmedCents ?? c.amountClaimedCents)} bestätigt · geht an ${m?.ngoName ?? 'deinen Verein'}';
    }

    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: VSpace.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var i = 0; i < 4; i++) ...[
                  if (i > 0)
                    Expanded(
                      child: Container(
                        height: 1,
                        color: i <= active ? VColors.ink : VColors.rule,
                      ),
                    ),
                  _Step(
                    label: i == 3 ? answeredLabel : _labels[i],
                    state: i < active
                        ? _StepState.done
                        : i == active
                        ? _StepState.active
                        : _StepState.ahead,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            if (ready && stage == _Stage.ready)
              VPrimaryButton(
                label: busy
                    ? 'Einen Moment …'
                    : '${fmtEuro(m.openCents / 100)} beantragen',
                icon: Icons.edit_outlined,
                onTap: busy ? null : onClaim,
              )
            else
              Text(
                line,
                style: VText.bodyS.copyWith(color: VColors.ink2),
                maxLines: 2,
              ),
            if (ready && stage != _Stage.ready) ...[
              const SizedBox(height: 10),
              VOutlineButton(
                label: busy
                    ? 'Einen Moment …'
                    : 'Nächstes Bündel · ${fmtEuro(m.openCents / 100)}',
                icon: Icons.edit_outlined,
                onTap: busy ? null : onClaim,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// When the railway answered: the reply date is not on the claim, so the sent date
  /// plus the usual four weeks stands in unless the claim is younger than that.
  static DateTime? _closedAt(ApiClaim c) {
    final sent = c.sentAt;
    if (sent == null) return null;
    final replied = c.expectedReplyBy ?? sent.add(const Duration(days: 28));
    return replied.isBefore(DateTime.now()) ? replied : DateTime.now();
  }
}

enum _StepState { done, active, ahead }

class _Step extends StatelessWidget {
  const _Step({required this.label, required this.state});
  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _StepState.active => VColors.ink,
      _StepState.done => VColors.ink2,
      _StepState.ahead => VColors.ink3,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: state == _StepState.ahead ? Colors.transparent : color,
            border: Border.all(color: color, width: 1.5),
          ),
          child: state == _StepState.active
              ? Center(
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: VColors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                )
              : null,
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: VText.tab.copyWith(
            color: color,
            fontWeight: state == _StepState.active
                ? FontWeight.w700
                : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 5 · Community with my share
// ---------------------------------------------------------------------------

class _Community extends StatelessWidget {
  const _Community({
    required this.standing,
    required this.tick,
    required this.onTap,
  });
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
            ? Text(
                'Wir haben zusammen gewartet. Zahlen folgen.',
                style: VText.caption,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: VText.body.copyWith(color: VColors.ink2),
                      children: [
                        TextSpan(
                          text: '${fmtInt(c.minutesTotal + tick)} Minuten',
                          style: VText.bodyStrong.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const TextSpan(text: ' haben wir gewartet'),
                        if (c.myMinutes > 0)
                          TextSpan(
                            text: ' · ${fmtInt(c.myMinutes)} davon deine',
                          ),
                        const TextSpan(text: '.'),
                      ],
                    ),
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
