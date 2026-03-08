import 'package:equatable/equatable.dart';

/// Base class for all failures in the application
abstract class Failure extends Equatable {
  final String message;
  final int? statusCode;

  const Failure(this.message, [this.statusCode]);

  @override
  List<Object?> get props => [message, statusCode];
}

/// Network-related failures (no internet, timeout, etc.)
class NetworkFailure extends Failure {
  const NetworkFailure(String message) : super(message);
}

/// Server-related failures (API errors, 500, etc.)
class ServerFailure extends Failure {
  const ServerFailure(String message, [int? statusCode]) : super(message, statusCode);
}

/// Cache-related failures (local database errors)
class CacheFailure extends Failure {
  const CacheFailure(String message) : super(message);
}

/// Validation failures (invalid input)
class ValidationFailure extends Failure {
  const ValidationFailure(String message) : super(message);
}

/// Authentication failures (unauthorized, token expired)
class AuthFailure extends Failure {
  const AuthFailure(String message, [int? statusCode]) : super(message, statusCode);
}

/// Generic failure for unexpected errors
class UnexpectedFailure extends Failure {
  const UnexpectedFailure([String message = 'An unexpected error occurred']) : super(message);
}
