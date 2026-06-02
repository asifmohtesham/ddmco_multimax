import 'package:dio/dio.dart';

mixin DioErrorMixin {
  String extractDioError(DioException e, String fallback) {
    try {
      final data = e.response?.data;
      if (data is Map) {
        final exc = data['exception'] as String? ?? '';
        if (exc.isNotEmpty) {
          final idx = exc.indexOf(':');
          return idx != -1 ? exc.substring(idx + 1).trim() : exc.trim();
        }
        final msg = data['message'] as String? ?? '';
        if (msg.isNotEmpty) return msg.trim();
      }
    } catch (_) {}
    return fallback;
  }
}