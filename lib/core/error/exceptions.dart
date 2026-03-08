/// Base exception class for data layer
class AppException implements Exception {
  final String message;

  AppException(this.message);

  @override
  String toString() => message;
}

/// Exception thrown when network is unavailable
class NetworkException extends AppException {
  NetworkException(String message) : super(message);
}

/// Exception thrown when server returns an error
class ServerException extends AppException {
  final int? statusCode;

  ServerException(String message, [this.statusCode]) : super(message);

  @override
  String toString() => 'ServerException: $message${statusCode != null ? ' (Status: $statusCode)' : ''}';
}

/// Exception thrown when validation fails
class ValidationException extends AppException {
  ValidationException(String message) : super(message);
}

/// Exception thrown when authentication fails
class AuthException extends AppException {
  AuthException(String message) : super(message);
}

/// Exception thrown when cache operations fail
class CacheException extends AppException {
  CacheException(String message) : super(message);
}
