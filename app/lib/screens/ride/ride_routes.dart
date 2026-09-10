import 'package:go_router/go_router.dart';

import '../../repo/app_repository.dart' show ApiArrivalResult;
import '../../router.dart';
import '../../state/ride_monitor.dart';
import '../onboarding/permissions_screen.dart';
import '../onboarding/setup_screen.dart';
import '../onboarding/welcome_screen.dart';
import 'angekommen_screen.dart';
import 'bahnsteig_screen.dart';
import 'checkin_screen.dart';
import 'exit_stop_screen.dart';
import 'nachtrag_screen.dart';
import 'welcher_zug_screen.dart';
import 'wohin_screen.dart';

// Owned by the "ride" builder. Onboarding + Bahnsteig + the ride loop.
//
// Query parameters:
//   /checkin?station=<id>&name=<name>
//   /wohin?station=<from id>&name=<from name>[&departure=<trip id>&line=]   (destination first, docs/17)
//   /welcher-zug?from=&fromName=&to=&toName=[&departure=]
//   /checkin/exit?departure=<trip id>&station=<from id>&name=<from name>   (legacy)
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
      fromLat: double.tryParse(s.uri.queryParameters['lat'] ?? ''),
      fromLon: double.tryParse(s.uri.queryParameters['lon'] ?? ''),
    ),
  ),
  GoRoute(
    path: Routes.wohin,
    builder: (_, s) => WohinScreen(
      fromStationId: s.uri.queryParameters['station'] ?? '',
      fromStationName: s.uri.queryParameters['name'] ?? s.uri.queryParameters['station'] ?? '',
      fromLat: double.tryParse(s.uri.queryParameters['lat'] ?? ''),
      fromLon: double.tryParse(s.uri.queryParameters['lon'] ?? ''),
      firstTripId: s.uri.queryParameters['departure'],
      firstLine: s.uri.queryParameters['line'],
    ),
  ),
  GoRoute(
    path: Routes.welcherZug,
    builder: (_, s) => WelcherZugScreen(
      fromStationId: s.uri.queryParameters['from'] ?? '',
      fromStationName: s.uri.queryParameters['fromName'] ?? '',
      toStationId: s.uri.queryParameters['to'] ?? '',
      toStationName: s.uri.queryParameters['toName'] ?? '',
      fromLat: double.tryParse(s.uri.queryParameters['lat'] ?? ''),
      fromLon: double.tryParse(s.uri.queryParameters['lon'] ?? ''),
      firstTripId: s.uri.queryParameters['departure'],
      continueJourneyId: s.uri.queryParameters['continue'],
      earliestOnwardArrival: DateTime.tryParse(s.uri.queryParameters['earliest'] ?? ''),
      countedMinutes: int.tryParse(s.uri.queryParameters['counted'] ?? ''),
    ),
  ),
  // The ride lives in the sheet over Home (docs/19); the route stays for pushes and deep links.
  GoRoute(
    path: Routes.unterwegs,
    redirect: (_, __) {
      requestRideSheet();
      return Routes.bahnsteigWithSheet;
    },
  ),
  GoRoute(
    path: Routes.angekommen,
    builder: (_, s) => AngekommenScreen(variant: s.uri.queryParameters['variant'], result: s.extra is ApiArrivalResult ? s.extra as ApiArrivalResult : null),
  ),
  GoRoute(path: Routes.nachtrag, builder: (_, __) => const NachtragScreen()),
];
