import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../main.dart' show apiUrl;
import '../../repo/repo_scope.dart';
import '../../state/demo_state.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import 'antrag_screen.dart';

/// The whole Antrag, walked through with example data, from an account that has never had a delay.
///
/// Two people need this and neither can get at it otherwise. Somebody who has just installed the
/// app has an empty Anträge tab and no way to find out what the tab is *for* until a train is an
/// hour late, which may be weeks. And an App Store reviewer has exactly one session to decide
/// whether the app does what the listing says; without this they see an empty screen and a promise.
///
/// It is the real flow, not a picture of it: the same [AntragScreen], the same five steps, the same
/// buttons. Only the repository underneath is the mock one, so nothing is drafted on the server and
/// no mail can leave. The session built here is local to this route and is thrown away with it —
/// the person's own account and backend mode are untouched.
class DemoAntragScreen extends StatefulWidget {
  const DemoAntragScreen({super.key});

  @override
  State<DemoAntragScreen> createState() => _DemoAntragScreenState();
}

class _DemoAntragScreenState extends State<DemoAntragScreen> {
  Session? _session;
  final _demo = DemoState();

  @override
  void initState() {
    super.initState();
    _build();
  }

  Future<void> _build() async {
    final prefs = await SharedPreferences.getInstance();
    // Demo is this Session's default mode and nothing here switches it, so the mock repository is
    // the only one it can reach.
    final s = Session(demo: _demo, prefs: prefs, apiUrl: apiUrl);
    if (!mounted) return;
    setState(() => _session = s);
    await _askWhereAClaimGoes();
  }

  /// The one fact the walkthrough cannot make up: the address a claim from this app really goes to.
  ///
  /// It comes from the operator directory, which answers it out of the same routing table the
  /// Senden step and the sender read — so when the desk is re-pointed with `stellwerk route set`,
  /// the walkthrough follows without anyone touching the app. This is the app's *real* session,
  /// the one the Anträge tab is running on; the throwaway demo session above cannot reach a server
  /// and is never asked to. A failure here is not worth a word on screen: the walkthrough simply
  /// says it does not know the address, which is what it said before this existed.
  Future<void> _askWhereAClaimGoes() async {
    if (!mounted) return;
    // Looked up without asserting: the walkthrough is also pumped on its own in a widget test,
    // where there is no app above it and no server to ask.
    final real = context.getInheritedWidgetOfExactType<RepoScope>()?.notifier;
    if (real == null || !real.isLocal) return;
    try {
      final ops = await real.repo.operators();
      final desk = ops.where((o) => o.desk == 'Servicecenter Fahrgastrechte').firstOrNull;
      if (!mounted || desk?.email == null) return;
      setState(() => _demo.deskEmail = desk!.email);
    } catch (_) {
      // Nothing. The walkthrough is not the place to report that a directory could not be read.
    }
  }

  @override
  void dispose() {
    _session?.dispose();
    _demo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    if (s == null) {
      return const VScreen(
        title: 'Vorführung',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [VSkeletonCard(), SizedBox(height: VSpace.md), VSkeletonList()]),
      );
    }
    return RepoScope(
      session: s,
      child: const AntragScreen(desk: 'Servicecenter Fahrgastrechte', demo: true),
    );
  }
}
