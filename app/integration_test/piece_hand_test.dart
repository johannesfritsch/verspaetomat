// The piece in the hand on a real engine (docs/51 §9a): the shader's light, a finger turning the
// piece, the back, a finished picture in its sheet, and its film playing (§9b). Demo mode; no server.
//
// flutter test integration_test/piece_hand_test.dart -d <simulator udid> --dart-define=NO_LOCATION=1
//
// Prints `SHOT <name>` and holds still at each moment worth a screenshot, so a loop watching the
// output can take it with `xcrun simctl io <udid> screenshot` (as tools/tour.sh does). Runs
// without NO_ANIM on purpose: this is the motion, not the still.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:verspaetomat/main.dart';
import 'package:verspaetomat/repo/repo_scope.dart';
import 'package:verspaetomat/router.dart';
import 'package:verspaetomat/state/demo_state.dart';
import 'package:verspaetomat/widgets/kit.dart' show PuzzleTapArea, Tile3D;

Future<void> wait(WidgetTester tester, int ms) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> shot(WidgetTester tester, String name) async {
  await wait(tester, 1200);
  // ignore: avoid_print
  print('SHOT $name');
  await wait(tester, 2500);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the piece in the hand', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final demo = DemoState();
    final session = Session(demo: demo, prefs: prefs, apiUrl: apiUrl);
    session.init();
    await tester.pumpWidget(VerspaetomatApp(state: demo, session: session));
    await wait(tester, 1500);
    void go(String route) => GoRouter.of(tester.element(find.byType(Scaffold).first)).go(route);

    go(Routes.tile3d);
    await shot(tester, 'hand-showcase');

    go(Routes.puzzles);
    await wait(tester, 1500);
    final board = tester.getRect(find.byType(PuzzleTapArea).first);
    await tester.tapAt(board.topLeft + Offset(board.width / 2, board.height * 3 / 8));
    await shot(tester, 'hand-rest');

    // A finger on it, turning it right and tipping it back, and holding there.
    final centre = tester.getCenter(find.byType(Tile3D));
    final finger = await tester.startGesture(centre);
    for (var i = 0; i < 12; i++) {
      await finger.moveBy(const Offset(9, -4));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await shot(tester, 'hand-drag');
    await finger.up();
    await wait(tester, 1500);

    await tester.fling(find.byType(Tile3D), const Offset(260, 0), 3000);
    await shot(tester, 'hand-back');

    await tester.tap(find.byKey(const Key('piece-in-hand-close')));
    await wait(tester, 800);
    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -500));
    await wait(tester, 600);
    await tester.tap(find.text('Die erste Reihe am Hang'), warnIfMissed: false);
    await shot(tester, 'picture-tile');

    // docs/51 §9b: the finished picture's film, playing.
    await tester.tap(find.byKey(const Key('film-button')));
    await wait(tester, 2500);
    await shot(tester, 'video-playing');
  });
}
