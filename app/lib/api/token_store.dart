import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
    return _memToken = await _read(_key);
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

  Future<void> save({required String deviceId, required String token}) async {
    _memToken = token;
    _memDevice = deviceId;
    if (_secure == null) return;
    try {
      await _secure.write(key: _key, value: token, iOptions: _ios);
      await _secure.write(key: _deviceKey, value: deviceId, iOptions: _ios);
    } catch (_) {
      // Keychain unavailable (simulator quirks, previews): memory keeps the session alive.
    }
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
