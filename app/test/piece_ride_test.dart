import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/api/models.dart';
import 'package:verspaetomat/screens/puzzles/piece_in_hand.dart' show pieceRideLines;

/// The ride on the back of a piece (migration 0052): what the server sends, what an older server
/// leaves out, and the three lines the back prints.
void main() {
  Map<String, dynamic> puzzle({Object? rides}) => {
        'image_id': 'a', 'rows': 4, 'cols': 3, 'owned': [0, 4, 7], 'title': 'Nachtschicht am Gleis 1',
        'ngo_id': 'bahnhofsmission', 'ngo_name': 'Bahnhofsmission Köln', 'image_url': '/v1/puzzle-images/a',
        if (rides != null) 'rides': rides,
      };

  test('each piece gets its ride, by slot, and the day stays the day it was', () {
    final p = ApiPuzzle.fromJson(puzzle(rides: [
      {'piece': 4, 'journey_id': 'j4', 'date': '2026-10-12', 'from': 'Köln Hbf', 'to': 'Düsseldorf Hbf', 'minutes': 68, 'lines': ['RE 1', 'S 11']},
      {'piece': 7, 'journey_id': 'j7', 'date': '2026-01-01', 'from': 'Kißlegg', 'to': 'Memmingen', 'minutes': 0, 'lines': <String>[]},
    ]));
    expect(p.rides.keys, unorderedEquals([4, 7]));
    expect(p.rides[0], isNull, reason: 'a piece naming no ride');
    final r = p.rides[4]!;
    expect((r.journeyId, r.from, r.to, r.minutes), ('j4', 'Köln Hbf', 'Düsseldorf Hbf', 68));
    expect(r.lines, ['RE 1', 'S 11']);
    // A calendar day, not a moment: never shifted into the day before by a time zone.
    expect((r.date!.year, r.date!.month, r.date!.day), (2026, 10, 12));
    expect(p.rides[7]!.date!.day, 1);
  });

  test('a server before rides, and an entry without a piece, leave nothing behind', () {
    expect(ApiPuzzle.fromJson(puzzle()).rides, isEmpty);
    expect(ApiPuzzle.fromJson(puzzle(rides: [{'journey_id': 'x', 'from': 'A', 'to': 'B'}])).rides, isEmpty);
    expect(ApiPuzzle.fromJson(puzzle(rides: [])).rides, isEmpty);
  });

  test('the back prints line, day, the way and the minutes, one short thing to a line', () {
    final r = ApiPieceRide(journeyId: 'j', date: DateTime(2026, 10, 12), from: 'Köln Hbf', to: 'Düsseldorf Hbf', minutes: 68, lines: ['RE 1']);
    expect(pieceRideLines(r), ['RE 1', '12. Okt.', 'Köln Hbf', '→ Düsseldorf Hbf', '68 Minuten']);
    expect(pieceRideLines(ApiPieceRide(journeyId: 'j', date: DateTime(2026, 9, 3), from: 'A', to: 'B', minutes: 1, lines: ['RE 96', 'RE 75'])),
        ['RE 96, RE 75', '3. Sept.', 'A', '→ B', '1 Minute']);
    // On time: no „0 Minuten"; without line or day, no empty line.
    expect(pieceRideLines(const ApiPieceRide(journeyId: 'j', from: 'A', to: 'B')), ['A', '→ B', 'pünktlich']);
  });
}
