import 'package:flutter/material.dart';

import '../../repo/app_repository.dart';
import '../../theme/tokens.dart';

// The screen that used to live here is gone: every check-in runs the sheets in
// `checkin_flow.dart` (docs/29). `DestinationButton` stays — the Wohin? sheet uses it.

/// A predicted destination as a one-tap button: label ("Nach Hause") and station.
class DestinationButton extends StatelessWidget {
  const DestinationButton({super.key, required this.destination, required this.onTap, this.primary = false});
  final ApiDestination destination;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final label = destination.label;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: VSpace.m, vertical: 14),
        decoration: BoxDecoration(
          color: primary ? VColors.ink : VColors.paperElevated,
          border: Border.all(color: primary ? VColors.ink : VColors.rule, width: 1.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(label == 'Nach Hause' ? Icons.home_outlined : Icons.place_outlined, size: 22, color: primary ? VColors.paper : VColors.ink),
            const SizedBox(width: 12),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: VText.bodyStrong.copyWith(color: primary ? VColors.paper : VColors.ink),
                  children: [
                    if (label != null) TextSpan(text: '$label · '),
                    TextSpan(text: destination.stationName),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.arrow_forward, size: 20, color: primary ? VColors.paper : VColors.ink2),
          ],
        ),
      ),
    );
  }
}
