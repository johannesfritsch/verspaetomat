import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:verspaetomat/repo/repo_scope.dart';
import 'package:verspaetomat/screens/ride/location_nudge.dart';
import 'package:verspaetomat/state/demo_state.dart';

/// #18: the card asks while the phone has not granted „Immer", and a closed card stays closed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(Session, LocationNudge)> nudgeWith(Map<String, Object> stored) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    final session = Session(demo: DemoState(), prefs: prefs, apiUrl: '');
    final nudge = LocationNudge(session);
    await nudge.check();
    return (session, nudge);
  }

  test('without „Immer" the card shows', () async {
    // No native side in a unit test: the permission reads as not determined, which is not „Immer".
    final (session, nudge) = await nudgeWith({});
    expect(nudge.visible, isTrue);
    nudge.dispose();
    session.dispose();
  });

  test('closing it is final, also for the next start', () async {
    final (session, nudge) = await nudgeWith({});
    await nudge.dismiss();
    expect(nudge.visible, isFalse);
    nudge.dispose();
    session.dispose();

    final (session2, again) = await nudgeWith({'location_nudge_dismissed': true});
    expect(again.visible, isFalse);
    again.dispose();
    session2.dispose();
  });
}
