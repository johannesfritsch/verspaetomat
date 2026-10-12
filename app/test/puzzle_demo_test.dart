import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/mock/mock_data.dart';
import 'package:verspaetomat/state/demo_state.dart';

/// docs/51 §2–§3 as Demo mode plays them.
void main() {
  /// A Demo whose day moves on with every ride, so the cap of three a day stays out of the way.
  DemoState demo() {
    var day = DateTime(2026, 10, 1, 8);
    return DemoState()
      ..puzzleClock = () {
        day = day.add(const Duration(days: 1));
        return day;
      };
  }

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
    final s = demo();
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
    final s = demo();
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

  test('a rare piece goes to a slot of its own tier on the other side before a lower one on its own', () {
    final s = demo();
    expect(ride(s, 70)!.imageId, 'demo-bahnhofsmission', reason: 'the own picture waits for its hour');
    // Bahnhofsmission has given its hour but still has a quarter open; the hour waiting in the
    // Kinderhospiz picture comes first, whichever side the dice name.
    final p = ride(s, 68)!;
    expect(p.imageId, 'demo-kinderhospiz');
    expect(tierOf(p), 'H');
    expect(p.ownCause, isFalse);
  });

  test('three pieces a day, then none until the next', () {
    var now = DateTime(2026, 10, 12, 7);
    final s = DemoState()..puzzleClock = () => now;
    for (var i = 0; i < DemoState.maxPiecesPerDay; i++) {
      expect(ride(s), isNotNull, reason: 'ride ${i + 1}');
    }
    expect(ride(s), isNull, reason: 'the fourth of the day brings nothing');
    now = DateTime(2026, 10, 13, 7);
    expect(ride(s), isNotNull, reason: 'a new day');
  });

  test('the showcase can bring the last piece of a picture', () {
    final s = demo()..preparePuzzleFinish();
    final p = ride(s, 14)!;
    expect(p.imageId, 'demo-bahnhofsmission');
    expect(tierOf(p), 'm', reason: 'the last gap is one any ride may fill');
    expect(s.puzzleComplete(p.imageId), isTrue);
    expect(s.puzzleCompleted[p.imageId], isNotNull);
  });
}
