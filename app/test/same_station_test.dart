import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/screens/ride/ride_widgets.dart';

/// docs/30: the feeds disagree about station names, and the away box showed „Ab Kißlegg" twice
/// because it compared ids and then raw names.
void main() {
  test('the same platform under two names', () {
    expect(sameStation('Kißlegg', 'Kißlegg Bahnhof'), isTrue);
    expect(sameStation('Kißlegg Bahnhof', 'Kißlegg'), isTrue);
    expect(sameStation('Köln Hbf', 'Köln Hauptbahnhof'), isTrue);
    expect(sameStation('Aulendorf', 'Aulendorf Bahnhof'), isTrue);
    expect(sameStation('Münster (Westf) Hbf', 'Münster Hbf'), isTrue);
    expect(sameStation('Rheine, Bahnhof', 'Rheine Bahnhof'), isTrue);
  });

  test('different places stay different', () {
    expect(sameStation('Kißlegg', 'Aulendorf'), isFalse);
    expect(sameStation('Köln Hbf', 'Köln Messe/Deutz'), isFalse);
    expect(sameStation('Wangen', 'Wangen im Allgäu Nord'), isFalse);
    // A Hauptbahnhof is not the town's other station.
    expect(sameStation('Düsseldorf Hbf', 'Düsseldorf Flughafen'), isFalse);
  });
}
