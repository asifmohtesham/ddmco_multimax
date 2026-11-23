import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:multimax/app/core/utils/html_text.dart';

/// User-visible error text for reports that run through Frappe.
String readableReportError(Object error, {required String reportName}) {
  if (kDebugMode) debugPrint('$reportName failed: $error');

  final fallback = 'Could not run $reportName. Try again.';
  if (error is! DioException) return fallback;

  final status = error.response?.statusCode;
  final data = error.response?.data;
  final body = data is Map ? data : const {};
  final rawException = body['exception'];
  final exception = rawException is String ? rawException : '';
  final exceptionClass = _exceptionClass.firstMatch(exception)?.group(1);
  final type = body['exc_type'] ?? exceptionClass;

  if (status == 403 || type == 'PermissionError') {
    return "You don't have permission to run $reportName. "
        'Ask your administrator.';
  }
  if (status != null && status >= 500) {
    return 'The server could not run $reportName. Try again later.';
  }
  if (status == 404 || type == 'DoesNotExistError') {
    return 'The server could not find $reportName or the data it needs.';
  }

  // Validation messages are written for the person running the report.
  // Extract the actual message field from Frappe's JSON and leave metadata
  // in the debug log.
  if (status == 417 || type == 'ValidationError') {
    final message = _serverMessageText(body['_server_messages']);
    if (message != null) return message;
    if (exceptionClass == 'ValidationError') {
      final separator = exception.indexOf(':');
      if (separator != -1) {
        final text = htmlToSingleLine(exception.substring(separator + 1));
        if (text.isNotEmpty) return text;
      }
    }
  }

  return switch (error.type) {
    DioExceptionType.connectionError || DioExceptionType.connectionTimeout =>
      'Could not reach the server. Check the connection and try again.',
    DioExceptionType.sendTimeout || DioExceptionType.receiveTimeout =>
      'The server took too long to answer. Try again.',
    _ => fallback,
  };
}

final _exceptionClass = RegExp(r'^(?:\w+\.)*(\w+)(?=:|$)');

/// API v1 uses a JSON array of JSON-encoded message objects.
String? _serverMessageText(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  try {
    final outer = jsonDecode(raw);
    if (outer is! List) return null;
    final texts = <String>[];
    for (final entry in outer) {
      final decoded = entry is String ? jsonDecode(entry) : entry;
      final message = decoded is Map ? decoded['message'] : null;
      if (message is! String) continue;
      final text = htmlToSingleLine(message);
      if (text.isNotEmpty) texts.add(text);
    }
    return texts.isEmpty ? null : texts.join('\n');
  } on FormatException {
    return null;
  }
}
