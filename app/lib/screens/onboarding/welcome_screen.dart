import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import '../ride/ride_widgets.dart';

/// Three cards. No account, no card. The first card is the whole pitch.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < 2) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      context.go(Routes.permissions);
    }
  }

  @override
  Widget build(BuildContext context) {
    return VScreen(
      showBack: false,
      scroll: false,
      padding: EdgeInsets.zero,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _page ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _page ? VColors.ink : VColors.rule,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
          const VGap.m(),
          VPrimaryButton(
            label: _page < 2 ? 'Weiter' : "Los geht's",
            onTap: _next,
          ),
          if (_page == 2) ...[
            const VGap.s(),
            Text('Ohne Konto. Ohne Kreditkarte.', style: VText.caption),
          ],
        ],
      ),
      child: PageView(
        controller: _controller,
        onPageChanged: (i) => setState(() => _page = i),
        children: const [_CardIdea(), _CardPromise(), _CardStart()],
      ),
    );
  }
}

class _CardIdea extends StatelessWidget {
  const _CardIdea();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        VSpace.page,
        VSpace.xxl,
        VSpace.page,
        VSpace.l,
      ),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CountUpDelay(14),
              const VGap.l(),
              Text('Du wartest sowieso.\nMach was draus.', style: VText.h1),
              const VGap.m(),
              Text(
                'Verspätungen werden Punkte. Große Verspätungen werden Spenden.',
                style: VText.body.copyWith(color: VColors.ink2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardPromise extends StatelessWidget {
  const _CardPromise();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        VSpace.page,
        VSpace.xxl,
        VSpace.page,
        VSpace.l,
      ),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Drei Versprechen.', style: VText.h1),
              const VGap.xl(),
              const _Promise(
                icon: Icons.location_on_outlined,
                text: 'Dein Standort bleibt am Bahnhof.',
              ),
              const VGap.m(),
              const VRule(),
              const VGap.m(),
              const _Promise(
                icon: Icons.account_balance_wallet_outlined,
                text: 'Kein Geld läuft durch uns.',
              ),
              const VGap.m(),
              const VRule(),
              const VGap.m(),
              const _Promise(
                icon: Icons.verified_outlined,
                text: 'Kein Euro gilt als gespendet, bevor er es ist.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Promise extends StatelessWidget {
  const _Promise({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 24, color: VColors.ink),
        const SizedBox(width: 16),
        Expanded(child: Text(text, style: VText.title)),
      ],
    );
  }
}

class _CardStart extends StatelessWidget {
  const _CardStart();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        VSpace.page,
        VSpace.xxl,
        VSpace.page,
        VSpace.l,
      ),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: VStationClock(size: 160, animated: true)),
              const VGap.xl(),
              Text('Die Uhr am Bahnhof wartet auch.', style: VText.h1),
              const VGap.m(),
              Text(
                'Der rote Zeiger läuft bis zur Zwölf, hält kurz an, und erst dann springt die Minute. Genau so machen wir das.',
                style: VText.body.copyWith(color: VColors.ink2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
