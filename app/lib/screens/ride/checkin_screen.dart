import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../mock/mock_data.dart';
import '../../router.dart';
import '../../state/demo_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'ride_widgets.dart';

enum _Filter { alle, regio, sbahn, fern }

/// Departures at a station. One thumb. Tap a train, pick the exit stop.
class CheckinScreen extends StatefulWidget {
  const CheckinScreen({super.key, this.stationId});
  final String? stationId;

  @override
  State<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends State<CheckinScreen> {
  _Filter _filter = _Filter.alle;
  String _query = '';

  Station get _station => Mock.nearbyStations.firstWhere((s) => s.id == widget.stationId, orElse: () => Mock.nearbyStations.first);

  List<Departure> get _departures => Mock.departuresKoelnHbf.where((d) {
        final okFilter = switch (_filter) {
          _Filter.alle => true,
          _Filter.regio => d.category == TrainCategory.re || d.category == TrainCategory.rb,
          _Filter.sbahn => d.category == TrainCategory.s,
          _Filter.fern => d.category == TrainCategory.fern,
        };
        final q = _query.trim().toLowerCase();
        final okQuery = q.isEmpty || d.line.toLowerCase().contains(q) || d.destination.toLowerCase().contains(q);
        return okFilter && okQuery;
      }).toList();

  @override
  Widget build(BuildContext context) {
    final state = DemoScope.of(context);
    final verified = state.locationMode != LocationMode.never;

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
              Expanded(child: Text(state.ticket.label, style: VText.bodySStrong)),
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
                Text(_station.name, style: VText.h1),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text('${fmtTime(TimeOfDay.fromDateTime(Mock.today))} Uhr', style: VText.caption),
                    Text(' · ', style: VText.caption),
                    Icon(verified ? Icons.check : Icons.location_off_outlined, size: 14, color: verified ? VColors.green : VColors.ink3),
                    const SizedBox(width: 4),
                    Text(verified ? 'Standort bestätigt' : 'Ohne Standort', style: VText.caption.copyWith(color: verified ? VColors.green : VColors.ink3)),
                  ],
                ),
                const VGap.m(),
                if (state.offline) ...[
                  const OfflineBanner(),
                  const VGap.m(),
                ],
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
            child: state.offline
                ? _ManualEntry(station: _station)
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
                    children: [
                      for (final d in _departures)
                        DepartureRow(
                          departure: d,
                          onTap: () => d.cancelled ? _cancelledFlow(context, d) : context.push('${Routes.exitStop}?departure=${d.id}'),
                        ),
                      if (_departures.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: VSpace.xl),
                          child: Text('Kein Zug passt. Versuch es ohne Filter.', style: VText.bodyS.copyWith(color: VColors.ink2)),
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
  void _cancelledFlow(BuildContext context, Departure cancelled) {
    final state = DemoScope.read(context);
    final later = Mock.departuresKoelnHbf.where((d) => !d.cancelled && (d.planned.hour * 60 + d.planned.minute) >= (cancelled.planned.hour * 60 + cancelled.planned.minute)).take(4).toList();
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
                        context.push('${Routes.exitStop}?departure=${d.id}');
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
                  state.checkIn(departure: cancelled, exitStop: cancelled.stops.last, fromStation: _station.name);
                  state.simulateArrival(minutes: 60, cancelled: true);
                  context.go('${Routes.angekommen}?variant=ausfall');
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

/// No live data: line, destination, planned departure by hand. Earns points,
/// can be claimed, marked "selbst eingetragen".
class _ManualEntry extends StatefulWidget {
  const _ManualEntry({required this.station});
  final Station station;

  @override
  State<_ManualEntry> createState() => _ManualEntryState();
}

class _ManualEntryState extends State<_ManualEntry> {
  final _line = TextEditingController(text: 'RE 7');
  final _dest = TextEditingController(text: 'Rheine');
  final _time = TextEditingController(text: '07:47');

  @override
  void dispose() {
    _line.dispose();
    _dest.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(VSpace.page, VSpace.l, VSpace.page, VSpace.l),
      children: [
        Text('Keine Live-Daten für diesen Bahnhof.', style: VText.h2),
        const VGap.s(),
        Text('Trag deinen Zug selbst ein. Die Fahrt zählt Punkte und kann beantragt werden, steht dann aber als „selbst eingetragen“ im Antrag.', style: VText.bodyS.copyWith(color: VColors.ink2)),
        const VGap.l(),
        TextField(controller: _line, decoration: const InputDecoration(labelText: 'Linie')),
        const VGap.m(),
        TextField(controller: _dest, decoration: const InputDecoration(labelText: 'Ziel')),
        const VGap.m(),
        TextField(controller: _time, decoration: const InputDecoration(labelText: 'Abfahrt laut Fahrplan')),
        const VGap.l(),
        VPrimaryButton(
          label: 'Weiter',
          onTap: () {
            final parts = _time.text.split(':');
            final h = int.tryParse(parts.first) ?? 7;
            final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
            final planned = TimeOfDay(hour: h, minute: m);
            final manual = Departure(
              id: 'manual',
              line: _line.text.trim().isEmpty ? 'RE 7' : _line.text.trim(),
              destination: _dest.text.trim().isEmpty ? 'Rheine' : _dest.text.trim(),
              planned: planned,
              platform: '–',
              category: TrainCategory.re,
              operator: 'Unbekannt',
              stops: [
                Stop(name: widget.station.name, planned: planned),
                Stop(name: _dest.text.trim().isEmpty ? 'Rheine' : _dest.text.trim(), planned: addMinutes(planned, 95)),
              ],
            );
            DemoScope.read(context).checkIn(departure: manual, exitStop: manual.stops.last, fromStation: widget.station.name, locationVerified: false);
            context.go(Routes.unterwegs);
          },
        ),
      ],
    );
  }
}
