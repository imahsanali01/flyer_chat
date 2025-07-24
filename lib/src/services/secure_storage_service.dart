import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage();
  static const _keyPrefix = 'flyer_chat_';

  // Keys
  static const _credentialsKey = '${_keyPrefix}credentials';
  static const _biometricEnabledKey = '${_keyPrefix}biometric_enabled';
  static const _themeColorsKey = '${_keyPrefix}theme_colors';

  Future<void> storeCredentials(String email, String password) async {
    final credentials = {
      'email': email,
      'password': password,
    };
    await _storage.write(
      key: _credentialsKey,
      value: json.encode(credentials),
    );
  }

  Future<Map<String, String>?> getCredentials() async {
    final data = await _storage.read(key: _credentialsKey);
    if (data != null) {
      final Map<String, dynamic> decoded = json.decode(data);
      return {
        'email': decoded['email'] as String,
        'password': decoded['password'] as String,
      };
    }
    return null;
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _storage.write(
      key: _biometricEnabledKey,
      value: enabled.toString(),
    );
  }

  Future<bool> isBiometricEnabled() async {
    final value = await _storage.read(key: _biometricEnabledKey);
    return value == 'true';
  }

  Future<void> deleteCredentials() async {
    await _storage.delete(key: _credentialsKey);
    await _storage.delete(key: _biometricEnabledKey);
  }

  Future<void> deleteAllData() async {
    await _storage.deleteAll();
  }
/// will use this to store the theme colors in future from settings screen
  Future<void> storeThemeColors(Map<String, String> colorHexMap) async {
    await _storage.write(
      key: _themeColorsKey,
      value: json.encode(colorHexMap),
    );
  }

  Future<Map<String, String>?> getThemeColors() async {
    final data = await _storage.read(key: _themeColorsKey);
    if (data != null) {
      final Map<String, dynamic> decoded = json.decode(data);
      return decoded.map((k, v) => MapEntry(k, v as String));
    }
    return null;
  }

  Future<void> deleteThemeColors() async {
    await _storage.delete(key: _themeColorsKey);
  }
} 