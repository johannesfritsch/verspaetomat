import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../theme/tokens.dart';
import 'setup_step.dart';

/// The end of the setup, and the only screen here that asks for nothing (#43).
///
/// It is also where onboarding is marked done. That used to happen on „Dein Ticket, dein Zweck",
/// which meant the last thing a new account did before reaching the Bahnsteig was confirm two
/// values the server had already defaulted correctly.
///
/// The three lines are what the app actually does, in the order it does them, and each one is a
/// place in the app rather than a promise: check in and the minutes are counted, the Wir screen
/// adds everyone's up, and a delay of 60 minutes or more becomes a claim whose payee is the
/// Verein — paid by the railway, never through us.
class FertigScreen extends StatefulWidget {
  const FertigScreen({super.key});

  @override
  State<FertigScreen> createState() => _FertigScreenState();
}

class _FertigScreenState extends State<FertigScreen> {
  bool _busy = false;

  Future<void> _done() async {
    final session = RepoScope.read(context);
    setState(() => _busy = true);
    await session.completeOnboarding();
    if (mounted) context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    return SetupStep(
      asset: 'assets/onboarding/setup-fertig.webp',
      title: "Los geht's!",
      centred: true,
      busy: _busy,
      body: const [
        SetupText('Gemeinsam aus Verspätungen etwas Gutes machen.', centred: true),
        _Line(icon: Icons.schedule, text: 'Einchecken und Minuten sammeln'),
        _Line(icon: Icons.groups_outlined, text: 'Zusammen zählt jede Minute mehr'),
        _Line(icon: Icons.favorite_border, text: 'Ab 60 Minuten zahlt die Bahn an deinen Verein'),
      ],
      primary: 'Zum Bahnsteig',
      onPrimary: _busy ? null : _done,
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: VSpace.m),
      child: Row(
        children: [
          Icon(icon, size: 24, color: VColors.red),
          const SizedBox(width: VSpace.m),
          Expanded(child: Text(text, style: VText.bodyL)),
        ],
      ),
    );
  }
}
