import 'package:equatable/equatable.dart';

/// Base class for all failures in the application
abstract class Failure extends Equatable {
  final String message;
  final int? code;
  final dynamic originalError;

  const Failure({
    required this.message,
    this.code,
    this.originalError,
  });

  @override
  List<Object?> get props => [message, code];
}

/// Failure for server-related errors
class ServerFailure extends Failure {
  const ServerFailure({
    required String message,
    int? code,
    dynamic originalError,
  }) : super(message: message, code: code, originalError: originalError);
}

/// Failure for network-related errors
class NetworkFailure extends Failure {
  const NetworkFailure({
    String message = 'Network connection error',
    dynamic originalError,
  }) : super(message: message, originalError: originalError);
}

/// Failure for cache-related errors
class CacheFailure extends Failure {
  const CacheFailure({
    String message = 'Cache error',
    dynamic originalError,
  }) : super(message: message, originalError: originalError);
}

/// Failure for validation errors
class ValidationFailure extends Failure {
  final Map<String, String>? fieldErrors;

  const ValidationFailure({
    required String message,
    this.fieldErrors,
    dynamic originalError,
  }) : super(message: message, originalError: originalError);

  @override
  List<Object?> get props => [message, fieldErrors];
}

/// Failure for authentication errors
class AuthenticationFailure extends Failure {
  const AuthenticationFailure({
    String message = 'Authentication failed',
    int? code,
    dynamic originalError,
  }) : super(message: message, code: code, originalError: originalError);
}

/// Failure for authorization errors
class AuthorizationFailure extends Failure {
  const AuthorizationFailure({
    String message = 'Not authorized to perform this action',
    dynamic originalError,
  }) : super(message: message, originalError: originalError);
}

/// Failure for not found errors
class NotFoundFailure extends Failure {
  const NotFoundFailure({
    String message = 'Resource not found',
    dynamic originalError,
  }) : super(message: message, originalError: originalError);
}

/// Failure for conflict errors (e.g., duplicate entries)
class ConflictFailure extends Failure {
  const ConflictFailure({
    required String message,
    dynamic originalError,
  }) : super(message: message, originalError: originalError);
}
