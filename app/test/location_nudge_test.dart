import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:verspaetomat/repo/repo_scope.dart';
import 'package:verspaetomat/screens/ride/location_nudge.dart';
import 'package:verspaetomat/state/demo_state.dart';

/// #18: the card asks while the phone has not granted „Immer". #48: „Nicht mehr fragen" is for
/// good, „Nächstes Mal erinnern" (and the ×) rests it for a week.
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

  test('„Nicht mehr fragen" is final, also for the next start', () async {
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

  test('„Nächstes Mal erinnern" rests the card for a week, then it is back', () async {
    final (session, nudge) = await nudgeWith({});
    await nudge.remindLater();
    expect(nudge.visible, isFalse);
    nudge.dispose();
    session.dispose();

    // Still inside the week on the next start.
    final soon = DateTime.now().add(const Duration(days: 6)).toIso8601String();
    final (session2, resting) = await nudgeWith({'location_nudge_snoozed_until': soon});
    expect(resting.visible, isFalse);
    resting.dispose();
    session2.dispose();

    // The week is over.
    final past = DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String();
    final (session3, back) = await nudgeWith({'location_nudge_snoozed_until': past});
    expect(back.visible, isTrue);
    back.dispose();
    session3.dispose();
  });
}
