import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../repo/app_repository.dart';
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'ride_widgets.dart';

/// Home. Three stacked blocks: the state of now, your numbers, the community line.
class BahnsteigScreen extends StatefulWidget {
  const BahnsteigScreen({super.key});

  @override
  State<BahnsteigScreen> createState() => _BahnsteigScreenState();
}

class _BahnsteigScreenState extends State<BahnsteigScreen> {
  bool _nudgeDismissed = false;
  ApiLocation? _position;
  List<ApiStation> _stations = const [];
  ApiRideLive? _live;
  ApiIncidents? _incidents;
  ApiCommunity? _community;
  bool _loading = true;
  String? _error;
  Timer? _poll;
  Timer? _ticker;
  int _minuteTick = 0;
  AppRepository? _lastRepo;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && _community != null) setState(() => _minuteTick += 1 + DateTime.now().second % 3);
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
    _poll?.cancel();
    _ticker?.cancel();
    super.dispose();
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
        repo.incidents(),
        repo.community(),
      ]);
      if (!mounted) return;
      setState(() {
        _stations = results[0] as List<ApiStation>;
        _live = results[1] as ApiRideLive?;
        _incidents = results[2] as ApiIncidents;
        _community = results[3] as ApiCommunity;
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
      if (mounted) setState(() => _live = live);
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

  ApiStation? get _nearStation {
    final p = _position;
    if (p == null || _stations.isEmpty) return null;
    final s = _stations.first;
    final d = s.distanceM;
    if (d != null) return d <= 300 ? s : null;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final session = RepoScope.of(context);
    final me = session.me;
    final riding = _live?.ride.status == ApiRideStatus.riding;
    final arrived = _live != null && _live!.ride.status == ApiRideStatus.arrived;
    final near = _nearStation;
    final showNudge = !riding && !arrived && !_nudgeDismissed && near != null;
    final now = DateTime.now();
    final open = _incidents?.incidents.where((i) => i.isOpen).toList() ?? const [];
    final openCents = open.fold(0, (s, i) => s + i.amountCents);
    final ready = _incidents?.summary.readyDesk != null;

    return VScreen(
      showBack: false,
      padding: const EdgeInsets.fromLTRB(VSpace.page, VSpace.s, VSpace.page, VSpace.l),
      child: RefreshIndicator(
        onRefresh: _load,
        color: VColors.ink,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('${fmtDay(now)} · ${fmtLocal(now)}', style: VText.caption)),
                const VStationClock(size: 32),
              ],
            ),
            if (_error != null) ...[const VGap.m(), OfflineBanner(stamp: null), ErrorLine(message: _error!, onRetry: _load)],
            if (showNudge) ...[
              const VGap.m(),
              NudgeBanner(
                station: near.name,
                onCheckIn: () => _openStation(near),
                onDismiss: () => setState(() => _nudgeDismissed = true),
              ),
            ],
            const VGap.l(),
            if (_loading && _live == null)
              const LoadingLine(label: 'Bahnsteig wird geladen …')
            else if (riding)
              _RidingBlock(live: _live!)
            else if (arrived)
              _ArrivedBlock(live: _live!, onDismiss: _dismiss)
            else
              _IdleBlock(stations: _stations, onStation: _openStation, onSearch: _search),
            const VGap.xl(),
            const VSection('Deine Zahlen'),
            InkWell(
              onTap: () => context.go(Routes.konto),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: VSpace.m),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${me?.pointsThisWeek ?? 0}', style: VText.number),
                          const SizedBox(height: 4),
                          Text('Geduldspunkte diese Woche', style: VText.caption),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(fmtEuro(openCents / 100), style: VText.numberM),
                          const SizedBox(height: 4),
                          Text(
                            ready ? '${open.length} Verspätungen · Bündel bereit' : '${open.length} Verspätungen gesammelt',
                            style: VText.caption,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const VRule(),
            const VGap.xl(),
            InkWell(
              onTap: () => context.go(Routes.wir),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('WIR', style: VText.eyebrow),
                  const SizedBox(height: 8),
                  if (_community == null)
                    Text('Wir haben zusammen gewartet. Zahlen folgen.', style: VText.body.copyWith(color: VColors.ink2))
                  else
                    RichText(
                      text: TextSpan(
                        style: VText.body.copyWith(color: VColors.ink2),
                        children: [
                          const TextSpan(text: 'Wir haben zusammen '),
                          TextSpan(
                            text: '${fmtInt(_community!.minutes + _minuteTick)} Minuten',
                            style: VText.bodyStrong.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                          ),
                          const TextSpan(text: ' gewartet und '),
                          TextSpan(text: fmtEuroWhole(_community!.confirmedCents / 100), style: VText.bodyStrong),
                          const TextSpan(text: ' bestätigt.'),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const VGap.l(),
            Center(child: VGhostButton(label: 'Gestern vergessen einzuchecken?', color: VColors.ink2, onTap: () => context.push(Routes.nachtrag))),
          ],
        ),
      ),
    );
  }

  void _openStation(ApiStation s) {
    context.push('${Routes.checkin}?station=${Uri.encodeComponent(s.id)}&name=${Uri.encodeComponent(s.name)}');
  }

  Future<void> _search() async {
    final s = await showStationSearch(context);
    if (s != null && mounted) _openStation(s);
  }
}

class _IdleBlock extends StatelessWidget {
  const _IdleBlock({required this.stations, required this.onStation, required this.onSearch});
  final List<ApiStation> stations;
  final ValueChanged<ApiStation> onStation;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Center(child: VStationClock(size: 140, animated: true)),
        const VGap.l(),
        Text('Kein Zug. Gut so.', style: VText.h1),
        const VGap.s(),
        Text('Wenn du an einem Bahnhof stehst, sagen wir Bescheid.', style: VText.bodyS.copyWith(color: VColors.ink2)),
        const VGap.m(),
        if (stations.isEmpty)
          Text('Kein Bahnhof in der Nähe gefunden. Such einen.', style: VText.caption)
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in stations.take(4))
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
                        if (s.distanceM != null) TextSpan(text: ' · ${_dist(s.distanceM!)}', style: VText.caption),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        const VGap.m(),
        TextField(
          readOnly: true,
          onTap: onSearch,
          decoration: const InputDecoration(
            hintText: 'Bahnhof suchen',
            prefixIcon: Icon(Icons.search, size: 20, color: VColors.ink2),
          ),
        ),
      ],
    );
  }

  static String _dist(int m) => m < 1000 ? '$m m' : '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
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
