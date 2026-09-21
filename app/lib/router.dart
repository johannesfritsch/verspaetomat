import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/claims/claims_routes.dart';
import 'screens/community/community_routes.dart';
import 'screens/ride/checkin_launcher.dart';
import 'screens/ride/ride_routes.dart';
import 'screens/ride/ride_sheet.dart';
import 'repo/repo_scope.dart';
import 'screens/claims/demo_antrag_screen.dart';
import 'screens/claims/demo_weiter_screen.dart';
import 'screens/onboarding/wiederherstellen_screen.dart';
import 'screens/showcase_screen.dart';
import 'widgets/geofence_map_showcase.dart';
import 'widgets/server_down.dart';
import 'state/demo_state.dart';
import 'state/nearby_monitor.dart';
import 'state/ride_monitor.dart';
import 'widgets/kit.dart';

/// Route names. Screens are declared in docs/11-screens.md.
/// Query parameters are documented next to each route.
class Routes {
  Routes._();
  static const welcome = '/welcome';
  // The setup, in the order it is asked (#43). `permissions` keeps its path so an older link and
  // INITIAL_ROUTE still land on the first question.
  static const permissions = '/permissions'; // Schritt 1: Mitteilungen
  static const standort = '/standort'; // Schritt 2
  static const standortImmer = '/standort/immer'; // the rest of Schritt 2, not a step of its own
  static const setup = '/setup'; // Schritt 3 und 4: Ticket und Zweck
  static const fertig = '/fertig'; // „Los geht's!", and the end of onboarding

  static const bahnsteig = '/bahnsteig'; // "Home" in the nav
  static const antraege = '/antraege'; // ?claim=<claim id> scrolls to that claim
  static const konto = '/konto'; // alias of antraege (older links, pushes)
  static const wir = '/wir';
  static const ich = '/ich';

  static const unterwegs = '/unterwegs'; // redirects to Home with the ride sheet open (docs/19)
  static const bahnsteigWithSheet = '/bahnsteig?ride=1';
  static const angekommen = '/angekommen'; // ?variant=68|14|59|ausfall|nodata (absent = use DemoState)
  static const nachtrag = '/nachtrag';

  static const antrag = '/antrag'; // ?desk=Servicecenter%20Fahrgastrechte | NordWestBahn | Unbekannt
  static const antwort = '/antwort'; // ?mail=<mail id>  or  ?demo=question|rejected
  static const zweck = '/zweck'; // ?id=bahnhofsmission
  static const historie = '/historie';
  static const einstellungen = '/einstellungen';
  static const datenherkunft = '/einstellungen/daten';

  /// docs/25 §5: the debug page. In every build, release included (issue #29).
  static const entwicklung = '/einstellungen/entwicklung';
  static const rechtlichesBase = '/rechtliches'; // /rechtliches/:id  (impressum | datenschutz | bote)
  static String rechtliches(String id) => '$rechtlichesBase/$id';
  /// The Antrag walked through with example data, from the empty Anträge tab. Reachable in a
  /// release build on purpose: it is how a new passenger — and an App Store reviewer — finds out
  /// what the tab is for before a train is ever an hour late.
  static const vorfuehrung = '/vorfuehrung';

  /// The rest of the story, after the five steps: what the railway answers and what happens then.
  static const vorfuehrungWeiter = '/vorfuehrung/weiter';

  /// Typing the twelve words back in, on a phone that is not the one they were written on.
  static const wiederherstellen = '/wiederherstellen';

  static const showcase = '/showcase';

  /// The „nicht erreichbar" page on its own (#28). A real outage cannot be arranged on demand, so
  /// the Showcase and the screenshot tour reach it by route instead of by breaking the server.
  static const stoerung = '/showcase/stoerung';

