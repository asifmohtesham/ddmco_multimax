/// Base class for all exceptions in the application
class AppException implements Exception {
  final String message;
  final int? code;
  final dynamic originalError;

  AppException({
    required this.message,
    this.code,
    this.originalError,
  });

  @override
  String toString() => 'AppException: $message (code: $code)';
}

/// Exception thrown when server returns an error
class ServerException extends AppException {
  ServerException({
    required String message,
    int? code,
    dynamic originalError,
  }) : super(message: message, code: code, originalError: originalError);
}

/// Exception thrown when there's a network error
class NetworkException extends AppException {
  NetworkException({
    String message = 'Network connection error',
    dynamic originalError,
  }) : super(message: message, originalError: originalError);
}

/// Exception thrown when there's a cache error
class CacheException extends AppException {
  CacheException({
    String message = 'Cache error',
    dynamic originalError,
  }) : super(message: message, originalError: originalError);
}

/// Exception thrown when data validation fails
class ValidationException extends AppException {
  final Map<String, String>? fieldErrors;

  ValidationException({
    required String message,
    this.fieldErrors,
    dynamic originalError,
  }) : super(message: message, originalError: originalError);
}

/// Exception thrown when authentication fails
class AuthenticationException extends AppException {
  AuthenticationException({
    String message = 'Authentication failed',
    int? code,
    dynamic originalError,
  }) : super(message: message, code: code, originalError: originalError);
}

/// Exception thrown when user is not authorized
class AuthorizationException extends AppException {
  AuthorizationException({
    String message = 'Not authorized',
    dynamic originalError,
  }) : super(message: message, originalError: originalError);
}

/// Exception thrown when resource is not found
class NotFoundException extends AppException {
  NotFoundException({
    String message = 'Resource not found',
    dynamic originalError,
  }) : super(message: message, originalError: originalError);
}
