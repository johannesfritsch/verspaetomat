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
    final content = m.overdue
        ? _stale(context)
        : m.transfer
            ? _transfer(context)
            : _riding(context);
    return Material(
      color: VColors.paperElevated,
      child: InkWell(
        key: const Key('ride-bar'),
        onTap: m.openSheet,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: VSpace.m),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: VColors.hairline, width: VControl.hairline)),
          ),
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
    // Capped at what the railway caused when the journey was interrupted (docs/21 §2).
    final delay = monitor.journey?.journey.cappedDelay(r.liveDelayMinutes) ?? r.liveDelayMinutes;
    return Row(
      children: [
        LineBadge(r.line, cancelled: r.cancelled),
        const SizedBox(width: 10),
        Flexible(
          child: Text('nach $headsign', style: VText.bodySStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        if (r.cancelled)
          const VPill('Ausfall', tone: VPillTone.red)
        else if (delay > 0)
          VDelayPill(delay, unit: false)
        else
          const VPill('pünktlich', tone: VPillTone.green),
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

  /// Hours past the planned arrival and still under way (docs/23 §3): the bar stops reporting
  /// and asks. Nothing is decided here — both answers are the passenger's.
  Widget _stale(BuildContext context) {
    final m = monitor;
    return Row(
      key: const Key('ride-bar-stale'),
      children: [
        // Expanded, not Flexible + Spacer: a Spacer would take half the free width and
        // truncate the question to "Noch unter…".
        Expanded(
          child: Text('Noch unterwegs?', style: VText.bodySStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        _SmallInkButton(
          label: m.busy ? '…' : 'Ich bin da',
          onTap: m.busy ? null : () => m.finish(arrived: true),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: m.busy ? null : () => m.finish(arrived: false),
          borderRadius: BorderRadius.circular(VRadius.button),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Text('Beenden', style: VText.buttonS.copyWith(color: VColors.ink2)),
          ),
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
      color: VColors.red,
      borderRadius: BorderRadius.circular(VRadius.button),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VRadius.button),
        splashColor: VColors.redPressed,
        highlightColor: VColors.redPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: VSpace.md, vertical: VSpace.s),
          child: Text(label, style: VText.buttonS.copyWith(color: VColors.paperElevated)),
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
            child: const ColoredBox(color: VColors.scrim),
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
            borderRadius: const BorderRadius.vertical(top: VRadius.mdR),
            clipBehavior: Clip.antiAlias,
            child: ListView(
              controller: scroll,
              padding: EdgeInsets.zero,
              children: [
                // Grab handle, then the header: an eyebrow over the line you are on, and a round
                // button to put the sheet away. The chevron is a filled circle here rather than a
                // bare glyph, because it is the one control in a header full of text.
                Padding(
                  key: const Key('ride-sheet-handle'),
                  padding: const EdgeInsets.fromLTRB(VSpace.sheet, 10, VSpace.sheet, VSpace.m),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: VColors.handle,
                            borderRadius: BorderRadius.circular(VRadius.full),
                          ),
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
                                Text(caption, style: VText.body),
                                Text(title, style: VText.h2, maxLines: 2, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          const SizedBox(width: VSpace.s),
                          VCircleIconButton(icon: Icons.expand_more, onTap: m.closeSheet),
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
