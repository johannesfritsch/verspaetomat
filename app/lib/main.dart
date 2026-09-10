import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'platform/geofence_sync.dart';
import 'repo/repo_scope.dart';
import 'router.dart';
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
      onNudge: (n) => router.go('${Routes.checkin}?station=${Uri.encodeComponent(n.stationId)}&name=${Uri.encodeComponent(n.stationName)}'),
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
