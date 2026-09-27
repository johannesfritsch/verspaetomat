import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:verspaetomat/api/client.dart';
import 'package:verspaetomat/api/token_store.dart';
import 'package:verspaetomat/repo/http_repository.dart';

/// A keychain that behaves like iOS with the phone locked: every read and write fails.
class _Locked extends FlutterSecureStorage {
  const _Locked();
  @override
  Future<String?> read({required String key, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async =>
      throw PlatformException(code: '-25308', message: 'User interaction is not allowed.');
  @override
  Future<void> write({required String key, required String? value, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async =>
      throw PlatformException(code: '-25308');
}

/// A keychain that stores by key *and* accessibility, as the real one matches on both.
class _Keychain extends FlutterSecureStorage {
  _Keychain(this.items);
  final Map<String, String> items; // "key|accessibility" → value
  String _k(String key, AppleOptions? o) => '$key|${o?.params['accessibility'] ?? 'unlocked'}';
  @override
  Future<String?> read({required String key, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async =>
      items[_k(key, iOptions)];
  @override
  Future<void> write({required String key, required String? value, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async =>
      items[_k(key, iOptions)] = value!;
  @override
  Future<void> delete({required String key, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async =>
      items.remove(_k(key, iOptions));
}

/// A keychain like iOS's for an entry the plugin's update cannot match: it is unique by key alone,
/// so an add under another accessibility fails as a duplicate while that entry is there.
class _Duplicate extends _Keychain {
  _Duplicate(super.items);
  @override
  Future<void> write({required String key, required String? value, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async {
    if (items.keys.any((k) => k.startsWith('$key|') && k != _k(key, iOptions))) throw PlatformException(code: '-25299', message: 'duplicate item');
    await super.write(key: key, value: value, iOptions: iOptions);
  }
}

/// A keychain that answers every write with success and keeps nothing.
class _Forgetful extends _Keychain {
  _Forgetful() : super({});
  @override
  Future<void> write({required String key, required String? value, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async {}
}

/// 23 September 2026: a background start with the phone locked read no token, made a new
/// account — four of them, in seven seconds — and the ride under way vanished from the app.
void main() {
  (HttpRepository, List<String>) repoOver(TokenStore tokens) {
    final created = <String>[];
    final client = MockClient((r) async {
      if (r.url.path == '/v1/devices') {
        created.add('d${created.length}');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response('{"device_id":"${created.last}","token":"t${created.length}"}', 200);
      }
      return http.Response('{}', 404);
    });
    final api = ApiClient(baseUrl: 'http://x', tokens: tokens, inner: client);
    return (HttpRepository(client: api, tokens: tokens), created);
  }

  test('a locked keychain is not „no account": nothing is created', () async {
    final tokens = TokenStore.over(const _Locked());
    final (repo, created) = repoOver(tokens);
    await expectLater(repo.ensureDevice(), throwsA(isA<KeychainUnavailable>()));
    expect(created, isEmpty);
  });

  test('five callers in the same moment make one account', () async {
    final tokens = TokenStore.over(_Keychain({}));
    final (repo, created) = repoOver(tokens);
    await Future.wait([for (var i = 0; i < 5; i++) repo.ensureDevice()]);
    expect(created, hasLength(1));
    expect(await tokens.token(), 't1');
  });

  test('a token stored by build 77 or older is found and moved to „after first unlock"', () async {
    final items = {'verspaetomat.device_token|unlocked': 'old', 'verspaetomat.device_id|unlocked': 'id-old'};
    final tokens = TokenStore.over(_Keychain(items));
    final (repo, created) = repoOver(tokens);
    expect(await tokens.token(), 'old');
    expect(items['verspaetomat.device_token|first_unlock'], 'old');
    expect(items.containsKey('verspaetomat.device_token|unlocked'), isFalse);
    await repo.ensureDevice();
    expect(created, isEmpty, reason: 'the old account is kept, no new one is made');
  });

  // 27 September 2026: a recovered account showed 158 minutes, and 0 after a restart. The token
  // write had failed and said nothing; memory carried the session until the app was closed.
  group('saving the token says whether it stuck', () {
    test('a plain save is read back', () async {
      final items = <String, String>{};
      final tokens = TokenStore.over(_Keychain(items));
      expect(await tokens.save(deviceId: 'd', token: 't'), isTrue);
      expect(items['verspaetomat.device_token|first_unlock'], 't');
    });

    test('an entry the update cannot match is cleared and the second write sticks', () async {
      final items = {'verspaetomat.device_token|unlocked': 'stale', 'verspaetomat.device_id|unlocked': 'id-stale'};
      final tokens = TokenStore.over(_Duplicate(items));
      expect(await tokens.save(deviceId: 'd', token: 'new'), isTrue);
      expect(items['verspaetomat.device_token|first_unlock'], 'new');
      expect(items.containsKey('verspaetomat.device_token|unlocked'), isFalse);
    });

    test('a keychain that keeps nothing: the session goes on, and the save says false', () async {
      final tokens = TokenStore.over(_Forgetful());
      expect(await tokens.save(deviceId: 'd', token: 't'), isFalse);
      expect(await tokens.token(), 't', reason: 'memory still carries this session');
    });

    test('a locked keychain: no throw, just false', () async {
      final tokens = TokenStore.over(const _Locked());
      expect(await tokens.save(deviceId: 'd', token: 't'), isFalse);
    });

    test('a recovery whose token does not stick is reported, not celebrated', () async {
      final tokens = TokenStore.over(_Forgetful());
      final client = MockClient((r) async => r.url.path == '/v1/devices/recover'
          ? http.Response('{"device_id":"old-account","token":"recovered"}', 200)
          : http.Response('{}', 404));
      final repo = HttpRepository(client: ApiClient(baseUrl: 'http://x', tokens: tokens, inner: client), tokens: tokens);
      await expectLater(repo.recover('zwölf wörter'), throwsA(isA<TokenNotSaved>()));
    });

    test('a recovery that sticks: the recovered token is the one stored', () async {
      final items = <String, String>{'verspaetomat.device_token|first_unlock': 'fresh-account'};
      final tokens = TokenStore.over(_Keychain(items));
      final client = MockClient((r) async => r.url.path == '/v1/devices/recover'
          ? http.Response('{"device_id":"old-account","token":"recovered"}', 200)
          : http.Response('{}', 404));
      final repo = HttpRepository(client: ApiClient(baseUrl: 'http://x', tokens: tokens, inner: client), tokens: tokens);
      await repo.recover('zwölf wörter');
      expect(items['verspaetomat.device_token|first_unlock'], 'recovered');
      expect(items['verspaetomat.device_id|first_unlock'], 'old-account');
    });
  });
}
