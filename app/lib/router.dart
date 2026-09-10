import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/claims/claims_routes.dart';
import 'screens/community/community_routes.dart';
import 'screens/ride/checkin_launcher.dart';
import 'screens/ride/ride_routes.dart';
import 'screens/showcase_screen.dart';
import 'state/demo_state.dart';
import 'widgets/kit.dart';

/// Route names. Screens are declared in docs/11-screens.md.
/// Query parameters are documented next to each route.
class Routes {
  Routes._();
  static const welcome = '/welcome';
  static const permissions = '/permissions';
  static const setup = '/setup';

  static const bahnsteig = '/bahnsteig'; // "Home" in the nav
  static const antraege = '/antraege'; // ?claim=<claim id> scrolls to that claim
  static const konto = '/konto'; // alias of antraege (older links, pushes)
  static const wir = '/wir';
  static const ich = '/ich';

  static const checkin = '/checkin'; // ?station=koeln-hbf
  static const exitStop = '/checkin/exit'; // ?departure=re7-0747  (legacy; the journey flow derives the exit stop)
  static const wohin = '/wohin'; // ?station=<id>&name=<name>[&lat=&lon=][&departure=<trip id>&line=RE 7]
  static const welcherZug = '/welcher-zug'; // ?from=<id>&fromName=&to=<id>&toName=[&lat=&lon=][&departure=<trip id>]
  static const unterwegs = '/unterwegs';
  static const angekommen = '/angekommen'; // ?variant=68|14|59|ausfall|nodata (absent = use DemoState)
  static const nachtrag = '/nachtrag';

  static const antrag = '/antrag'; // ?desk=Servicecenter%20Fahrgastrechte | NordWestBahn | Unbekannt
  static const antwort = '/antwort'; // ?mail=<mail id>  or  ?demo=question|rejected
  static const zweck = '/zweck'; // ?id=bahnhofsmission
  static const historie = '/historie';
  static const einstellungen = '/einstellungen';
  static const datenherkunft = '/einstellungen/daten';
  static const rechtlichesBase = '/rechtliches'; // /rechtliches/:id  (impressum | datenschutz | bote)
  static String rechtliches(String id) => '$rechtlichesBase/$id';
  static const showcase = '/showcase';
}

/// Where the app opens. `INITIAL_ROUTE` wins (tests, showcase runs). Otherwise a release
/// build starts at Willkommen until onboarding is done, then at the Bahnsteig; a debug
/// build starts at the Showcase.
String initialLocationFor({required bool onboardingDone}) {
  const forced = String.fromEnvironment('INITIAL_ROUTE', defaultValue: '');
  if (forced.isNotEmpty) return forced;
  if (!kReleaseMode) return Routes.showcase;
  return onboardingDone ? Routes.bahnsteig : Routes.welcome;
}

GoRouter buildRouter(DemoState state, {required String initialLocation}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/', redirect: (_, __) => Routes.showcase),
      GoRoute(path: Routes.showcase, builder: (_, __) => const ShowcaseScreen()),

      // The four tabs live in a shell with the bottom navigation; the Einchecken square in the middle is not a tab.
      ShellRoute(
        builder: (context, routerState, child) => _TabShell(location: routerState.uri.path, child: child),
        routes: [
          GoRoute(path: Routes.bahnsteig, builder: (c, s) => bahnsteigBuilder(c, s)),
          GoRoute(path: Routes.antraege, builder: (c, s) => antraegeBuilder(c, s)),
          GoRoute(path: Routes.konto, builder: (c, s) => antraegeBuilder(c, s)),
          GoRoute(path: Routes.wir, builder: (c, s) => wirBuilder(c, s)),
          GoRoute(path: Routes.ich, builder: (c, s) => ichBuilder(c, s)),
        ],
      ),

      ...rideRoutes,
      ...claimsRoutes,
      ...communityRoutes,
    ],
  );
}

/// The tab shell: Home · Anträge · [Einchecken] · Wir · Ich.
class _TabShell extends StatelessWidget {
  const _TabShell({required this.location, required this.child});
  final String location;
  final Widget child;

  static const _tabs = [Routes.bahnsteig, Routes.antraege, Routes.wir, Routes.ich];

  @override
  Widget build(BuildContext context) {
    var index = _tabs.indexWhere((t) => location.startsWith(t));
    if (location.startsWith(Routes.konto)) index = 1;
    return Scaffold(
      body: child,
      bottomNavigationBar: VBottomNav(index: index.clamp(0, 3), onTap: (i) => context.go(_tabs[i]), onCheckin: () => startCheckin(context)),
    );
  }
}
