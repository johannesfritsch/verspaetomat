import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../platform/geofence.dart';
import '../../platform/geofence_sync.dart';
import '../../repo/repo_scope.dart';
import '../../router.dart';
import 'setup_step.dart';

/// Schritt 2 von 3: may we tell you what happens to your rides and your claims? (#43)
///
/// The first of the two permission questions, and asked on its own, because it is the one whose
/// answer is worth something whatever is decided about location. `push.rs` sends the arrival with its delay, the
/// transfer question, „Post von der Bahn", „Verfällt bald" and „Noch keine Antwort", and
/// `push.rs:537` gates every one of them on this single flag. Somebody who never grants location
/// and checks in by hand still wants to know the railway wrote back.
///
/// The old screen made this an outlined button halfway down a page of location cards, and then
/// asked for notifications anyway from inside the location request — so the dialog arrived a
/// screen later whether or not the button was ever pressed.
class MitteilungenScreen extends StatefulWidget {
  const MitteilungenScreen({super.key});

  @override
  State<MitteilungenScreen> createState() => _MitteilungenScreenState();
}

class _MitteilungenScreenState extends State<MitteilungenScreen> {
  bool _busy = false;

  Future<void> _ask() async {
    final session = RepoScope.read(context);
    setState(() => _busy = true);
    // The screen stands still until the system dialog has been answered. That is the whole point
    // of the rebuild: every dialog used to land on the screen after the one that asked.
    final granted = GeofenceSync.automation ? true : await Geofence.instance.registerPush();
    await session.updateSettings(MePatch(notifications: granted));
    if (!mounted) return;
    setState(() => _busy = false);
    _onward();
  }

  Future<void> _decline() async {
    // „Ohne Mitteilungen weiter" is an answer, not a postponement: it is written down so nothing
    // asks again, and so the server stops sending what nobody will see.
    await RepoScope.read(context).updateSettings(const MePatch(notifications: false));
    if (mounted) _onward();
  }

  void _onward() => context.go(Routes.standort);

  @override
  Widget build(BuildContext context) {
    return SetupStep(
      step: 2,
      asset: 'assets/onboarding/setup-mitteilungen.webp',
      title: 'Sollen wir uns melden?',
      busy: _busy,
      body: const [
        SetupText('Wenn du angekommen bist, sagen wir dir, wie spät der Zug war und ob daraus ein Antrag wird.'),
        SetupText('Später melden wir uns, wenn ein Anschluss wackelt, wenn die Bahn auf deinen Antrag antwortet und bevor ein Anspruch verfällt.'),
      ],
      primary: 'Mitteilungen erlauben',
      onPrimary: _busy ? null : _ask,
      secondary: 'Ohne Mitteilungen weiter',
      onSecondary: _busy ? null : _decline,
      footnote: 'Du kannst das jederzeit in den Einstellungen ändern.',
    );
  }
}
