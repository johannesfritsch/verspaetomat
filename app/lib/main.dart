import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/models.dart';
import 'platform/diagnose_log.dart';
import 'platform/geofence.dart';
import 'platform/geofence_sync.dart';
import 'repo/repo_scope.dart';
import 'router.dart';
import 'screens/ride/checkin_flow.dart';
import 'state/demo_state.dart';
import 'state/ride_monitor.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';
import 'widgets/demo_band.dart';

/// Backend base URL. `--dart-define=API_URL=http://192.168.0.10:8080` for a phone.
const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://127.0.0.1:8080');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ));
  final prefs = await SharedPreferences.getInstance();
  final demo = DemoState();
  final session = Session(demo: demo, prefs: prefs, apiUrl: apiUrl);
  // Do not block the first frame on the network; the session reports its state.
  session.init();
  runApp(VerspaetomatApp(state: demo, session: session));
}

class VerspaetomatApp extends StatefulWidget {
  const VerspaetomatApp({super.key, required this.state, required this.session});
  final DemoState state;
  final Session session;

  @override
  State<VerspaetomatApp> createState() => _VerspaetomatAppState();
}

class _VerspaetomatAppState extends State<VerspaetomatApp> {
  late final router = buildRouter(widget.state, initialLocation: initialLocationFor(onboardingDone: widget.session.prefs.getBool(Session.onboardingDoneKey) ?? false));
  late final GeofenceSync _geofence;

  @override
  void initState() {
    super.initState();
    // Keeps the phone's station regions in step with the account; a tapped nudge opens the check-in.
    // GeofenceSync hands a tap over only once the first frame is drawn and the account is
    // loaded (#87).
    _geofence = GeofenceSync(session: widget.session, onNudge: (n) => unawaited(_openNudge(n)))..start();
  }

  /// A station nudge opens the check-in; a journey push (docs/17) the transfer card or the
  /// arrival; mail opens the reply, the rest lands on Anträge.
  Future<void> _openNudge(GeofenceNudge n) async {
    DiagnoseLog.instance.add('push', 'tapped ${n.kind}${n.isStation ? ' · ${n.stationName}' : ''}');
    var running = false;
    BuildContext? shell;
    if (n.isStation) {
      // docs/29: a nudge opens the same check-in as every other entry, at "Wohin?" — it
      // already knows the station. It used to open the train-first board from before
      // docs/17, which is why a nudge and the Einchecken square disagreed about the trains.
      router.go(Routes.home);
      await WidgetsBinding.instance.endOfFrame;
      // The shell Navigator's overlay, as the Einchecken square uses (router.dart): a context
      // below RideScope and NearbyScope, so the sheets find the monitors. The root navigator
      // used to be the one, and the check-in it opened could not reach either (#87).
      shell = shellNavigatorKey.currentState?.overlay?.context;
      if (shell == null || !shell.mounted) return;
      // #80, #87: a nudge from before the check-in can still be tapped during the journey. Ask
      // fresh rather than trust a monitor that may not have loaded yet on a cold start.
      final monitor = RideScope.read(shell);
      if (monitor != null) {
        await monitor.refresh(quiet: true);
        running = monitor.active;
      } else {
        // No monitor mounted yet: ask the server the way the geofence sync does.
        try {
          running = await GeofenceSync.ridingNow(widget.session.repo);
        } catch (_) {}
      }
      if (!shell.mounted) return;
    }
    switch (n.target(journeyRunning: running)) {
      case NudgeTarget.snooze:
        // "3 Stunden Ruhe" from the notification itself (docs/24 §3): no screen opens, the
        // pause is simply set — that is the whole point of doing it from there.
        await widget.session.snoozeNudges(Duration(hours: int.tryParse(n.data['hours'] ?? '') ?? 3));
      case NudgeTarget.checkin:
        await runCheckinFlow(shell!, from: ApiStation(id: n.stationId, name: n.stationName));
      case NudgeTarget.ride:
        router.go(Routes.ride);
      case NudgeTarget.arrival:
        router.go(Routes.arrived);
      case NudgeTarget.mail:
        // Railway mail lands on Anträge, scrolled to its claim (docs/11 §10).
        router.go(n.claimId == null ? Routes.claims : '${Routes.claims}?claim=${Uri.encodeComponent(n.claimId!)}');
      case NudgeTarget.claims:
        router.go(Routes.claims);
      case NudgeTarget.none:
        break;
    }
  }

  @override
  void dispose() {
    _geofence.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepoScope(
      session: widget.session,
      child: DemoScope(
        state: widget.state,
        child: MaterialApp.router(
          title: 'Verspätomat',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          routerConfig: router,
          color: VColors.paper,
          // Over every route and sheet while a walkthrough runs (#72).
          builder: (context, child) => DemoBand(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
