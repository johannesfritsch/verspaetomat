import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../mock/mock_data.dart' show TicketTypeX;
import '../../repo/app_repository.dart';
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'ride_widgets.dart';

enum _Filter { alle, regio, sbahn, fern }

/// Departures at a station. One thumb. Tap a train, pick the exit stop.
class CheckinScreen extends StatefulWidget {
  const CheckinScreen({super.key, this.stationId, this.stationName});
  final String? stationId;
  final String? stationName;

  @override
  State<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends State<CheckinScreen> {
  _Filter _filter = _Filter.alle;
  String _query = '';
  ApiStation? _station;
  List<ApiDeparture> _departures = const [];
  bool _loading = true;
  String? _error;
  ApiLocation? _position;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repo = RepoScope.read(context).repo;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      currentPosition(timeout: const Duration(seconds: 3)).then((p) {
        if (mounted) setState(() => _position = p);
      });
      var station = _station;
      if (station == null) {
        final nearby = await repo.nearbyStations();
        final byId = widget.stationId == null ? null : nearby.where((s) => s.id == widget.stationId).firstOrNull;
        station = byId ??
            (widget.stationId != null
                ? ApiStation(id: widget.stationId!, name: widget.stationName ?? widget.stationId!)
                : (nearby.isNotEmpty ? nearby.first : null));
        if (station == null) throw StateError('Kein Bahnhof gewählt.');
      }
      final deps = await repo.departures(station.id);
      if (!mounted) return;
      setState(() {
        _station = station;
        _departures = deps;
      });
    } catch (e) {
      if (mounted) setState(() => _error = shortError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ApiDeparture> get _filtered => _departures.where((d) {
        final okFilter = switch (_filter) {
          _Filter.alle => true,
          _Filter.regio => d.category == ApiCategory.re || d.category == ApiCategory.rb,
          _Filter.sbahn => d.category == ApiCategory.s,
          _Filter.fern => d.category == ApiCategory.fern,
        };
        final q = _query.trim().toLowerCase();
        final okQuery = q.isEmpty || d.line.toLowerCase().contains(q) || d.destination.toLowerCase().contains(q);
        return okFilter && okQuery;
      }).toList();

  void _toExit(ApiDeparture d) {
    final s = _station!;
    context.push('${Routes.exitStop}?departure=${Uri.encodeComponent(d.tripId)}&station=${Uri.encodeComponent(s.id)}&name=${Uri.encodeComponent(s.name)}');
  }

  @override
  Widget build(BuildContext context) {
    final session = RepoScope.of(context);
    final ticket = session.me?.settings.ticket;
    final verified = _position != null;
    final name = _station?.name ?? widget.stationName ?? 'Bahnhof';

    return VScreen(
      scroll: false,
      padding: EdgeInsets.zero,
      bottom: InkWell(
        onTap: () => showTicketSheet(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.confirmation_number_outlined, size: 20, color: VColors.ink2),
              const SizedBox(width: 10),
              Expanded(child: Text(ticket?.label ?? 'Ticket wählen', style: VText.bodySStrong)),
              const Icon(Icons.expand_more, size: 20, color: VColors.ink2),
            ],
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(VSpace.page, 0, VSpace.page, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: VText.h1, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text('${fmtLocal(DateTime.now())} Uhr', style: VText.caption),
                    Text(' · ', style: VText.caption),
                    Icon(verified ? Icons.check : Icons.location_off_outlined, size: 14, color: verified ? VColors.green : VColors.ink3),
                    const SizedBox(width: 4),
                    Text(verified ? 'Standort bestätigt' : 'Ohne Standort', style: VText.caption.copyWith(color: verified ? VColors.green : VColors.ink3)),
                  ],
                ),
                const VGap.m(),
                TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(hintText: 'Zugnummer oder Ziel', prefixIcon: Icon(Icons.search, size: 20, color: VColors.ink2)),
                ),
                const VGap.m(),
                Row(
                  children: [
                    for (final f in _Filter.values) ...[
                      _FilterChip(
                        label: switch (f) { _Filter.alle => 'Alle', _Filter.regio => 'RE/RB', _Filter.sbahn => 'S', _Filter.fern => 'Fern' },
                        selected: _filter == f,
                        onTap: () => setState(() => _filter = f),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
                const VGap.s(),
              ],
            ),
          ),
          const VRule(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
              children: [
                if (_loading) const LoadingLine(label: 'Abfahrten werden geladen …'),
                if (_error != null) ...[
                  const VGap.m(),
                  const OfflineBanner(),
                  ErrorLine(message: 'Keine Live-Daten für diesen Bahnhof. $_error', onRetry: _load),
                ],
                for (final d in _filtered) DepartureRow(departure: d, onTap: () => d.cancelled ? _cancelledFlow(context, d) : _toExit(d)),
                if (!_loading && _error == null && _filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: VSpace.xl),
                    child: Text(
                      _departures.isEmpty ? 'Gerade keine Abfahrten. Zieh nach unten oder versuch es gleich noch mal.' : 'Kein Zug passt. Versuch es ohne Filter.',
                      style: VText.bodyS.copyWith(color: VColors.ink2),
                    ),
                  ),
                const VGap.xl(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// E1: a cancelled train. Ask what the customer took instead.
  void _cancelledFlow(BuildContext context, ApiDeparture cancelled) {
    final later = _departures.where((d) => !d.cancelled && !d.scheduledDeparture.isBefore(cancelled.scheduledDeparture)).take(4).toList();
    showVSheet(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(bottom: VSpace.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VSheetHeader(title: '${cancelled.line} fällt aus.', subtitle: 'Wann fährst du stattdessen?'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
              child: Column(
                children: [
                  for (final d in later)
                    DepartureRow(
                      departure: d,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _toExit(d);
                      },
                    ),
                ],
              ),
            ),
            const VGap.m(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
              child: VGhostButton(
                label: 'Ich fahre gar nicht',
                icon: Icons.cancel_outlined,
                onTap: () {
                  Navigator.of(ctx).pop();
                  _notTravelling(cancelled);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
              child: Text('„Reise nicht angetreten“ ist ein gültiger Antragsgrund. Wir rechnen 60 Minuten an.', style: VText.caption),
            ),
          ],
        ),
      ),
    );
  }

  /// Check in to the cancelled trip and close it at once as "not travelled".
  Future<void> _notTravelling(ApiDeparture cancelled) async {
    final repo = RepoScope.read(context).repo;
    final s = _station!;
    try {
      final trip = await repo.trip(cancelled.tripId);
      final from = fromIndex(trip.stops, s.id, s.name);
      final exit = trip.stops.isEmpty ? null : trip.stops.last;
      await repo.checkIn(CheckInRequest(
        tripId: cancelled.tripId,
        fromStationId: s.id,
        fromStationName: s.name,
        exitStationId: exit?.stationId ?? exit?.name ?? cancelled.destination,
        exitStationName: exit?.name ?? cancelled.destination,
        location: _position,
      ));
      final _ = from;
      final result = await repo.arrival(const ArrivalRequest(delayMinutes: 60, cancelled: true));
      if (mounted) context.go(Routes.angekommen, extra: result);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Das ging nicht: ${shortError(e)}')));
    }
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? VColors.ink : Colors.transparent,
          border: Border.all(color: selected ? VColors.ink : VColors.rule),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label, style: VText.bodySStrong.copyWith(color: selected ? VColors.paper : VColors.ink)),
      ),
    );
  }
}
