import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/api/models.dart';

/// docs/51 §8: the wire as the concept writes it down.
void main() {
  const piece = {
    'image_id': '0f9a7c1e-2b3d-4e5f-8a9b-0c1d2e3f4a5b',
    'piece': 7,
    'tier': 'quarter',
    'rows': 4,
    'tiers': ['minute', 'quarter', 'minute', 'minute', 'hour', 'minute', 'quarter', 'minute', 'minute', 'minute', 'quarter', 'minute'],
    'cols': 3,
    'owned': [0, 3, 7],
    'complete': false,
    'title': 'Nachtschicht am Gleis 1',
    'caption': 'Ein Becher Tee um drei Uhr nachts.',
    'ngo_id': 'bahnhofsmission',
    'ngo_name': 'Bahnhofsmission Köln',
    'own_cause': true,
    'image_url': '/v1/puzzle-images/0f9a7c1e-2b3d-4e5f-8a9b-0c1d2e3f4a5b',
    'width': 900,
    'height': 1200,
    'awarded_at': '2026-10-12T17:40:00Z',
  };

  test('a piece', () {
    final p = ApiPuzzlePiece.fromJson(piece);
    expect(p.piece, 7);
    expect(p.ownCause, isTrue);
    expect(p.awardedAt, DateTime.utc(2026, 10, 12, 17, 40));
    expect(p.puzzle.imageId, '0f9a7c1e-2b3d-4e5f-8a9b-0c1d2e3f4a5b');
    expect(p.puzzle.rows, 4);
    expect(p.puzzle.cols, 3);
    expect(p.puzzle.pieces, 12);
    expect(p.puzzle.owned, [0, 3, 7]);
    expect(p.puzzle.complete, isFalse);
    expect(p.puzzle.ngoName, 'Bahnhofsmission Köln');
    expect(p.puzzle.imageUrl, startsWith('/v1/puzzle-images/'));
    expect(p.puzzle.aspectRatio, 0.75);
  });

  test('tiers', () {
    final p = ApiPuzzlePiece.fromJson(piece);
    expect(p.tier, PieceTier.quarter);
    expect(p.puzzle.tiers, hasLength(12));
    expect(p.puzzle.tierOf(4), PieceTier.hour);
    expect(p.puzzle.tierOf(1), PieceTier.quarter);
    expect(p.puzzle.tierOf(0), PieceTier.minute);
    expect(p.puzzle.slotTiers.where((t) => t == PieceTier.quarter), hasLength(3));
  });

  test('a server before tiers: every slot a minute', () {
    final old = {...piece}
      ..remove('tier')
      ..remove('tiers');
    final p = ApiPuzzlePiece.fromJson(old);
    expect(p.tier, PieceTier.minute);
    expect(p.puzzle.tiers, isEmpty);
    expect(p.puzzle.slotTiers, List.filled(12, PieceTier.minute));
    expect(p.puzzle.tierOf(4), PieceTier.minute);
    // A tier this build has never heard of is a minute too, not a crash.
    expect(ApiPuzzlePiece.fromJson({...piece, 'tier': 'tag'}).tier, PieceTier.minute);
    // Without its own tier a piece takes its slot's.
    expect(ApiPuzzlePiece.fromJson({...piece}..remove('tier')).tier, PieceTier.minute);
    expect(ApiPuzzlePiece.fromJson({...piece, 'piece': 4}..remove('tier')).tier, PieceTier.hour);
  });

  test('a picture that moves: promised before it is finished, named once it is', () {
    final underway = ApiPuzzle.fromJson({...piece, 'has_video': true, 'video': null});
    expect(underway.hasVideo, isTrue);
    expect(underway.video, isNull);
    final done = ApiPuzzle.fromJson({
      ...piece,
      'complete': true,
      'has_video': true,
      'video': {'url': '/v1/puzzle-videos/x', 'bytes': 2400000, 'seconds': 20.5, 'sha256': 'ab' * 32, 'width': 900, 'height': 1200},
    });
    expect(done.video!.url, '/v1/puzzle-videos/x');
    expect(done.video!.bytes, 2400000);
    expect(done.video!.seconds, 20.5);
    expect(done.video!.aspectRatio, 0.75);
    expect(ApiPuzzlePiece.fromJson({...piece, 'has_video': true}).puzzle.hasVideo, isTrue);
  });

  test('a server before films: no promise, no film', () {
    final p = ApiPuzzle.fromJson(piece);
    expect(p.hasVideo, isFalse);
    expect(p.video, isNull);
  });

  test('the current journey carries it beside just_arrived, and an older server not at all', () {
    final journey = {'id': 'j1', 'status': 'arrived', 'created_at': '2026-10-12T17:00:00Z'};
    final live = ApiJourneyLive.fromJson({'journey': journey, 'just_arrived': true, 'piece': piece});
    expect(live.piece?.piece, 7);
    expect(ApiJourneyLive.fromJson({'journey': journey, 'just_arrived': true}).piece, isNull);
    expect(ApiJourneyLive.fromJson({'journey': journey, 'piece': null}).piece, isNull);
  });

  test('the finished journey carries it too', () {
    final j = ApiJourney.fromJson({'id': 'j1', 'status': 'arrived', 'created_at': '2026-10-12T17:00:00Z', 'piece': piece});
    expect(j.piece?.puzzle.title, 'Nachtschicht am Gleis 1');
  });

  test('the collection', () {
    final all = ApiPuzzles.fromJson({
      'puzzles': [
        {...({...piece}..remove('piece')), 'started_at': '2026-10-01T08:00:00Z', 'last_piece_at': '2026-10-12T17:40:00Z', 'completed_at': null},
        {
          ...piece,
          'image_id': 'w',
          'owned': [for (var i = 0; i < 12; i++) i],
          'complete': true,
          'completed_at': '2026-10-03T07:12:00Z',
        },
      ],
      'more_waiting': false,
    });
    expect(all.puzzles, hasLength(2));
    expect(all.moreWaiting, isFalse);
    expect(all.puzzles.first.lastPieceAt, DateTime.utc(2026, 10, 12, 17, 40));
    expect(all.puzzles.first.completedAt, isNull);
    expect(all.puzzles.last.complete, isTrue);
    expect(all.puzzles.last.completedAt, DateTime.utc(2026, 10, 3, 7, 12));
    // Absent means there may well be more: never „Alle Bilder sind fertig" on a guess.
    expect(ApiPuzzles.fromJson({'puzzles': []}).moreWaiting, isTrue);
  });
}
