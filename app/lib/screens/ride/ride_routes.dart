import 'package:go_router/go_router.dart';

import '../../repo/app_repository.dart' show ApiArrivalResult;
import '../../router.dart';
import '../../state/ride_monitor.dart';
import '../onboarding/fertig_screen.dart';
import '../onboarding/mitteilungen_screen.dart';
import '../onboarding/standort_immer_screen.dart';
import '../onboarding/standort_screen.dart';
import '../onboarding/zweck_screen.dart';
import '../onboarding/welcome_screen.dart';
import 'bahnsteig_screen.dart';
import 'nachtrag_screen.dart';

// Owned by the "ride" builder. Onboarding + Bahnsteig + the ride loop.
//
// Query parameters:
//   /checkin?station=<id>&name=<name>
//   /wohin?station=<from id>&name=<from name>[&departure=<trip id>&line=]   (destination first, docs/17)
//   /welcher-zug?from=&fromName=&to=&toName=[&departure=]
//   /checkin/exit?departure=<trip id>&station=<from id>&name=<from name>   (legacy)
//   /arrived?variant=68|14|59|cancelled|nodata   (demo mode) or `extra: ApiArrivalResult`

GoRouterWidgetBuilder bahnsteigBuilder = (_, __) => const BahnsteigScreen();

final rideRoutes = <RouteBase>[
  GoRoute(path: Routes.welcome, builder: (_, __) => const WelcomeScreen()),
  GoRoute(path: Routes.permissions, builder: (_, __) => const MitteilungenScreen()),
  GoRoute(path: Routes.location, builder: (_, __) => const StandortScreen()),
  GoRoute(path: Routes.locationAlways, builder: (_, __) => const StandortImmerScreen()),
  GoRoute(path: Routes.chooseCause, builder: (_, __) => const ZweckScreen()),
  GoRoute(path: Routes.ready, builder: (_, __) => const FertigScreen()),
  // The ride lives in the sheet over Home (docs/19); the route stays for pushes and deep links.
  GoRoute(
    path: Routes.ride,
    redirect: (_, __) {
      requestRideSheet();
      return Routes.homeWithRide;
    },
  ),
  // The arrival is a sheet over Home too (#63); the route stays for pushes, deep links and
  // the showcase.
  GoRoute(
    path: Routes.arrived,
    redirect: (_, s) {
      requestArrivalSheet(variant: s.uri.queryParameters['variant'], result: s.extra is ApiArrivalResult ? s.extra as ApiArrivalResult : null);
      return Routes.home;
    },
  ),
  GoRoute(path: Routes.addRide, builder: (_, __) => const NachtragScreen()),
];
