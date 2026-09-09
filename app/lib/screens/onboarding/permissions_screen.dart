import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../../state/demo_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';

/// Two asks. Every path continues. Nothing is gated.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  bool _notifications = false;

  @override
  Widget build(BuildContext context) {
    final state = DemoScope.of(context);
    return VScreen(
      eyebrow: 'Schritt 1 von 2',
      title: 'Zwei Fragen',
      bottom: VPrimaryButton(label: 'Weiter', onTap: () => context.go(Routes.setup)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VGap.m(),
          const VSection('Mitteilungen'),
          const VGap.m(),
          Text('Damit wir dir beim Ankommen sagen können, wie spät es war.', style: VText.body),
          const VGap.m(),
          if (_notifications)
            Row(
              children: [
                const Icon(Icons.check, size: 20, color: VColors.green),
                const SizedBox(width: 8),
                Text('Erlaubt', style: VText.bodySStrong.copyWith(color: VColors.green)),
              ],
            )
          else
            VOutlineButton(
              label: 'Mitteilungen erlauben',
              icon: Icons.notifications_none,
              onTap: () {
                state.notificationsGranted = true;
                setState(() => _notifications = true);
              },
            ),
          const VGap.xl(),
          const VSection('Standort am Bahnhof'),
          const VGap.m(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const VStationClock(size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Wir schauen nur, ob du an einem Bahnhof stehst. Während der Fahrt folgen wir dem Zug, nicht dir.',
                  style: VText.body,
                ),
              ),
            ],
          ),
          const VGap.l(),
          for (final mode in [LocationMode.always, LocationMode.whileUsing, LocationMode.never]) ...[
            VChoiceCard(
              title: _title(mode),
              subtitle: _subtitle(mode),
              selected: state.locationMode == mode,
              onTap: () => state.setLocationMode(mode),
            ),
            const VGap.s(),
          ],
          const VGap.s(),
          Text('Du kannst das jederzeit in den Einstellungen ändern. Alles funktioniert auch ohne.', style: VText.caption),
        ],
      ),
    );
  }

  String _title(LocationMode m) => switch (m) {
        LocationMode.always => 'Auch im Hintergrund',
        LocationMode.whileUsing => 'Nur wenn die App offen ist',
        LocationMode.never => 'Später, ich checke selbst ein',
      };

  String _subtitle(LocationMode m) => switch (m) {
        LocationMode.always => 'Empfohlen für den Bahnsteig-Hinweis. Wir merken, wenn du drei Minuten am Bahnhof stehst.',
        LocationMode.whileUsing => 'Bestätigt deinen Bahnhof beim Einchecken. Kein Hinweis von selbst.',
        LocationMode.never => 'Manuell einchecken, Widget oder Bahnsteig-Screen. Geht genauso gut.',
      };
}
