/// Pure helpers behind the Dashboard rack scan: which rows of the Stock
/// Balance report sit on the scanned rack, and what to tell the user when the
/// look-up fails.
///
/// Free of Flutter/GetX so the wire contract unit-tests without a binding.
library;

import 'package:dio/dio.dart';
import 'package:multimax/app/modules/hr/reports/common/hr_report_support.dart'
    show readableReportError, reportMaps;

/// Rows of a `frappe.desk.query_report.run` Stock Balance body whose `rack`
/// is [rackCode].
///
/// ERPNext v16 appends the report's total row as a positional list
/// (`["Total", "", …]`) after the map rows; it and any other non-map entry are
/// skipped. The rack match is still applied client-side even though the
/// request filters by rack, so a server that ignores the filter cannot put
/// another rack's stock in the sheet.
///
/// Throws [FormatException] when the body has no `message.result` list.
List<Map<String, dynamic>> rackRowsFromStockBalance(
  Object? body,
  String rackCode,
) {
  final message = body is Map ? body['message'] : null;
  final result = message is Map ? message['result'] : null;
  if (result is! List) {
    throw const FormatException(
      'Stock Balance response has no message.result list',
    );
  }
  return [
    for (final row in reportMaps(result))
      if (row['rack']?.toString() == rackCode) row,
  ];
}

/// Snackbar title and message for a rack look-up that threw [error].
///
/// Keeps the three failure kinds apart: the server answered with an error
/// (status and the server's own text), the request never got an answer
/// (connection or time-out), or the answer was not a Stock Balance reply.
({String title, String message}) rackLookupFailure(Object error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status != null) {
      return (
        title: 'Server Error',
        message: 'HTTP $status: ${readableReportError(error)}',
      );
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.connectionError => (
        title: 'Network Error',
        message: 'Could not reach the server. Check the connection and try '
            'again.',
      ),
      DioExceptionType.sendTimeout || DioExceptionType.receiveTimeout => (
        title: 'Network Error',
        message: 'The server took too long to answer. Try again.',
      ),
      _ => (
        title: 'Network Error',
        message: error.message ?? 'The request failed. Try again.',
      ),
    };
  }
  if (error is FormatException) {
    return (
      title: 'Unexpected Response',
      message: 'The server sent a Stock Balance reply the app does not '
          'recognise.',
    );
  }
  return (title: 'Rack Look-up Failed', message: '$error');
}

/// Message for a scanned code that is not a `<company>-<type>-<site>-<shelf>`
/// rack code, e.g. `KA-WH-DXB1-121D`.
String invalidRackCodeMessage(String rackCode) =>
    '"$rackCode" is not a rack code (expected e.g. KA-WH-DXB1-121D).';
