import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/utils/report_error.dart';

DioException _responseError(int status, Object? body) {
  final options = RequestOptions(
    path: '/api/method/frappe.desk.query_report.run',
  );
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: options, statusCode: status, data: body),
  );
}

void main() {
  const reportName = 'Monthly Attendance Sheet';
  const permissionMessage =
      "You don't have permission to run Monthly Attendance Sheet. "
      'Ask your administrator.';

  String describe(Object error) =>
      readableReportError(error, reportName: reportName);

  test('HTTP 403 produces a permission message when the body is absent', () {
    expect(describe(_responseError(403, null)), permissionMessage);
  });

  test('PermissionError uses the permission message regardless of metadata', () {
    final body = {
      'exc_type': 'PermissionError',
      '_server_messages': jsonEncode([
        jsonEncode({
          'message': "You don't have permission to get a report on: Attendance",
          'indicator': 'red',
          'raise_exception': 1,
          '__frappe_exc_id': 'internal-id',
        }),
      ]),
    };
    expect(describe(_responseError(417, body)), permissionMessage);
    expect(
      describe(_responseError(417, {
        'exception': 'frappe.exceptions.PermissionError: Access refused',
      })),
      permissionMessage,
    );
  });

  test('network errors give a connection hint without the transport details', () {
    final error = DioException(
      requestOptions: RequestOptions(path: '/'),
      type: DioExceptionType.connectionError,
      message: 'SocketException: private host',
    );
    expect(describe(error),
        'Could not reach the server. Check the connection and try again.');
  });

  test('HTTP 500 hides the server exception and message log', () {
    final body = {
      'exception': 'IndexError: list index out of range',
      '_server_messages': jsonEncode([
        jsonEncode({'message': 'Traceback and diagnostic ID'}),
      ]),
    };
    expect(
      describe(_responseError(500, body)),
      'The server could not run Monthly Attendance Sheet. Try again later.',
    );
  });

  test('validation keeps readable instructions and skips metadata', () {
    final body = {
      '_server_messages': jsonEncode([
        jsonEncode({
          'message':
              'Please set <b>Standard Working Hours</b> in <a href="/app/hr-settings">HR Settings</a>.',
          'indicator': 'red',
          '__frappe_exc_id': 'internal-id',
        }),
      ]),
    };
    expect(describe(_responseError(417, body)),
        'Please set Standard Working Hours in HR Settings.');
  });

  test('a validation exception falls back to its plain message', () {
    final body = {
      'exception':
          'frappe.exceptions.ValidationError: From Date must come before To Date',
    };
    expect(describe(_responseError(417, body)),
        'From Date must come before To Date');
  });

  test('malformed validation messages do not render raw response text', () {
    expect(
      describe(_responseError(417, {
        '_server_messages': '{"private": "broken JSON"',
      })),
      'Could not run Monthly Attendance Sheet. Try again.',
    );
  });

  test('missing reports and data get a plain message', () {
    expect(
      describe(_responseError(404, {'exc_type': 'DoesNotExistError'})),
      'The server could not find Monthly Attendance Sheet or the data it needs.',
    );
  });

  test('unexpected errors never echo raw exception text', () {
    expect(
      describe(StateError('internal details')),
      'Could not run Monthly Attendance Sheet. Try again.',
    );
  });
}
