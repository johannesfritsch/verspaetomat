import 'package:flutter/material.dart';

import '../../repo/repo_scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import '../ride/ride_widgets.dart' show fmtLocal;

/// "Benachrichtigungen pausieren" (docs/24 §3): the time-boxed global pause on station
/// nudges. The per-station mute ("Köln Hbf bleibt still") is a different thing and stays.
///
/// Travelling without the app means a nudge at every station the geofence knows, which is
/// the moment this is wanted — so it is reachable from Einstellungen and straight from the
/// nudge notification itself. While it runs the geofence layer is configured `enabled:
/// false`, so nothing is scheduled and no notification can fire.
///
/// Ride and claim pushes are deliberately not affected: someone who is not checked in gets
/// none of those anyway, and someone who is checked in asked for them.
Future<void> showRuheSheet(BuildContext context) async {
  final session = RepoScope.read(context);
  await showVSheet<void>(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.only(bottom: VSpace.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VSheetHeader(
            title: session.nudgesSnoozed ? 'Pause läuft' : 'Benachrichtigungen pausieren',
            subtitle: session.nudgesSnoozed
                ? 'Keine Hinweise am Bahnhof. Fahrten und Anträge melden sich weiter.'
                : 'Keine Hinweise am Bahnhof, bis die Pause vorbei ist. Fahrten und Anträge melden sich weiter.',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A running pause is lifted where it was set, and on the Home line (docs/24 §3).
                if (session.nudgesSnoozed) ...[
                  VListRow(
                    key: const Key('pause-aufheben'),
                    title: 'Pause aufheben',
                    subtitle: session.me?.settings.snoozedOpenEnded == true
                        ? 'Hinweise sofort wieder einschalten'
                        : 'Stumm bis ${fmtLocal(session.nudgeSnoozeUntil)}',
                    onTap: () {
                      Navigator.of(ctx).pop();
                      session.unsnoozeNudges();
                    },
                  ),
                  const VGap.s(),
                ],
                for (final h in _ladder)
                  VListRow(
                    title: h == 24 ? '24 Stunden' : '$h ${h == 1 ? 'Stunde' : 'Stunden'}',
                    subtitle: 'Bis ${fmtLocal(DateTime.now().add(Duration(hours: h)))}',
                    onTap: () {
                      Navigator.of(ctx).pop();
                      session.snoozeNudges(Duration(hours: h));
                    },
                  ),
                VListRow(
                  title: 'Bis ich sie wieder einschalte',
                  subtitle: 'Kein Hinweis mehr, bis du ihn hier aufhebst',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    session.snoozeNudges(null);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Johannes' ladder. Not a slider: six answers cover every reason someone wants quiet.
const _ladder = [1, 2, 3, 5, 8, 24];
