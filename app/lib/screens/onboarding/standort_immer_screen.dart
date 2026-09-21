import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../platform/geofence.dart';
import '../../platform/geofence_sync.dart';
import '../../repo/repo_scope.dart';
import '../../state/demo_state.dart' show LocationMode;
import '../../router.dart';
import 'setup_step.dart';

/// The second state of the Standort question, and the reason it needs one (#43).
///
/// iOS answers a cold location ask with „Einmal / Beim Verwenden der App / Nicht erlauben". There
/// is no „Immer" on that dialog and there cannot be: the upgrade is only offered once While-Using
/// is held. The old screen promised „Auch im Hintergrund" on a card and then showed a dialog
/// without that option, and the upgrade — when it came at all — landed on „Dein Ticket, dein
/// Zweck" two screens later.
///
/// So it is a screen, with a back arrow and no step counter, because it is not a fourth question:
/// it is the rest of the second one.
class StandortImmerScreen extends StatefulWidget {
  const StandortImmerScreen({super.key});

  @override
  State<StandortImmerScreen> createState() => _StandortImmerScreenState();
}

class _StandortImmerScreenState extends State<StandortImmerScreen> {
  bool _busy = false;

  Future<void> _upgrade() async {
    final session = RepoScope.read(context);
    setState(() => _busy = true);
    final granted = await GeofenceSync.requestFor(LocationMode.always);
    if (!mounted) return;
    setState(() => _busy = false);
    // Denied leaves While-Using standing, which is a working answer and not a failure: the
    // station is still confirmed at check-in, only the reminder is missing.
    await session.updateSettings(MePatch(
      locationMode: granted == GeofencePermission.always ? LocationMode.always : LocationMode.whileUsing,
    ));
    if (mounted) _onward();
  }

  void _onward() => context.go(Routes.setup);

  @override
  Widget build(BuildContext context) {
    return SetupStep(
      onBack: () => context.go(Routes.standort),
      asset: 'assets/onboarding/setup-immer.webp',
      title: 'Fast geschafft.',
      busy: _busy,
      body: const [
        SetupText('„Beim Verwenden" bestätigt deinen Bahnhof beim Einchecken. Für die Erinnerung bei geschlossener App braucht dein Telefon „Immer".'),
      ],
      primary: 'Auf „Immer" stellen',
      onPrimary: _busy ? null : _upgrade,
      secondary: 'Reicht mir so',
      onSecondary: _busy ? null : _onward,
      footnote: 'Du kannst das jederzeit in den Einstellungen ändern.',
    );
  }
}
