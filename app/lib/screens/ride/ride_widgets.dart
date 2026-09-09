import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../mock/mock_data.dart';
import '../../router.dart';
import '../../state/demo_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';

/// The line label ("RE 7") as a small ink block, the way boards set it.
class LineBadge extends StatelessWidget {
  const LineBadge(this.line, {super.key, this.cancelled = false, this.large = false});
  final String line;
  final bool cancelled;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 10 : 8, vertical: large ? 5 : 3),
      decoration: BoxDecoration(
        color: cancelled ? VColors.red : VColors.ink,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        line,
        style: (large ? VText.bodyStrong : VText.captionInk).copyWith(
          color: VColors.paper,
          fontWeight: FontWeight.w800,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// One departure in board style: line, destination, planned time, platform, delay.
class DepartureRow extends StatelessWidget {
  const DepartureRow({super.key, required this.departure, required this.onTap});
  final Departure departure;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = departure;
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    fmtTime(d.planned),
                    style: VText.mono.copyWith(
                      color: d.cancelled ? VColors.ink3 : VColors.ink,
                      decoration: d.cancelled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                LineBadge(d.line, cancelled: d.cancelled),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.destination, style: VText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('Gl. ${d.platform} · ${d.operator}', style: VText.caption),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (d.cancelled)
                  const VChip('Ausfall', tone: VTone.red)
                else if (d.delay > 0)
                  VDelay(d.delay, size: VDelaySize.small)
                else
                  Text('pünktlich', style: VText.caption.copyWith(color: VColors.green)),
              ],
            ),
          ),
          const VRule(),
        ],
      ),
    );
  }
}

/// A vertical line of stops: dots joined by a rule. Passed dots are filled,
/// the next one pulses, the exit stop is marked with a ring.
class StopLine extends StatefulWidget {
  const StopLine({
    super.key,
    required this.stops,
    this.passed = -1,
    this.exitIndex,
    this.selectedIndex,
    this.onSelect,
    this.delay = 0,
    this.compact = false,
  });
  final List<Stop> stops;

  /// Index of the last passed stop (-1 = none yet).
  final int passed;
  final int? exitIndex;
  final int? selectedIndex;
  final ValueChanged<int>? onSelect;

  /// Live delay to add to stops after [passed].
  final int delay;
  final bool compact;

  @override
  State<StopLine> createState() => _StopLineState();
}

class _StopLineState extends State<StopLine> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < widget.stops.length; i++) {
      final s = widget.stops[i];
      final isPassed = i <= widget.passed;
      final isNext = i == widget.passed + 1;
      final isExit = widget.exitIndex == i;
      final isSelected = widget.selectedIndex == i;
      final isLast = i == widget.stops.length - 1;
      final afterExit = widget.exitIndex != null && i > widget.exitIndex!;
      final shownDelay = (!isPassed && widget.delay > 0) ? widget.delay : 0;

