class AppException implements Exception {
  final String message;


  @override
  String toString() => message;
}

class NetworkException extends AppException {
  NetworkException(String message) : super(message);
}

class ServerException extends AppException {

}

class ValidationException extends AppException {
  ValidationException(String message) : super(message);
}

class AuthException extends AppException {
}
