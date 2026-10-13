import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:verspaetomat/api/models.dart';
import 'package:verspaetomat/repo/repo_scope.dart';
import 'package:verspaetomat/screens/ride/bahnsteig_screen.dart';
import 'package:verspaetomat/screens/ride/ride_routes.dart';
import 'package:verspaetomat/state/demo_state.dart';
import 'package:verspaetomat/state/nearby_monitor.dart';
import 'package:verspaetomat/state/ride_monitor.dart';

/// „Gestern vergessen einzuchecken?" is gone: a ride named after the fact opened a claim on a
/// train nobody had to be on. The server no longer suggests it and refuses the request
/// (`api_tests::a_ride_entered_afterwards_is_refused_and_writes_nothing`); these pin the app's
/// half — Home shows no link even when a server still sends the old hint, and there is no screen
/// to reach.
void main() {
  testWidgets('Home shows no Nachtrag link, even when the server still suggests one', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final session = _OldServer(demo: DemoState(), prefs: await SharedPreferences.getInstance(), apiUrl: '');
    await tester.binding.setSurfaceSize(const Size(393, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(RepoScope(
      session: session,
      child: RideScope(
        monitor: RideMonitor(session),
        child: NearbyScope(
          monitor: NearbyMonitor(session),
          child: const MaterialApp(home: BahnsteigScreen()),
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(session.asked, isTrue, reason: 'Home loaded its standing, the old hint included');
    expect(find.text('Gestern vergessen einzuchecken?'), findsNothing);
    expect(find.textContaining('nachtragen'), findsNothing);
    expect(find.textContaining('vergessen'), findsNothing);
  });

  test('there is no route to a Nachtrag screen', () {
    final paths = [for (final r in rideRoutes) if (r is GoRoute) r.path];
    expect(paths, isNot(contains('/add-ride')));
  });

  test('an old server\'s nachtrag hint still parses, so nothing breaks while it is around', () {
    final st = ApiStanding.fromJson(_oldStanding);
    expect(st.next?.kind, 'nachtrag');
  });
}

const _oldStanding = <String, dynamic>{
  'minutes_this_week': 12,
  'next': {'kind': 'nachtrag', 'title': 'Gestern vergessen einzuchecken?', 'body': 'Fahrt nachtragen, deine Minuten zählen trotzdem.'},
};

/// A server from before the removal: its standing still carries `next.kind == nachtrag`.
class _OldServer extends Session {
  _OldServer({required super.demo, required super.prefs, required super.apiUrl});

  bool asked = false;

  @override
  Future<ApiStanding> loadStanding() async {
    asked = true;
    return ApiStanding.fromJson(_oldStanding);
  }
}