      final dot = AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final pulse = isNext ? 0.55 + 0.45 * _pulse.value : 1.0;
          return Opacity(
            opacity: afterExit ? 0.35 : pulse,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isPassed ? VColors.ink : VColors.paper,
                border: Border.all(color: isExit || isSelected ? VColors.red : VColors.ink, width: isExit || isSelected ? 3 : 2),
              ),
            ),
          );
        },
      );

      rows.add(
        InkWell(
          onTap: widget.onSelect == null || i == 0 ? null : () => widget.onSelect!(i),
          child: SizedBox(
            height: widget.compact ? 40 : 52,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 28,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(
                        top: i == 0 ? null : 0,
                        bottom: isLast ? null : 0,
                        child: Container(
                          width: 2,
                          height: widget.compact ? 20 : 26,
                          color: afterExit ? VColors.rule : VColors.ink,
                        ),
                      ),
                      if (!isLast && i != 0) Container(width: 2, color: afterExit ? VColors.rule : VColors.ink),
                      if (i == 0 && !isLast)
                        Positioned(top: (widget.compact ? 20 : 26), bottom: 0, child: Container(width: 2, color: VColors.ink)),
                      if (isLast && i != 0)
                        Positioned(top: 0, bottom: (widget.compact ? 20 : 26), child: Container(width: 2, color: afterExit ? VColors.rule : VColors.ink)),
                      dot,
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.name,
                          style: (isExit || isSelected ? VText.bodyStrong : VText.body).copyWith(color: afterExit ? VColors.ink3 : VColors.ink),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isExit && !widget.compact) ...[
                        const VChip('Ausstieg', tone: VTone.red),
                        const SizedBox(width: 10),
                      ],
                      Text(
                        fmtTime(shownDelay > 0 ? addMinutes(s.planned, shownDelay) : s.planned),
                        style: VText.mono.copyWith(
                          color: afterExit ? VColors.ink3 : (shownDelay > 0 ? VColors.red : VColors.ink),
                          fontWeight: isExit ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

/// The station nudge as an in-app banner (the real one is a notification).
class NudgeBanner extends StatelessWidget {
  const NudgeBanner({super.key, required this.station, required this.onCheckIn, required this.onDismiss});
  final String station;
  final VoidCallback onCheckIn;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: VColors.paperElevated,
        border: Border.all(color: VColors.ink, width: 1.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const VStationClock(size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$station? Check dich ein.', style: VText.bodyStrong),
                    Text('Seit 3 Minuten in der Nähe.', style: VText.caption),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onDismiss, child: Text('Heute nicht', style: VText.bodySStrong.copyWith(color: VColors.ink2))),
              const SizedBox(width: 4),
              TextButton(onPressed: onCheckIn, child: Text('Einchecken', style: VText.bodySStrong.copyWith(color: VColors.red))),
            ],
          ),
        ],
      ),
    );
  }
}

/// E8: the app says how old what it shows is.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, this.stamp = '08:41'});
  final String stamp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: VColors.ruleSoft, borderRadius: BorderRadius.circular(4)),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined, size: 18, color: VColors.ink2),
          const SizedBox(width: 10),
          Expanded(child: Text('Offline. Letzter Stand $stamp Uhr. Check-ins werden später abgeglichen.', style: VText.caption)),
        ],
      ),
    );
  }
}

/// The delay figure counting up from zero. Used once, at arrival.
class CountUpDelay extends StatelessWidget {
  const CountUpDelay(this.minutes, {super.key, this.cancelled = false, this.size = VDelaySize.display});
  final int minutes;
  final bool cancelled;
  final VDelaySize size;

  @override
  Widget build(BuildContext context) {
    if (cancelled) return VDelay(0, size: size, cancelled: true);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: minutes.toDouble()),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => VDelay(v.round(), size: size),
    );
  }
}

/// The sheet that switches the ticket type for the next ride.
Future<void> showTicketSheet(BuildContext context) {
  final state = DemoScope.read(context);
  return showVSheet(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.only(bottom: VSpace.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VSheetHeader(title: 'Welches Ticket?', subtitle: 'Entscheidet, was eine Verspätung wert ist.'),
          for (final t in TicketType.values)
            Padding(
              padding: const EdgeInsets.fromLTRB(VSpace.page, VSpace.s, VSpace.page, 0),
              child: ListenableBuilder(
                listenable: state,
                builder: (context, _) => VChoiceCard(
                  title: t.label,
                  subtitle: t.rule,
                  selected: state.ticket == t,
                  onTap: () {
                    state.setTicket(t);
                    Navigator.of(ctx).pop();
                  },
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Finds a departure by id, falling back to the RE 7.
Departure departureById(String? id) => Mock.departuresKoelnHbf.firstWhere((d) => d.id == id, orElse: () => Mock.departuresKoelnHbf.first);

/// Demo shortcut: check in to RE 7 → Münster and go to the ride screen.
void demoCheckInRe7(BuildContext context) {
  final state = DemoScope.read(context);
  final re7 = Mock.departuresKoelnHbf.first;
  final exit = re7.stops.firstWhere((s) => s.name.startsWith('Münster'), orElse: () => re7.stops.last);
  state.checkIn(departure: re7, exitStop: exit, fromStation: Mock.homeStation);
  context.go(Routes.unterwegs);
}
