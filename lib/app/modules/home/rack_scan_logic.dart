/// Pure helpers behind the Dashboard rack scan: which rows of the Stock
/// Balance report sit on the scanned rack, and what to tell the user when the
/// look-up fails.
///
/// Unit-testable without a widget tree.
library;

import 'package:dio/dio.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/utils/report_error.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_fields.dart';

/// Rows of a `frappe.desk.query_report.run` Stock Balance body whose `rack`
/// is [rackCode].
///
/// The rack match is applied client-side even when the request filters by
/// rack. The Stock Balance adapter removes the server total and handles both
/// named and positional data rows.
///
/// Throws [FormatException] when the body has no `message.result` list.
List<Map<String, dynamic>> rackRowsFromStockBalance(
  Object? body,
  String rackCode,
) => rackResultFromStockBalance(body, rackCode).rows;

({List<Map<String, dynamic>>? columns, List<Map<String, dynamic>> rows})
rackResultFromStockBalance(Object? body, String rackCode) {
  final message = body is Map ? body['message'] : null;
  if (message is! Map || message['result'] is! List) {
    throw const FormatException(
      'Stock Balance response has no message.result list',
    );
  }
  final result = ApiProvider.parseStockBalanceResponse(
    Map<String, dynamic>.from(message),
  );
  final rackColumn = result.columns.where(stockBalanceRackColumn).firstOrNull;
  return (
    columns: message['columns'] is List ? result.columns : null,
    rows: List.unmodifiable([
      for (final row in result.rows)
        if ((rackColumn == null
                    ? row['rack']
                    : stockBalanceColumnValue(row, rackColumn))
                ?.toString() ==
            rackCode)
          row,
    ]),
  );
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
      message:
          'The server sent a Stock Balance reply the app does not '
          'recognise.',
    );
  }
  return (title: 'Rack Look-up Failed', message: message);
}

/// Message for a scanned code that is not a `<company>-<type>-<site>-<shelf>`
/// rack code, e.g. `KA-WH-DXB1-121D`.
String invalidRackCodeMessage(String rackCode) =>
    '"$rackCode" is not a rack code (expected e.g. KA-WH-DXB1-121D).';
