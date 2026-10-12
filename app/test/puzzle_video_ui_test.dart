import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:verspaetomat/api/models.dart';
import 'package:verspaetomat/repo/repo_scope.dart';
import 'package:verspaetomat/screens/puzzles/piece_in_hand.dart';
import 'package:verspaetomat/screens/puzzles/puzzle_video.dart';
import 'package:verspaetomat/screens/puzzles/puzzle_widgets.dart';
import 'package:verspaetomat/screens/puzzles/puzzles_screen.dart';
import 'package:verspaetomat/state/demo_state.dart';
import 'package:verspaetomat/state/puzzle_video_store.dart';

/// docs/51 §9b in the app: the button on a finished picture in each of its states, the player it
/// opens, the arrival's line for a finished picture that moves, and the promise on one under way.
void main() {
  final all = [for (var i = 0; i < 12; i++) i];

  ApiPuzzle puzzle({bool complete = true, bool hasVideo = true, String url = '/v1/puzzle-videos/w'}) => ApiPuzzle(
        imageId: 'w',
        rows: 4,
        cols: 3,
        owned: complete ? all : const [0, 1, 2],
        complete: complete,
        title: 'Die erste Reihe am Hang',
        caption: 'Vierhundert Setzlinge.',
        ngoId: 'wald',
        ngoName: 'Wald für morgen e.V.',
        imageUrl: 'assets/demo/puzzles/wald.webp',
        width: 900,
        height: 1200,
        hasVideo: hasVideo,
        video: complete && hasVideo ? ApiPuzzleVideo(url: url, bytes: 1000, seconds: 20, sha256: 'abcdef01', width: 900, height: 1200) : null,
      );

  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('films'));
  tearDown(() => dir.delete(recursive: true));

  Future<Session> session(VideoFetch fetch) async {
    SharedPreferences.setMockInitialValues({});
    return Session(
      demo: DemoState(),
      prefs: await SharedPreferences.getInstance(),
      apiUrl: '',
      videoStore: PuzzleVideoStore(fetch: fetch, directory: () async => dir),
    );
  }

  Future<void> pump(WidgetTester tester, Session s, Widget child) async {
    await tester.binding.setSurfaceSize(const Size(393, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(RepoScope(session: s, child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)))));
  }

  group('the button on a finished picture', () {
    testWidgets('while it comes: a ring that fills, and a tap only pulses it', (tester) async {
      final body = StreamController<List<int>>();
      var calls = 0;
      // The first answer streams on; any later one (after the test closes it short) is refused.
      final s = await session((url, {from = 0}) async => calls++ == 0 ? http.StreamedResponse(body.stream, 200) : http.StreamedResponse(const Stream.empty(), 403));
      await tester.runAsync(() async {
        await pump(tester, s, Center(child: PictureTile(puzzle: puzzle(), width: 240)));
        body.add(List.filled(300, 1));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      final ring = tester.widget<CircularProgressIndicator>(find.byKey(const Key('film-progress')));
      expect(ring.value, closeTo(0.3, 1e-9));
      await tester.tap(find.byKey(const Key('film-button')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(PuzzleVideoPage), findsNothing);
      await tester.runAsync(() => body.close());
    });

    testWidgets('when it did not come: a way to try again', (tester) async {
      var asked = 0;
      final s = await session((url, {from = 0}) async {
        asked++;
        return http.StreamedResponse(const Stream.empty(), 403);
      });
      await tester.runAsync(() async {
        await pump(tester, s, Center(child: PictureTile(puzzle: puzzle(), width: 240)));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.byKey(const Key('film-progress')), findsNothing);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('film-button')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      expect(asked, 2);
    });

    testWidgets('when it is here: play, and the player opens and closes', (tester) async {
      final s = await session((url, {from = 0}) => throw StateError('Demo fetches nothing'));
      await pump(tester, s, Center(child: PictureTile(puzzle: puzzle(url: 'assets/demo/puzzles/wald.mp4'), width: 240)));
      await tester.pump();
      expect(find.byKey(const Key('film-progress')), findsNothing);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      await tester.tap(find.byKey(const Key('film-button')));
      await tester.pumpAndSettle();
      expect(find.byType(PuzzleVideoPage), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is AnnotatedRegion<SystemUiOverlayStyle> && w.value == SystemUiOverlayStyle.light), findsOneWidget);
      // No player in a test: the picture stands and the way out is there.
      await tester.tap(find.byKey(const Key('puzzle-video-close')));
      await tester.pumpAndSettle();
      expect(find.byType(PuzzleVideoPage), findsNothing);
    });

    testWidgets('a picture without a film has no button', (tester) async {
      final s = await session((url, {from = 0}) => throw StateError('nothing to fetch'));
      await pump(tester, s, Center(child: PictureTile(puzzle: puzzle(hasVideo: false), width: 240)));
      await tester.pump();
      expect(find.byKey(const Key('film-button')), findsNothing);
    });

    testWidgets('the player says what it plays, and can be closed', (tester) async {
      final semantics = tester.ensureSemantics();
      final s = await session((url, {from = 0}) => throw StateError('nothing to fetch'));
      final p = puzzle(url: 'assets/demo/puzzles/wald.mp4');
      await pump(tester, s, PuzzleVideoPage(puzzle: p, film: const PuzzleVideoState(VideoPhase.ready, asset: 'assets/demo/puzzles/wald.mp4')));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp(r'^Video: Die erste Reihe am Hang, 20 Sekunden')), findsWidgets);
      expect(find.bySemanticsLabel('Schließen'), findsOneWidget);
      semantics.dispose();
    });
  });

  testWidgets('on a sheet, a drag on the picture turns it and does not take the sheet away', (tester) async {
    final s = await session((url, {from = 0}) => throw StateError('Demo fetches nothing'));
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(RepoScope(
      session: s,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => showFinishedPicture(context, puzzle(url: 'assets/demo/puzzles/wald.mp4')), child: const Text('go')),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('picture-tile')), findsOneWidget);
    await tester.drag(find.byKey(const Key('picture-tile')), const Offset(0, 160));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('picture-tile')), findsOneWidget, reason: 'the sheet stays');
  });

  testWidgets('the arrival offers the film to a screen reader too, and „Ansehen" waits to be seen', (tester) async {
    final semantics = tester.ensureSemantics();
    final s = await session((url, {from = 0}) => throw StateError('Demo fetches nothing'));
    await pump(tester, s, ArrivalPiece(piece: ApiPuzzlePiece(puzzle: puzzle(url: 'assets/demo/puzzles/wald.mp4'), piece: 4, ownCause: true), delay: const Duration(milliseconds: 300)));
    // Mid-animation: the link is there but takes no taps.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.ancestor(of: find.byKey(const Key('arrival-watch')), matching: find.byWidgetPredicate((w) => w is IgnorePointer && w.ignoring)), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.ancestor(of: find.byKey(const Key('arrival-watch')), matching: find.byWidgetPredicate((w) => w is IgnorePointer && w.ignoring)), findsNothing);
    final node = tester.getSemantics(find.byKey(const Key('arrival-piece')));
    final labels = (node.getSemanticsData().customSemanticsActionIds ?? const <int>[]).map((id) => CustomSemanticsAction.getAction(id)?.label);
    expect(labels, contains('Video ansehen'));
    semantics.dispose();
  });

  testWidgets('the arrival of the last piece of a picture that moves says so, and starts the film', (tester) async {
    var asked = 0;
    final s = await session((url, {from = 0}) async {
      asked++;
      return http.StreamedResponse(const Stream.empty(), 403);
    });
    await tester.runAsync(() async {
      await pump(tester, s, ArrivalPiece(piece: ApiPuzzlePiece(puzzle: puzzle(), piece: 4, ownCause: true)));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(find.text('Das Bild bewegt sich jetzt.'), findsOneWidget);
    expect(find.text('Ansehen'), findsOneWidget);
    expect(asked, 1, reason: 'the download starts with the arrival');
  });

  testWidgets('„Bewegt sich, wenn es fertig ist." only on a picture under way that will move', (tester) async {
    final s = await session((url, {from = 0}) => throw StateError('nothing to fetch'));
    await pump(tester, s, PuzzlesBody(puzzles: ApiPuzzles(puzzles: [puzzle(complete: false)])));
    expect(find.text('Bewegt sich, wenn es fertig ist.'), findsOneWidget);
    await pump(tester, s, PuzzlesBody(puzzles: ApiPuzzles(puzzles: [puzzle(complete: false, hasVideo: false)])));
    expect(find.text('Bewegt sich, wenn es fertig ist.'), findsNothing);
    await pump(tester, s, PuzzlesBody(puzzles: ApiPuzzles(puzzles: [puzzle(url: 'assets/demo/puzzles/wald.mp4')])));
    expect(find.text('Bewegt sich, wenn es fertig ist.'), findsNothing);
    expect(find.byKey(const Key('film-badge')), findsOneWidget, reason: 'a finished one wears the badge instead');
  });
}
