import 'package:equatable/equatable.dart';

/// Base class for all failures in the domain layer
abstract class Failure extends Equatable {
  final String message;

  const Failure(this.message);

  @override
  List<Object?> get props => [message];
}

/// Failure due to network connectivity issues
class NetworkFailure extends Failure {
  const NetworkFailure(String message) : super(message);
}

/// Failure due to server errors
class ServerFailure extends Failure {
  final int? statusCode;

  const ServerFailure(String message, [this.statusCode]) : super(message);

  @override
  List<Object?> get props => [message, statusCode];
}

/// Failure due to validation errors
class ValidationFailure extends Failure {
  const ValidationFailure(String message) : super(message);
}

/// Failure due to authentication/authorization issues
class AuthFailure extends Failure {
  const AuthFailure(String message) : super(message);
}

/// Failure due to cache/local storage errors
class CacheFailure extends Failure {
  const CacheFailure(String message) : super(message);
}

/// Failure for unexpected errors
class UnexpectedFailure extends Failure {
  const UnexpectedFailure(String message) : super(message);
}
