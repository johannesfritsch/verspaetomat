import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../mock/mock_data.dart' show Mock;
import '../../repo/repo_scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import '../claims/claims_widgets.dart';
import '../ride/ride_widgets.dart' show fmtLocal;
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
    return Loader<List<ApiJourney>>(
      load: (repo) => repo.journeys(),
      builder: (context, all, refresh) {
        final lines = all.expand((j) => j.legs.map((l) => l.line)).where((l) => l.isNotEmpty).toSet().toList()..sort();
        final journeys = all.where((j) => _line == null || j.legs.any((l) => l.line == _line)).toList();
        final groups = <String, List<ApiJourney>>{};
        for (final j in journeys) {
          groups.putIfAbsent(Mock.shortDate(j.date), () => []).add(j);
        }
        final counted = journeys.where((j) => !j.neverTravelled).toList();
        final total = counted.fold(0, (s, j) => s + (j.finalDelayMin ?? 0));

        return VScreen(
          title: 'Alle Fahrten',
          eyebrow: 'Historie',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const VGap.s(),
              FilterChips(options: lines, selected: _line, onSelect: (v) => setState(() => _line = v)),
              const VGap.m(),
              Text('${counted.length} Fahrten · ${fmtInt(total)} Minuten gewartet', style: VText.caption),
              const VGap.m(),
              for (final entry in groups.entries) ...[
                VSection(entry.key),
                for (final j in entry.value) _JourneyRow(journey: j, onDeleted: refresh),
                const VGap.m(),
              ],
              if (journeys.isEmpty) Text(all.isEmpty ? 'Noch keine Fahrten.' : 'Keine Fahrten für diesen Filter.', style: VText.body.copyWith(color: VColors.ink2)),
            ],
          ),
        );
      },
    );
  }
}

/// One journey: the lines, origin → destination, the delay at the destination. A tap opens
/// the detail sheet, which is also where a ride is deleted (docs/23 §2).
class _JourneyRow extends StatelessWidget {
  const _JourneyRow({required this.journey, required this.onDeleted});
  final ApiJourney journey;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    final j = journey;
    final open = j.riding || j.inTransfer;
    final chips = <Widget>[
      if (open) const VChip('unterwegs', tone: VTone.ink),
      if (j.cancelled) const VChip('Ausfall', tone: VTone.red),
      if (j.missedConnection) const VChip('Anschluss verpasst', tone: VTone.red),
      if (j.incomplete) const VChip('unvollständig'),
      if (j.gaveUp) const VChip('aufgegeben'),
      if (j.neverTravelled) const VChip('nicht gefahren'),
      if (j.status == ApiJourneyStatus.abandoned && j.endReason == null) const VChip('abgebrochen'),
      if (j.transfers > 0) VChip('${j.transfers}× umsteigen'),
    ];
    return Column(
      children: [
        InkWell(
          key: Key('journey-row-${j.id}'),
          onTap: () => showJourneySheet(context, j, onDeleted: onDeleted),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Text(
                    j.legs.isEmpty ? '–' : j.legs.first.line,
                    style: VText.bodyStrong.copyWith(color: j.neverTravelled ? VColors.ink3 : null),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${j.originStationName} → ${j.destinationStationName}',
                        style: VText.bodyS.copyWith(color: j.neverTravelled ? VColors.ink3 : null),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (chips.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Wrap(spacing: 6, runSpacing: 4, children: chips),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Giving up keeps the waiting (docs/22 §1): the journey has no arrival delay,
                // but its Geduldspunkte are the minutes that were really spent waiting.
                VDelay(j.finalDelayMin ?? (j.gaveUp ? j.points : 0), size: VDelaySize.small, cancelled: j.cancelled),
              ],
            ),
          ),
        ),
        const VRule.soft(),
      ],
    );
  }
}

/// One ride in full: its legs with the times they promised, and the way to get rid of it
/// (docs/23 §2). When the ride is in a sent Antrag the action is there but disabled, with
/// the reason beside it, so it is never a silent absence.
Future<void> showJourneySheet(BuildContext context, ApiJourney j, {required VoidCallback onDeleted}) {
  return showVSheet(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.only(bottom: VSpace.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VSheetHeader(title: '${j.originStationName} → ${j.destinationStationName}', subtitle: '${Mock.shortDate(j.date)} · ${j.lineLabel}'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VGap.s(),
                for (final l in j.legs) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(width: 56, child: Text(l.line, style: VText.captionInk)),
                        Expanded(
                          child: Text(
                            '${l.fromStationName} ${fmtLocal(l.plannedDeparture)} → ${l.toStationName} ${fmtLocal(l.plannedArrival)}',
                            style: VText.caption,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (l.finalDelayMin != null) VDelay(l.finalDelayMin!, size: VDelaySize.small, cancelled: l.cancelled),
                      ],
                    ),
                  ),
                  const VRule.soft(),
                ],
                const VGap.xs(),
                VKeyValue('Ankunft laut Fahrplan', fmtLocal(j.plannedArrival)),
                const VRule(),
                VKeyValue('Tatsächliche Ankunft', fmtLocal(j.actualArrival), strong: true),
                const VRule(),
                VKeyValue('Geduldspunkte', '${j.points}', strong: true),
                const VGap.m(),
                if (j.deletable)
                  VGhostButton(
                    key: const Key('delete-ride'),
                    label: 'Fahrt löschen',
                    icon: Icons.delete_outline,
                    color: VColors.red,
                    onTap: () async {
                      final session = RepoScope.read(context);
                      Navigator.of(ctx).pop();
                      if (!await confirmDeleteRide(context)) return;
                      try {
                        if (j.legacy) {
                          await session.repo.deleteRide(j.id);
                        } else {
                          await session.repo.deleteJourney(j.id);
                        }
                        await session.refresh();
                        onDeleted();
                      } catch (e) {
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ging nicht: $e')));
                      }
                    },
                  )
                else ...[
                  VGhostButton(label: 'Fahrt löschen', icon: Icons.delete_outline, color: VColors.ink3, onTap: null),
                  const SizedBox(height: 2),
                  Text(j.deleteRefusal ?? 'Diese Fahrt steckt in einem eingereichten Antrag.', style: VText.caption),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
