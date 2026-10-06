import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/api/models.dart';
import 'package:verspaetomat/screens/ride/ride_widgets.dart';

/// #78: „Nächster Halt" was Türkheim, two stops behind the passenger's exit in Memmingen. The
/// server counted the stops from the train's origin and every screen added the boarding stop on
/// top. The count now starts at the boarding stop, and the app caps the sum at the exit, so a
/// server that still counts the old way cannot push it past it either.
void main() {
  // RE 96 Lindau-Reutin → Buchloe, boarded in Kißlegg (4), off in Memmingen (9).
  const names = [
    'Lindau-Reutin', 'Lindau-Insel', 'Hergatz', 'Wangen (Allgäu)', 'Kißlegg', 'Leutkirch', 'Aichstetten', //
    'Aitrach-Marstetten', 'Tannheim (Württ)', 'Memmingen', 'Mindelheim', 'Türkheim', 'Buchloe',
  ];
  final stops = [for (final n in names) ApiStop(name: n, stationId: 'test:$n')];

  ApiRide ride(int passed, {String from = 'Kißlegg', String exit = 'Memmingen'}) => ApiRide.fromJson({
        'id': 'r',
        'trip_id': 're96',
        'line': 'RE 96',
        'operator': 'Arverio Bayern',
        'from_station_id': 'test:$from',
        'from_station_name': from,
        'exit_station_id': 'test:$exit',
        'exit_station_name': exit,
        'status': 'riding',
        'passed_stops': passed,
      });

  test('the boarding stop plus the stops behind the train on this leg', () {
    expect(nextStopIndex(stops, ride(0)), 4, reason: 'still in Kißlegg');
    expect(stops[nextStopIndex(stops, ride(3))].name, 'Aitrach-Marstetten', reason: '08:45 by the timetable');
  });

  test('never beyond the exit', () {
    expect(nextStopIndex(stops, ride(5)), 9);
    // What a server counting from the origin sent at 08:45: 4 + 7 was Türkheim.
    expect(stops[nextStopIndex(stops, ride(7))].name, 'Memmingen');
    expect(nextStopIndex(stops, ride(40)), 9);
  });

  test('an exit that is not on the trip caps at its last stop', () {
    expect(nextStopIndex(stops, ride(40, exit: 'Augsburg Hbf')), stops.length - 1);
  });

  test('no stops, no next stop', () {
    expect(nextStopIndex(const [], ride(3)), -1);
  });

  test('„pünktlich" only when the feed has said so', () {
    Map<String, dynamic> wire(Object? known) => {'id': 'r', 'status': 'riding', if (known != null) 'live_known': known};
    expect(onTimeKnown(ApiRide.fromJson(wire(false))), isFalse, reason: 'no realtime: 0 minutes is the timetable');
    expect(onTimeKnown(ApiRide.fromJson(wire(true))), isTrue);
    expect(ApiRide.fromJson(wire(null)).liveKnown, isNull);
    expect(onTimeKnown(ApiRide.fromJson(wire(null))), isTrue, reason: 'a server that does not say keeps today’s behaviour');
  });

  test('the next stop shows its own live time', () {
    final planned = DateTime.utc(2026, 10, 2, 6, 47);
    final late = ApiStop(name: 'Aitrach-Marstetten', scheduledArrival: planned, arrival: planned.add(const Duration(minutes: 9)));
    expect(stopTime(late, 2), planned.add(const Duration(minutes: 9)), reason: 'not the delay at the exit');
    expect(stopTime(ApiStop(name: 'x', scheduledArrival: planned), 2), planned.add(const Duration(minutes: 2)));
  });
}
