import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../router.dart';
import 'antrag_screen.dart';
import 'antwort_screen.dart';
import 'konto_screen.dart';
import 'zweck_screen.dart';

/// Owned by the "claims" builder. Konto + Antrag + Antwort + Zweck.

GoRouterWidgetBuilder kontoBuilder = (_, __) => const KontoScreen();

final claimsRoutes = <RouteBase>[
  GoRoute(
    path: Routes.antrag,
    builder: (_, s) => AntragScreen(
      desk: s.uri.queryParameters['desk'] ?? 'Servicecenter Fahrgastrechte',
      claimId: s.uri.queryParameters['id'],
      draft: s.extra is ApiClaimDraft ? s.extra as ApiClaimDraft : null,
    ),
  ),
  GoRoute(
    path: Routes.antwort,
    builder: (_, s) => AntwortScreen(mailId: s.uri.queryParameters['mail'], demo: s.uri.queryParameters['demo']),
  ),
  GoRoute(
    path: Routes.zweck,
    builder: (_, s) => ZweckScreen(ngoId: s.uri.queryParameters['id'] ?? 'bahnhofsmission'),
  ),
];
