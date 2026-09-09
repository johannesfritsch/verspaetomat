import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../mock/mock_data.dart';
import '../../router.dart';
import '../../state/demo_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'ride_widgets.dart';

/// E4: forgot to check in yesterday. One point, claimable, never ranks.
class NachtragScreen extends StatefulWidget {
  const NachtragScreen({super.key});

  @override
  State<NachtragScreen> createState() => _NachtragScreenState();
}

class _NachtragScreenState extends State<NachtragScreen> {
  int _dayOffset = 1;
  Departure _departure = Mock.departuresKoelnHbf.first;
  int _exit = 6;

  @override
  Widget build(BuildContext context) {
    final date = Mock.today.subtract(Duration(days: _dayOffset));
    final trains = Mock.departuresKoelnHbf.where((d) => !d.cancelled).toList();
    final exitIndex = _exit.clamp(1, _departure.stops.length - 1);
    return VScreen(
      eyebrow: 'Nachtrag',
      title: 'Gestern vergessen einzuchecken?',
      bottom: VPrimaryButton(
        label: 'Nachtragen',
        onTap: () {
          final state = DemoScope.read(context);
          final exit = _departure.stops[exitIndex];
          state.addNachtrag(departure: _departure, exitStop: exit, date: date);
          final d = _departure.cancelled ? 60 : _departure.delay;
          final delayText = d > 0 ? '+$d am ${exit.name}' : 'pünktlich am ${exit.name}';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nachgetragen: ${_departure.line}, $delayText · 1 Geduldspunkt.')));
          context.go(Routes.bahnsteig);
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VGap.m(),
          const VSection('Tag'),
          Row(
            children: [
              for (final (offset, label) in [(1, 'Gestern'), (2, 'Vorgestern'), (3, Mock.shortDate(Mock.today.subtract(const Duration(days: 3))))]) ...[
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
          Text(Mock.longDate(date), style: VText.caption),
          const VGap.l(),
          const VSection('Bahnhof'),
          const VGap.s(),
          Text(Mock.homeStation, style: VText.bodyStrong),
          const VGap.l(),
          const VSection('Zug'),
          for (final d in trains)
            InkWell(
              onTap: () => setState(() {
                _departure = d;
                _exit = d.stops.length - 1;
              }),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        SizedBox(width: 52, child: Text(fmtTime(d.planned), style: VText.mono)),
                        const SizedBox(width: 10),
                        LineBadge(d.line),
                        const SizedBox(width: 12),
                        Expanded(child: Text(d.destination, style: VText.bodyStrong)),
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _departure.id == d.id ? VColors.red : Colors.transparent,
                            border: Border.all(color: _departure.id == d.id ? VColors.red : VColors.rule, width: 1.5),
                          ),
                          child: _departure.id == d.id ? const Icon(Icons.check, size: 14, color: VColors.paper) : null,
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
          StopLine(
            stops: _departure.stops,
            passed: 0,
            selectedIndex: exitIndex,
            onSelect: (i) => setState(() => _exit = i),
            compact: true,
          ),
          const VGap.l(),
          Text('Ein Nachtrag bringt einen Geduldspunkt, zählt für Anträge, wenn Verspätungsdaten dazu existieren, und taucht nie in Ranglisten auf.', style: VText.caption),
        ],
      ),
    );
  }
}
