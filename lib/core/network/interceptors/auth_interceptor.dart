import 'package:dio/dio.dart';
import '../../storage/secure_storage.dart';

/// Adds Bearer token to every outbound request.
///
/// Token is cached in memory after the first read so we don't pay the
/// EncryptedSharedPreferences decryption cost on every API call (which on
/// Android can take 50–200ms and was visibly freezing the UI on scroll/send).
class AuthInterceptor extends Interceptor {
  final SecureStorage _storage;
  String? _cachedToken;

  AuthInterceptor(this._storage);

  /// Synchronous accessor for the cached token. Returns null until the
  /// first request runs or [updateToken] is called.
  String? get cachedToken => _cachedToken;

  /// Called by the auth controller after login/logout so the next request
  /// uses the fresh token without reading from disk.
  void updateToken(String? token) {
    _cachedToken = token;
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    var token = _cachedToken;
    if (token == null || token.isEmpty) {
      token = await _storage.getToken();
      _cachedToken = token;
    }
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    options.headers['Accept'] = 'application/json';
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401) {
      _cachedToken = null;
      await _storage.clearToken();
    }
    handler.next(err);
  }
}
