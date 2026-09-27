import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../platform/diagnose_log.dart';

/// The keychain could not be read — on iOS almost always because the phone is locked and the
/// app was started in the background (prewarming, a geofence wake, a push). It is not the same
/// as „there is no token": treating it as that created a new, empty account under a passenger
/// who was on a train, and their ride vanished from the app (23 September 2026).
class KeychainUnavailable implements Exception {
  KeychainUnavailable(this.cause);
  final Object cause;
  @override
  String toString() => 'Schlüsselbund gerade nicht lesbar ($cause)';
}

/// The keychain did not keep a token that was just written: the account works for this session,
/// but the next start will not find it.
class TokenNotSaved implements Exception {
  const TokenNotSaved();
  @override
  String toString() => 'Dieses Telefon hat sich das Konto nicht gemerkt. Versuch es gleich noch einmal — die zwölf Wörter bleiben gültig.';
}

/// Holds the device token. Keychain / Keystore on phones; in-memory fallback
/// on web and desktop so the showcase runs everywhere.
///
/// iOS: stored „after first unlock", so a background start with the phone locked can still read
/// it. Builds up to 77 stored it „when unlocked" (the plugin's default), and the keychain matches
/// on that attribute, so the first read after unlocking moves an old item across.
class TokenStore {
  TokenStore._(this._secure, String namespace)
      : _key = 'verspaetomat.${namespace}device_token',
        _deviceKey = 'verspaetomat.${namespace}device_id';

  /// Keychain keys. A namespace ("e2e.") keeps a test run on its own customer,
  /// so the integration test never touches the account a person uses on the same device.
  final String _key;
  final String _deviceKey;

  static const _ios = IOSOptions(accessibility: KeychainAccessibility.first_unlock);
  static const _iosBefore78 = IOSOptions(accessibility: KeychainAccessibility.unlocked);

  final FlutterSecureStorage? _secure;
  String? _memToken;
  String? _memDevice;

  /// For tests: a store over a given keychain, to stand in for a locked one.
  @visibleForTesting
  factory TokenStore.over(FlutterSecureStorage storage, {String namespace = ''}) => TokenStore._(storage, namespace);

  factory TokenStore({String namespace = ''}) {
    final usePlatform = !kIsWeb && (Platform.isIOS || Platform.isAndroid);
    return TokenStore._(usePlatform ? const FlutterSecureStorage(iOptions: _ios) : null, namespace);
  }

  /// The token, or null when this install has never had one. Throws [KeychainUnavailable] when
  /// the keychain cannot be read: the caller must not take that as „no account yet".
  Future<String?> token() async {
    if (_memToken != null || _secure == null) return _memToken;
    final t = _memToken = await _read(_key);
    // Once per start (the value is kept in memory after this): whether the account survived the
    // last restart is the first thing to know when „my minutes are gone" (#69 follow-up).
    DiagnoseLog.instance.add('keychain', t == null ? 'kein Token im Schlüsselbund' : 'Token aus dem Schlüsselbund gelesen', bad: t == null);
    return t;
  }

  Future<String?> deviceId() async {
    if (_memDevice != null || _secure == null) return _memDevice;
    try {
      return _memDevice = await _read(_deviceKey);
    } on KeychainUnavailable {
      return null;
    }
  }

  Future<String?> _read(String key) async {
    final secure = _secure!;
    try {
      final v = await secure.read(key: key, iOptions: _ios);
      if (v != null) return v;
      final old = await secure.read(key: key, iOptions: _iosBefore78);
      if (old != null) {
        try {
          await secure.write(key: key, value: old, iOptions: _ios);
          await secure.delete(key: key, iOptions: _iosBefore78);
        } catch (_) {
          // Moved next time; the old item still answers until then.
        }
      }
      return old;
    } catch (e) {
      throw KeychainUnavailable(e);
    }
  }

  /// Stores the token and checks that it is there: true when the keychain gives back what was
  /// written. Memory always holds it, so this session goes on either way; a false means the next
  /// start would not find it — which is how a recovered account showed 158 minutes and then 0
  /// after a restart (27 September 2026, the #69 follow-up). The write used to be silent about it.
  ///
  /// First the plugin's own write (update or add). Only if what comes back is not the token does
  /// it clear every variant of the entry and write again: an entry the plugin's update cannot
  /// match — another accessibility, another sync state — makes its add fail as a duplicate. The
  /// clearing is the second attempt and never the first, so a failure cannot cost a token that
  /// was still intact.
  Future<bool> save({required String deviceId, required String token}) async {
    _memToken = token;
    _memDevice = deviceId;
    final secure = _secure;
    if (secure == null) return true;
    Future<bool> writeAndCheck() async {
      await secure.write(key: _key, value: token, iOptions: _ios);
      await secure.write(key: _deviceKey, value: deviceId, iOptions: _ios);
      return await secure.read(key: _key, iOptions: _ios) == token;
    }

    Object? error;
    try {
      if (await writeAndCheck()) {
        DiagnoseLog.instance.add('keychain', 'Token gespeichert');
        return true;
      }
    } catch (e) {
      error = e;
    }
    try {
      for (final o in const [_ios, _iosBefore78]) {
        try {
          await secure.delete(key: _key, iOptions: o);
          await secure.delete(key: _deviceKey, iOptions: o);
        } catch (_) {}
      }
      if (await writeAndCheck()) {
        DiagnoseLog.instance.add('keychain', 'Token gespeichert (zweiter Versuch${error == null ? '' : ' nach ${_short(error)}'})');
        return true;
      }
    } catch (e) {
      error = e;
    }
    DiagnoseLog.instance.add('keychain', 'Token NICHT gespeichert${error == null ? ': gelesen wird ein anderer Wert' : ': ${_short(error)}'}', bad: true);
    return false;
  }

  static String _short(Object e) {
    final s = e.toString().replaceAll('\n', ' ');
    return s.length > 60 ? '${s.substring(0, 60)}…' : s;
  }

  Future<void> clear() async {
    _memToken = null;
    _memDevice = null;
    if (_secure == null) return;
    for (final o in const [_ios, _iosBefore78]) {
      try {
        await _secure.delete(key: _key, iOptions: o);
        await _secure.delete(key: _deviceKey, iOptions: o);
      } catch (_) {}
    }
  }
}
