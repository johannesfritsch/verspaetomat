import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../repo/app_repository.dart';
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'ride_widgets.dart';

/// The ride. Glanced at, not read. The number is the whole screen.
class UnterwegsScreen extends StatefulWidget {
  const UnterwegsScreen({super.key});

  @override
  State<UnterwegsScreen> createState() => _UnterwegsScreenState();
}

class _UnterwegsScreenState extends State<UnterwegsScreen> {
  ApiRideLive? _live;
  bool _loading = true;
  bool _stale = false;
  DateTime? _stamp;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    final repo = RepoScope.read(context).repo;
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final live = await repo.currentRide();
      if (!mounted) return;
      final wasRiding = _live?.ride.status == ApiRideStatus.riding;
      setState(() {
        _live = live;
        _stale = false;
        _stamp = DateTime.now();
        _error = null;
      });
      // The ride ended while we were watching: the reveal, once.
      if (wasRiding && live != null && live.ride.status == ApiRideStatus.arrived && mounted) {
        context.go(Routes.angekommen);
        return;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _stale = true;
          if (_live == null) _error = shortError(e);
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
      _poll?.cancel();
      if (mounted && _live?.ride.status == ApiRideStatus.riding) {
        _poll = Timer(const Duration(seconds: 20), () => _load(quiet: true));
      }
    }
  }

  Future<void> _simulateArrival() async {
    final repo = RepoScope.read(context).repo;
    try {
      final result = await repo.arrival(const ArrivalRequest(delayMinutes: 68));
      if (mounted) context.go(Routes.angekommen, extra: result);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ankunft nicht möglich: ${shortError(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = RepoScope.of(context);
    final live = _live;
    if (!_loading && (live == null || live.ride.status != ApiRideStatus.riding)) {
      return _NotRiding(error: _error, onRetry: _load, arrived: live?.ride.status == ApiRideStatus.arrived);
    }
    if (live == null) {
      return VScreen(title: 'Unterwegs', child: const LoadingLine(label: 'Fahrt wird geladen …'));
    }

    final r = live.ride;
    final stops = live.stops;
    final exitIndex = stops.isEmpty ? -1 : fromIndex(stops, r.exitStationId, r.exitStationName);
    final delay = r.liveDelayMinutes;
    final planned = r.plannedArrival ?? (exitIndex >= 0 ? plannedAt(stops[exitIndex]) : null);
    final eta = live.eta ?? planned?.add(Duration(minutes: delay));
    final stamp = fmtLocal(_stamp);
    final headsign = stops.isEmpty ? r.exitStationName : stops.last.name;

    return VScreen(
      scroll: true,
      trailing: VIconButton(icon: Icons.close, onTap: () => context.go(Routes.bahnsteig)),
      showBack: false,
      // Demo mode fakes the world from here. In local mode the Stellwerk on the backend does.
      bottom: session.isLocal
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
            ),
      child: Column(
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
          Text(r.operator, style: VText.caption),
          const VGap.xl(),
          Opacity(
            opacity: _stale ? 0.45 : 1,
            child: VDelay(delay, size: VDelaySize.display, cancelled: r.cancelled),
          ),
          const VGap.m(),
          Text(
            delay > 0 ? 'Ankunft ${r.exitStationName} ${fmtLocal(eta)} statt ${fmtLocal(planned)}' : 'Ankunft ${r.exitStationName} ${fmtLocal(planned)}',
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
          const VGap.l(),
          const VRule(),
          const VGap.m(),
          Text(
            _stale ? 'Letzter Stand $stamp · Verbindung fehlt.' : 'Stand $stamp · Wir folgen dem Zug, nicht dir.',
            style: VText.caption,
          ),
          if (delay >= 60) ...[
            const VGap.xs(),
            Text('Ab hier entsteht ein Anspruch.', style: VText.captionInk),
          ],
          const VGap.l(),
          VGhostButton(label: 'Falscher Zug?', color: VColors.ink2, onTap: () => _wrongTrain(context, r)),
        ],
      ),
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
            arrived ? 'Die letzte Fahrt ist abgeschlossen. Schau sie dir an.' : 'Check am Bahnsteig ein, dann siehst du hier die Fahrt.',
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
