import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/claims/claims_routes.dart';
import 'screens/community/community_routes.dart';
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

  static const bahnsteig = '/bahnsteig';
  static const konto = '/konto';
  static const wir = '/wir';
  static const ich = '/ich';

  static const checkin = '/checkin'; // ?station=koeln-hbf
  static const exitStop = '/checkin/exit'; // ?departure=re7-0747
  static const unterwegs = '/unterwegs';
  static const angekommen = '/angekommen'; // ?variant=68|14|59|ausfall|nodata (absent = use DemoState)
  static const nachtrag = '/nachtrag';

  static const antrag = '/antrag'; // ?desk=Servicecenter%20Fahrgastrechte | NordWestBahn | Unbekannt
  static const antwort = '/antwort'; // ?mail=<mail id>  or  ?demo=question|rejected
  static const zweck = '/zweck'; // ?id=bahnhofsmission
  static const team = '/team'; // ?id=buero-nord
  static const historie = '/historie';
  static const einstellungen = '/einstellungen';
  static const datenherkunft = '/einstellungen/daten';
  static const showcase = '/showcase';
}

GoRouter buildRouter(DemoState state) {
  return GoRouter(
    initialLocation: const String.fromEnvironment('INITIAL_ROUTE', defaultValue: Routes.showcase),
    routes: [
      GoRoute(path: '/', redirect: (_, __) => Routes.showcase),
      GoRoute(path: Routes.showcase, builder: (_, __) => const ShowcaseScreen()),

      // The four tabs live in a shell with the bottom navigation.
      ShellRoute(
        builder: (context, routerState, child) => _TabShell(location: routerState.uri.path, child: child),
        routes: [
          GoRoute(path: Routes.bahnsteig, builder: (c, s) => bahnsteigBuilder(c, s)),
          GoRoute(path: Routes.konto, builder: (c, s) => kontoBuilder(c, s)),
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

/// The four-tab shell: Bahnsteig, Konto, Wir, Ich.
class _TabShell extends StatelessWidget {
  const _TabShell({required this.location, required this.child});
  final String location;
  final Widget child;

  static const _tabs = [Routes.bahnsteig, Routes.konto, Routes.wir, Routes.ich];

  @override
  Widget build(BuildContext context) {
    final index = _tabs.indexWhere((t) => location.startsWith(t)).clamp(0, 3);
    return Scaffold(
      body: child,
      bottomNavigationBar: VBottomNav(index: index, onTap: (i) => context.go(_tabs[i])),
    );
  }
}
