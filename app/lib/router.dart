import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/claims/claims_routes.dart';
import 'screens/community/community_routes.dart';
import 'screens/ride/checkin_launcher.dart';
import 'screens/ride/ride_routes.dart';
import 'screens/ride/ride_sheet.dart';
import 'repo/repo_scope.dart';
import 'screens/showcase_screen.dart';
import 'state/demo_state.dart';
import 'state/nearby_monitor.dart';
import 'state/ride_monitor.dart';
import 'widgets/kit.dart';

/// Route names. Screens are declared in docs/11-screens.md.
/// Query parameters are documented next to each route.
class Routes {
  Routes._();
  static const welcome = '/welcome';
  static const permissions = '/permissions';
  static const setup = '/setup';

  static const bahnsteig = '/bahnsteig'; // "Home" in the nav
  static const antraege = '/antraege'; // ?claim=<claim id> scrolls to that claim
  static const konto = '/konto'; // alias of antraege (older links, pushes)
  static const wir = '/wir';
  static const ich = '/ich';

  static const checkin = '/checkin'; // ?station=koeln-hbf
  static const exitStop = '/checkin/exit'; // ?departure=re7-0747  (legacy; the journey flow derives the exit stop)
  static const wohin = '/wohin'; // ?station=<id>&name=<name>[&lat=&lon=][&departure=<trip id>&line=RE 7]
  static const welcherZug = '/welcher-zug'; // ?from=<id>&fromName=&to=<id>&toName=[&lat=&lon=][&departure=<trip id>]
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
  static const rechtlichesBase = '/rechtliches'; // /rechtliches/:id  (impressum | datenschutz | bote)
  static String rechtliches(String id) => '$rechtlichesBase/$id';
  static const showcase = '/showcase';
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

GoRouter buildRouter(DemoState state, {required String initialLocation}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/', redirect: (_, __) => Routes.showcase),
      GoRoute(path: Routes.showcase, builder: (_, __) => const ShowcaseScreen()),

      // The four tabs live in a shell with the bottom navigation; the Einchecken square in the middle is not a tab.
      ShellRoute(
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
                        onCheckin: () => monitor.active ? monitor.openSheet() : startCheckin(context),
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
