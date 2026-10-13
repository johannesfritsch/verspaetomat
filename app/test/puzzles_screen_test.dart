import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:verspaetomat/api/models.dart';
import 'package:verspaetomat/flags/flags.dart';
import 'package:verspaetomat/repo/repo_scope.dart';
import 'package:verspaetomat/screens/puzzles/puzzle_widgets.dart';
import 'package:verspaetomat/screens/puzzles/puzzles_screen.dart';
import 'package:verspaetomat/state/demo_state.dart';
import 'package:verspaetomat/widgets/puzzle.dart';

/// docs/51 §5 and §6: the Puzzles page in each of its states, and the arrival's card, which only
/// shows while the puzzles are on.
void main() {
  // The server's default for twelve: the hour at 4, quarters at 1, 6 and 10.
  const tiers = 'mqmmHmqmmmqm';
  ApiPuzzle puzzle(String id, List<int> owned, {DateTime? completedAt, DateTime? lastPieceAt, bool hasVideo = false}) => ApiPuzzle(
        imageId: id,
        rows: 4,
        cols: 3,
        owned: owned,
        tiers: [for (final c in tiers.split('')) c == 'H' ? PieceTier.hour : (c == 'q' ? PieceTier.quarter : PieceTier.minute)],
        complete: owned.length == 12,
        title: 'Bild $id',
        caption: 'Satz zu $id.',
        ngoId: 'bahnhofsmission',
        ngoName: 'Bahnhofsmission Köln',
        imageUrl: 'assets/demo/puzzles/bahnhofsmission.webp',
        width: 900,
        height: 1200,
        completedAt: completedAt,
        lastPieceAt: lastPieceAt,
        hasVideo: hasVideo,
      );
  final all = [for (var i = 0; i < 12; i++) i];

  Future<Session> session() async {
    SharedPreferences.setMockInitialValues({});
    return Session(demo: DemoState(), prefs: await SharedPreferences.getInstance(), apiUrl: '');
  }

  Future<void> pump(WidgetTester tester, Session s, Widget child) async {
    await tester.binding.setSurfaceSize(const Size(393, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(RepoScope(session: s, child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)))));
    await tester.pumpAndSettle();
  }

  test('a short last word stays with the one before it', () {
    expect(keepLastWord('Nachtschicht am Gleis 1'), 'Nachtschicht am Gleis\u00A01');
    expect(keepLastWord('Die erste Reihe am Hang'), 'Die erste Reihe am\u00A0Hang');
    expect(keepLastWord('Der Garten in Ehrenfeld'), 'Der Garten in Ehrenfeld');
  });

  group('„Fehlt noch"', () {
    List<int> allBut(List<int> gaps) => [for (var i = 0; i < 12; i++) if (!gaps.contains(i)) i];
    test('only while no minute would do', () {
      expect(stillMissing(puzzle('a', allBut([0, 4]))), isNull);
      expect(stillMissing(puzzle('a', allBut([]))), isNull);
    });
    test('one of a kind', () {
      expect(stillMissing(puzzle('a', allBut([4]))), 'Fehlt noch: das Stunden-Teil.');
      expect(stillMissing(puzzle('a', allBut([6]))), 'Fehlt noch: das Viertelstunden-Teil.');
    });
    test('more than one', () {
      expect(stillMissing(puzzle('a', allBut([1, 6]))), 'Fehlt noch: zwei Viertelstunden-Teile.');
      expect(stillMissing(puzzle('a', allBut([1, 6, 10]))), 'Fehlt noch: drei Viertelstunden-Teile.');
    });
    test('both, the hour first', () {
      expect(stillMissing(puzzle('a', allBut([4, 10]))), 'Fehlt noch: das Stunden-Teil und das Viertelstunden-Teil.');
      expect(stillMissing(puzzle('a', allBut([1, 4, 10]))), 'Fehlt noch: das Stunden-Teil und zwei Viertelstunden-Teile.');
    });
  });

  group('the page', () {
    testWidgets('a picture under way and a finished one', (tester) async {
      await pump(
        tester,
        await session(),
        PuzzlesBody(puzzles: ApiPuzzles(puzzles: [puzzle('a', [0, 3, 7, 9, 10, 11, 2]), puzzle('b', all, completedAt: DateTime(2026, 10, 3))])),
      );
      expect(find.text('ANGEFANGEN'), findsOneWidget);
      expect(find.text('FERTIG'), findsOneWidget);
      expect(find.text('7 von 12'), findsOneWidget);
      expect(find.text('Bild\u00A0a'), findsOneWidget);
      expect(find.text('Bild\u00A0b'), findsOneWidget);
      // No second number: nothing adds pieces up across pictures (docs/47).
      expect(find.textContaining('19'), findsNothing);
      expect(find.textContaining('Teile'), findsNothing);

      await tester.tap(find.text('Bild\u00A0b'), warnIfMissed: false); // the card's ink lies over its text
      await tester.pumpAndSettle();
      expect(find.text('Satz zu b.'), findsOneWidget);
      expect(find.textContaining('Fertig am 3. Oktober'), findsOneWidget);
    });

    testWidgets('each picture is one node, and its board says what it shows', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, await session(), PuzzlesBody(puzzles: ApiPuzzles(puzzles: [puzzle('a', [0, 3, 7, 9, 10, 11, 2]), puzzle('b', all)])));
      expect(find.bySemanticsLabel(RegExp(r'^Puzzle Bild a, 7 von 12 Teilen')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Puzzle Bild b, fertig')), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('nothing yet', (tester) async {
      await pump(tester, await session(), const PuzzlesBody(puzzles: ApiPuzzles()));
      expect(find.text('Deine erste Fahrt bringt das erste Teil.'), findsOneWidget);
      expect(find.byType(PuzzleBoard), findsOneWidget);
    });

    testWidgets('everything finished', (tester) async {
      await pump(tester, await session(), PuzzlesBody(puzzles: ApiPuzzles(puzzles: [puzzle('b', all)], moreWaiting: false)));
      expect(find.text('Alle Bilder sind fertig. Neue kommen, wenn die Vereine welche schicken.'), findsOneWidget);
      expect(find.text('ANGEFANGEN'), findsNothing);
    });

    testWidgets('a picture waiting only on rare pieces says which', (tester) async {
      await pump(tester, await session(), PuzzlesBody(puzzles: ApiPuzzles(puzzles: [puzzle('a', [0, 2, 3, 4, 5, 7, 8, 9, 11])])));
      expect(find.text('9 von 12'), findsOneWidget);
      expect(find.text('Fehlt noch: drei Viertelstunden-Teile.'), findsOneWidget);
    });

    testWidgets('a picture under way is not „all finished", whatever more_waiting says', (tester) async {
      await pump(tester, await session(), PuzzlesBody(puzzles: ApiPuzzles(puzzles: [puzzle('a', [1])], moreWaiting: false)));
      expect(find.textContaining('Alle Bilder sind fertig'), findsNothing);
      expect(find.text('1 von 12'), findsOneWidget);
    });

    testWidgets('the whole screen loads from the Demo repository', (tester) async {
      await pump(tester, await session(), const SizedBox(height: 1200, child: PuzzlesScreen()));
      expect(find.text('Deine Puzzles'), findsOneWidget);
      expect(find.text('7 von 12'), findsOneWidget, reason: 'the seeded Bahnhofsmission picture');
      expect(find.textContaining('Fehlt noch'), findsNothing, reason: 'it still has minute gaps');
      expect(find.text('Die erste Reihe am\u00A0Hang'), findsOneWidget, reason: 'the seeded finished one');
    });
  });

  group('the arrival', () {
    final piece = ApiPuzzlePiece(puzzle: puzzle('a', [0, 3, 7, 9, 10, 11, 2, 5]), piece: 5, ownCause: true);

    testWidgets('Demo shows the piece, though every flag is off there', (tester) async {
      final s = await session();
      expect(s.flags.on(Flag.puzzles), isFalse);
      await pump(tester, s, ArrivalPiece(piece: piece));
      expect(find.byKey(const Key('arrival-piece')), findsOneWidget);
      expect(find.text('EIN TEIL FÜR BAHNHOFSMISSION KÖLN'), findsOneWidget);
      expect(find.text('Ein Minuten-Teil.'), findsOneWidget);
      expect(find.text('8 von 12.'), findsOneWidget);
    });

    testWidgets('names the tier, and what the picture still waits for', (tester) async {
      // Everything but the hour; the quarter at 6 just came.
      final p = ApiPuzzlePiece(puzzle: puzzle('a', [0, 1, 2, 3, 5, 6, 7, 8, 9, 10, 11]), piece: 6, ownCause: true);
      await pump(tester, await session(), ArrivalPiece(piece: p));
      expect(find.text('Ein Viertelstunden-Teil.'), findsOneWidget);
      expect(find.text('11 von 12.'), findsOneWidget);
      expect(find.text('Fehlt noch: das Stunden-Teil.'), findsOneWidget);
    });

    testWidgets('against a server, only while the flag is on', (tester) async {
      final s = await session()..mode = BackendMode.local;
      await pump(tester, s, ArrivalPiece(piece: piece));
      expect(find.byKey(const Key('arrival-piece')), findsNothing);

      s.flagStore.pin(Flag.puzzles, on: true);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('arrival-piece')), findsOneWidget);
    });

    testWidgets('a screen reader hears the card whole, from the first frame', (tester) async {
      final semantics = tester.ensureSemantics();
      final s = await session();
      await tester.binding.setSurfaceSize(const Size(393, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(RepoScope(session: s, child: MaterialApp(home: Scaffold(body: ArrivalPiece(piece: piece)))));
      // Before the piece has come in and „8 von 12" has faded up: the label does not wait for it.
      await tester.pump();
      expect(find.bySemanticsLabel('Ein Minuten-Teil für Bahnhofsmission Köln, 8 von 12'), findsOneWidget);
      await tester.pumpAndSettle();
      final node = tester.getSemantics(find.bySemanticsLabel('Ein Minuten-Teil für Bahnhofsmission Köln, 8 von 12'));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

      final waiting = ApiPuzzlePiece(puzzle: puzzle('a', [0, 1, 2, 3, 5, 6, 7, 8, 9, 10, 11]), piece: 6);
      await tester.pumpWidget(RepoScope(session: s, child: MaterialApp(home: Scaffold(body: ArrivalPiece(piece: waiting)))));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Ein Viertelstunden-Teil von Bahnhofsmission Köln, 11 von 12. Fehlt noch: das Stunden-Teil.'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('no piece, no card', (tester) async {
      await pump(tester, await session(), const ArrivalPiece(piece: null));
      expect(find.byKey(const Key('arrival-piece')), findsNothing);
    });

    testWidgets('a piece from somebody else\'s Verein says so', (tester) async {
      await pump(tester, await session(), ArrivalPiece(piece: ApiPuzzlePiece(puzzle: piece.puzzle, piece: 5)));
      expect(find.text('EIN TEIL VON BAHNHOFSMISSION KÖLN'), findsOneWidget);
      expect(find.text('Ein Verein, den andere unterstützen.'), findsOneWidget);
    });

    testWidgets('the last piece finishes the picture', (tester) async {
      await pump(tester, await session(), ArrivalPiece(piece: ApiPuzzlePiece(puzzle: puzzle('a', all), piece: 4, ownCause: true)));
      expect(find.text('Ein Stunden-Teil.'), findsOneWidget);
      expect(find.text('12 von 12.'), findsOneWidget);
      expect(find.text('Fertig: Bild\u00A0a.'), findsOneWidget);
      expect(find.text('Satz zu a.'), findsOneWidget);
    });
  });

  group('Home and Ich', () {
    final mon = DateTime.utc(2026, 10, 5);
    final tue = DateTime.utc(2026, 10, 6);

    test('the picture most recently added to comes first, then the finished ones, newest first', () {
      final order = puzzlesInOrder(ApiPuzzles(puzzles: [
        puzzle('alt', all, completedAt: mon),
        puzzle('b', [0], lastPieceAt: mon),
        puzzle('neu', all, completedAt: tue),
        puzzle('c', [0, 1], lastPieceAt: tue),
      ]));
      expect(order.map((p) => p.imageId), ['c', 'b', 'neu', 'alt']);
    });

    testWidgets('Home shows the picture under way, how far it is and what it waits for', (tester) async {
      await pump(tester, await session(), HomePuzzlesCard(puzzles: ApiPuzzles(puzzles: [
        puzzle('fertig', all, completedAt: tue),
        puzzle('a', [0, 1, 2, 3, 5, 6, 7, 8, 9, 10, 11], lastPieceAt: mon, hasVideo: true),
      ])));
      expect(find.text('DEINE PUZZLES'), findsOneWidget);
      expect(find.text('Alle ansehen'), findsOneWidget);
      expect(find.text('Bild\u00A0a'), findsOneWidget);
      expect(find.text('11 von 12'), findsOneWidget);
      expect(find.text('Fehlt noch: das Stunden-Teil.'), findsOneWidget);
      expect(find.text('Bild fertig'), findsNothing);
    });

    testWidgets('Home promises the film while minutes would still do', (tester) async {
      await pump(tester, await session(), HomePuzzlesCard(puzzles: ApiPuzzles(puzzles: [puzzle('a', [0, 3], lastPieceAt: mon, hasVideo: true)])));
      expect(find.text('2 von 12'), findsOneWidget);
      expect(find.text('Bewegt sich, wenn es fertig ist.'), findsOneWidget);
    });

    testWidgets('Home with everything finished shows the newest', (tester) async {
      await pump(tester, await session(), HomePuzzlesCard(puzzles: ApiPuzzles(puzzles: [puzzle('alt', all, completedAt: mon), puzzle('neu', all, completedAt: tue, hasVideo: true)])));
      expect(find.text('Bild\u00A0neu'), findsOneWidget);
      expect(find.text('Fertig'), findsOneWidget);
      expect(find.text('Das Bild bewegt sich jetzt.'), findsOneWidget);
    });

    testWidgets('Home before the first piece', (tester) async {
      await pump(tester, await session(), const HomePuzzlesCard(puzzles: ApiPuzzles()));
      expect(find.text('Deine erste Fahrt bringt das erste Teil.'), findsOneWidget);
      await pump(tester, await session(), const HomePuzzlesCard(puzzles: ApiPuzzles(moreWaiting: false)));
      expect(find.text('Noch keine Bilder.'), findsOneWidget);
    });

    testWidgets('Ich: one board per picture, the count under it', (tester) async {
      await pump(tester, await session(), PuzzlesStrip(puzzles: ApiPuzzles(puzzles: [puzzle('fertig', all, completedAt: tue), puzzle('a', [0, 3], lastPieceAt: mon)])));
      expect(find.byType(PuzzleBoard), findsNWidgets(2));
      expect(find.text('2 von 12'), findsOneWidget);
      expect(find.text('Fertig'), findsOneWidget);
      // The one under way first.
      expect(tester.getTopLeft(find.text('2 von 12')).dx, lessThan(tester.getTopLeft(find.text('Fertig')).dx));
    });

    testWidgets('Ich before the first piece', (tester) async {
      await pump(tester, await session(), const PuzzlesStrip(puzzles: ApiPuzzles()));
      expect(find.text('Deine erste Fahrt bringt das erste Teil.'), findsOneWidget);
    });
  });
}
