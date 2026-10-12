import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:verspaetomat/api/client.dart';
import 'package:verspaetomat/api/puzzle_image.dart';
import 'package:verspaetomat/api/token_store.dart';

/// docs/51 §8: a puzzle picture is fetched once and kept on the phone — and what is kept has to
/// be a picture, or the phone would show a hotel's login page as a Verein's photo for ever.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A real PNG, [w] × [h], drawn here.
  Future<Uint8List> png(int w, int h) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint()..color = const ui.Color(0xFF15305A));
    final image = await recorder.endRecording().toImage(w, h);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  Future<Directory> temp() async {
    final dir = await Directory.systemTemp.createTemp('puzzles');
    addTearDown(() => dir.delete(recursive: true));
    return dir;
  }

  testWidgets('a picture is fetched once and then read from disk', (tester) async {
    await tester.runAsync(() async {
      final dir = await temp();
      final bytes = await png(3, 4);
      var fetches = 0;
      PuzzleImageFile file() => PuzzleImageFile('0f9a/../x', () async {
            fetches++;
            return bytes;
          }, directory: () async => dir);
      expect(await file().bytes(), bytes);
      expect(await file().bytes(), bytes);
      expect(fetches, 1);
      expect(File('${dir.path}/puzzles/0f9a____x').existsSync(), isTrue, reason: 'the id never leaves the folder');
      final codec = await file().codec(PaintingBinding.instance.instantiateImageCodecWithSize);
      final frame = await codec.getNextFrame();
      expect([frame.image.width, frame.image.height], [3, 4]);
      frame.image.dispose();
    });
  });

  testWidgets('bytes that do not decode leave the disk, and the next look fetches again', (tester) async {
    await tester.runAsync(() async {
      final dir = await temp();
      final cached = File('${dir.path}/puzzles/p1');
      await cached.create(recursive: true);
      await cached.writeAsBytes([1, 2, 3]);
      final good = await png(2, 2);
      var fetches = 0;
      final file = PuzzleImageFile('p1', () async {
        fetches++;
        return good;
      }, directory: () async => dir);
      final decode = PaintingBinding.instance.instantiateImageCodecWithSize;

      await expectLater(file.codec(decode), throwsA(anything));
      expect(cached.existsSync(), isFalse);
      expect(fetches, 0, reason: 'the broken file was read, not refetched, the first time');

      final codec = await file.codec(decode);
      expect((await codec.getNextFrame()).image.width, 2);
      expect(fetches, 1);
      expect(await cached.readAsBytes(), good, reason: 'the good picture took its place');
    });
  });

  test('a large picture is decoded at no more than 1200 on its longest side', () {
    expect(PuzzleImageFile.boundedSize(900, 1200).width, isNull, reason: 'already small enough');
    expect(PuzzleImageFile.boundedSize(900, 1200).height, isNull);
    expect(PuzzleImageFile.boundedSize(3000, 4000).height, 1200);
    expect(PuzzleImageFile.boundedSize(3000, 4000).width, isNull, reason: 'the other side follows');
    expect(PuzzleImageFile.boundedSize(4000, 3000).width, 1200);
  });

  group('the client takes only a picture', () {
    ApiClient client(http.Response Function() answer) =>
        ApiClient(baseUrl: 'https://api.example', tokens: TokenStore(), inner: MockClient((_) async => answer()));
    const path = '/v1/puzzle-images/p1';

    test('an image', () async {
      final bytes = await client(() => http.Response.bytes([1, 2, 3], 200, headers: {'content-type': 'image/webp'})).puzzleImage(path);
      expect(bytes, [1, 2, 3]);
    });

    test('a login page answering 200 is not one', () {
      expect(
        client(() => http.Response('<html>Bitte anmelden</html>', 200, headers: {'content-type': 'text/html'})).puzzleImage(path),
        throwsA(isA<ApiException>()),
      );
    });

    test('an empty body is not one', () {
      expect(client(() => http.Response.bytes([], 200, headers: {'content-type': 'image/png'})).puzzleImage(path), throwsA(isA<ApiException>()));
    });

    test('an error is an error', () {
      expect(client(() => http.Response('', 404)).puzzleImage(path), throwsA(isA<ApiException>()));
    });
  });
}
