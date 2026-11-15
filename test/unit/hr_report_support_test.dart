import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/hr/reports/common/hr_report_support.dart';

DioException _dioError(Object? body, {int status = 403}) {
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
  group('parseReportSummary', () {
    test('keeps server order, labels, indicators and int values', () {
      // Verbatim shape of Shift Attendance on erp.multimax.cloud, 2026-11-15.
      final items = parseReportSummary([
        {
          'value': 314,
          'indicator': 'Green',
          'label': 'Present Records',
          'datatype': 'Int',
        },
        {
          'value': 0,
          'indicator': 'Blue',
          'label': 'Half Day Records',
          'datatype': 'Int',
        },
        {
          'value': 6,
          'indicator': 'Red',
          'label': 'Late Entries',
          'datatype': 'Int',
        },
      ]);
      expect(items.map((i) => i.label), [
        'Present Records',
        'Half Day Records',
        'Late Entries',
      ]);
      expect(items.map((i) => i.value), ['314', '0', '6']);
      expect(items.map((i) => i.indicator), [
        SummaryIndicator.green,
        SummaryIndicator.blue,
        SummaryIndicator.red,
      ]);
    });

    test('string and float values; missing indicator is none', () {
      final items = parseReportSummary([
        {'value': '82.5%', 'indicator': 'Green', 'label': 'Avg Utilization'},
        {'value': 1234.567, 'label': 'Total Billed Hours', 'datatype': 'Float'},
        {'value': 12.0, 'label': 'Whole float'},
      ]);
      expect(items[0].value, '82.5%');
      expect(items[1].value, '1,234.57');
      expect(items[1].indicator, SummaryIndicator.none);
      expect(items[2].value, '12');
    });

    test('null / malformed → empty', () {
      expect(parseReportSummary(null), isEmpty);
      expect(parseReportSummary('nope'), isEmpty);
      expect(
        parseReportSummary([
          1,
          {'value': 3},
        ]),
        isEmpty,
      );
    });
  });

  group('formatHours', () {
    test('hours and minutes', () {
      expect(formatHours(3.93), '3h 56m');
      expect(formatHours(10), '10h');
      expect(formatHours(0.75), '45m');
      expect(formatHours(0), '0h');
      expect(formatHours(-1), '0h');
    });
  });

  group('readableReportError', () {
    test('reads the message out of _server_messages', () {
      // Verbatim from the live 403 on the Timesheet-based report.
      final body = {
        'exception':
            "frappe.exceptions.PermissionError: You don't have permission to get a report on: Timesheet",
        '_server_messages': jsonEncode([
          jsonEncode({
            'message':
                "You don't have permission to get a report on: Timesheet",
            'indicator': 'red',
            'raise_exception': 1,
          }),
        ]),
      };
      expect(
        readableReportError(_dioError(body)),
        "You don't have permission to get a report on: Timesheet",
      );
    });

    test('strips HTML from a server message', () {
      final body = {
        '_server_messages': jsonEncode([
          jsonEncode({
            'message':
                'The metrics for this report are calculated based on <b>Standard Working Hours</b>. '
                'Please set <b>Standard Working Hours</b> in <a href="/app/hr-settings">HR Settings</a>.',
          }),
        ]),
      };
      expect(
        readableReportError(_dioError(body, status: 417)),
        'The metrics for this report are calculated based on Standard Working Hours. '
        'Please set Standard Working Hours in HR Settings.',
      );
    });

    test('falls back to the exception text without its class', () {
      final body = {
        'exception':
            'frappe.exceptions.ValidationError: From Date must come before To Date',
      };
      expect(
        readableReportError(_dioError(body, status: 417)),
        'From Date must come before To Date',
      );
    });

    test('connection failure reads as such', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/'),
        type: DioExceptionType.connectionError,
      );
      expect(
        readableReportError(error),
        contains('Could not reach the server'),
      );
    });
  });

  group('ReportPeriod', () {
    final now = DateTime(2026, 11, 15, 14, 30);

    String fmt((DateTime, DateTime) range) =>
        '${kReportDate.format(range.$1)}..${kReportDate.format(range.$2)}';

    test('ranges are inclusive and ignore the time of day', () {
      expect(fmt(ReportPeriod.today.rangeFor(now)), '2026-11-15..2026-11-15');
      expect(
        fmt(ReportPeriod.yesterday.rangeFor(now)),
        '2026-11-14..2026-11-14',
      );
      expect(
        fmt(ReportPeriod.last7Days.rangeFor(now)),
        '2026-11-09..2026-11-15',
      );
      expect(
        fmt(ReportPeriod.thisMonth.rangeFor(now)),
        '2026-11-01..2026-11-15',
      );
      expect(
        fmt(ReportPeriod.lastMonth.rangeFor(now)),
        '2026-10-01..2026-10-31',
      );
      expect(
        fmt(ReportPeriod.last30Days.rangeFor(now)),
        '2026-10-17..2026-11-15',
      );
    });

    test('last month across a year boundary', () {
      expect(
        fmt(ReportPeriod.lastMonth.rangeFor(DateTime(2027, 1, 3))),
        '2026-12-01..2026-12-31',
      );
    });

    test('matchingPeriod finds the preset for a range', () {
      const options = ReportPeriod.values;
      expect(
        matchingPeriod(options, '2026-11-01', '2026-11-15', now),
        ReportPeriod.thisMonth,
      );
      expect(matchingPeriod(options, '2026-11-02', '2026-11-15', now), isNull);
    });

    test('periodLabel', () {
      expect(periodLabel('2026-11-01', '2026-11-15'), '1 Nov → 15 Nov 2026');
      expect(periodLabel('2026-11-14', '2026-11-14'), 'Sat 14 Nov 2026');
      expect(
        periodLabel('2026-12-20', '2027-01-05'),
        '20 Dec 2026 → 5 Jan 2027',
      );
    });
  });
}
