import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../mock/mock_data.dart' show Mock;
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import '../claims/claims_widgets.dart';
import 'community_widgets.dart';

/// All rides, grouped by day, filterable by line.
class HistorieScreen extends StatefulWidget {
  const HistorieScreen({super.key});

  @override
  State<HistorieScreen> createState() => _HistorieScreenState();
}

class _HistorieScreenState extends State<HistorieScreen> {
  String? _line;

  @override
  Widget build(BuildContext context) {
    return Loader<List<ApiRide>>(
      load: (repo) => repo.rides(),
      builder: (context, all, refresh) {
        final lines = all.map((r) => r.line).toSet().toList()..sort();
        final rides = all.where((r) => _line == null || r.line == _line).toList();
        final groups = <String, List<ApiRide>>{};
        for (final r in rides) {
          groups.putIfAbsent(Mock.shortDate(r.date), () => []).add(r);
        }
        final total = rides.fold(0, (s, r) => s + (r.finalDelayMinutes ?? 0));

        return VScreen(
          title: 'Alle Fahrten',
          eyebrow: 'Historie',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const VGap.s(),
              FilterChips(options: lines, selected: _line, onSelect: (v) => setState(() => _line = v)),
              const VGap.m(),
              Text('${rides.length} Fahrten · ${fmtInt(total)} Minuten gewartet', style: VText.caption),
              const VGap.m(),
              for (final entry in groups.entries) ...[
                VSection(entry.key),
                for (final r in entry.value) _rideRow(r),
                const VGap.m(),
              ],
              if (rides.isEmpty) Text(all.isEmpty ? 'Noch keine Fahrten.' : 'Keine Fahrten für diesen Filter.', style: VText.body.copyWith(color: VColors.ink2)),
            ],
          ),
        );
      },
    );
  }

  Widget _rideRow(ApiRide r) {
    final riding = r.status == ApiRideStatus.riding;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              SizedBox(width: 64, child: Text(r.line, style: VText.bodyStrong)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${r.fromStationName} → ${r.exitStationName}', style: VText.bodyS, overflow: TextOverflow.ellipsis),
                    if (r.cancelled || !r.locationVerified || r.nachtrag || riding) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (riding) const VChip('unterwegs', tone: VTone.ink),
                          if (r.cancelled) const VChip('Ausfall', tone: VTone.red),
                          if (r.nachtrag) const VChip('Nachtrag'),
                          if (!r.locationVerified) const VChip('nicht verifiziert'),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              VDelay(r.finalDelayMinutes ?? r.liveDelayMinutes, size: VDelaySize.small),
            ],
          ),
        ),
        const VRule.soft(),
      ],
    );
  }
}
