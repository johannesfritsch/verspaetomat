import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/api/models.dart' show PieceTier;
import 'package:verspaetomat/widgets/puzzle.dart';
import 'package:verspaetomat/widgets/tile3d.dart';

/// docs/51 §9a: the arithmetic of turning a piece in the hand, and the way it is drawn when the
/// shader cannot be.
void main() {
  group('tilt', () {
    test('a finger turns it, and past 60° it resists', () {
      final p = TiltPhysics(start: TileTilt.rest);
      p.drag(const Offset(30, 0), 300);
      expect(p.y, closeTo(TileTilt.rest.y + math.pi * 30 / 300, 1e-9), reason: 'half a turn for a full width');
      for (var i = 0; i < 100; i++) {
        p.drag(const Offset(40, 40), 300);
      }
      expect((p.y - TileTilt.rest.y).abs(), lessThan(TiltPhysics.limit + 0.34), reason: 'never much past the limit');
      expect((p.x - TileTilt.rest.x).abs(), lessThan(TiltPhysics.limit + 0.34));
      expect((p.y - TileTilt.rest.y).abs(), greaterThan(TiltPhysics.limit), reason: 'but a little, so it can be felt');
    });

    test('let go, it swings back and comes to rest', () {
      final p = TiltPhysics(start: TileTilt.flat);
      p.drag(const Offset(90, -60), 300);
      p.release(const Offset(200, 0), 300);
      for (var i = 0; i < 180; i++) {
        p.step(1 / 60);
      }
      expect(p.settled, isTrue);
      expect(p.x, closeTo(TileTilt.rest.x, 1e-3));
      expect(p.y, closeTo(TileTilt.rest.y, 1e-3));
      expect(p.tilt.front, isTrue);
    });

    test('a fast swipe turns it over, and it rests on its back', () {
      final p = TiltPhysics(start: TileTilt.rest);
      p.drag(const Offset(20, 0), 300);
      p.release(const Offset(2500, 0), 300);
      expect(p.back, isTrue);
      for (var i = 0; i < 240; i++) {
        p.step(1 / 60);
      }
      expect(p.settled, isTrue);
      expect(p.tilt.front, isFalse);
      // And back again the other way.
      p.release(const Offset(-2500, 0), 300);
      expect(p.back, isFalse);
    });

    test('a frame that took long does not throw it off', () {
      final p = TiltPhysics(start: const TileTilt(0.5, 0.5));
      p.step(2);
      expect(p.x.isFinite && p.y.isFinite, isTrue);
      expect((p.x - TileTilt.rest.x).abs(), lessThan(0.5));
    });

    test('the light stays in the room: up and to the left, whichever way the piece turns', () {
      final flat = tileLight(TileTilt.flat).light;
      expect(flat[0], lessThan(0), reason: 'from the left');
      expect(flat[1], lessThan(0), reason: 'from above');
      expect(flat[2], greaterThan(0), reason: 'in front of the face');
      // Turned to face right, the same light comes more from the front-left of the piece's own frame.
      final turned = tileLight(const TileTilt(0, 0.6)).light;
      expect(turned[0], isNot(closeTo(flat[0], 1e-3)));
      final len = math.sqrt(turned.fold(0.0, (s, v) => s + v * v));
      expect(len, closeTo(1, 1e-9));
    });
  });

  group('drawn without the shader', () {
    setUp(() {
      TileShading.debugReset();
      TileShading.disabled = true;
    });
    tearDown(() {
      TileShading.disabled = false;
      TileShading.debugReset();
    });

    testWidgets('a piece, front and back, and a finger on it', (tester) async {
      const cut = PuzzleCut(imageId: 'x', rows: 4, cols: 3);
      final outline = cut.piece(4, const Size(100, 100));
      Widget tile({TileTilt? tilt}) => MaterialApp(
            home: Scaffold(
              body: Center(
                child: Tile3D(
                  cacheKey: 'test/4',
                  outline: outline,
                  image: null,
                  source: outline.getBounds(),
                  tier: PieceTier.hour,
                  width: 200,
                  tilt: tilt,
                  back: (context) => const Text('Rückseite'),
                ),
              ),
            ),
          );
      await tester.pumpWidget(tile(tilt: TileTilt.rest));
      expect(tester.takeException(), isNull);
      expect(find.text('Rückseite'), findsNothing);

      await tester.pumpWidget(tile(tilt: const TileTilt(0.14, 3.0)));
      expect(find.text('Rückseite'), findsOneWidget, reason: 'turned past 90°, the back shows');

      await tester.pumpWidget(tile());
      await tester.drag(find.byType(Tile3D), const Offset(60, 20));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.fling(find.byType(Tile3D), const Offset(250, 0), 3000);
      await tester.pumpAndSettle();
      expect(find.text('Rückseite'), findsOneWidget, reason: 'a fast swipe turns it over');
    });
  });
}
