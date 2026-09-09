import 'package:go_router/go_router.dart';

import '../../repo/app_repository.dart' show ApiArrivalResult;
import '../../router.dart';
import '../onboarding/permissions_screen.dart';
import '../onboarding/setup_screen.dart';
import '../onboarding/welcome_screen.dart';
import 'angekommen_screen.dart';
import 'bahnsteig_screen.dart';
import 'checkin_screen.dart';
import 'exit_stop_screen.dart';
import 'nachtrag_screen.dart';
import 'unterwegs_screen.dart';

// Owned by the "ride" builder. Onboarding + Bahnsteig + the ride loop.
//
// Query parameters:
//   /checkin?station=<id>&name=<name>
//   /checkin/exit?departure=<trip id>&station=<from id>&name=<from name>
//   /angekommen?variant=68|14|59|ausfall|nodata   (demo mode) or `extra: ApiArrivalResult`

GoRouterWidgetBuilder bahnsteigBuilder = (_, __) => const BahnsteigScreen();

final rideRoutes = <RouteBase>[
  GoRoute(path: Routes.welcome, builder: (_, __) => const WelcomeScreen()),
  GoRoute(path: Routes.permissions, builder: (_, __) => const PermissionsScreen()),
  GoRoute(path: Routes.setup, builder: (_, __) => const SetupScreen()),
  GoRoute(
    path: Routes.checkin,
    builder: (_, s) => CheckinScreen(stationId: s.uri.queryParameters['station'], stationName: s.uri.queryParameters['name']),
  ),
  GoRoute(
    path: Routes.exitStop,
    builder: (_, s) => ExitStopScreen(
      tripId: s.uri.queryParameters['departure'],
      fromStationId: s.uri.queryParameters['station'],
      fromStationName: s.uri.queryParameters['name'],
    ),
  ),
  GoRoute(path: Routes.unterwegs, builder: (_, __) => const UnterwegsScreen()),
  GoRoute(
    path: Routes.angekommen,
    builder: (_, s) => AngekommenScreen(variant: s.uri.queryParameters['variant'], result: s.extra is ApiArrivalResult ? s.extra as ApiArrivalResult : null),
  ),
  GoRoute(path: Routes.nachtrag, builder: (_, __) => const NachtragScreen()),
];
