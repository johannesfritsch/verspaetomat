import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../mock/mock_data.dart';
import '../../router.dart';
import '../../state/demo_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'ride_widgets.dart';

/// Home. Three stacked blocks: the state of now, your numbers, the community line.
class BahnsteigScreen extends StatefulWidget {
  const BahnsteigScreen({super.key});

  @override
  State<BahnsteigScreen> createState() => _BahnsteigScreenState();
}

class _BahnsteigScreenState extends State<BahnsteigScreen> {
  bool _nudgeDismissed = false;
  int _communityMinutes = Mock.communityMinutes;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() => _communityMinutes += 3 + DateTime.now().second % 5);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = DemoScope.of(context);
    final showNudge = state.phase == TripPhase.idle && !_nudgeDismissed && state.locationMode == LocationMode.always;

    return VScreen(
      showBack: false,
      padding: const EdgeInsets.fromLTRB(VSpace.page, VSpace.s, VSpace.page, VSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('${Mock.shortDate(Mock.today)} · ${fmtTime(TimeOfDay.fromDateTime(Mock.today))}', style: VText.caption)),
              const VStationClock(size: 32),
            ],
          ),
          if (state.offline) ...[const VGap.m(), const OfflineBanner()],
          if (showNudge) ...[
            const VGap.m(),
            NudgeBanner(
              station: 'Hauptbahnhof',
              onCheckIn: () => context.push('${Routes.checkin}?station=koeln-hbf'),
              onDismiss: () => setState(() => _nudgeDismissed = true),
            ),
          ],
          const VGap.l(),
          switch (state.phase) {
            TripPhase.idle => _IdleBlock(onStation: (id) => context.push('${Routes.checkin}?station=$id')),
            TripPhase.riding => _RidingBlock(state: state),
            TripPhase.arrived => _ArrivedBlock(state: state),
          },
          const VGap.xl(),
          const VSection('Deine Zahlen'),
          InkWell(
            onTap: () => context.go(Routes.konto),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: VSpace.m),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${Mock.pointsThisWeek + DemoScope.of(context).bonusPoints}', style: VText.number),
                        const SizedBox(height: 4),
                        Text('Geduldspunkte diese Woche', style: VText.caption),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fmtEuro(state.openIncidents.fold(0.0, (s, i) => s + i.amount)), style: VText.numberM),
                        const SizedBox(height: 4),
                        Text(
                          state.readyDesk != null
                              ? '${state.openIncidents.length} Verspätungen · Bündel bereit'
                              : '${state.openIncidents.length} Verspätungen gesammelt',
                          style: VText.caption,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const VRule(),
          const VGap.xl(),
          InkWell(
            onTap: () => context.go(Routes.wir),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('WIR', style: VText.eyebrow),
                const SizedBox(height: 8),
                RichText(
                  text: TextSpan(
                    style: VText.body.copyWith(color: VColors.ink2),
                    children: [
                      const TextSpan(text: 'Wir haben zusammen '),
                      TextSpan(text: '${fmtInt(_communityMinutes)} Minuten', style: VText.bodyStrong.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                      const TextSpan(text: ' gewartet und '),
                      TextSpan(text: fmtEuro(Mock.communityConfirmed), style: VText.bodyStrong),
                      const TextSpan(text: ' bestätigt.'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const VGap.l(),
          Center(child: VGhostButton(label: 'Gestern vergessen einzuchecken?', color: VColors.ink2, onTap: () => context.push(Routes.nachtrag))),
        ],
      ),
    );
  }
}

class _IdleBlock extends StatelessWidget {
  const _IdleBlock({required this.onStation});
  final ValueChanged<String> onStation;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Center(child: VStationClock(size: 140, animated: true)),
        const VGap.l(),
        Text('Kein Zug. Gut so.', style: VText.h1),
        const VGap.s(),
        Text('Wenn du an einem Bahnhof stehst, sagen wir Bescheid.', style: VText.bodyS.copyWith(color: VColors.ink2)),
        const VGap.m(),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in Mock.nearbyStations)
              ActionChip(
                onPressed: () => onStation(s.id),
                backgroundColor: VColors.paperElevated,
                side: const BorderSide(color: VColors.rule),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                label: RichText(
                  text: TextSpan(
                    style: VText.bodySStrong,
                    children: [
                      TextSpan(text: s.name),
                      TextSpan(text: ' · ${s.distanceLabel}', style: VText.caption),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const VGap.m(),
        TextField(
          readOnly: true,
          onTap: () => onStation('koeln-hbf'),
          decoration: const InputDecoration(
            hintText: 'Bahnhof suchen',
            prefixIcon: Icon(Icons.search, size: 20, color: VColors.ink2),
          ),
        ),
      ],
    );
  }
}

class _RidingBlock extends StatelessWidget {
  const _RidingBlock({required this.state});
  final DemoState state;

  @override
  Widget build(BuildContext context) {
    final t = state.trip!;
    final stops = t.departure.stops;
    final nextIndex = (state.passedStops + 1).clamp(0, stops.length - 1);
    return InkWell(
      onTap: () => context.push(Routes.unterwegs),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.all(VSpace.m),
        decoration: BoxDecoration(border: Border.all(color: VColors.ink, width: 1.5), borderRadius: BorderRadius.circular(4)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('UNTERWEGS', style: VText.eyebrow),
            const SizedBox(height: 10),
            Row(
              children: [
                LineBadge(t.departure.line, large: true),
                const SizedBox(width: 12),
                Expanded(child: Text('nach ${t.departure.destination}', style: VText.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                VDelay(state.liveDelay, size: VDelaySize.medium),
              ],
            ),
            const SizedBox(height: 10),
            Text('Nächster Halt ${stops[nextIndex].name} · Ausstieg ${t.exitStop.name}', style: VText.caption),
          ],
        ),
      ),
    );
  }
}

class _ArrivedBlock extends StatelessWidget {
  const _ArrivedBlock({required this.state});
  final DemoState state;

  @override
  Widget build(BuildContext context) {
    final delay = state.finalDelay ?? 0;
    return Container(
      padding: const EdgeInsets.all(VSpace.m),
      decoration: BoxDecoration(border: Border.all(color: VColors.rule), borderRadius: BorderRadius.circular(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ANGEKOMMEN', style: VText.eyebrow),
          const SizedBox(height: 10),
          Row(
            children: [
              VDelay(delay, size: VDelaySize.large, cancelled: state.finalCancelled),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  '${state.trip?.exitStop.name ?? ''}\n$delay Geduldspunkte',
                  style: VText.bodyS.copyWith(color: VColors.ink2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: VOutlineButton(label: 'Ansehen', onTap: () => context.push(Routes.angekommen))),
              const SizedBox(width: 10),
              Expanded(child: VGhostButton(label: 'Fertig', onTap: state.dismissArrival)),
            ],
          ),
        ],
      ),
    );
  }
}
