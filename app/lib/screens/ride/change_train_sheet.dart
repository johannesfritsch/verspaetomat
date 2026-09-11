import 'package:flutter/material.dart';

import '../../repo/app_repository.dart';
import '../../repo/repo_scope.dart';
import '../../state/ride_monitor.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'ride_widgets.dart';
import 'welcher_zug_screen.dart';

/// "Zug wechseln" (docs/24 §2): the passenger got off and took another train, which a journey
/// as one ride had no way back into. The machinery is docs/21 §2's `replan`; this is the one
/// clearly named action for it, instead of hiding it behind "Falscher Zug?", which read like
/// an error report.
///
/// The itineraries run from wherever the passenger is now to the **unchanged** destination.
/// What the confirm does is worked out rather than asked: still at the boarding station with
/// no stop behind them, the leg is replaced (a mis-tap, nothing earned, no interruption);
/// otherwise the leg ends as docs/21 §2 ends it, keeping its Geduldspunkte (docs/22 §1), and
/// the chosen train becomes the next one under the delay ceiling.
Future<void> showChangeTrainSheet(
  BuildContext context, {
  required RideMonitor monitor,
  required String fromStationId,
  required String fromStationName,
  required String toStationId,
  required String toStationName,
}) async {
  final session = RepoScope.read(context);
  await showVSheet<void>(
    context,
    expand: true,
    builder: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const VSheetHeader(
          title: 'Zug wechseln',
          subtitle: 'Ein anderer Zug zum selben Ziel. Ein anderes Ziel wäre eine neue Fahrt.',
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
            child: _ChangeTrainList(
              session: session,
              monitor: monitor,
              fromStationId: fromStationId,
              fromStationName: fromStationName,
              toStationId: toStationId,
              toStationName: toStationName,
              onDone: () => Navigator.of(ctx).pop(),
            ),
          ),
        ),
      ],
    ),
  );
}

class _ChangeTrainList extends StatefulWidget {
  const _ChangeTrainList({
    required this.session,
    required this.monitor,
    required this.fromStationId,
    required this.fromStationName,
    required this.toStationId,
    required this.toStationName,
    required this.onDone,
  });
  final Session session;
  final RideMonitor monitor;
  final String fromStationId;
  final String fromStationName;
  final String toStationId;
  final String toStationName;
  final VoidCallback onDone;

  @override
  State<_ChangeTrainList> createState() => _ChangeTrainListState();
}

class _ChangeTrainListState extends State<_ChangeTrainList> {
  List<ApiItinerary> _itineraries = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plan = await widget.session.repo.planJourney(from: widget.fromStationId, to: widget.toStationId);
      final list = [...plan.itineraries]..sort((a, b) {
        if (a.preferred != b.preferred) return a.preferred ? -1 : 1;
        final da = a.plannedDeparture, db = b.plannedDeparture;
        if (da == null || db == null) return 0;
        return da.compareTo(db);
      });
      if (mounted) setState(() => _itineraries = list);
    } catch (e) {
      if (mounted) setState(() => _error = shortError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick(ApiItinerary it) async {
    final j = widget.monitor.journey?.journey;
    if (j == null || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.session.repo.changeTrain(
        j.id,
        it.legs.first.tripId,
        fromStationId: widget.fromStationId,
        fromStationName: widget.fromStationName,
      );
      await widget.monitor.refresh(quiet: true);
      if (mounted) widget.onDone();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Das ging nicht: ${shortError(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const VGap.s(),
        Text('Ab ${widget.fromStationName} → ${widget.toStationName}', style: VText.bodyStrong),
        const SizedBox(height: 2),
        Text('Deine Geduldspunkte bleiben. Die Verspätung zählt weiter am Ziel.', style: VText.caption),
        const VGap.m(),
        if (_loading) const LoadingLine(label: 'Verbindungen werden geladen …'),
        if (_error != null) ...[const OfflineBanner(), ErrorLine(message: _error!, onRetry: _load)],
        if (!_loading && _error == null && _itineraries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: VSpace.l),
            child: Text(
              'Von hier sehen wir gerade keine Verbindung zum Ziel.',
              style: VText.bodyS.copyWith(color: VColors.ink2),
            ),
          ),
        for (final it in _itineraries) ItineraryRow(itinerary: it, onTap: _sending ? null : () => _pick(it)),
        if (_sending) const LoadingLine(label: 'Wird übernommen …'),
        const VGap.l(),
      ],
    );
  }
}
