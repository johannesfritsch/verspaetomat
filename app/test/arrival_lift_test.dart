import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:verspaetomat/api/models.dart';
import 'package:verspaetomat/repo/repo_scope.dart';
import 'package:verspaetomat/screens/puzzles/piece_in_hand.dart' show PieceInHand;
import 'package:verspaetomat/screens/puzzles/puzzle_widgets.dart';
import 'package:verspaetomat/state/demo_state.dart';
import 'package:verspaetomat/widgets/puzzle.dart' show PuzzleTapArea;

/// After a ride (Johannes, 14 October 2026): the new piece rises into the hand in 3D once the
/// minutes have counted up, and goes into its slot on the arrival card when it is put back.
void main() {
  const tiers = 'mqmmHmqmmmqm';
  final piece = ApiPuzzlePiece(
    puzzle: ApiPuzzle(
      imageId: 'a',
      rows: 4,
      cols: 3,
      owned: const [0, 2, 3, 5, 7, 9, 10, 11],
      tiers: [for (final c in tiers.split('')) c == 'H' ? PieceTier.hour : (c == 'q' ? PieceTier.quarter : PieceTier.minute)],
      title: 'Nachtschicht am Gleis 1',
      ngoId: 'bahnhofsmission',
      ngoName: 'Bahnhofsmission Köln',
      imageUrl: 'assets/demo/puzzles/bahnhofsmission.webp',
      width: 900,
      height: 1200,
      rides: {5: ApiPieceRide(journeyId: 'j', date: DateTime(2026, 10, 14), from: 'Kißlegg', to: 'Memmingen', minutes: 70, lines: ['RE 96'])},
    ),
    piece: 5,
    ownCause: true,
  );

  setUp(ArrivalPieceCard.lifted.clear);

  Future<void> pump(WidgetTester tester, Widget card, {bool reduceMotion = false}) async {
    SharedPreferences.setMockInitialValues({});
    final s = Session(demo: DemoState(), prefs: await SharedPreferences.getInstance(), apiUrl: '');
    tester.view
      ..physicalSize = const Size(393, 852)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepoScope(
      session: s,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion), child: child!),
        home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.only(top: 500), child: card))),
      ),
    ));
  }

  testWidgets('it rises out of its slot once the minutes have counted, and clicks in when put back', (tester) async {
    await pump(tester, ArrivalPiece(piece: piece, delay: const Duration(milliseconds: 600), lift: true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(PieceInHand), findsNothing, reason: 'not before the minutes have counted');

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byType(PieceInHand), findsOneWidget);
    expect(find.text('Platz 6 von 12'), findsOneWidget);
    // Out of its own slot on the card, which was scrolled into view first.
    final hand = tester.widget<PieceInHand>(find.byType(PieceInHand));
    expect(hand.slot, 5);
    final board = tester.getRect(find.byKey(const Key('arrival-piece')));
    expect(hand.from, isNotNull);
    expect(board.overlaps(hand.from!), isTrue, reason: '${hand.from} on the card $board');
    expect(board.bottom, lessThanOrEqualTo(852), reason: 'the card is on the screen');
    // While it is in the hand, its slot on the board stays empty: the board takes no taps yet.
    expect(find.byType(PuzzleTapArea), findsNothing);

    await tester.tap(find.byKey(const Key('piece-in-hand-close')));
    await tester.pumpAndSettle();
    expect(find.byType(PieceInHand), findsNothing);
    // In its slot now, the reveal run to its end: the board takes taps again.
    expect(find.byType(PuzzleTapArea), findsOneWidget);
    expect(find.text('8 von 12.'), findsOneWidget);
  });

  testWidgets('once per piece: the sheet opened again shows it in place', (tester) async {
    await pump(tester, ArrivalPiece(piece: piece, delay: const Duration(milliseconds: 100), lift: true));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('piece-in-hand-close')));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    await pump(tester, ArrivalPiece(piece: piece, delay: const Duration(milliseconds: 100), lift: true));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.byType(PieceInHand), findsNothing);
    expect(find.byType(PuzzleTapArea), findsOneWidget);
  });

  testWidgets('not where no ride ended, and not with animations switched off', (tester) async {
    await pump(tester, ArrivalPiece(piece: piece, delay: const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.byType(PieceInHand), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await pump(tester, ArrivalPiece(piece: piece, delay: const Duration(milliseconds: 100), lift: true), reduceMotion: true);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.byType(PieceInHand), findsNothing);
    expect(find.byType(PuzzleTapArea), findsOneWidget, reason: 'in place at once, a tap away from the hand');
  });
}
