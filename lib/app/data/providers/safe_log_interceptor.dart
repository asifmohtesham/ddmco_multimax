import 'package:dio/dio.dart';

/// Request/response logging for debugging that keeps credentials out of
/// the console.
///
/// Headers are never logged, because they carry the session cookie. A
/// request whose body names a credential field has the whole body hidden:
/// a password can contain any character, so it cannot be cut out of the
/// printed text reliably.
class SafeLogInterceptor extends LogInterceptor {
  SafeLogInterceptor()
      : super(
          requestHeader: false,
          responseHeader: false,
          requestBody: true,
          responseBody: true,
        );

  static final _credentialField =
      RegExp(r'pass|pwd|secret|token', caseSensitive: false);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!_carriesCredentials(options.data)) {
      super.onRequest(options, handler);
      return;
    }
    logPrint('*** Request ***');
    logPrint('uri: ${options.uri}');
    logPrint('method: ${options.method}');
    logPrint('data: [hidden: contains credentials]');
    handler.next(options);
  }

  bool _carriesCredentials(Object? data) {
    if (data is Map) {
      return data.keys.any((key) => _credentialField.hasMatch('$key'));
    }
    if (data is FormData) {
      return data.fields.any((field) => _credentialField.hasMatch(field.key));
    }
    return false;
  }
}
