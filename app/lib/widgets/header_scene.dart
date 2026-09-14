import 'package:flutter/material.dart';

/// The landscape behind the header on Home and Wir.
///
/// It is atmosphere, not a picture. Most of it sits within a few steps of the page background —
/// pale hills, a haze of cloud — so a title can be set straight over the left half of it and still
/// read. Only the train and the trees carry any real colour, and they keep to the right where no
/// text goes.
///
/// The drawing is an asset rather than a painter. It was painted in Dart first and the flat shapes
/// came out flat: a train nose is a few long curves, and a stylised one reads as a slab. The
/// illustration was worth more than the scalability.
///
/// Two files, differing only in the heart Wir floats over the hills, so the heart sits exactly
/// where it was drawn rather than being placed again in code. Neither carries a railway's livery:
/// the badge on the nose of the original was painted out, because this app files claims against
/// railways and wearing one's marks in its own header would say something untrue about it.
class VHeaderScene extends StatelessWidget {
  const VHeaderScene({super.key, this.height, this.heart = false});

  /// How tall the band is. Null means *take what you are given*, which is how the tab scaffold
  /// uses it: the scene is the header's background, so the header decides how tall it is.
  final double? height;

  /// Wir floats a heart over the hills; Home does not.
  final bool heart;

  static const _plain = 'assets/header/header-scene.webp';
  static const _withHeart = 'assets/header/header-scene-heart.webp';

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: height,
        width: double.infinity,
        // Two masks, because the drawing has to dissolve on two sides. Its own background is a
        // hair brighter than the page, so any edge it ends on shows as a faint rectangle: down the
        // middle of the screen where the title sits, and across the top under the masthead.
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.white, Colors.white, Colors.transparent],
            stops: [0, 0.62, 1],
          ).createShader(rect),
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
              colors: [Colors.white, Colors.white, Colors.transparent],
              stops: [0, 0.34, 0.88],
            ).createShader(rect),
            child: ClipRect(
              child: Image.asset(
                heart ? _withHeart : _plain,
                // fitWidth, not cover. Cover scales the drawing to fill the band's height, and a
                // header band is short, so the train grew until it filled the screen and the empty
                // left third the title needs was cropped away. Tying the drawing to the *width*
                // keeps it the size it was drawn at, and a band shorter than it loses sky off the
                // top rather than track off the bottom.
                fit: BoxFit.fitWidth,
                alignment: Alignment.bottomCenter,
                filterQuality: FilterQuality.medium,
                excludeFromSemantics: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
