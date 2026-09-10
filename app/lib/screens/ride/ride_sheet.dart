import 'package:flutter/material.dart';

import '../../state/ride_monitor.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'ride_widgets.dart';
import 'unterwegs_screen.dart';

/// The ride's presence while the sheet is closed (docs/19 §5): a 56 px strip docked
/// above the bottom nav on every tab. Riding: line, headsign, delay, next stop. Transfer:
/// the next train, the station, "Ich bin drin". Tapping it opens the sheet.
class RideBar extends StatelessWidget {
  const RideBar({super.key, required this.monitor});
  final RideMonitor monitor;

  static const height = 56.0;

  @override
  Widget build(BuildContext context) {
    final m = monitor;
    final content = m.transfer ? _transfer(context) : _riding(context);
    return Material(
      color: VColors.paperElevated,
      child: InkWell(
        key: const Key('ride-bar'),
        onTap: m.openSheet,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: VSpace.m),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: VColors.rule))),
          child: content,
        ),
      ),
    );
  }

  Widget _riding(BuildContext context) {
    final live = monitor.rideLive;
    final r = live?.ride;
    if (r == null) return const SizedBox.shrink();
    final stops = live!.stops;
    final headsign = stops.isEmpty ? r.exitStationName : stops.last.name;
    final nextIdx = (r.passedStops + fromIndex(stops, r.fromStationId, r.fromStationName)).clamp(0, stops.isEmpty ? 0 : stops.length - 1);
    final next = stops.isEmpty ? null : stops[nextIdx];
    final delay = r.liveDelayMinutes;
    return Row(
      children: [
        LineBadge(r.line, cancelled: r.cancelled),
        const SizedBox(width: 10),
        Flexible(
          child: Text('nach $headsign', style: VText.bodySStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        if (r.cancelled)
          const VChip('Ausfall', tone: VTone.red)
        else if (delay > 0)
          VDelay(delay, size: VDelaySize.small)
        else
          Text('pünktlich', style: VText.caption.copyWith(color: VColors.green)),
        const Spacer(),
        if (next != null)
          Text(
            '${next.name} ${fmtLocal(plannedAt(next)?.add(Duration(minutes: delay)))}',
            style: VText.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
          ),
      ],
    );
  }

  Widget _transfer(BuildContext context) {
    final j = monitor.journey!;
    final next = j.nextLeg ?? j.journey.nextLeg;
    final where = j.journey.transferStationName ?? next?.fromStationName ?? '';
    return Row(
      children: [
        if (next != null) ...[LineBadge(next.line, cancelled: next.cancelled), const SizedBox(width: 10)],
        Expanded(
          child: Text('Umsteigen in $where', style: VText.bodySStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        if (next != null)
          _SmallInkButton(
            label: monitor.busy ? '…' : 'Ich bin drin',
            onTap: monitor.busy ? null : () => monitor.confirmLeg(next),
          ),
      ],
    );
  }
}

class _SmallInkButton extends StatelessWidget {
  const _SmallInkButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: VColors.ink,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(label, style: VText.bodySStrong.copyWith(color: VColors.paper)),
        ),
      ),
    );
  }
}

/// The ride as a draggable bottom sheet over the active tab (docs/19 §5): grab handle,
/// the header pattern, then the Unterwegs body. Snaps at 0.92 and 0.5; dragging it below
/// 0.3 closes it and the bar reappears.
class RideSheetLayer extends StatefulWidget {
  const RideSheetLayer({super.key, required this.monitor});
  final RideMonitor monitor;

  static const full = 0.92;
  static const half = 0.5;
  static const closeBelow = 0.3;

  @override
  State<RideSheetLayer> createState() => _RideSheetLayerState();
}

class _RideSheetLayerState extends State<RideSheetLayer> {
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    widget.monitor.sheetController.addListener(_onSize);
  }

  @override
  void dispose() {
    widget.monitor.sheetController.removeListener(_onSize);
    super.dispose();
  }

  void _onSize() {
    final c = widget.monitor.sheetController;
    if (!c.isAttached || _closing) return;
    if (c.size < RideSheetLayer.closeBelow) {
      _closing = true;
      widget.monitor.closeSheet();
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.monitor;
    final (caption, title) = rideSheetTitle(m);
    return Stack(
      children: [
        // The scrim: a tap outside returns to the tab.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: m.closeSheet,
            child: Container(color: const Color(0x33111111)),
          ),
        ),
        DraggableScrollableSheet(
          controller: m.sheetController,
          initialChildSize: RideSheetLayer.full,
          minChildSize: 0,
          maxChildSize: RideSheetLayer.full,
          snap: true,
          snapSizes: const [RideSheetLayer.half, RideSheetLayer.full],
          builder: (context, scroll) => Material(
            key: const Key('ride-sheet'),
            color: VColors.paperElevated,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            clipBehavior: Clip.antiAlias,
            child: ListView(
              controller: scroll,
              padding: EdgeInsets.zero,
              children: [
                // Grab handle, then the header pattern (caption + h2), like every sub-screen.
                Padding(
                  key: const Key('ride-sheet-handle'),
                  padding: const EdgeInsets.fromLTRB(VSpace.page, 10, VSpace.page, VSpace.m),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(color: VColors.rule, borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(caption, style: VText.caption),
                                Text(title, style: VText.h2, maxLines: 2, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          VIconButton(icon: Icons.expand_more, onTap: m.closeSheet, color: VColors.ink2),
                        ],
                      ),
                    ],
                  ),
                ),
                RideSheetBody(monitor: m),
                SizedBox(height: MediaQuery.paddingOf(context).bottom + VSpace.l),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
