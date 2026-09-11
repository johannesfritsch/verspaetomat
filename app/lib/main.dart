import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/models.dart';
import 'platform/diagnose_log.dart';
import 'platform/geofence_sync.dart';
import 'repo/repo_scope.dart';
import 'router.dart';
import 'screens/ride/checkin_flow.dart';
import 'state/demo_state.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';

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
    _geofence = GeofenceSync(
      session: widget.session,
      onNudge: (n) {
        DiagnoseLog.instance.add('push', 'tapped ${n.kind}${n.isStation ? ' · ${n.stationName}' : ''}');
        // A station nudge opens the check-in; a journey push (docs/17) the transfer card or the arrival;
        // mail opens the reply, the rest lands on the Konto.
        // "3 Stunden Ruhe" from the notification itself (docs/24 §3): no screen opens, the
        // pause is simply set — that is the whole point of doing it from there.
        if (n.kind == 'snooze') {
          widget.session.snoozeNudges(Duration(hours: int.tryParse(n.data['hours'] ?? '') ?? 3));
        } else if (n.isStation) {
          // docs/29: a nudge opens the same check-in as every other entry, at "Wohin?" — it
          // already knows the station. It used to open the train-first board from before
          // docs/17, which is why a nudge and the Einchecken square disagreed about the trains.
          router.go(Routes.bahnsteig);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final ctx = router.routerDelegate.navigatorKey.currentContext;
            if (ctx != null) runCheckinFlow(ctx, from: ApiStation(id: n.stationId, name: n.stationName));
          });
        } else if (n.isJourney) {
          router.go(n.journeyArrived ? Routes.angekommen : Routes.unterwegs);
        } else if (n.kind == 'mail') {
          // Railway mail lands on Anträge, scrolled to its claim (docs/11 §10).
          router.go(n.claimId == null ? Routes.antraege : '${Routes.antraege}?claim=${Uri.encodeComponent(n.claimId!)}');
        } else if (n.kind != 'station') {
          router.go(Routes.antraege);
        }
      },
    )..start();
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
        ),
      ),
    );
  }
}
