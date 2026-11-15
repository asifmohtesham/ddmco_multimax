// test/unit/home_rack_scan_logic_test.dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/home/rack_scan_logic.dart';

/// A Stock Balance row as ERPNext 16.55 returns it with
/// `show_dimension_wise_stock` and `show_variant_attributes` set (trimmed to
/// the fields the rack sheet reads plus a few attribute columns).
Map<String, dynamic> _row(String itemCode, String? rack, double balQty) => {
      'item_code': itemCode,
      'warehouse': 'WH-DXB1 - KA',
      'item_group': 'Belts',
      'company': 'Multimax',
      'stock_uom': 'Nos',
      'item_name': itemCode,
      'opening_qty': balQty,
      'in_qty': 0.0,
      'out_qty': 0.0,
      'bal_qty': balQty,
      'val_rate': 0.0,
      'rack': rack,
      'Colour': 'MIX',
      'Width': '30mm',
      'reserved_stock': 0.0,
    };

/// The total row v16 appends because the report has `add_total_row` set:
/// a positional list, not a map, one cell per column.
const List<Object> _v16TotalRow = [
  'Total', '', '', '', '', '', 1079213.0, 301100.73, 1079213.0, 301100.73,
  '', '', '', '', 24293.645, '', '', '', '', '', '', '', '', '', '', '',
];

Map<String, dynamic> _body(List<Object?> result) => {
      'message': {
        'result': result,
        'columns': const [],
        'add_total_row': true,
        'skip_total_row': 0,
      },
    };

DioException _dio(DioExceptionType type, {int? status, Object? data}) {
  final options = RequestOptions(path: '/api/method/frappe.desk.query_report.run');
  return DioException(
    requestOptions: options,
    type: type,
    response: status == null
        ? null
        : Response(requestOptions: options, statusCode: status, data: data),
  );
}

void main() {
  const rack = 'KA-WH-DXB1-121D';

  group('rackRowsFromStockBalance', () {
    test('skips the v16 positional total row instead of throwing', () {
      final body = _body([
        _row('3000247', rack, 36),
        _row('2002849', rack, 168),
        _v16TotalRow,
      ]);

      final rows = rackRowsFromStockBalance(body, rack);

      expect(rows.map((r) => r['item_code']), ['3000247', '2002849']);
      expect(rows.first['bal_qty'], 36);
    });

    test('keeps only rows on the scanned rack', () {
      final body = _body([
        _row('2001221', null, 0),
        _row('3000247', rack, 36),
        _row('3000999', 'KA-WH-DXB1-121C', 4),
        _v16TotalRow,
      ]);

      expect(
        rackRowsFromStockBalance(body, rack).map((r) => r['item_code']),
        ['3000247'],
      );
    });

    test('accepts a v15 body with no total row', () {
      final body = _body([_row('3000247', rack, 36)]);
      expect(rackRowsFromStockBalance(body, rack), hasLength(1));
    });

    test('returns empty for a rack with no rows (Empty Rack, not an error)', () {
      final body = _body([_v16TotalRow]);
      expect(rackRowsFromStockBalance(body, rack), isEmpty);
    });

    test('skips scalars and nulls in result', () {
      final body = _body([null, 'stray', 42, _row('3000247', rack, 36)]);
      expect(rackRowsFromStockBalance(body, rack), hasLength(1));
    });

    test('throws FormatException when message.result is missing', () {
      expect(
        () => rackRowsFromStockBalance({'message': {}}, rack),
        throwsFormatException,
      );
      expect(
        () => rackRowsFromStockBalance({'message': 'oops'}, rack),
        throwsFormatException,
      );
      expect(
        () => rackRowsFromStockBalance(null, rack),
        throwsFormatException,
      );
    });
  });

  group('rackLookupFailure', () {
    test('server error carries the HTTP status and the server text', () {
      // Live v16 answer for a well-formed code whose warehouse does not exist.
      final failure = rackLookupFailure(_dio(
        DioExceptionType.badResponse,
        status: 500,
        data: {
          'exception': 'IndexError: list index out of range',
          'exc_type': 'IndexError',
        },
      ));

      expect(failure.title, 'Server Error');
      expect(failure.message, 'HTTP 500: list index out of range');
    });

    test('server error prefers _server_messages over exception', () {
      final failure = rackLookupFailure(_dio(
        DioExceptionType.badResponse,
        status: 403,
        data: {
          '_server_messages':
              '["{\\"message\\": \\"Not permitted to run <b>Stock Balance</b>\\"}"]',
          'exception': 'frappe.exceptions.PermissionError',
        },
      ));

      expect(failure.title, 'Server Error');
      expect(failure.message, 'HTTP 403: Not permitted to run Stock Balance');
    });

    test('connection failure is a network error, not a server error', () {
      for (final type in [
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
      ]) {
        final failure = rackLookupFailure(_dio(type));
        expect(failure.title, 'Network Error');
        expect(failure.message, contains('Could not reach the server'));
      }
    });

    test('receive time-out says the server was too slow', () {
      final failure = rackLookupFailure(_dio(DioExceptionType.receiveTimeout));
      expect(failure.title, 'Network Error');
      expect(failure.message, contains('too long'));
    });

    test('unrecognised body is reported as an unexpected response', () {
      final failure = rackLookupFailure(const FormatException('x'));
      expect(failure.title, 'Unexpected Response');
    });

    test('anything else keeps its own text', () {
      final failure = rackLookupFailure(StateError('boom'));
      expect(failure.title, 'Rack Look-up Failed');
      expect(failure.message, contains('boom'));
    });
  });

  test('invalidRackCodeMessage names the scanned code', () {
    expect(invalidRackCodeMessage('KA-WH-DXB1'), contains('"KA-WH-DXB1"'));
  });
}
