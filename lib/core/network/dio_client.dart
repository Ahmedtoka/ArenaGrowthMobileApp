import 'dart:io' show HttpClient;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:flutter/foundation.dart';

import '../constants/api_constants.dart';
import '../errors/api_exception.dart';
import '../storage/secure_storage.dart';
import 'interceptors/auth_interceptor.dart';

class DioClient {
  late final Dio dio;
  final SecureStorage _storage;
  late final AuthInterceptor authInterceptor;

  DioClient(this._storage) {
    dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        // Reasonable timeouts — POSTs that fan out to FCM + Reverb broadcast
        // can take a few seconds on Windows dev servers; 60s gives them
        // headroom without making genuine server-down feel snappy enough.
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        headers: {
          'Accept': 'application/json',
        },
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    // Reuse a small pool of keep-alive connections instead of opening a fresh
    // TCP socket per request. Without this, bursts of requests churn through
    // ephemeral ports (TIME_WAIT pile-up) and start failing with
    // connectionTimeout — exactly the symptom on the Windows dev stack.
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.maxConnectionsPerHost = 8; // cap concurrent sockets per host
        client.idleTimeout = const Duration(seconds: 20); // keep alive to reuse
        client.connectionTimeout = const Duration(seconds: 30);
        return client;
      },
    );

    authInterceptor = AuthInterceptor(_storage);
    dio.interceptors.add(authInterceptor);

    if (kDebugMode) {
      dio.interceptors.add(
        PrettyDioLogger(
          requestHeader: false,
          requestBody: false,
          // ⚠️ responseBody = false: previously this synchronously printed
          // ~hundreds of KB of JSON per messages request and froze the UI
          // thread on every scroll/refresh.
          responseBody: false,
          responseHeader: false,
          compact: true,
          maxWidth: 90,
        ),
      );
    }
  }

  // ============ Convenience wrappers ============

  Future<Response> get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await dio.get(path, queryParameters: query);
      _throwIfError(res);
      return res;
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  Future<Response> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? query,
    // Upload progress (multipart) — drives the Create-task progress bar.
    ProgressCallback? onSendProgress,
  }) async {
    try {
      final res = await dio.post(
        path,
        data: data,
        queryParameters: query,
        onSendProgress: onSendProgress,
      );
      _throwIfError(res);
      return res;
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  Future<Response> put(String path, {dynamic data}) async {
    try {
      final res = await dio.put(path, data: data);
      _throwIfError(res);
      return res;
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  Future<Response> patch(String path, {dynamic data}) async {
    try {
      final res = await dio.patch(path, data: data);
      _throwIfError(res);
      return res;
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  Future<Response> delete(String path, {dynamic data}) async {
    try {
      final res = await dio.delete(path, data: data);
      _throwIfError(res);
      return res;
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  // ============ Helpers ============

  void _throwIfError(Response res) {
    final code = res.statusCode ?? 0;
    if (code >= 200 && code < 300) return;

    final data = res.data;
    String message = 'An unexpected error occurred';
    Map<String, List<String>>? validationErrors;

    if (data is Map) {
      message = (data['message'] ?? data['error'] ?? message).toString();
      if (data['errors'] is Map) {
        validationErrors = (data['errors'] as Map).map(
          (k, v) => MapEntry(
            k.toString(),
            (v as List).map((e) => e.toString()).toList(),
          ),
        );
      }
    }

    throw ApiException(
      message: message,
      statusCode: code,
      data: data,
      validationErrors: validationErrors,
    );
  }

  ApiException _mapDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return ApiException(message: 'Connection timed out, please try again');
      case DioExceptionType.connectionError:
        return ApiException(message: 'Could not reach the server, check your connection');
      case DioExceptionType.cancel:
        return ApiException(message: 'Request was cancelled');
      default:
        // 500s land here (validateStatus filtered them out). Pull the
        // human-readable message out of the response body if present.
        final data = e.response?.data;
        String message = e.message ?? 'Unknown error';
        if (data is Map) {
          message = (data['message'] ?? data['error'] ?? message).toString();
        }
        return ApiException(
          message: message,
          statusCode: e.response?.statusCode,
          data: data,
        );
    }
  }
}
