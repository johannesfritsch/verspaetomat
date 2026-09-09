import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../mock/mock_data.dart';
import '../../router.dart';
import '../../state/demo_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'ride_widgets.dart';

/// The ride. Glanced at, not read. The number is the whole screen.
class UnterwegsScreen extends StatelessWidget {
  const UnterwegsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = DemoScope.of(context);
    if (state.phase != TripPhase.riding || state.trip == null) return const _NotRiding();

    final t = state.trip!;
    final stops = t.departure.stops;
    final exitIndex = stops.indexWhere((s) => s.name == t.exitStop.name);
    final delay = state.liveDelay;
    final eta = addMinutes(t.exitStop.planned, delay);
    final stamp = fmtTime(TimeOfDay.fromDateTime(DateTime.now()));

    return VScreen(
      scroll: true,
      trailing: VIconButton(icon: Icons.close, onTap: () => context.go(Routes.bahnsteig)),
      showBack: false,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: VDemoControl(label: 'Nächster Halt', icon: Icons.skip_next_outlined, onTap: state.tickRide)),
              const SizedBox(width: 8),
              Expanded(
                child: VDemoControl(
                  label: 'Ankunft',
                  icon: Icons.flag_outlined,
                  onTap: () {
                    state.simulateArrival();
                    context.go(Routes.angekommen);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LineBadge(t.departure.line, large: true),
              const SizedBox(width: 12),
              Expanded(child: Text('nach ${t.departure.destination}', style: VText.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 4),
          Text(t.departure.operator, style: VText.caption),
          const VGap.xl(),
          Opacity(
            opacity: state.offline ? 0.45 : 1,
            child: VDelay(delay, size: VDelaySize.display, cancelled: t.departure.cancelled),
          ),
          const VGap.m(),
          Text(
            delay > 0 ? 'Ankunft ${t.exitStop.name} ${fmtTime(eta)} statt ${fmtTime(t.exitStop.planned)}' : 'Ankunft ${t.exitStop.name} ${fmtTime(t.exitStop.planned)}',
            style: VText.body,
          ),
          if (state.liveCause != null) Text(state.liveCause!, style: VText.caption),
          const VGap.l(),
          const VRule.red(),
          const VGap.m(),
          StopLine(
            stops: stops,
            passed: state.passedStops,
            exitIndex: exitIndex < 0 ? null : exitIndex,
            delay: delay,
            compact: true,
          ),
          const VGap.l(),
          const VRule(),
          const VGap.m(),
          Text(
            state.offline ? 'Letzter Stand $stamp · Verbindung fehlt.' : 'Stand $stamp · Wir folgen dem Zug, nicht dir.',
            style: VText.caption,
          ),
          if (delay >= 60) ...[
            const VGap.xs(),
            Text('Ab hier entsteht ein Anspruch.', style: VText.captionInk),
          ],
          const VGap.l(),
          VGhostButton(label: 'Falscher Zug?', color: VColors.ink2, onTap: () => _wrongTrain(context)),
        ],
      ),
    );
  }

  /// E2: pick another departure from the same station within the last 30 minutes.
  void _wrongTrain(BuildContext context) {
    final state = DemoScope.read(context);
    final current = state.trip!.departure;
    final others = Mock.departuresKoelnHbf.where((d) => d.id != current.id && !d.cancelled).toList();
    showVSheet(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(bottom: VSpace.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const VSheetHeader(title: 'Welcher Zug dann?', subtitle: 'Abfahrten der letzten 30 Minuten. Punkte bleiben.'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
              child: Column(
                children: [
                  for (final d in others)
                    DepartureRow(
                      departure: d,
                      onTap: () {
                        state.changeTrain(d);
                        Navigator.of(ctx).pop();
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Calm empty state so the screen is always demonstrable.
class _NotRiding extends StatelessWidget {
  const _NotRiding();

  @override
  Widget build(BuildContext context) {
    return VScreen(
      title: 'Unterwegs',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VGap.xl(),
          const Center(child: VStationClock(size: 96, animated: true)),
          const VGap.l(),
          Text('Gerade kein Zug.', style: VText.h2),
          const VGap.s(),
          Text('Check am Bahnsteig ein, dann siehst du hier die Fahrt.', style: VText.body.copyWith(color: VColors.ink2)),
          const VGap.xl(),
          VDemoControl(label: 'RE 7 nach Münster einchecken', icon: Icons.train_outlined, onTap: () => demoCheckInRe7(context)),
        ],
      ),
    );
  }
}
