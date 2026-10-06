import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/api/models.dart';
import 'package:verspaetomat/screens/ride/ride_widgets.dart';

/// #79: Kißlegg moved the RE 96 from track 3 to 1, and the journey view still said 3. The leg's
/// track was the one stored at check-in; the stop's own track comes with every `journeys/current`.
void main() {
  test('a stop carries its track from the wire', () {
    expect(ApiStop.fromJson({'name': 'Kißlegg', 'track': '1'}).track, '1');
    expect(ApiStop.fromJson({'name': 'Kißlegg'}).track, isNull, reason: 'a server or snapshot without it');
  });

  test('the live track of the stop wins over the one stored with the leg', () {
    const stops = [ApiStop(name: 'Kißlegg', track: '1'), ApiStop(name: 'Leutkirch'), ApiStop(name: 'Memmingen', track: ' ')];
    expect(stopTrack(stops, 0, '3'), '1');
    expect(stopTrack(stops, 1, '2'), '2', reason: 'no live track: the stored one');
    expect(stopTrack(stops, 2, '51'), '51', reason: 'a blank track is no track');
    expect(stopTrack(stops, 2, null), isNull);
    expect(stopTrack(stops, -1, '51'), '51', reason: 'a stop not on the trip');
    expect(stopTrack(const [], 0, '3'), '3');
  });
}
