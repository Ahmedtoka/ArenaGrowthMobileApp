import 'dart:convert';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/storage/secure_storage.dart';
import '../models/user_model.dart';

/// Talks to Laravel `/api/auth/*` and persists the Sanctum token + cached user.
///
/// Response shapes (from `AuthController`):
///   POST /auth/login → { "token": "...", "user": { ...UserResource } }
///   GET  /auth/me    → { "user": { ...UserResource } }
class AuthRepository {
  final DioClient _client;
  final SecureStorage _storage;

  AuthRepository(this._client, this._storage);

  /// Login with email + password. `deviceName` is required by the backend
  /// so each device gets its own revokable Sanctum token.
  Future<UserModel> login({
    required String email,
    required String password,
    required String deviceName,
  }) async {
    final res = await _client.post(
      ApiConstants.login,
      data: {
        'email': email,
        'password': password,
        'device_name': deviceName,
      },
    );

    final data = res.data as Map<String, dynamic>;
    final token = data['token']?.toString();
    final userJson = data['user'] as Map<String, dynamic>;

    if (token == null || token.isEmpty) {
      throw StateError('Login response missing token');
    }

    await _storage.saveToken(token);
    // Push the new token into the interceptor's in-memory cache so the
    // very next request (e.g. listMyGroups) uses it without re-reading
    // EncryptedSharedPreferences (which can briefly miss the just-written value).
    _client.authInterceptor.updateToken(token);
    final user = UserModel.fromJson(userJson);
    await _storage.saveUserData(jsonEncode(user.toJson()));
    return user;
  }

  /// Fetches the current user from the server.
  Future<UserModel> me() async {
    final res = await _client.get(ApiConstants.me);
    final data = res.data as Map<String, dynamic>;
    final userJson = data['user'] as Map<String, dynamic>;
    final user = UserModel.fromJson(userJson);
    await _storage.saveUserData(jsonEncode(user.toJson()));
    return user;
  }

  /// Revokes the current Sanctum token on the server and clears local state.
  ///
  /// Note: callers should DELETE the FCM token via the FCM repository
  /// BEFORE calling this — otherwise the device will still receive pushes
  /// until the token is GC'd server-side.
  Future<void> logout() async {
    try {
      await _client.post(ApiConstants.logout);
    } catch (_) {
      // Even if the server call fails, clear locally so the user
      // isn't stuck in a half-logged-in state.
    } finally {
      await _storage.clearAll();
      _client.authInterceptor.updateToken(null);
    }
  }

  Future<UserModel?> getCachedUser() async {
    final json = await _storage.getUserData();
    if (json == null) return null;
    try {
      return UserModel.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasToken() async {
    final t = await _storage.getToken();
    return t != null && t.isNotEmpty;
  }
}
