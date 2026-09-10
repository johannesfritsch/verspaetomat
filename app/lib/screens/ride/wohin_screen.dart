import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../repo/app_repository.dart';
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'ride_widgets.dart';

/// "Wohin?" (docs/17): the destination first. Predictions on top, recent ones
/// below, search for everything else. Replaces "Wo steigst du aus?": the exit
/// stop follows from the itinerary and is never asked.
///
/// With [firstTripId] the customer tapped a train first; the plan is then
/// filtered to itineraries starting with that train.
class WohinScreen extends StatefulWidget {
  const WohinScreen({super.key, required this.fromStationId, required this.fromStationName, this.fromLat, this.fromLon, this.firstTripId, this.firstLine});
  final String fromStationId;
  final String fromStationName;
  final double? fromLat;
  final double? fromLon;
  final String? firstTripId;
  final String? firstLine;

  @override
  State<WohinScreen> createState() => _WohinScreenState();
}

class _WohinScreenState extends State<WohinScreen> {
  ApiDestinations _dest = ApiDestinations.empty;
  bool _loading = true;
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
      final d = await repo.destinations(from: widget.fromStationId);
      if (mounted) setState(() => _dest = d);
    } catch (e) {
      if (mounted) setState(() => _error = shortError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _pick(ApiStation to) {
    context.push(welcherZugRoute(
      fromId: widget.fromStationId,
      fromName: widget.fromStationName,
      to: to,
      lat: widget.fromLat,
      lon: widget.fromLon,
      firstTripId: widget.firstTripId,
    ));
  }

  Future<void> _search() async {
    final s = await showStationSearch(context);
    if (s != null && mounted) _pick(s);
  }

  @override
  Widget build(BuildContext context) {
    final predicted = _dest.predicted.where((d) => d.stationId != widget.fromStationId).toList();
    final recent = _dest.recent.where((d) => d.stationId != widget.fromStationId && !predicted.any((p) => p.stationId == d.stationId)).toList();
    final viaTrain = widget.firstLine != null;

    return VScreen(
      eyebrow: viaTrain ? 'Mit ${widget.firstLine} ab ${widget.fromStationName}' : 'Ab ${widget.fromStationName}',
      title: 'Wohin?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VGap.s(),
          if (_loading) const LoadingLine(label: 'Deine Ziele werden geladen …'),
          if (_error != null) ErrorLine(message: _error!, onRetry: _load),
          if (!_loading && predicted.isEmpty && recent.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: VSpace.m),
              child: Text('Beim ersten Mal suchst du dein Ziel. Ab dann steht es hier.', style: VText.body.copyWith(color: VColors.ink2)),
            ),
          if (predicted.isNotEmpty) ...[
            for (final d in predicted) ...[
              DestinationButton(destination: d, primary: identical(d, predicted.first), onTap: () => _pick(d.station)),
              const VGap.s(),
            ],
            const VGap.s(),
          ],
          if (recent.isNotEmpty) ...[
            const VSection('Zuletzt'),
            for (final d in recent) VListRow(title: d.stationName, chevron: true, onTap: () => _pick(d.station)),
            const VGap.m(),
          ],
          VOutlineButton(label: 'Bahnhof suchen', icon: Icons.search, onTap: _search),
          const VGap.m(),
          Text('Der Ausstieg ergibt sich aus der Verbindung. Wir fragen nicht danach.', style: VText.caption),
        ],
      ),
    );
  }
}

/// A predicted destination as a one-tap button: label ("Nach Hause") and station.
class DestinationButton extends StatelessWidget {
  const DestinationButton({super.key, required this.destination, required this.onTap, this.primary = false});
  final ApiDestination destination;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final label = destination.label;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: VSpace.m, vertical: 14),
        decoration: BoxDecoration(
          color: primary ? VColors.ink : VColors.paperElevated,
          border: Border.all(color: primary ? VColors.ink : VColors.rule, width: 1.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(label == 'Nach Hause' ? Icons.home_outlined : Icons.place_outlined, size: 22, color: primary ? VColors.paper : VColors.ink),
            const SizedBox(width: 12),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: VText.bodyStrong.copyWith(color: primary ? VColors.paper : VColors.ink),
                  children: [
                    if (label != null) TextSpan(text: '$label · '),
                    TextSpan(text: destination.stationName),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.arrow_forward, size: 20, color: primary ? VColors.paper : VColors.ink2),
          ],
        ),
      ),
    );
  }
}

/// Route to "Welcher Zug?" with everything the plan needs.
String welcherZugRoute({required String fromId, required String fromName, required ApiStation to, double? lat, double? lon, String? firstTripId}) {
  final coords = lat != null && lon != null && (lat != 0 || lon != 0) ? '&lat=$lat&lon=$lon' : '';
  final first = firstTripId == null ? '' : '&departure=${Uri.encodeComponent(firstTripId)}';
  return '${Routes.welcherZug}?from=${Uri.encodeComponent(fromId)}&fromName=${Uri.encodeComponent(fromName)}&to=${Uri.encodeComponent(to.id)}&toName=${Uri.encodeComponent(to.name)}$coords$first';
}

/// Route to "Wohin?" from a station, optionally with the train the customer tapped.
String wohinRoute({required ApiStation from, ApiDeparture? departure}) {
  final coords = from.lat != 0 || from.lon != 0 ? '&lat=${from.lat}&lon=${from.lon}' : '';
  final first = departure == null ? '' : '&departure=${Uri.encodeComponent(departure.tripId)}&line=${Uri.encodeComponent(departure.line)}';
  return '${Routes.wohin}?station=${Uri.encodeComponent(from.id)}&name=${Uri.encodeComponent(from.name)}$coords$first';
}
