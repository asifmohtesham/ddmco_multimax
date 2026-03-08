/// Base exception class
class AppException implements Exception {
  final String message;
  final int? statusCode;

  AppException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

/// Thrown when network request fails
class NetworkException extends AppException {
  NetworkException(String message) : super(message);
}

/// Thrown when server returns an error
class ServerException extends AppException {
  ServerException(String message, [int? statusCode]) : super(message, statusCode);
}

/// Thrown when cache operation fails
class CacheException extends AppException {
  CacheException(String message) : super(message);
}

/// Thrown when validation fails
class ValidationException extends AppException {
  ValidationException(String message) : super(message);
}

/// Thrown when authentication fails
class AuthException extends AppException {
  AuthException(String message, [int? statusCode]) : super(message, statusCode);
}
