import 'package:go_router/go_router.dart';

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

/// Owned by the "ride" builder. Onboarding + Bahnsteig + the ride loop.

GoRouterWidgetBuilder bahnsteigBuilder = (_, __) => const BahnsteigScreen();

final rideRoutes = <RouteBase>[
  GoRoute(path: Routes.welcome, builder: (_, __) => const WelcomeScreen()),
  GoRoute(path: Routes.permissions, builder: (_, __) => const PermissionsScreen()),
  GoRoute(path: Routes.setup, builder: (_, __) => const SetupScreen()),
  GoRoute(path: Routes.checkin, builder: (_, s) => CheckinScreen(stationId: s.uri.queryParameters['station'])),
  GoRoute(path: Routes.exitStop, builder: (_, s) => ExitStopScreen(departureId: s.uri.queryParameters['departure'])),
  GoRoute(path: Routes.unterwegs, builder: (_, __) => const UnterwegsScreen()),
  GoRoute(path: Routes.angekommen, builder: (_, s) => AngekommenScreen(variant: s.uri.queryParameters['variant'])),
  GoRoute(path: Routes.nachtrag, builder: (_, __) => const NachtragScreen()),
];
