import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/repo/mock_repository.dart';
import 'package:verspaetomat/state/demo_state.dart';

/// The demo's pieces tell a story that holds together: each has a day it came and a ride, the
/// ride before the day, the day between the picture's first piece and its last — so the tour never
/// shows a piece that came after its picture was finished.
void main() {
  Future<void> holdsTogether(MockRepository repo) async {
    final list = (await repo.puzzles()).puzzles;
    expect(list, isNotEmpty);
    for (final p in list) {
      for (final slot in p.owned) {
        final at = p.awardedAt[slot];
        final ride = p.rides[slot];
        expect(at, isNotNull, reason: '${p.imageId} #$slot has a day');
        expect(ride, isNotNull, reason: '${p.imageId} #$slot has a ride');
        final day = DateTime(at!.toLocal().year, at.toLocal().month, at.toLocal().day);
        expect(ride!.date!.isAfter(day), isFalse, reason: '${p.imageId} #$slot: the ride ${ride.date} is not after the day it came, $day');
        if (p.startedAt != null) expect(at.isBefore(p.startedAt!), isFalse, reason: '${p.imageId} #$slot after the first piece');
        if (p.lastPieceAt != null) expect(at.isAfter(p.lastPieceAt!), isFalse, reason: '${p.imageId} #$slot before the last piece');
        if (p.completedAt != null) expect(at.isAfter(p.completedAt!), isFalse, reason: '${p.imageId} #$slot came before the picture was finished');
      }
    }
  }

  test('as seeded', () async {
    await holdsTogether(MockRepository(DemoState()));
  });

  test('after the showcase readies a picture to finish', () async {
    final state = DemoState()..preparePuzzleFinish();
    final list = (await MockRepository(state).puzzles()).puzzles;
    for (final p in list) {
      for (final slot in p.owned) {
        expect(p.awardedAt[slot], isNotNull, reason: '${p.imageId} #$slot has a day');
        expect(p.rides[slot], isNotNull, reason: '${p.imageId} #$slot has a ride');
      }
    }
  });
}
