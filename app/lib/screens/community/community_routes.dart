import 'package:go_router/go_router.dart';

import '../../content/legal.dart';

import '../../router.dart';
import 'datenherkunft_screen.dart';
import 'entwicklung_screen.dart';
import 'einstellungen_screen.dart';
import 'historie_screen.dart';
import 'ich_screen.dart';
import 'rechtliches_screen.dart';
import 'wir_screen.dart';

/// Owned by the "community" builder. Wir + Ich + Historie +
/// Einstellungen + Datenherkunft.

GoRouterWidgetBuilder wirBuilder = (_, __) => const WirScreen();
GoRouterWidgetBuilder ichBuilder = (_, __) => const IchScreen();

final communityRoutes = <RouteBase>[
  GoRoute(path: Routes.history, builder: (_, __) => const HistorieScreen()),
  GoRoute(path: Routes.settings, builder: (_, __) => const EinstellungenScreen()),
  GoRoute(path: Routes.dataSources, builder: (_, __) => const DatenherkunftScreen()),
  GoRoute(path: Routes.developer, builder: (_, __) => const EntwicklungScreen()),
  GoRoute(path: '${Routes.legalBase}/:id', builder: (_, s) => RechtlichesScreen(doc: legalDocById(s.pathParameters['id'] ?? 'impressum'))),
];
