import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../router.dart';
import 'antrag_screen.dart';
import 'antwort_screen.dart';
import 'antraege_screen.dart';
import 'zweck_screen.dart';

/// Owned by the "claims" builder. Anträge + Antrag + Antwort + Zweck.

GoRouterWidgetBuilder antraegeBuilder = (_, s) => AntraegeScreen(claimId: s.uri.queryParameters['claim']);

final claimsRoutes = <RouteBase>[
  GoRoute(
    path: Routes.claim,
    builder: (_, s) => AntragScreen(
      desk: s.uri.queryParameters['desk'] ?? 'Servicecenter Fahrgastrechte',
      claimId: s.uri.queryParameters['id'],
      draft: s.extra is ApiClaimDraft ? s.extra as ApiClaimDraft : null,
    ),
  ),
  GoRoute(
    path: Routes.reply,
    builder: (_, s) => AntwortScreen(mailId: s.uri.queryParameters['mail'], demo: s.uri.queryParameters['demo']),
  ),
  GoRoute(
    path: Routes.cause,
    builder: (_, s) => ZweckScreen(ngoId: s.uri.queryParameters['id'] ?? 'bahnhofsmission'),
  ),
];
