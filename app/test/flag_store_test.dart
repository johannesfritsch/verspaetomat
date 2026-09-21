import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:verspaetomat/flags/flag_client.dart';
import 'package:verspaetomat/flags/flag_store.dart';
import 'package:verspaetomat/flags/flags.dart';

/// The server, answering from a list. No socket is opened in any test in this file.
class _CannedClient extends FlagClient {
  _CannedClient(this._answers) : super(baseUrl: 'http://nowhere.invalid');

  final List<FlagFetchResult> _answers;
  final List<String?> etagsSeen = [];
  int calls = 0;

  @override
  Future<FlagFetchResult> fetch({String? etag}) async {
    etagsSeen.add(etag);
    calls++;
    return _answers.length == 1 ? _answers.first : _answers.removeAt(0);
  }

  @override
  void close() {}
}

/// Jitter with the randomness taken out, so a test does not wait thirty seconds to find out that
/// a request was made.
class _NoJitter implements Random {
  @override
  int nextInt(int max) => 0;
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
}

const _onBody = '{"flags":{"stations_local":true}}';
/// Nothing switched on: what the server publishes on an ordinary day.
const _offBody = '{"flags":{}}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<FlagStore> storeWith(Map<String, Object> stored, {FlagClient? client}) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    return FlagStore(prefs: prefs, apiUrl: 'http://nowhere.invalid', client: client, random: _NoJitter());
  }

  /// Let a zero-length jitter timer and the fetch behind it run.
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  test('the held document is in hand before anything is awaited', () async {
    SharedPreferences.setMockInitialValues({
      'flags.doc': _onBody,
      'flags.confirmed_at': DateTime.now().toUtc().toIso8601String(),
    });
    final prefs = await SharedPreferences.getInstance();

    // No await between the constructor and the question: this is the property that means a flag
    // has its value in the first build() of the first screen.
    final store = FlagStore(prefs: prefs, apiUrl: 'http://nowhere.invalid', client: _CannedClient([]));
    expect(store.on(Flag.stationsLocal), isTrue);
    store.dispose();
  });

  test('a phone that has never been online answers false and does not throw', () async {
    final store = await storeWith({}, client: _CannedClient([]));
    expect(store.flags.on(Flag.stationsLocal), isFalse);
    expect(store.flags.doc.isEmpty, isTrue);
    store.dispose();
  });

  test('a cached document that will not parse is not a crash, it is „nobody has said"', () async {
    final store = await storeWith({'flags.doc': 'halb geschrieben {'}, client: _CannedClient([]));
    expect(store.flags.on(Flag.stationsLocal), isFalse);
    store.dispose();
  });

  test('a fresh document is stored, resolved and announced', () async {
    final client = _CannedClient([const FlagFetchFresh(body: _onBody, etag: '"12"')]);
    final store = await storeWith({}, client: client);
    var notified = 0;
    store.addListener(() => notified++);

    await store.refreshNow();

    expect(store.on(Flag.stationsLocal), isTrue);
    expect(notified, 1);
    expect(store.prefs.getString('flags.doc'), _onBody);
    expect(store.prefs.getString('flags.etag'), '"12"');
    expect(store.etag, '"12"');
    expect(store.flags.confirmedAt, isNotNull);
    store.dispose();
  });

  test('the etag is replayed exactly as it was received', () async {
    final client = _CannedClient([
      const FlagFetchFresh(body: _onBody, etag: 'W/"12-gzip"'),
      const FlagFetchNotModified(),
    ]);
    final store = await storeWith({}, client: client);
    await store.refreshNow();
    await store.refreshNow();
    expect(client.etagsSeen, [null, 'W/"12-gzip"']);
    store.dispose();
  });

  test('a 304 confirms the document, which is the only thing that dates the answer', () async {
    final old = DateTime.now().toUtc().subtract(const Duration(hours: 40));
    final client = _CannedClient([const FlagFetchNotModified()]);
    final store = await storeWith({
      'flags.doc': _onBody,
      'flags.etag': '"12"',
      'flags.confirmed_at': old.toIso8601String(),
    }, client: client);

    // Forty hours without a word from the server. The value stands — the backend publishes no
    // maximum age, so nothing expires — but the page has to be able to say how old it is.
    expect(store.on(Flag.stationsLocal), isTrue);
    expect(store.flags.confirmedAt, old);

    await store.refreshNow();

    expect(store.on(Flag.stationsLocal), isTrue);
    expect(store.flags.confirmedAt!.isAfter(old), isTrue, reason: 'a 304 is a real answer');
    store.dispose();
  });

  test('a 304 that changes nothing does not rebuild the tree', () async {
    final client = _CannedClient([const FlagFetchNotModified()]);
    final store = await storeWith({
      'flags.doc': _onBody,
      'flags.etag': '"12"',
      'flags.confirmed_at': DateTime.now().toUtc().toIso8601String(),
    }, client: client);
    var notified = 0;
    store.addListener(() => notified++);
    await store.refreshNow();
    expect(notified, 0);
    store.dispose();
  });

  test('a failed fetch changes nothing at all — not the value, not its age', () async {
    final confirmed = DateTime.now().toUtc().subtract(const Duration(hours: 2));
    final client = _CannedClient([const FlagFetchFailed('timeout')]);
    final store = await storeWith({
      'flags.doc': _onBody,
      'flags.etag': '"12"',
      'flags.confirmed_at': confirmed.toIso8601String(),
    }, client: client);

    await store.refreshNow();

    expect(store.on(Flag.stationsLocal), isTrue, reason: 'a failed call is not an answer');
    expect(store.flags.confirmedAt, confirmed,
        reason: 'a failure that dated the answer would make the page say the server had just '
            'confirmed something it never answered');
    expect(store.prefs.getString('flags.doc'), _onBody);
    store.dispose();
  });

  test('a 200 that is not a document is refused, not obeyed', () async {
    final client = _CannedClient([const FlagFetchFresh(body: '<html>502 Bad Gateway</html>', etag: '"x"')]);
    final store = await storeWith({
      'flags.doc': _onBody,
      'flags.confirmed_at': DateTime.now().toUtc().toIso8601String(),
    }, client: client);

    await store.refreshNow();

    expect(store.on(Flag.stationsLocal), isTrue, reason: 'a bad publish must not blank every flag');
    expect(store.prefs.getString('flags.doc'), _onBody);
    store.dispose();
  });

  test('the interval gate is inside the store, so a resume storm is free', () async {
    final client = _CannedClient([const FlagFetchNotModified()]);
    final store = await storeWith({
      'flags.doc': _onBody,
      'flags.next_check_at': DateTime.now().toUtc().add(const Duration(minutes: 20)).toIso8601String(),
    }, client: client);

    for (var i = 0; i < 20; i++) {
      await store.maybeCheckForUpdate();
    }
    expect(client.calls, 0);

    // And the door out of the gate, for an event that says „now".
    await store.refreshNow();
    expect(client.calls, 1);
    store.dispose();
  });

  test('a check moves the gate, and a failed one moves it less far', () async {
    final client = _CannedClient([
      const FlagFetchNotModified(),
      const FlagFetchFailed('timeout'),
    ]);
    final store = await storeWith({'flags.doc': _onBody}, client: client);

    await store.maybeCheckForUpdate();
    expect(client.calls, 1, reason: 'nothing held it back on a phone with no gate yet');
    final afterSuccess = store.nextCheckAt!.difference(DateTime.now().toUtc());
    expect(afterSuccess.inMinutes, closeTo(FlagStore.checkEvery.inMinutes, 1));

    await store.refreshNow();
    final afterFailure = store.nextCheckAt!.difference(DateTime.now().toUtc());
    expect(afterFailure.inMinutes, closeTo(FlagStore.retryAfter.inMinutes, 1));
    store.dispose();
  });

  test('an SSE flip is answered once, however many events land', () async {
    final client = _CannedClient([const FlagFetchFresh(body: _offBody, etag: '"13"')]);
    final store = await storeWith({
      'flags.doc': _onBody,
      'flags.next_check_at': DateTime.now().toUtc().add(const Duration(minutes: 29)).toIso8601String(),
    }, client: client);

    store.refreshSoon();
    store.refreshSoon();
    store.refreshSoon();
    await settle();

    expect(client.calls, 1, reason: 'three events in one second are one request');
    expect(store.on(Flag.stationsLocal), isFalse, reason: 'and the gate did not hold the flip back');
    expect(store.flags.stateOf(Flag.stationsLocal).source, FlagSource.shipped,
        reason: 'the key is simply gone from the document again');
    store.dispose();
  });

  test('two callers at once are one request', () async {
    final client = _CannedClient([const FlagFetchNotModified()]);
    final store = await storeWith({'flags.doc': _onBody}, client: client);
    await Future.wait([store.refreshNow(), store.refreshNow(), store.refreshNow()]);
    expect(client.calls, 1);
    store.dispose();
  });

  test('a pin overrides the server, and unpinning gives it back', () async {
    final store = await storeWith({'flags.doc': _offBody}, client: _CannedClient([]));
    expect(store.on(Flag.stationsLocal), isFalse);
    store.pin(Flag.stationsLocal, on: true);
    expect(store.on(Flag.stationsLocal), isTrue);
    store.unpin(Flag.stationsLocal);
    expect(store.on(Flag.stationsLocal), isFalse);
    store.dispose();
  });

  test('an authenticated map replaces the document wholesale', () async {
    final store = await storeWith({'flags.doc': _onBody}, client: _CannedClient([]));
    expect(store.on(Flag.stationsLocal), isTrue, reason: 'the public document says so');

    var notified = 0;
    store.addListener(() => notified++);

    // What `/v1/me` sends for somebody taken back out of a rollout: the key omitted, because
    // `false` is the default. A merge would keep the document's `true`.
    store.setPersonal(const <String, Object?>{});

    expect(store.on(Flag.stationsLocal), isFalse);
    expect(notified, 1, reason: 'the answer changed, so the app is told');
    store.dispose();
  });

  test('a payload with no flags key teaches nothing and forgets nothing', () async {
    // An older backend, or a build pointed at one. Null is not an empty map.
    final store = await storeWith({'flags.doc': _onBody}, client: _CannedClient([]));
    store.setPersonal(null);
    expect(store.on(Flag.stationsLocal), isTrue, reason: 'the document still answers');
    store.dispose();
  });

  test('a later document does not overrule the authenticated answer already held', () async {
    final client = _CannedClient([const FlagFetchFresh(body: _onBody, etag: '"12"')]);
    final store = await storeWith({}, client: client);
    store.setPersonal(const <String, Object?>{});
    expect(store.on(Flag.stationsLocal), isFalse);

    await store.refreshNow(); // the public document arrives, saying the flag is on for everybody
    expect(store.on(Flag.stationsLocal), isFalse,
        reason: 'only the authenticated answer knows who is asking');
    store.dispose();
  });

  test('a disposed store does not answer an event that lands after it', () async {
    final client = _CannedClient([const FlagFetchNotModified()]);
    final store = await storeWith({'flags.doc': _onBody}, client: client);
    store.refreshSoon();
    store.dispose();
    await settle();
    expect(client.calls, 0);
  });
}
