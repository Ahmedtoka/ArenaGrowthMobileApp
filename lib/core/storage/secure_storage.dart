import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/storage_keys.dart';

/// Unified wrapper: FlutterSecureStorage for sensitive tokens/user JSON,
/// SharedPreferences for non-sensitive user preferences (language, theme).
class SecureStorage {
  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final SharedPreferences _prefs;

  SecureStorage._(this._prefs);

  /// Construct with an already-initialized SharedPreferences instance.
  /// Used by the Riverpod provider after `main()` has awaited
  /// `SharedPreferences.getInstance()`.
  factory SecureStorage.withPrefs(SharedPreferences prefs) =>
      SecureStorage._(prefs);

  SharedPreferences get prefs => _prefs;

  // ─── Token ──────────────────────────────────────────────
  Future<void> saveToken(String token) =>
      _secure.write(key: StorageKeys.authToken, value: token);

  Future<String?> getToken() => _secure.read(key: StorageKeys.authToken);

  Future<void> clearToken() => _secure.delete(key: StorageKeys.authToken);

  Future<void> clearAll() => _secure.deleteAll();

  // ─── User data ──────────────────────────────────────────
  Future<void> saveUserData(String json) =>
      _secure.write(key: StorageKeys.userData, value: json);

  Future<String?> getUserData() => _secure.read(key: StorageKeys.userData);

  // ─── Settings ───────────────────────────────────────────
  Future<void> setLanguage(String code) =>
      _prefs.setString(StorageKeys.language, code);

  String? getLanguage() => _prefs.getString(StorageKeys.language);

  Future<void> setThemeMode(String mode) =>
      _prefs.setString(StorageKeys.themeMode, mode);

  String? getThemeMode() => _prefs.getString(StorageKeys.themeMode);

  Future<void> setOnboardingDone(bool value) =>
      _prefs.setBool(StorageKeys.onboardingDone, value);

  bool getOnboardingDone() =>
      _prefs.getBool(StorageKeys.onboardingDone) ?? false;
}
