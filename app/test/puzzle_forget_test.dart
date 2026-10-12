import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:verspaetomat/repo/repo_scope.dart';
import 'package:verspaetomat/state/demo_state.dart';
import 'package:verspaetomat/state/puzzle_video_store.dart';

/// docs/51: the pictures and films on the phone belong to the account. „Alles löschen" takes them
/// with it, and so does bringing another account onto this phone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('„Alles löschen" leaves no puzzle picture or film behind', () async {
    final dir = await Directory.systemTemp.createTemp('forget');
    addTearDown(() => dir.delete(recursive: true));
    File('${dir.path}/puzzles/p1')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    File('${dir.path}/puzzle-videos/p1-abcdef01.mp4')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    SharedPreferences.setMockInitialValues({});
    final session = Session(
      demo: DemoState(),
      prefs: await SharedPreferences.getInstance(),
      apiUrl: '',
      videoStore: PuzzleVideoStore(fetch: (url, {from = 0}) => throw StateError('no fetch'), directory: () async => dir),
    )..puzzleDirectory = () async => dir;

    expect(await session.deleteEverything(), isTrue);
    expect(Directory('${dir.path}/puzzles').existsSync(), isFalse);
    expect(Directory('${dir.path}/puzzle-videos').existsSync(), isFalse);
    session.dispose();
  });
}
