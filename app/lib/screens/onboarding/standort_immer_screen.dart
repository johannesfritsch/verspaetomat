import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
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
    // The setting is written BEFORE the dialog, and it is not corrected by the answer. Tapping
    // this button is choosing the reminder; `loc_mode` records that choice, and the OS records
    // what it currently permits — two different facts.
    //
    // Reading the answer instead was the bug that left the layer with nothing registered: iOS
    // grants „Immer" on its own schedule, and `requestPermission` answers after three seconds
    // with whatever `authStatus` says by then, which is usually still „whileInUse". So a person
    // who tapped „Auf „Immer" stellen" and agreed was recorded as while-using — and
    // `nudges_enabled` (handlers.rs) needs `always`, so the server replied `enabled: false` and
    // `configure` registered zero regions. `location_nudge.dart` has always done it this way.
    //
    // If the phone really does grant less, the Bahnsteig card says so and offers the upgrade.
    await session.updateSettings(const MePatch(locationMode: LocationMode.always));
    await GeofenceSync.requestFor(LocationMode.always);
    if (!mounted) return;
    setState(() => _busy = false);
    if (mounted) _onward();
  }

  void _onward() => context.go(Routes.ready);

  @override
  Widget build(BuildContext context) {
    return SetupStep(
      onBack: () => context.go(Routes.location),
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
