import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../repo/app_repository.dart';
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'ride_widgets.dart';

/// E4: forgot to check in. One point, claimable if the feed shows a delay, never ranks.
class NachtragScreen extends StatefulWidget {
  const NachtragScreen({super.key});

  @override
  State<NachtragScreen> createState() => _NachtragScreenState();
}

class _NachtragScreenState extends State<NachtragScreen> {
  int _dayOffset = 1;
  ApiStation? _station;
  List<ApiDeparture> _departures = const [];
  ApiDeparture? _departure;
  ApiTrip? _trip;
  int _from = 0;
  int _exit = 0;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStation());
  }

  Future<void> _loadStation() async {
    final repo = RepoScope.read(context).repo;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_station == null) {
        final nearby = (await repo.nearbyStations()).stations;
        if (nearby.isEmpty) throw StateError('Kein Bahnhof gefunden. Such einen.');
        _station = nearby.first;
      }
      final deps = (await repo.departures(_station!.id)).where((d) => !d.cancelled).toList();
      if (!mounted) return;
      setState(() {
        _departures = deps;
        _departure = null;
        _trip = null;
      });
      if (deps.isNotEmpty) await _pick(deps.first);
    } catch (e) {
      if (mounted) setState(() => _error = shortError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick(ApiDeparture d) async {
    final repo = RepoScope.read(context).repo;
    setState(() {
      _departure = d;
      _trip = null;
    });
    try {
      final trip = await repo.trip(d.tripId);
      if (!mounted) return;
      final from = fromIndex(trip.stops, _station?.id, _station?.name ?? '');
      setState(() {
        _trip = trip;
        _from = from;
        _exit = trip.stops.length - 1;
      });
    } catch (e) {
      if (mounted) setState(() => _error = shortError(e));
    }
  }

  Future<void> _search() async {
    final s = await showStationSearch(context);
    if (s == null || !mounted) return;
    setState(() => _station = s);
    _loadStation();
  }

  Future<void> _submit() async {
    final t = _trip;
    final s = _station;
    if (t == null || s == null || t.stops.isEmpty) return;
    final exit = t.stops[_exit.clamp(0, t.stops.length - 1)];
    final date = DateTime.now().subtract(Duration(days: _dayOffset));
    setState(() => _sending = true);
    try {
      final result = await RepoScope.read(context).repo.nachtrag(NachtragRequest(
        tripId: t.tripId,
        fromStationId: s.id,
        fromStationName: s.name,
        exitStationId: exit.stationId ?? exit.name,
        exitStationName: exit.name,
        date: date,
      ));
      if (!mounted) return;
      final d = result.ride.finalDelayMinutes ?? 0;
      final delayText = result.ride.cancelled ? 'Ausfall' : (d > 0 ? '+$d am ${exit.name}' : 'pünktlich am ${exit.name}');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nachgetragen: ${t.line}, $delayText · 1 Geduldspunkt.')));
      context.go(Routes.bahnsteig);
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nachtrag nicht möglich: ${shortError(e)}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = DateTime.now().subtract(Duration(days: _dayOffset));
    final t = _trip;
    final canSubmit = t != null && t.stops.isNotEmpty && !_sending;

    return VScreen(
      eyebrow: 'Nachtrag',
      title: 'Gestern vergessen?',
      bottom: VPrimaryButton(label: _sending ? 'Wird nachgetragen …' : 'Nachtragen', onTap: canSubmit ? _submit : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VGap.m(),
          const VSection('Tag'),
          Row(
            children: [
              for (final (offset, label) in [(1, 'Gestern'), (2, 'Vorgestern'), (3, fmtDay(DateTime.now().subtract(const Duration(days: 3))))]) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12, right: 8),
                  child: InkWell(
                    onTap: () => setState(() => _dayOffset = offset),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _dayOffset == offset ? VColors.ink : Colors.transparent,
                        border: Border.all(color: _dayOffset == offset ? VColors.ink : VColors.rule),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(label, style: VText.bodySStrong.copyWith(color: _dayOffset == offset ? VColors.paper : VColors.ink)),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const VGap.s(),
          Text(fmtDay(date), style: VText.caption),
          const VGap.l(),
          VSection('Bahnhof', trailing: InkWell(onTap: _search, child: Padding(padding: const EdgeInsets.all(8), child: Text('Ändern', style: VText.bodySStrong)))),
          const VGap.s(),
          Text(_station?.name ?? '–', style: VText.bodyStrong),
          const VGap.l(),
          const VSection('Zug'),
          if (_loading) const LoadingLine(label: 'Züge werden geladen …'),
          if (_error != null) ErrorLine(message: _error!, onRetry: _loadStation),
          for (final d in _departures.take(8))
            InkWell(
              onTap: () => _pick(d),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        SizedBox(width: 52, child: Text(fmtLocal(d.scheduledDeparture), style: VText.mono)),
                        const SizedBox(width: 10),
                        LineBadgeColumn(child: LineBadge(d.line)),
                        Expanded(child: Text(d.destination, style: VText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _departure?.tripId == d.tripId ? VColors.red : Colors.transparent,
                            border: Border.all(color: _departure?.tripId == d.tripId ? VColors.red : VColors.rule, width: 1.5),
                          ),
                          child: _departure?.tripId == d.tripId ? const Icon(Icons.check, size: 14, color: VColors.paper) : null,
                        ),
                      ],
                    ),
                  ),
                  const VRule(),
                ],
              ),
            ),
          const VGap.l(),
          const VSection('Ausstieg'),
          const VGap.s(),
          if (_departure != null && t == null) const LoadingLine(label: 'Halte werden geladen …'),
          if (t != null)
            StopLine(
              stops: t.stops,
              passed: _from - 1,
              selectedIndex: _exit,
              firstSelectable: _from + 1,
              onSelect: (i) => setState(() => _exit = i),
              compact: true,
            ),
          const VGap.l(),
          Text('Ein Nachtrag bringt einen Geduldspunkt, zählt für Anträge, wenn der Feed eine Verspätung kennt, und taucht nie in Ranglisten auf. Der Fahrplan zeigt die Züge von heute.', style: VText.caption),
        ],
      ),
    );
  }
}
