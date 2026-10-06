import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/platform/geofence.dart';

/// #87: where a tapped notification leads. The app decides it in `main.dart`; the decision is
/// pulled out so it can be pinned here without driving the shell.
void main() {
  test('a station nudge opens the check-in at that station', () {
    const n = GeofenceNudge(stationId: 'vs:4711', stationName: 'München, Pasing');
    expect(n.target(journeyRunning: false), NudgeTarget.checkin);
  });

  test('a station nudge while a journey runs opens the journey, not a second check-in', () {
    // #80, 08:55:42: the tap opened „Wohin?" over the ICE that was already under way.
    const n = GeofenceNudge(stationId: 'vs:4711', stationName: 'München, Pasing');
    expect(n.target(journeyRunning: true), NudgeTarget.ride);
  });

  test('everything else leads where it always did', () {
    NudgeTarget of(Map<String, dynamic> m, {bool running = false}) => GeofenceNudge.fromMap(m).target(journeyRunning: running);

    expect(of({'kind': 'snooze', 'hours': '3'}, running: true), NudgeTarget.snooze);
    expect(of({'kind': 'journey', 'journey_id': 'j', 'arrived': 'true'}), NudgeTarget.arrival);
    expect(of({'kind': 'journey', 'journey_id': 'j', 'transfer': 'true'}, running: true), NudgeTarget.ride);
    expect(of({'kind': 'mail', 'claim_id': 'c-1'}), NudgeTarget.mail);
    expect(of({'kind': 'incident'}), NudgeTarget.claims);
    expect(of({'kind': 'claim'}), NudgeTarget.claims);
    // A station nudge that lost its station on the way (an old pending entry): nothing opens.
    expect(of({'kind': 'station'}), NudgeTarget.none);
    expect(of({'kind': 'station'}, running: true), NudgeTarget.none);
  });
}
