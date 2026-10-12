import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/mock/mock_data.dart';
import 'package:verspaetomat/state/demo_state.dart';

/// docs/51 §2–§3 as Demo mode plays them.
void main() {
  /// One arrived journey of [minutes], and the piece it brought.
  DemoPiece? ride(DemoState s, [int minutes = 5]) {
    final d = Mock.allDepartures.first;
    s.checkIn(departure: d, exitStop: d.stops.last, fromStation: d.stops.first.name);
    s.simulateArrival(minutes: minutes);
    return s.journeyHistory.first.piece;
  }

  String tierOf(DemoPiece p) => Mock.puzzles.firstWhere((x) => x.id == p.imageId).tiers[p.piece];
  int owned(DemoState s) => s.puzzlePieces.values.fold(0, (n, p) => n + p.length);

  test('every journey brings one new piece until there is none left', () {
    final s = DemoState();
    final total = Mock.puzzles.length * DemoPuzzle.rows * DemoPuzzle.cols;
    var i = owned(s);
    // An hour, a quarter and a minute in turn: every slot finds a ride that may fill it.
    for (var n = 0; i < total; n++) {
      final p = ride(s, const [70, 30, 5][n % 3]);
      expect(p, isNotNull);
      expect(s.puzzlePieces[p!.imageId], contains(p.piece));
      expect(owned(s), ++i, reason: 'no duplicates');
    }
    expect(Mock.puzzles.every((p) => s.puzzleComplete(p.id)), isTrue);
    expect(ride(s, 90), isNull, reason: 'docs/51 §2.5: nothing left, nothing brought');
  });

  test('a ride fills a slot of its own tier, and a minute never fills a rare one', () {
    final s = DemoState();
    final hour = ride(s, 68)!;
    expect(tierOf(hour), 'H');
    expect(hour.imageId, 'demo-bahnhofsmission', reason: 'the seeded picture waits for its hour');
    expect(tierOf(ride(s, 25)!), 'q');
    for (var n = 0; n < 40; n++) {
      final p = ride(s, 3);
      if (p == null) break;
      expect(tierOf(p), 'm');
    }
    // Only rare slots are left, and a punctual ride brings nothing.
    expect(ride(s, 0), isNull);
    expect(Mock.puzzles.any((p) => !s.puzzleComplete(p.id)), isTrue);
  });

  test('a rare ride with no slot of its tier left on its side takes the next tier down', () {
    final s = DemoState();
    ride(s, 70);
    final p = ride(s, 70)!;
    // Bahnhofsmission has given its hour: a second hour ride from that side fills its quarter,
    // one from the other side finds the Kinderhospiz picture's hour still open.
    expect(tierOf(p), p.imageId == 'demo-bahnhofsmission' ? 'q' : 'H');
  });

  test('the showcase can bring the last piece of a picture', () {
    final s = DemoState()..preparePuzzleFinish();
    final p = ride(s, 14)!;
    expect(p.imageId, 'demo-bahnhofsmission');
    expect(tierOf(p), 'm', reason: 'the last gap is one any ride may fill');
    expect(s.puzzleComplete(p.imageId), isTrue);
    expect(s.puzzleCompleted[p.imageId], isNotNull);
  });
}
