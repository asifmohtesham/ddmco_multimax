import 'dart:async';

import 'package:dio/dio.dart';

/// Supplies Frappe's CSRF token to cookie-session writes.
///
/// Frappe rejects an unsafe request (POST/PUT/DELETE…) with
/// `CSRFTokenError` once the session holds a `csrf_token` and the request
/// does not echo it in `X-Frappe-CSRF-Token`. Whether a session holds one
/// varies by server (seen on ERPNext v16; production v15 never asked), so the
/// token is fetched lazily: on the first CSRF rejection the desk boot page is
/// read for `csrf_token = "…"`, cached, and the request retried once. Later
/// writes carry the cached token up front. A stale token (new login) simply
/// triggers the same refresh again.
class CsrfInterceptor extends Interceptor {
  CsrfInterceptor({required Dio dio}) : _dio = dio;

  /// Desk boot page. v15 serves it at /app; v16 redirects /app → /desk.
  static const deskPath = '/app';
  static const header = 'X-Frappe-CSRF-Token';
  static const _retriedKey = 'csrfRetried';
  static const _unsafe = {'POST', 'PUT', 'PATCH', 'DELETE'};
  static final _tokenPattern = RegExp(r'''csrf_token\s*=\s*["']([^"']+)["']''');

  final Dio _dio;
  String? _token;
  Future<String?>? _refresh;

  String? get token => _token;

  static String? parseToken(String html) {
    final t = _tokenPattern.firstMatch(html)?.group(1);
    // Jinja renders "{{ csrf_token }}" literally only if templating failed.
    return (t == null || t.isEmpty || t.contains('{')) ? null : t;
  }

  static bool isCsrfRejection(DioException err) {
    final status = err.response?.statusCode;
    if (status != 400 && status != 403) return false;
    final data = err.response?.data;
    if (data is Map) return data['exc_type'] == 'CSRFTokenError';
    return data is String && data.contains('CSRFTokenError');
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final t = _token;
    if (t != null && _unsafe.contains(options.method.toUpperCase())) {
      options.headers[header] = t;
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final req = err.requestOptions;
    if (!isCsrfRejection(err) || req.extra[_retriedKey] == true) {
      return handler.next(err);
    }
    // Requests rejected together share one token fetch.
    final t = await (_refresh ??= _fetchToken().whenComplete(() => _refresh = null));
    if (t == null) return handler.next(err);
    try {
      final data = req.data;
      final retry = req.copyWith(
        data: data is FormData ? data.clone() : data,
        headers: {...req.headers, header: t},
        extra: {...req.extra, _retriedKey: true},
      );
      handler.resolve(await _dio.fetch(retry));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  Future<String?> _fetchToken() async {
    try {
      final res = await _dio.get<String>(deskPath,
          options: Options(responseType: ResponseType.plain));
      final t = parseToken(res.data ?? '');
      if (t != null) _token = t;
      return t;
    } catch (_) {
      return null;
    }
  }
}
