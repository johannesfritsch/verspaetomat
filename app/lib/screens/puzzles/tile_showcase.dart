import 'package:flutter/material.dart';

import '../../api/models.dart' show PieceTier;
import '../../widgets/kit.dart';
import 'piece_in_hand.dart' show PieceBack;

/// docs/51 §9a: the piece in the hand at fixed tilts, a minute, a quarter and an hour, and one to
/// turn with a finger — so the light, the edge and the materials can be looked at on a real engine
/// without collecting anything first. Demo's Bahnhofsmission picture; reachable from the Showcase.
class TileShowcase extends StatelessWidget {
  const TileShowcase({super.key});

  static const _cut = PuzzleCut(imageId: 'demo-bahnhofsmission', rows: 4, cols: 3);
  static const _image = AssetImage('assets/demo/puzzles/bahnhofsmission.webp');
  static const _board = Size(1000, 1000 / 0.75);
  static const _tilts = [TileTilt.rest, TileTilt(0.14, 0.52), TileTilt(0.1, 1.4), TileTilt(0.14, 3.0)];

  Widget _piece(int slot, PieceTier tier, double width, {TileTilt? tilt}) => PuzzlePicture(
        image: _image,
        builder: (context, img) {
          final shape = pieceShape(_cut, slot, _board, img == null ? _board : Size(img.width.toDouble(), img.height.toDouble()));
          return Tile3D(
            cacheKey: 'showcase/$slot',
            outline: shape.outline,
            image: img,
            source: shape.source,
            tier: tier,
            width: width,
            tilt: tilt,
            back: (context) => PieceBack(tier: tier, ngoName: 'Bahnhofsmission Köln', title: 'Nachtschicht am Gleis 1'),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    return VScreen(
      eyebrow: 'Vorführung',
      title: 'Teil in der Hand',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (slot, tier) in const [(1, PieceTier.minute), (5, PieceTier.quarter), (7, PieceTier.hour)]) ...[
            VEyebrow(switch (tier) { PieceTier.minute => 'Minute', PieceTier.quarter => 'Viertelstunde', PieceTier.hour => 'Stunde' }),
            const VGap.s(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [for (final t in _tilts) SizedBox(width: 72, height: 96, child: Center(child: _piece(slot, tier, 64, tilt: t)))],
            ),
            const VGap.l(),
          ],
          const VEyebrow('Zum Drehen'),
          const VGap.l(),
          Center(child: _piece(7, PieceTier.hour, 220)),
          const VGap.xl(),
        ],
      ),
    );
  }
}
