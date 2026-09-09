import 'package:go_router/go_router.dart';

import '../../router.dart';
import 'datenherkunft_screen.dart';
import 'einstellungen_screen.dart';
import 'historie_screen.dart';
import 'ich_screen.dart';
import 'team_screen.dart';
import 'wir_screen.dart';

/// Owned by the "community" builder. Wir + Team + Ich + Historie +
/// Einstellungen + Datenherkunft.

GoRouterWidgetBuilder wirBuilder = (_, __) => const WirScreen();
GoRouterWidgetBuilder ichBuilder = (_, __) => const IchScreen();

final communityRoutes = <RouteBase>[
  GoRoute(path: Routes.team, builder: (_, s) => TeamScreen(teamId: s.uri.queryParameters['id'] ?? 'buero-nord')),
  GoRoute(path: Routes.historie, builder: (_, __) => const HistorieScreen()),
  GoRoute(path: Routes.einstellungen, builder: (_, __) => const EinstellungenScreen()),
  GoRoute(path: Routes.datenherkunft, builder: (_, __) => const DatenherkunftScreen()),
];
