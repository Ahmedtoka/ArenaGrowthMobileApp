/// Unified exception for any API error.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic data;
  final Map<String, List<String>>? validationErrors;

  ApiException({
    required this.message,
    this.statusCode,
    this.data,
    this.validationErrors,
  });

  bool get isValidationError => statusCode == 422;
  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isServerError => (statusCode ?? 0) >= 500;

  @override
  String toString() => 'ApiException($statusCode): $message';
}
