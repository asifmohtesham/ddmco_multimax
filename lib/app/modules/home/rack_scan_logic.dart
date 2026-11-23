/// Pure helpers behind the Dashboard rack scan: which rows of the Stock
/// Balance report sit on the scanned rack, and what to tell the user when the
/// look-up fails.
///
/// Unit-testable without a widget tree.
library;

import 'package:dio/dio.dart';
import 'package:multimax/app/data/utils/report_error.dart';
import 'package:multimax/app/modules/hr/reports/common/hr_report_support.dart'
    show reportMaps;

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
({String title, String message}) rackLookupFailure(Object error) {
  final message = readableReportError(error, reportName: 'Stock Balance');
  if (error is DioException) {
    return (
      title: error.response == null ? 'Network Error' : 'Server Error',
      message: message,
    );
  }
  if (error is FormatException) {
    return (
      title: 'Unexpected Response',
      message: 'The server sent a Stock Balance reply the app does not '
          'recognise.',
    );
  }
  return (title: 'Rack Look-up Failed', message: message);
}

/// Message for a scanned code that is not a `<company>-<type>-<site>-<shelf>`
/// rack code, e.g. `KA-WH-DXB1-121D`.
String invalidRackCodeMessage(String rackCode) =>
    '"$rackCode" is not a rack code (expected e.g. KA-WH-DXB1-121D).';
