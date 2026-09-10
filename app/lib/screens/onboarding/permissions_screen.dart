import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../platform/geofence.dart';
import '../../platform/geofence_sync.dart';
import '../../repo/repo_scope.dart';
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
  bool _asked = false;

  @override
  Widget build(BuildContext context) {
    final session = RepoScope.of(context);
    final demo = DemoScope.of(context);
    final locationMode = session.me?.settings.locationMode ?? demo.locationMode;
    return VScreen(
      eyebrow: 'Schritt 1 von 2',
      title: 'Zwei Fragen',
      bottom: VPrimaryButton(
        label: 'Weiter',
        onTap: () async {
          // The preselected "Auch im Hintergrund" asks the OS on the way out, so nobody has to tap twice.
          if (!_asked) await GeofenceSync.requestFor(locationMode);
          if (context.mounted) context.go(Routes.setup);
        },
      ),
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
              onTap: () async {
                // Asks iOS/Android for notification permission and registers with the push
                // service; the token reaches the server through GeofenceSync.
                final granted = GeofenceSync.automation ? true : await Geofence.instance.registerPush();
                await session.updateSettings(MePatch(notifications: granted));
                if (mounted) setState(() => _notifications = granted);
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
              selected: locationMode == mode,
              onTap: () async {
                await session.updateSettings(MePatch(locationMode: mode));
                _asked = true;
                await GeofenceSync.requestFor(mode);
              },
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
        LocationMode.always => 'Empfohlen. Dein Telefon merkt, wenn du an einem deiner Bahnhöfe stehst, auch bei geschlossener App. Kein Tracking, keine Historie.',
        LocationMode.whileUsing => 'Bestätigt deinen Bahnhof beim Einchecken. Kein Hinweis von selbst.',
        LocationMode.never => 'Manuell einchecken, Widget oder Bahnsteig-Screen. Geht genauso gut.',
      };
}
