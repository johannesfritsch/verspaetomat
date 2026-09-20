import 'package:flutter/material.dart';

/// The landscape behind the header on a tab.
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
/// One file per tab rather than one landscape with a symbol dropped over it in code, so whatever
/// stands in the hills stands exactly where it was drawn. None of them carries a railway's livery:
/// the badge on the nose of the original was painted out, because this app files claims against
/// railways and wearing one's marks in its own header would say something untrue about it.
///
/// The values below are the drawings. The landscape band comes first, one per tab: the plain
/// hills on Home, and for Anträge, Wir and Ich the same hills with the thing that tab is about
/// standing in them — a clipboard with its tick, a winners' podium, an identity card, each of them
/// out on the right where no text goes. The rest are the corner vignettes of the Antrag: one
/// per step, each naming what that step is about — the clock the delay is measured against, a
/// ticket on a phone, a heart in a hand, the form being signed, the letter going out. They are
/// drawn on the same near-white ground and anchored top-right, so the same two gradients dissolve
/// them into the page.
///
/// Each value names its own file and says which of the two it is. The test used to be a negative
/// one — *everything that is not the landscape is a vignette* — and a fourth landscape would have
/// fallen through it silently and faded out halfway down.
enum VHeaderSceneArt {
  landscape('assets/header/header-scene.webp'),
  landscapeAntraege('assets/header/header-scene-antraege.webp'),
  landscapeWir('assets/header/header-scene-wir.webp'),
  landscapeIch('assets/header/header-scene-ich.webp'),
  antragPruefen('assets/header/antrag-pruefen.webp', vignette: true),
  antragTicket('assets/header/antrag-ticket.webp', vignette: true),
  antragZweck('assets/header/antrag-zweck.webp', vignette: true),
  antragUnterschrift('assets/header/antrag-unterschrift.webp', vignette: true),
  antragSenden('assets/header/antrag-senden.webp', vignette: true);

  const VHeaderSceneArt(this.asset, {this.vignette = false});

  /// The file, spelled out in full so a grep for the filename finds the drawing that uses it.
  final String asset;

  /// A corner vignette, drawn against the top of its plate, rather than a landscape band hanging
  /// from its horizon. The default is the band: a new drawing that forgets to say is far more
  /// likely to be a landscape, and that is also the harmless way round.
  final bool vignette;
}

class VHeaderScene extends StatelessWidget {
  const VHeaderScene({super.key, this.height, this.art = VHeaderSceneArt.landscape});

  /// How tall the band is. Null means *take what you are given*, which is how the tab scaffold
  /// uses it: the scene is the header's background, so the header decides how tall it is.
  final double? height;

  /// Which drawing. Each tab has its own landscape, and each Antrag step its own vignette.
  final VHeaderSceneArt art;

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
            stops: art.vignette ? const [0, 0.42, 0.78] : const [0, 0.88, 1],
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
                art.asset,
                // fitWidth, not cover. The drawing is shipped at the band's own proportions, so
                // tying it to the width fills the band top to bottom at exactly the size it was
                // drawn. Cover would scale it to the height instead and the train would grow
                // until it filled the screen.
                fit: BoxFit.fitWidth,
                // The landscape hangs from its horizon, so it is anchored at the bottom. A corner
                // vignette is drawn against the top of its plate and has to stay there.
                alignment: art.vignette ? Alignment.topCenter : Alignment.bottomCenter,
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
