import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:verspaetomat/api/models.dart';
import 'package:verspaetomat/repo/repo_scope.dart';
import 'package:verspaetomat/screens/puzzles/puzzle_widgets.dart' show ArrivalPiece;
import 'package:verspaetomat/screens/puzzles/puzzles_screen.dart';
import 'package:verspaetomat/state/demo_state.dart';
import 'package:verspaetomat/widgets/puzzle.dart';

/// docs/51 §9a: a tap on a piece you have lifts it into the hand; a tap on a gap does nothing.
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
  );

  Future<void> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final session = Session(demo: DemoState(), prefs: await SharedPreferences.getInstance(), apiUrl: '');
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(RepoScope(
      session: session,
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PuzzlesBody(puzzles: ApiPuzzles(puzzles: [puzzle]))))),
    ));
    await tester.pumpAndSettle();
  }

  /// The middle of slot [slot] on the started card's board.
  Offset slotCentre(WidgetTester tester, int slot) {
    final r = tester.getRect(find.byType(PuzzleTapArea));
    final cw = r.width / 3, ch = r.height / 4;
    return r.topLeft + Offset((slot % 3 + 0.5) * cw, (slot ~/ 3 + 0.5) * ch);
  }

  testWidgets('an owned piece rises into the hand, and goes back', (tester) async {
    await pump(tester);
    await tester.tapAt(slotCentre(tester, 4));
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
  });

  testWidgets('a tap beside the piece puts it back too', (tester) async {
    await pump(tester);
    await tester.tapAt(slotCentre(tester, 3));
    await tester.pumpAndSettle();
    expect(find.text('Ein Minuten-Teil'), findsOneWidget);
    await tester.tapAt(const Offset(30, 820));
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
    await tester.tapAt(slotCentre(tester, 4));
    await tester.pumpAndSettle();
    await tester.flingFrom(const Offset(40, 780), const Offset(0, 60), 1200);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('piece-in-hand')), findsNothing);
  });

  testWidgets('a screen reader can take a piece into the hand from the started card', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    final node = tester.getSemantics(find.bySemanticsLabel(RegExp(r'^Puzzle Nachtschicht')));
    final actions = node.getSemanticsData().customSemanticsActionIds ?? const <int>[];
    expect(actions.map((id) => CustomSemanticsAction.getAction(id)?.label), contains('Teil in die Hand nehmen'));
    semantics.dispose();
  });

  testWidgets('a gap is not a piece', (tester) async {
    await pump(tester);
    await tester.tapAt(slotCentre(tester, 5));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('piece-in-hand')), findsNothing);
  });

  testWidgets('a screen reader hears what it is, and can close it', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    await tester.tapAt(slotCentre(tester, 4));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp(r'^Ein Stunden-Teil von Bahnhofsmission Köln, Platz 5 von 12')), findsWidgets);
    expect(find.bySemanticsLabel('Schließen'), findsOneWidget);
    semantics.dispose();
  });
}
