import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:verspaetomat/flags/flag_client.dart';
import 'package:verspaetomat/flags/flag_store.dart';
import 'package:verspaetomat/flags/flags.dart';
import 'package:verspaetomat/repo/repo_scope.dart';
import 'package:verspaetomat/state/demo_state.dart';

/// **How a test pins a flag.** This file is the reference for it, because the alternative is that
/// every test touching a flagged path inherits whatever the process default happens to be and
/// then passes for the wrong reason — green on the branch nobody meant to test.
///
/// There is one mechanism and it is synchronous: `session.flagStore.pin(Flag.x, on: true)`. No
/// mock server, no `--dart-define`, no waiting for a fetch, and nothing that can reach a socket.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Session> sessionWith(Map<String, Object> stored) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    return Session(demo: DemoState(), prefs: prefs, apiUrl: '');
  }

  test('a test pins a flag, and nothing it did before decides the answer', () async {
    final session = await sessionWith({});

    // The shipped path, which is what a test gets unless it says otherwise.
    expect(session.flags.on(Flag.stationsLocal), isFalse);

    session.flagStore.pin(Flag.stationsLocal, on: true);
    expect(session.flags.on(Flag.stationsLocal), isTrue);

    session.flagStore.pin(Flag.stationsLocal, on: false);
    expect(session.flags.on(Flag.stationsLocal), isFalse,
        reason: 'pinning off is as explicit as pinning on, and not the same as not pinning');

    session.dispose();
  });

  test('a pin beats a document the phone already holds', () async {
    final session = await sessionWith({
      'flags.doc': '{"flags":{"stations_local":true}}',
      'flags.confirmed_at': DateTime.now().toUtc().toIso8601String(),
    });
    expect(session.flags.on(Flag.stationsLocal), isTrue);
    session.flagStore.pin(Flag.stationsLocal, on: false);
    expect(session.flags.on(Flag.stationsLocal), isFalse);
    session.dispose();
  });

  test('a pinned flag tells the app, so a widget under a RepoScope rebuilds', () async {
    final session = await sessionWith({});
    var notified = 0;
    session.addListener(() => notified++);
    session.flagStore.pin(Flag.stationsLocal, on: true);
    expect(notified, 1);
    session.dispose();
  });

  test('a session can be handed a store that answers from canned bytes', () async {
    // The other seam: for a test about what happens *when the server says something*, rather than
    // about a pinned value.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final session = Session(
      demo: DemoState(),
      prefs: prefs,
      apiUrl: '',
      flagStore: FlagStore(prefs: prefs, apiUrl: '', client: _AlwaysOn()),
    );
    expect(session.flags.on(Flag.stationsLocal), isFalse, reason: 'nothing has been fetched yet');
    await session.flagStore.refreshNow();
    expect(session.flags.on(Flag.stationsLocal), isTrue);
    session.dispose();
  });

  test('Demo never asks anybody: the flag check is a no-op without a backend', () async {
    final session = await sessionWith({});
    expect(session.isLocal, isFalse, reason: 'a fresh session with no stored mode is Demo');
    // It must complete rather than throw, and it must not reach for a host that is not there.
    await session.flagsUpdateCheck();
    expect(session.flags.on(Flag.stationsLocal), isFalse);
    session.dispose();
  });
}

class _AlwaysOn extends FlagClient {
  _AlwaysOn() : super(baseUrl: 'http://nowhere.invalid');
  @override
  Future<FlagFetchResult> fetch({String? etag}) async =>
      const FlagFetchFresh(body: '{"flags":{"stations_local":true}}', etag: '"1"');
  @override
  void close() {}
}
