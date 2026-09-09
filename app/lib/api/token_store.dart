import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Holds the device token. Keychain / Keystore on phones; in-memory fallback
/// on web and desktop so the showcase runs everywhere.
class TokenStore {
  TokenStore._(this._secure, String namespace)
      : _key = 'verspaetomat.${namespace}device_token',
        _deviceKey = 'verspaetomat.${namespace}device_id';

  /// Keychain keys. A namespace ("e2e.") keeps a test run on its own customer,
  /// so the integration test never touches the account a person uses on the same device.
  final String _key;
  final String _deviceKey;

  final FlutterSecureStorage? _secure;
  String? _memToken;
  String? _memDevice;

  factory TokenStore({String namespace = ''}) {
    final usePlatform = !kIsWeb && (Platform.isIOS || Platform.isAndroid);
    return TokenStore._(usePlatform ? const FlutterSecureStorage() : null, namespace);
  }

  Future<String?> token() async {
    if (_secure == null) return _memToken;
    try {
      return await _secure.read(key: _key);
    } catch (_) {
      return _memToken;
    }
  }

  Future<String?> deviceId() async {
    if (_secure == null) return _memDevice;
    try {
      return await _secure.read(key: _deviceKey);
    } catch (_) {
      return _memDevice;
    }
  }

  Future<void> save({required String deviceId, required String token}) async {
    _memToken = token;
    _memDevice = deviceId;
    if (_secure == null) return;
    try {
      await _secure.write(key: _key, value: token);
      await _secure.write(key: _deviceKey, value: deviceId);
    } catch (_) {
      // Keychain unavailable (simulator quirks, previews): memory keeps the session alive.
    }
  }

  Future<void> clear() async {
    _memToken = null;
    _memDevice = null;
    if (_secure == null) return;
    try {
      await _secure.delete(key: _key);
      await _secure.delete(key: _deviceKey);
    } catch (_) {}
  }
}
