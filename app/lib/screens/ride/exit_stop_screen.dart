import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../mock/mock_data.dart' show TicketTypeX;
import '../../repo/app_repository.dart';
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'ride_widgets.dart';

/// The train's stops as a line. One tap selects, a confirm bar appears.
class ExitStopScreen extends StatefulWidget {
  const ExitStopScreen({super.key, this.tripId, this.fromStationId, this.fromStationName, this.fromLat, this.fromLon});
  final String? tripId;
  final String? fromStationId;
  final String? fromStationName;
  /// The from-station's coordinates, passed through from the check-in list (docs/15).
  final double? fromLat;
  final double? fromLon;

  @override
  State<ExitStopScreen> createState() => _ExitStopScreenState();
}

class _ExitStopScreenState extends State<ExitStopScreen> {
  ApiTrip? _trip;
  int _from = 0;
  int _selected = 0;
  bool _loading = true;
  bool _sending = false;
  String? _error;

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
      if (widget.tripId == null) throw StateError('Kein Zug gewählt.');
      final trip = await repo.trip(widget.tripId!);
      if (trip.stops.isEmpty) throw StateError('Der Zug hat keine Halte im Fahrplan.');
      final from = fromIndex(trip.stops, widget.fromStationId, widget.fromStationName ?? '');
      if (!mounted) return;
      setState(() {
        _trip = trip;
        _from = from;
        _selected = _usualIndex(trip, from);
      });
    } catch (e) {
      if (mounted) setState(() => _error = shortError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The customer's usual stop on this line, pre-highlighted after the second ride.
  int _usualIndex(ApiTrip t, int from) {
    final i = t.stops.indexWhere((s) => s.name.startsWith('Münster'));
    if (i > from) return i;
    return t.stops.length - 1;
  }

  Future<void> _confirm() async {
    final t = _trip!;
    final exit = t.stops[_selected];
    final from = t.stops[_from];
    final repo = RepoScope.read(context).repo;
    setState(() => _sending = true);
    try {
      HapticFeedback.mediumImpact();
      final loc = await currentPosition(timeout: const Duration(seconds: 2));
      await repo.checkIn(CheckInRequest(
        tripId: t.tripId,
        fromStationId: widget.fromStationId ?? from.stationId ?? from.name,
        fromStationName: widget.fromStationName ?? from.name,
        exitStationId: exit.stationId ?? exit.name,
        exitStationName: exit.name,
        location: loc,
        fromLat: widget.fromLat,
        fromLon: widget.fromLon,
      ));
      if (mounted) context.go(Routes.unterwegs);
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Check-in nicht möglich: ${shortError(e)}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = RepoScope.of(context);
    final t = _trip;
    final exit = t == null || t.stops.isEmpty ? null : t.stops[_selected.clamp(0, t.stops.length - 1)];
    final headsign = t == null ? '' : (t.stops.isEmpty ? '' : t.stops.last.name);

    return VScreen(
      eyebrow: 'Wo steigst du aus?',
      title: t == null ? 'Zug wird geladen …' : '${t.line} nach $headsign',
      // docs/22 §5: no bottom bar. The button belongs to the stop it confirms, inside the list.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VGap.s(),
          if (_loading) const LoadingLine(label: 'Halte werden geladen …'),
          if (_error != null) ErrorLine(message: _error!, onRetry: _load),
          if (t != null) ...[
            Text('Tipp auf deinen Ausstieg.', style: VText.bodyStrong),
            const SizedBox(height: 2),
            Text('Der übliche Halt ist vorgewählt.', style: VText.caption),
            const VGap.m(),
            StopLine(
              stops: t.stops,
              passed: _from - 1,
              selectedIndex: _selected,
              firstSelectable: _from + 1,
              showRadios: true,
              onSelect: (i) => setState(() => _selected = i),
              inlineChild: exit == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${session.me?.settings.ticket.label ?? 'Ticket'} · ${t.operator}',
                            style: VText.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          VPrimaryButton(
                            key: const Key('exit-stop-confirm'),
                            label: _sending ? 'Einchecken …' : 'Einchecken',
                            icon: Icons.check,
                            onTap: _sending ? null : _confirm,
                          ),
                        ],
                      ),
                    ),
            ),
            const VGap.xl(),
          ],
        ],
      ),
    );
  }
}
