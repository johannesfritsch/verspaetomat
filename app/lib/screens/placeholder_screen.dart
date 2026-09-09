import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/kit.dart';

/// Stands in for a screen that is not built yet.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title, this.note});
  final String title;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return VScreen(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VGap.xl(),
          const VStationClock(size: 64),
          const VGap.l(),
          Text('Noch nicht gebaut.', style: VText.h2),
          const VGap.s(),
          Text(note ?? 'Dieser Screen ist in docs/11-screens.md beschrieben.', style: VText.body.copyWith(color: VColors.ink2)),
        ],
      ),
    );
  }
}
