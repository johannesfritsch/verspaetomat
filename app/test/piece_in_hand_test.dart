import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:verspaetomat/api/models.dart';
import 'package:verspaetomat/repo/repo_scope.dart';
import 'package:verspaetomat/screens/puzzles/piece_in_hand.dart' show PieceBack, boardFor;
import 'package:verspaetomat/screens/puzzles/puzzle_widgets.dart' show ArrivalPiece, cutOf;
import 'package:verspaetomat/screens/puzzles/puzzles_screen.dart';
import 'package:verspaetomat/state/demo_state.dart';
import 'package:verspaetomat/widgets/kit.dart' show VSegmented;
import 'package:verspaetomat/widgets/puzzle.dart';

/// docs/51 §6, §9a: a started picture opens whole, with its holes, or laid apart into its pieces;
/// a tap on a piece you have lifts it into the hand, a tap on a gap does nothing.
void main() {
  const tiers = 'mqmmHmqmmmqm';
  final puzzle = ApiPuzzle(
    imageId: 'a',
    rows: 4,
    cols: 3,
    owned: const [0, 3, 4, 7],
    tiers: [for (final c in tiers.split('')) c == 'H' ? PieceTier.hour : (c == 'q' ? PieceTier.quarter : PieceTier.minute)],
    title: 'Nachtschicht am Gleis 1',
    ngoId: 'bahnhofsmission',
    ngoName: 'Bahnhofsmission Köln',
    imageUrl: 'assets/demo/puzzles/bahnhofsmission.webp',
    width: 900,
    height: 1200,
    // Slot 7 names the ride that brought it; the others name none.
    rides: {7: ApiPieceRide(journeyId: 'j7', date: DateTime(2026, 10, 12), from: 'Köln Hbf', to: 'Düsseldorf Hbf', minutes: 68, lines: ['RE 1'])},
  );

  Future<void> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final session = Session(demo: DemoState(), prefs: await SharedPreferences.getInstance(), apiUrl: '');
    // A phone's screen, and the same size in MediaQuery: the piece in the hand is laid out from it.
    tester.view
      ..physicalSize = const Size(393, 852)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepoScope(
      session: session,
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PuzzlesBody(puzzles: ApiPuzzles(puzzles: [puzzle]))))),
    ));
    await tester.pumpAndSettle();
  }

  /// The middle of slot [slot] on an arrival card's board.
  Offset slotCentre(WidgetTester tester, int slot) {
    final r = tester.getRect(find.byType(PuzzleTapArea));
    final cw = r.width / 3, ch = r.height / 4;
    return r.topLeft + Offset((slot % 3 + 0.5) * cw, (slot ~/ 3 + 0.5) * ch);
  }

  /// Opens the picture from its card, and lays it apart into its pieces.
  Future<void> openPieces(WidgetTester tester) async {
    await tester.tap(find.text('4 von 12'), warnIfMissed: false); // the card's ink lies over its text
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('segment-Teile')));
    await tester.pumpAndSettle();
  }

  /// The middle of slot [slot]'s body among the pieces laid apart.
  Offset spreadCentre(WidgetTester tester, int slot) {
    final r = tester.getRect(find.byKey(const Key('puzzle-spread')));
    final f = PuzzleSpread.fit(const PuzzleCut(imageId: 'a', rows: 4, cols: 3), 0.75, r.size);
    final cell = Rect.fromLTWH((slot % 3) * f.cell.width, (slot ~/ 3) * f.cell.height, f.cell.width, f.cell.height);
    return r.topLeft + PuzzleSpread.shift(const PuzzleCut(imageId: 'a', rows: 4, cols: 3), slot, f.gap) + cell.center;
  }

  testWidgets('the card opens the picture whole, with a hole for each missing piece', (tester) async {
    await pump(tester);
    // The card's board lifts nothing by itself any more: the whole card opens the picture.
    expect(find.byType(PuzzleTapArea), findsNothing);
    await tester.tap(find.text('4 von 12'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('puzzle-tile')), findsOneWidget);
    expect(find.byKey(const Key('puzzle-spread')), findsNothing);
    expect(find.text('Zum Drehen ziehen.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('segment-Teile')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('puzzle-tile')), findsNothing);
    expect(find.byKey(const Key('puzzle-spread')), findsOneWidget);

    await tester.tap(find.byKey(const Key('segment-Puzzle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('puzzle-tile')), findsOneWidget);
  });

  testWidgets('an owned piece rises into the hand, and goes back', (tester) async {
    await pump(tester);
    await openPieces(tester);
    await tester.tapAt(spreadCentre(tester, 4));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('piece-in-hand')), findsOneWidget);
    // On the dark ground the status bar's text is light.
    expect(find.byWidgetPredicate((w) => w is AnnotatedRegion<SystemUiOverlayStyle> && w.value == SystemUiOverlayStyle.light), findsOneWidget);
    expect(find.text('Ein Stunden-Teil'), findsOneWidget);
    expect(find.text('Platz 5 von 12'), findsOneWidget);
    expect(find.text('Bahnhofsmission Köln'), findsWidgets);

    await tester.tap(find.byKey(const Key('piece-in-hand-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('piece-in-hand')), findsNothing);
    // Back on the pieces, where it was taken from.
    expect(find.byKey(const Key('puzzle-spread')), findsOneWidget);
  });

  testWidgets('it rises front up, and the switch turns it over and back', (tester) async {
    await pump(tester);
    await openPieces(tester);
    await tester.tapAt(spreadCentre(tester, 4));
    await tester.pumpAndSettle();
    expect(find.byType(PieceBack), findsNothing);

    await tester.tap(find.byKey(const Key('segment-Rückseite')));
    await tester.pumpAndSettle();
    expect(find.byType(PieceBack), findsOneWidget);
    // The back says what the piece is, whose, and where it goes.
    expect(find.descendant(of: find.byType(PieceBack), matching: find.text('Stunden-Teil')), findsOneWidget);
    expect(find.descendant(of: find.byType(PieceBack), matching: find.text('Platz 5 von 12')), findsOneWidget);

    await tester.tap(find.byKey(const Key('segment-Vorderseite')));
    await tester.pumpAndSettle();
    expect(find.byType(PieceBack), findsNothing);
  });

  testWidgets('a swipe that turns it over moves the switch with it', (tester) async {
    await pump(tester);
    await openPieces(tester);
    await tester.tapAt(spreadCentre(tester, 4));
    await tester.pumpAndSettle();
    await tester.fling(find.byKey(const Key('piece-in-hand')), const Offset(260, 0), 3000);
    await tester.pumpAndSettle();
    expect(find.byType(PieceBack), findsOneWidget);
    expect(tester.widget<VSegmented<bool>>(find.byKey(const Key('piece-side'))).value, isTrue);
  });

  testWidgets('a tap beside the piece puts it back too', (tester) async {
    await pump(tester);
    await openPieces(tester);
    await tester.tapAt(spreadCentre(tester, 3));
    await tester.pumpAndSettle();
    expect(find.text('Ein Minuten-Teil'), findsOneWidget);
    await tester.tapAt(const Offset(30, 700));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('piece-in-hand')), findsNothing);
  });

  testWidgets('on the arrival, once the piece is in, its board takes the tap', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final session = Session(demo: DemoState(), prefs: await SharedPreferences.getInstance(), apiUrl: '');
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(RepoScope(
      session: session,
      child: MaterialApp(home: Scaffold(body: ArrivalPiece(piece: ApiPuzzlePiece(puzzle: puzzle, piece: 7, ownCause: true)))),
    ));
    // While the piece comes in, the board takes no taps of its own.
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(PuzzleTapArea), findsNothing);
    await tester.pumpAndSettle();
    await tester.tapAt(slotCentre(tester, 7));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('piece-in-hand')), findsOneWidget);
    expect(find.text('Platz 8 von 12'), findsOneWidget);
  });

  testWidgets('a swipe down beside the piece puts it back', (tester) async {
    await pump(tester);
    await openPieces(tester);
    await tester.tapAt(spreadCentre(tester, 4));
    await tester.pumpAndSettle();
    await tester.flingFrom(const Offset(40, 680), const Offset(0, 60), 1200);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('piece-in-hand')), findsNothing);
  });

  testWidgets('a screen reader hears each piece laid apart, and can take it into the hand', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    await openPieces(tester);
    final piece = find.semantics.byLabel('Stunden-Teil, Platz 5 von 12');
    expect(piece, findsOne);
    expect(piece.evaluate().single.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    // A gap is not a piece: it says nothing.
    expect(find.semantics.byLabel(RegExp(r'Platz 6 von 12')), findsNothing);
    tester.semantics.tap(piece);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('piece-in-hand')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a gap is not a piece', (tester) async {
    await pump(tester);
    await openPieces(tester);
    await tester.tapAt(spreadCentre(tester, 5));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('piece-in-hand')), findsNothing);
  });

  testWidgets('a screen reader hears what it is, and can close it', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    await openPieces(tester);
    await tester.tapAt(spreadCentre(tester, 4));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp(r'^Ein Stunden-Teil von Bahnhofsmission Köln, Platz 5 von 12')), findsWidgets);
    expect(find.bySemanticsLabel('Schließen'), findsOneWidget);
    semantics.dispose();
  });

  test('the board as it stands has a hole where each missing piece belongs', () {
    const cut = PuzzleCut(imageId: 'a', rows: 4, cols: 3);
    const board = Size(300, 400);
    final outline = boardOutline(cut, const {0, 3, 4, 7}, board, radius: 10);
    Offset middle(int slot) => cut.cellRect(slot, const Size(100, 100)).center;
    for (final owned in [0, 3, 4, 7]) {
      expect(outline.contains(middle(owned)), isTrue, reason: 'slot $owned');
    }
    for (final gap in [1, 2, 5, 6, 8, 9, 10, 11]) {
      expect(outline.contains(middle(gap)), isFalse, reason: 'slot $gap');
    }
    // Whole: no holes at all.
    final whole = boardOutline(cut, {for (var i = 0; i < 12; i++) i}, board);
    expect(whole.contains(middle(5)), isTrue);
  });

  test('pieces laid apart never touch', () {
    const cut = PuzzleCut(imageId: 'a', rows: 4, cols: 3);
    final f = PuzzleSpread.fit(cut, 0.75, const Size(340, 380));
    for (var i = 0; i < 12; i++) {
      final a = cut.piece(i, f.cell).shift(PuzzleSpread.shift(cut, i, f.gap));
      for (final j in [i + 1, i + 3]) {
        if (j >= 12 || (j == i + 1 && j % 3 == 0)) continue;
        final b = cut.piece(j, f.cell).shift(PuzzleSpread.shift(cut, j, f.gap));
        final both = Path.combine(PathOperation.intersect, a, b);
        expect(both.getBounds().isEmpty, isTrue, reason: '$i and $j');
      }
    }
  });

  testWidgets('the body stands in the middle and the piece turns about it, wherever its knobs are', (tester) async {
    await pump(tester);
    final cut = cutOf(puzzle);
    final board = boardFor(puzzle);
    final cell = Size(board.width / cut.cols, board.height / cut.rows);
    var lopsided = 0;
    double? line;
    await openPieces(tester);
    for (final slot in puzzle.owned) {
      final bounds = cut.piece(slot, cell).getBounds();
      final body = cut.cellRect(slot, cell);
      // Knobs on one side only: the box they span is off the body's middle.
      if ((bounds.center.dx - body.center.dx).abs() > 1) lopsided++;

      await tester.tapAt(spreadCentre(tester, slot));
      await tester.pumpAndSettle();
      final tile = find.byKey(const Key('piece-in-hand'));
      final r = tester.getRect(tile);
      final scale = r.width / bounds.width;
      final middle = (body.center - bounds.topLeft) * scale;
      expect(r.left + middle.dx, closeTo(393 / 2, 0.5), reason: 'slot $slot stands in the middle');
      // Every piece's body on the same line, whatever reaches out above or below it.
      line ??= r.top + middle.dy;
      expect(r.top + middle.dy, closeTo(line, 0.5), reason: 'slot $slot keeps the line');
      final pivot = (tester.state(tile) as dynamic).pivot as Offset;
      expect(pivot.dx, closeTo(middle.dx, 0.01), reason: 'slot $slot turns about its body');
      expect(pivot.dy, closeTo(middle.dy, 0.01), reason: 'slot $slot turns about its body');

      await tester.tap(find.byKey(const Key('piece-in-hand-close')));
      await tester.pumpAndSettle();
    }
    expect(lopsided, greaterThan(0), reason: 'at least one piece has a knob on one side only, or this proves nothing');
  });

  testWidgets('the back names the ride that brought the piece, and a piece without one says nothing of a ride', (tester) async {
    await pump(tester);
    await openPieces(tester);
    await tester.tapAt(spreadCentre(tester, 7));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('segment-Rückseite')));
    await tester.pumpAndSettle();
    Finder onBack(String text) => find.descendant(of: find.byType(PieceBack), matching: find.text(text));
    expect(onBack('RE 1'), findsOneWidget);
    expect(onBack('12. Okt.'), findsOneWidget);
    expect(onBack('Köln Hbf'), findsOneWidget);
    expect(onBack('→ Düsseldorf Hbf'), findsOneWidget);
    expect(onBack('68 Minuten'), findsOneWidget);
    // With a ride, the clock and the ride: tier and place stand on the page under the piece.
    expect(onBack('Minuten-Teil'), findsNothing);
    expect(onBack('Platz 8 von 12'), findsNothing);
    expect(find.text('Platz 8 von 12'), findsOneWidget);

    await tester.tap(find.byKey(const Key('piece-in-hand-close')));
    await tester.pumpAndSettle();
    await tester.tapAt(spreadCentre(tester, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('segment-Rückseite')));
    await tester.pumpAndSettle();
    expect(find.byType(PieceBack), findsOneWidget);
    expect(onBack('Minuten-Teil'), findsOneWidget, reason: 'without a ride, the back is as it was');
    expect(find.descendant(of: find.byType(PieceBack), matching: find.textContaining('→')), findsNothing);
    // „Minuten-Teil" is its tier; a ride's minutes would be a line of their own.
    expect(find.descendant(of: find.byType(PieceBack), matching: find.textContaining(RegExp(r'^\d+ Minuten?$|^pünktlich$'))), findsNothing);
  });
}
