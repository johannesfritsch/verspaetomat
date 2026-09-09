import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Holds the device token. Keychain / Keystore on phones; in-memory fallback
/// on web and desktop so the showcase runs everywhere.
class TokenStore {
  TokenStore._(this._secure);

  static const _key = 'verspaetomat.device_token';
  static const _deviceKey = 'verspaetomat.device_id';

  final FlutterSecureStorage? _secure;
  String? _memToken;
  String? _memDevice;

  factory TokenStore() {
    final usePlatform = !kIsWeb && (Platform.isIOS || Platform.isAndroid);
    return TokenStore._(usePlatform ? const FlutterSecureStorage() : null);
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
