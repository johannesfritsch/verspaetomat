import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../mock/mock_data.dart';
import '../../router.dart';
import '../../state/demo_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'ride_widgets.dart';

/// The train's stops as a line. One tap selects, a confirm bar appears.
class ExitStopScreen extends StatefulWidget {
  const ExitStopScreen({super.key, this.departureId});
  final String? departureId;

  @override
  State<ExitStopScreen> createState() => _ExitStopScreenState();
}

class _ExitStopScreenState extends State<ExitStopScreen> {
  late final Departure _departure = departureById(widget.departureId);
  late int _selected = _usualIndex();

  /// The customer's usual stop on this line, pre-highlighted after the second ride.
  int _usualIndex() {
    final i = _departure.stops.indexWhere((s) => s.name.startsWith('Münster'));
    return i > 0 ? i : _departure.stops.length - 1;
  }

  @override
  Widget build(BuildContext context) {
    final state = DemoScope.of(context);
    final exit = _departure.stops[_selected];
    return VScreen(
      eyebrow: 'Wo steigst du aus?',
      title: '${_departure.line} nach ${_departure.destination}',
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ausstieg ${exit.name} · ${fmtTime(exit.planned)}', style: VText.bodySStrong),
          Text('${state.ticket.label} · ${_departure.operator}', style: VText.caption),
          const VGap.m(),
          VPrimaryButton(
            label: 'Einchecken',
            icon: Icons.check,
            onTap: () {
              HapticFeedback.mediumImpact();
              state.checkIn(
                departure: _departure,
                exitStop: exit,
                fromStation: _departure.stops.first.name,
                locationVerified: state.locationMode != LocationMode.never,
              );
              context.go(Routes.unterwegs);
            },
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VGap.s(),
          Text('Der übliche Halt ist vorgewählt. Tipp auf einen anderen.', style: VText.caption),
          const VGap.m(),
          StopLine(
            stops: _departure.stops,
            passed: 0,
            selectedIndex: _selected,
            onSelect: (i) => setState(() => _selected = i),
            delay: _departure.delay,
          ),
        ],
      ),
    );
  }
}
