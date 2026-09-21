import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';

/// Five illustrated cards, then the setup (#43).
///
/// The pictures are the drawn mockups, cropped to the artwork band: the title, the subtitle and
/// the bottom bar are Archivo drawn by Flutter, not pixels baked into a PNG. Three reasons, and
/// the first is the one that decides it — the mockups are 16:9 and a phone is 19.5:9, so a
/// full-bleed picture could only ever be letterboxed or cropped through its own type. Baked type
/// also cannot be changed without redrawing the picture (this button's label changed once
/// already), and it is invisible to a screen reader.
///
/// The bottom bar is identical on all five cards — same height, same three slots, same
/// coordinates — so nothing a thumb is already travelling towards moves underneath it. The old
/// screen grew two rows under the button on its last card, which lifted the button by about
/// 80 pt and put the recovery link exactly where the button had been on the two cards before.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

/// One card. [red] is the half of the title that carries the one red; the other half is ink.
class _Card {
  const _Card({
    required this.asset,
    required this.head,
    required this.tail,
    required this.redFirst,
    required this.subtitle,
  });

  final String asset;
  final String head;
  final String tail;
  final bool redFirst;
  final String subtitle;
}

const _cards = <_Card>[
  _Card(
    asset: 'assets/onboarding/gemeinsam.webp',
    head: 'Gemeinsam',
    tail: ' unterwegs.',
    redFirst: true,
    subtitle: 'Verspätungen sammeln. Zusammen Gutes tun.',
  ),
  _Card(
    asset: 'assets/onboarding/einchecken.webp',
    head: 'Einchecken.',
    tail: '',
    redFirst: false,
    subtitle: 'Von wo, wohin, welcher Zug.',
  ),
  _Card(
    asset: 'assets/onboarding/warten.webp',
    head: 'Warten ',
    tail: 'zählt.',
    redFirst: false,
    subtitle: 'Minuten werden zu Punkten.',
  ),
  _Card(
    asset: 'assets/onboarding/zweck.webp',
    head: 'Zusammen ',
    tail: 'helfen.',
    redFirst: false,
    subtitle: 'Du wählst den Zweck.',
  ),
  _Card(
    asset: 'assets/onboarding/losgehts.webp',
    head: 'Los ',
    tail: "geht's.",
    redFirst: true,
    subtitle: 'Einchecken und mitmachen.',
  ),
];

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _last => _page == _cards.length - 1;

  void _next() {
    if (_last) {
      _done();
    } else {
      _controller.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    }
  }

  /// Both the button on the last card and „Überspringen" end here: the cards explain, they never
  /// gate, so skipping them costs nothing but the explanation.
  void _done() => context.go(Routes.permissions);

  @override
  Widget build(BuildContext context) {
    return VScreen(
      showBack: false,
      scroll: false,
      padding: EdgeInsets.zero,
      bottom: Row(
        children: [
          // On the last card „Überspringen" would go exactly where the button beside it goes, so
          // the slot carries the one thing the five drawn cards have no place for: the way back
          // into an account that already exists. Same slot, same style, same coordinates — the
          // bar does not change shape, only that one label.
          //
          // „Schon dabei?" and not „Konto zurückholen", which is what the screen it opens is
          // called: the long label overflowed this row by 22 pt beside the five dots and the
          // button when that button still read „Jetzt einrichten". „Einrichten" has since given
          // the row its 22 pt back, so the longer label would fit — the short question stays
          // because it is the one the old screen asked and it reads as an aside rather than as a
          // second instruction competing with the button.
          _last
              ? VGhostButton(label: 'Schon dabei?', color: VColors.ink2, onTap: () => context.push(Routes.wiederherstellen))
              : VGhostButton(label: 'Überspringen', color: VColors.ink2, onTap: _done),
          const Spacer(),
          for (var i = 0; i < _cards.length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == _page ? VColors.red : VColors.rule,
              ),
            ),
          const Spacer(),
          VPrimaryButton(
            label: _last ? 'Einrichten' : 'Weiter',
            expanded: false,
            onTap: _next,
          ),
        ],
      ),
      child: PageView(
        controller: _controller,
        onPageChanged: (i) => setState(() => _page = i),
        children: [for (final c in _cards) _CardView(card: c)],
      ),
    );
  }
}

class _CardView extends StatelessWidget {
  const _CardView({required this.card});
  final _Card card;

  @override
  Widget build(BuildContext context) {
    const ink = TextStyle(color: VColors.ink);
    const red = TextStyle(color: VColors.red);
    return Column(
      children: [
        const VGap.xl(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: VSpace.l),
          child: Column(
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: card.head, style: card.redFirst ? red : ink),
                    if (card.tail.isNotEmpty) TextSpan(text: card.tail, style: card.redFirst ? ink : red),
                  ],
                ),
                // h2 rather than h1: „Gemeinsam unterwegs." is the longest of the five and does
                // not fit one line at h1 on a 393 pt phone. One card breaking to two lines while
                // the other four stay on one moves the picture down on that card alone, and the
                // drawn cards all have their title on one line.
                style: VText.h2,
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
              const VGap.s(),
              Text(card.subtitle, style: VText.bodyL.copyWith(color: VColors.ink2), textAlign: TextAlign.center),
            ],
          ),
        ),
        const VGap.m(),
        // The picture takes whatever is left and is cropped from its centre, so a short phone
        // loses the outer greenery rather than the train.
        Expanded(
          child: Image.asset(
            card.asset,
            fit: BoxFit.cover,
            width: double.infinity,
            // A card with no picture is still a readable card: the title and the subtitle carry it.
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}
