import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../repo/repo_scope.dart';
import 'ride_widgets.dart';
import 'wohin_screen.dart';

/// The raised "Einchecken" square in the bottom nav (decided 10 September 2026).
/// Not a tab: at a station (≤ 300 m) it opens "Wohin?" for that station, predictions
/// first; elsewhere the station choice, then "Wohin?" for the chosen station.
Future<void> startCheckin(BuildContext context) async {
  final repo = RepoScope.read(context).repo;
  ApiStation? near;
  try {
    final pos = await currentPosition(timeout: const Duration(seconds: 3));
    final nearby = await repo.nearbyStations(lat: pos?.lat, lon: pos?.lon);
    near = nearby.stations.where((s) => (s.distanceM ?? 1 << 30) <= 300).fold<ApiStation?>(null, (best, s) => best == null || (s.distanceM ?? 0) < (best.distanceM ?? 0) ? s : best);
  } catch (_) {
    near = null;
  }
  if (!context.mounted) return;
  if (near != null) {
    context.push(wohinRoute(from: near));
    return;
  }
  final chosen = await showStationSearch(context);
  if (chosen != null && context.mounted) context.push(wohinRoute(from: chosen));
}
