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
/// Which drawing sits behind a header.
///
/// The first two are the landscape band Home and Wir share. The rest are the corner vignettes of
/// the Antrag: one per step, each naming what that step is about — the clock the delay is measured
/// against, a ticket on a phone, a heart in a hand, the form being signed, the letter going out.
/// They are drawn on the same near-white ground and anchored top-right, so the same two gradients
/// dissolve them into the page.
enum VHeaderSceneArt {
  landscape,
  landscapeHeart,
  antragPruefen,
  antragTicket,
  antragZweck,
  antragUnterschrift,
  antragSenden,
}

class VHeaderScene extends StatelessWidget {
  const VHeaderScene({super.key, this.height, this.art = VHeaderSceneArt.landscape});

  /// How tall the band is. Null means *take what you are given*, which is how the tab scaffold
  /// uses it: the scene is the header's background, so the header decides how tall it is.
  final double? height;

  /// Which drawing. Wir floats a heart over the hills; Home does not; each Antrag step has its own.
  final VHeaderSceneArt art;

  /// The corner vignettes sit at the top of their plate, not the bottom like the landscape band.
  bool get _isAntrag => art != VHeaderSceneArt.landscape && art != VHeaderSceneArt.landscapeHeart;

  String get _asset => switch (art) {
        VHeaderSceneArt.landscape => 'assets/header/header-scene.webp',
        VHeaderSceneArt.landscapeHeart => 'assets/header/header-scene-heart.webp',
        VHeaderSceneArt.antragPruefen => 'assets/header/antrag-pruefen.webp',
        VHeaderSceneArt.antragTicket => 'assets/header/antrag-ticket.webp',
        VHeaderSceneArt.antragZweck => 'assets/header/antrag-zweck.webp',
        VHeaderSceneArt.antragUnterschrift => 'assets/header/antrag-unterschrift.webp',
        VHeaderSceneArt.antragSenden => 'assets/header/antrag-senden.webp',
      };

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: height,
        width: double.infinity,
        // Two masks. The left one lets the drawing dissolve into the page where the title sits;
        // the bottom one stops it ending on a horizontal line just above the first card, because
        // its own background is a hair brighter than the paper. Nothing fades at the top: the
        // drawing is meant to run up behind the status bar and off the screen.
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [Colors.white, Colors.white, Colors.transparent],
            // The landscape holds almost to its own edge and only stops short of the first card.
            // A corner vignette has to give way sooner: the step ribbon crosses its lower half,
            // and five small words have to stay legible over whatever is behind them.
            stops: _isAntrag ? const [0, 0.42, 0.78] : const [0, 0.88, 1],
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
                _asset,
                // fitWidth, not cover. The drawing is shipped at the band's own proportions, so
                // tying it to the width fills the band top to bottom at exactly the size it was
                // drawn. Cover would scale it to the height instead and the train would grow
                // until it filled the screen.
                fit: BoxFit.fitWidth,
                // The landscape hangs from its horizon, so it is anchored at the bottom. A corner
                // vignette is drawn against the top of its plate and has to stay there.
                alignment: _isAntrag ? Alignment.topCenter : Alignment.bottomCenter,
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
