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
