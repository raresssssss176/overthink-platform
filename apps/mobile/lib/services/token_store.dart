// lib/services/token_store.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps the JWT tokens encrypted on the device.
class TokenStore {
  static final FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _accessKey = 'access_token';
  static const String _refreshKey = 'refresh_token';

  static Future<void> save({required String access, required String refresh}) async {
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
  }

  static Future<String?> accessToken() => _storage.read(key: _accessKey);

  static Future<String?> refreshToken() => _storage.read(key: _refreshKey);

  static Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}
