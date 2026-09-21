import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../flags/flags.dart';
import '../../platform/geofence.dart';
import '../../platform/geofence_sync.dart';
import '../../repo/repo_scope.dart';
import '../../state/demo_state.dart' show LocationMode;
import '../../router.dart';
import 'setup_step.dart';

/// Schritt 2 von 4: may your phone wake up at a station and remind you? (#43)
///
/// One ask, not three cards. „Nur wenn die App offen ist" and „Später, ich checke selbst ein"
/// produced nearly the same day, and the difference between them could not be told in one line —
/// so the screen asks the question it means and lets iOS's own two-step decide the rest.
///
/// Nothing is preselected. The old screen showed „Auch im Hintergrund" with a filled red check
/// before anything had been granted, and in a release build it was not even the selected one:
/// migration 0002 defaults `loc_mode` to `while_using`, so the „Empfohlen" card and the chosen
/// card disagreed.
class StandortScreen extends StatefulWidget {
  const StandortScreen({super.key});

  @override
  State<StandortScreen> createState() => _StandortScreenState();
}

class _StandortScreenState extends State<StandortScreen> {
  bool _busy = false;

  Future<void> _ask() async {
    final session = RepoScope.read(context);
    setState(() => _busy = true);
    // iOS offers „Einmal / Beim Verwenden / Nicht erlauben" on a cold ask and never „Immer", so
    // this asks for what it can actually get and the upgrade gets its own screen.
    final granted = await GeofenceSync.requestFor(LocationMode.whileUsing);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (granted) {
      // While-using in hand: „Immer" is the one thing still missing, and now iOS will offer it.
      case GeofencePermission.whileInUse:
        await session.updateSettings(const MePatch(locationMode: LocationMode.whileUsing));
        if (mounted) context.go(Routes.standortImmer);
      // Already Always (a reinstall, or Android granting both at once): nothing left to ask.
      case GeofencePermission.always:
        await session.updateSettings(const MePatch(locationMode: LocationMode.always));
        if (mounted) _onward();
      case GeofencePermission.denied:
      case GeofencePermission.notDetermined:
        await session.updateSettings(const MePatch(locationMode: LocationMode.never));
        if (mounted) _onward();
    }
  }

  Future<void> _decline() async {
    await RepoScope.read(context).updateSettings(const MePatch(locationMode: LocationMode.never));
    if (mounted) _onward();
  }

  void _onward() => context.go(Routes.zweckWaehlen);

  @override
  Widget build(BuildContext context) {
    final session = RepoScope.of(context);
    // „Nichts verlässt dein Telefon" is true of the background watching only once the phone
    // answers „welche Bahnhöfe sind hier?" from the extract on its own disk. Until `stations_local`
    // is on, that question still goes to our server on every umbrella exit, so the promise is
    // simply absent rather than written and wrong. It arrives the day the behaviour does (#41).
    final local = session.flags.on(Flag.stationsLocal);
    return SetupStep(
      step: 2,
      asset: 'assets/onboarding/setup-standort.webp',
      title: 'Sollen wir dich am Bahnsteig erinnern?',
      busy: _busy,
      body: [
        const SetupText('Dein Telefon merkt, wenn du an einem deiner Bahnhöfe stehst, und erinnert dich ans Einchecken — auch wenn die App zu ist.'),
        SetupText(
          local
              ? 'Wir schauen nur, ob du an einem Bahnhof stehst. Nichts verlässt dein Telefon. Kein Tracking, keine Historie. Während der Fahrt folgen wir dem Zug, nicht dir.'
              : 'Wir schauen nur, ob du an einem Bahnhof stehst. Kein Tracking, keine Historie. Während der Fahrt folgen wir dem Zug, nicht dir.',
        ),
      ],
      primary: 'Standort erlauben',
      onPrimary: _busy ? null : _ask,
      secondary: 'Ich checke selbst ein',
      onSecondary: _busy ? null : _decline,
      footnote: 'Ohne Standort funktioniert alles — du wählst den Bahnhof dann selbst.',
    );
  }
}