  /// docs/25 §5: the fence drawing on its own, with an invented set, so it can be looked at
  /// without standing at a station (issue #29). The page itself draws only what the phone says.
  static const zaunkarte = '/showcase/zaunkarte';
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

/// The Navigator that renders the four tabs, below the bottom bar (issue #12).
///
/// A sheet pushed on the root Navigator covers the whole app, bar included; one pushed here sits
/// in the Scaffold's body and leaves the bar standing. Home's button has always been inside this
/// Navigator, the square in the bar is outside it, and that was the whole of the difference.
final shellNavigatorKey = GlobalKey<NavigatorState>();

GoRouter buildRouter(DemoState state, {required String initialLocation}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/', redirect: (_, __) => Routes.showcase),
      GoRoute(path: Routes.stoerung, builder: (context, __) => ServerDownScreen(onRetry: () => context.pop())),
      GoRoute(path: Routes.zaunkarte, builder: (_, __) => const GeofenceMapShowcase()),
      GoRoute(path: Routes.showcase, builder: (_, __) => const ShowcaseScreen()),
      GoRoute(path: Routes.vorfuehrung, builder: (_, __) => const DemoAntragScreen()),
      GoRoute(path: Routes.vorfuehrungWeiter, builder: (_, __) => const DemoWeiterScreen()),
      GoRoute(path: Routes.wiederherstellen, builder: (_, __) => const WiederherstellenScreen()),

      // The four tabs live in a shell with the bottom navigation; the Einchecken square in the middle is not a tab.
      ShellRoute(
        navigatorKey: shellNavigatorKey,
        builder: (context, routerState, child) => _TabShell(location: routerState.uri.toString(), child: child),
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

/// The tab shell: Home · Anträge · [Einchecken] · Wir · Ich, plus the ride (docs/19):
/// the persistent bar above the nav while a journey is under way, and the draggable sheet
/// over the active tab. One [RideMonitor] feeds both and the Bahnsteig, and one
/// [NearbyMonitor] is the single live answer to "which station am I at" (docs/24 §0).
class _TabShell extends StatefulWidget {
  const _TabShell({required this.location, required this.child});
  final String location;
  final Widget child;

  static const _tabs = [Routes.bahnsteig, Routes.antraege, Routes.wir, Routes.ich];

  @override
  State<_TabShell> createState() => _TabShellState();
}

class _TabShellState extends State<_TabShell> {
  RideMonitor? _monitor;
  NearbyMonitor? _nearby;
  String? _consumedLocation;

  @override
  void initState() {
    super.initState();
    rideSheetRequests.addListener(_onSheetRequest);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_monitor == null) {
      _monitor = RideMonitor(RepoScope.of(context))..start();
      _monitor!.addListener(_syncRiding);
    }
    _nearby ??= NearbyMonitor(RepoScope.of(context))..start();
    _consumeSheetRequest();
  }

  /// Home hides the Einchecken card while a journey runs, so the position stream sleeps
  /// with it (docs/24 §0). A setter, not a read during build: it starts and stops a stream.
  void _syncRiding() {
    final m = _monitor, n = _nearby;
    if (m != null && n != null) n.riding = m.active;
  }

  /// The redirect fires during routing; open after the frame, never inside a build.
  void _onSheetRequest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openSheetWhenKnown();
    });
  }

  @override
  void didUpdateWidget(covariant _TabShell old) {
    super.didUpdateWidget(old);
    if (old.location != widget.location) {
      _consumedLocation = null; // a second check-in lands on the same location again
      _consumeSheetRequest();
    }
  }

  /// `/bahnsteig?ride=1` (the old /unterwegs, pushes, a finished check-in) opens the sheet once.
  void _consumeSheetRequest() {
    final loc = widget.location;
    if (!loc.contains('ride=1') || _consumedLocation == loc) return;
    _consumedLocation = loc;
    _openSheetWhenKnown();
  }

  /// Right after a check-in the monitor may not know the journey yet: fetch it fresh, then
  /// open (a couple of retries cover a poll that was already in flight with the old answer).
  void _openSheetWhenKnown() {
    final m = _monitor;
    if (m == null) return;
    if (m.active || m.arrived) {
      m.openSheet();
      return;
    }
    Future<void> attempt(int left) async {
      await m.refresh(quiet: true);
      if (!mounted) return;
      if (m.active || m.arrived) {
        m.openSheet();
      } else if (left > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        if (mounted) await attempt(left - 1);
      }
    }
    attempt(3);
  }

  @override
  void dispose() {
    rideSheetRequests.removeListener(_onSheetRequest);
    _monitor?.removeListener(_syncRiding);
    _monitor?.dispose();
    _nearby?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.location;
    var index = _TabShell._tabs.indexWhere((t) => location.startsWith(t));
    if (location.startsWith(Routes.konto)) index = 1;
    final session = RepoScope.of(context);
    final monitor = _monitor!;
    final nearby = _nearby!;
    return RideScope(
      monitor: monitor,
      child: NearbyScope(
        monitor: nearby,
        child: AnimatedBuilder(
          animation: Listenable.merge([session, monitor, nearby]),
          builder: (context, _) {
            final showBar = monitor.active && !monitor.sheetOpen;
            return Stack(
              children: [
                Scaffold(
                  body: widget.child,
                  bottomNavigationBar: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showBar) RideBar(monitor: monitor),
                      VBottomNav(
                        index: index.clamp(0, 3),
                        onTap: (i) => context.go(_TabShell._tabs[i]),
                        // Under way, the square points at the journey you are on (docs/20 §1).
                        // The shell Navigator's overlay: a context *below* that Navigator, so the
                        // sheet lands in the body and the bar stays visible (issue #12). Wrapping
                        // the shell's child in a Builder does not do it — that context is above.
                        onCheckin: () => monitor.active
                            ? monitor.openSheet()
                            : startCheckin(shellNavigatorKey.currentState?.overlay?.context ?? context),
                        checkinEnabled: !monitor.active,
                        badges: {1: session.unreadMails},
                      ),
                    ],
                  ),
                ),
                if (monitor.sheetOpen) Positioned.fill(child: RideSheetLayer(monitor: monitor)),
              ],
            );
          },
        ),
      ),
    );
  }
}
