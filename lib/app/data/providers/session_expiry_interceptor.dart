import 'package:dio/dio.dart';

/// Tells the app when the server has stopped accepting the session.
///
/// Frappe answers 403 both for "you are logged out" and for "you may not
/// read this DocType", so a 401/403 on its own proves nothing. On such a
/// failure this interceptor asks the server who is logged in, and reports
/// expiry only when the answer is Guest or a refusal.
///
/// The original error always continues to the caller unchanged.
class SessionExpiryInterceptor extends Interceptor {
  SessionExpiryInterceptor({
    required Dio dio,
    required this.hasActiveSession,
    required this.onSessionExpired,
    DateTime Function()? now,
  })  : _dio = dio,
        _now = now ?? DateTime.now;

  static const identityPath = '/api/method/frappe.auth.get_logged_user';

  static const _uncheckedKey = 'uncheckedSession';

  /// How long a confirmed identity is trusted. Keeps a user who simply lacks
  /// a permission from paying for an identity check on every refusal.
  static const _confirmationLifetime = Duration(seconds: 30);

  /// Marks a request whose 401/403 must not be read as session expiry:
  /// login, logout and the identity check itself.
  static Options unchecked([Options? options]) {
    return (options ?? Options()).copyWith(
      extra: {...?options?.extra, _uncheckedKey: true},
    );
  }

  final Dio _dio;
  final DateTime Function() _now;
  final bool Function() hasActiveSession;
  final void Function() onSessionExpired;

  Future<void>? _check;
  DateTime? _confirmedAt;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (_mayMeanExpiry(err)) {
      // Requests failing together share one identity check.
      await (_check ??= _checkIdentity().whenComplete(() => _check = null));
    }
    handler.next(err);
  }

  bool _mayMeanExpiry(DioException err) {
    final status = err.response?.statusCode;
    if (status != 401 && status != 403) return false;
    if (err.requestOptions.extra[_uncheckedKey] == true) return false;
    if (!hasActiveSession()) return false;
    final confirmedAt = _confirmedAt;
    return confirmedAt == null ||
        _now().difference(confirmedAt) >= _confirmationLifetime;
  }

  Future<void> _checkIdentity() async {
    try {
      final response = await _dio.get(identityPath, options: unchecked());
      final data = response.data;
      final user = data is Map ? data['message'] : null;
      if (user == 'Guest') {
        _reportExpiry();
      } else if (user is String && user.isNotEmpty) {
        _confirmedAt = _now();
      }
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) _reportExpiry();
      // Anything else means the server could not be asked: say nothing.
    }
  }

  void _reportExpiry() {
    _confirmedAt = null;
    onSessionExpired();
  }
}
