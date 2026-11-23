import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/stock/reports/item_variant_details/item_variant_details_logic.dart';

void main() {
  test('encodes scalar, list and omitted report filters', () {
    expect(ApiProvider.itemVariantDetailsFilters(), isEmpty);
    expect(ApiProvider.itemVariantDetailsFilters(items: ['ACP-25']), {
      'item': 'ACP-25',
    });
    expect(
      ApiProvider.itemVariantDetailsFilters(
        items: ['ACP-25', 'ACP-MIX'],
        warehouses: ['POS-DXB2 - KA', 'WH-DXB1 - KA'],
      ),
      {
        'item': ['ACP-25', 'ACP-MIX'],
        'warehouse': ['POS-DXB2 - KA', 'WH-DXB1 - KA'],
      },
    );
    expect(
      ApiProvider.itemVariantDetailsFilters(itemGroups: ['Belts', 'Wallets']),
      {
        'item_group': ['Belts', 'Wallets'],
      },
    );
  });

  test(
    'keeps the live multi-template block order in a single request',
    () async {
      // Trimmed from the production items.json capture.
      final rows = <Map<String, dynamic>>[
        {'variant_name': 'ACP-25', 'indent': 0},
        {'variant_name': '2002506', 'template': 'ACP-25', 'indent': 1},
        {'variant_name': '2002492', 'template': 'ACP-25', 'indent': 1},
        {'variant_name': 'ACP-MIX', 'indent': 0},
        {'variant_name': '2002499', 'template': 'ACP-MIX', 'indent': 1},
      ];
      final calls = <Map<String, dynamic>>[];
      final result = await ApiProvider.requestItemVariantDetails(
        items: ['ACP-MIX', 'ACP-25'],
        itemGroups: [],
        warehouses: [],
        request: (filters) async {
          calls.add(filters);
          return (
            columns: [
              {
                'fieldname': 'item_group',
                'fieldtype': 'Link',
                'options': 'Item Group',
              },
              {'fieldname': 'stock_uom', 'fieldtype': 'Link', 'options': 'UOM'},
            ],
            rows: rows,
          );
        },
      );
      expect(calls, [
        {
          'item': ['ACP-MIX', 'ACP-25'],
        },
      ]);
      expect(result.rows, rows);
      expect(variantRowsOf(result.rows).map((row) => row['variant_name']), [
        '2002506',
        '2002492',
        '2002499',
      ]);
    },
  );

  test(
    'retries a legacy list rejection with ordered scalar requests',
    () async {
      final calls = <Map<String, dynamic>>[];
      final result = await ApiProvider.requestItemVariantDetails(
        items: ['ACP-MIX', 'ACP-25'],
        itemGroups: [],
        warehouses: [],
        request: (filters) async {
          calls.add(filters);
          final item = filters['item'];
          if (item is List) throw _reportError(500, 'ValueError');
          final isMix = item == 'ACP-MIX';
          return (
            columns: [
              {'fieldname': 'variant_name'},
              {'fieldname': isMix ? 'colour' : 'material'},
            ],
            rows: [
              if (isMix)
                {'variant_name': '2002499'}
              else ...[
                {'variant_name': '2002506'},
                {'variant_name': '2002492'},
              ],
            ],
          );
        },
      );
      expect(calls, [
        {
          'item': ['ACP-MIX', 'ACP-25'],
        },
        {'item': 'ACP-MIX'},
        {'item': 'ACP-25'},
      ]);
      expect(result.rows.map((row) => row['variant_name']), [
        '2002499',
        '2002506',
        '2002492',
      ]);
      expect(result.columns.map((column) => column['fieldname']), [
        'variant_name',
        'colour',
        'material',
      ]);
    },
  );

  test(
    'retries an empty legacy success for a list as scalar requests',
    () async {
      final calls = <Object?>[];
      final result = await ApiProvider.requestItemVariantDetails(
        items: ['ACP-25', 'ACP-MIX'],
        itemGroups: [],
        warehouses: [],
        request: (filters) async {
          final item = filters['item'];
          calls.add(item);
          const legacyColumns = [
            {'fieldname': 'variant_name'},
            {'fieldname': 'item_group', 'fieldtype': 'Data'},
            {'fieldname': 'stock_uom', 'fieldtype': 'Data'},
          ];
          return (
            columns: legacyColumns,
            rows: <Map<String, dynamic>>[
              if (item is String)
                {'variant_name': item == 'ACP-25' ? '2002506' : '2002499'},
            ],
          );
        },
      );
      expect(calls, [
        ['ACP-25', 'ACP-MIX'],
        'ACP-25',
        'ACP-MIX',
      ]);
      expect(result.rows.map((row) => row['variant_name']), [
        '2002506',
        '2002499',
      ]);
    },
  );

  test('discards legacy results that ignored warehouses', () async {
    await expectLater(
      ApiProvider.requestItemVariantDetails(
        items: ['ACP-25'],
        itemGroups: [],
        warehouses: ['POS-DXB2 - KA'],
        request: (filters) async {
          expect(filters, {
            'item': 'ACP-25',
            'warehouse': ['POS-DXB2 - KA'],
          });
          return (
            columns: [
              {'fieldname': 'variant_name'},
            ],
            rows: [
              {'variant_name': '2002506', 'current_stock': 936.0},
            ],
          );
        },
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('cannot apply'),
        ),
      ),
    );
  });

  test(
    'keeps warehouses on scalar retry and rejects unscoped legacy rows',
    () async {
      final calls = <Map<String, dynamic>>[];
      await expectLater(
        ApiProvider.requestItemVariantDetails(
          items: ['ACP-25', 'ACP-MIX'],
          itemGroups: [],
          warehouses: ['POS-DXB2 - KA'],
          request: (filters) async {
            calls.add(filters);
            if (filters['item'] is List) throw _reportError(500, 'TypeError');
            return (
              columns: [
                {'fieldname': 'variant_name'},
              ],
              rows: <Map<String, dynamic>>[],
            );
          },
        ),
        throwsA(isA<FormatException>()),
      );
      expect(calls, [
        {
          'item': ['ACP-25', 'ACP-MIX'],
          'warehouse': ['POS-DXB2 - KA'],
        },
        {
          'item': 'ACP-25',
          'warehouse': ['POS-DXB2 - KA'],
        },
      ]);
    },
  );

  test(
    'group-only legacy errors tell the user how to run the report',
    () async {
      await expectLater(
        ApiProvider.requestItemVariantDetails(
          items: [],
          itemGroups: ['Belts'],
          warehouses: [],
          request: (_) async => throw _reportError(404, 'DoesNotExistError'),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Try selecting Items'),
          ),
        ),
      );
    },
  );

  test('does not split a permission failure', () async {
    final error = _reportError(403, 'PermissionError');
    var requests = 0;
    await expectLater(
      ApiProvider.requestItemVariantDetails(
        items: ['ACP-25', 'ACP-MIX'],
        itemGroups: [],
        warehouses: [],
        request: (_) async {
          requests++;
          throw error;
        },
      ),
      throwsA(same(error)),
    );
    expect(requests, 1);
  });

  group('ApiProvider.parseItemVariantDetailsResponse', () {
    test('16.60 tree preserves headings and populated variant chips', () {
      // Trimmed from the 16.60.0 production response (indent 0/1, "-" placeholders).
      final report = ApiProvider.parseItemVariantDetailsResponse({
        'columns': [
          {'fieldname': 'variant_name', 'label': 'Item'},
          {'fieldname': 'item_group', 'label': 'Item Group'},
          {'fieldname': 'brand', 'label': 'Brand'},
          {'fieldname': 'material', 'label': 'Material'},
          {'fieldname': 'hole', 'label': 'Hole'},
          {'fieldname': 'length', 'label': 'Length'},
          {'fieldname': 'stock_uom', 'label': 'Stock UOM'},
          {'fieldname': 'current_stock', 'label': 'Current Stock'},
          {'fieldname': 'open_orders', 'label': 'Open Sales Orders'},
        ],
        'result': [
          {
            'variant_name': 'TEMPLATE-A',
            'item_group': 'Belts',
            'indent': 0,
            'current_stock': null,
            'open_orders': 0,
          },
          {
            'variant_name': 'VARIANT-A',
            'template': 'TEMPLATE-A',
            'item_group': 'Belts',
            'indent': 1,
            'brand': 'Example',
            'material': '-',
            'hole': '',
            'stock_uom': 'Nos',
            'current_stock': 0,
          },
          {'variant_name': 'TEMPLATE-B', 'indent': 0},
          {'variant_name': 'VARIANT-B', 'template': 'TEMPLATE-B', 'indent': 1},
        ],
      });
      final variants = variantRowsOf(report.rows);
      expect(report.rows.map(isTemplateRow), [true, false, true, false]);
      expect(variants.map((row) => row['variant_name']), [
        'VARIANT-A',
        'VARIANT-B',
      ]);
      expect(templateTotals(report.rows.first, report.columns), [
        (label: 'Open Sales Orders', value: '0'),
      ]);
      expect(variantChips(variants.first, report.columns), [
        (label: 'Brand', value: 'Example'),
      ]);
      expect(variantChips(variants.last, report.columns), isEmpty);
    });

    test('T-1: returns empty record when message is null', () {
      final result = ApiProvider.parseItemVariantDetailsResponse(null);
      expect(result.columns, isEmpty);
      expect(result.rows, isEmpty);
    });

    test(
      'T-2: returns empty record when message lacks columns/result keys',
      () {
        final result = ApiProvider.parseItemVariantDetailsResponse({
          'other': 'data',
        });
        expect(result.columns, isEmpty);
        expect(result.rows, isEmpty);
      },
    );

    test('T-3: parses columns and rows from a well-formed message', () {
      final message = <String, dynamic>{
        'columns': [
          {'fieldname': 'item', 'label': 'Item'},
          {'fieldname': 'colour', 'label': 'Colour'},
          {'fieldname': 'size', 'label': 'Size'},
        ],
        'result': [
          {'item': 'BLUE-T-S', 'colour': 'Blue', 'size': 'S'},
          {'item': 'BLUE-T-M', 'colour': 'Blue', 'size': 'M'},
        ],
      };
      final result = ApiProvider.parseItemVariantDetailsResponse(message);
      expect(result.columns.length, 3);
      expect(result.rows.length, 2);
      expect(result.columns.first['fieldname'], 'item');
      expect(result.rows.first['item'], 'BLUE-T-S');
      expect(result.rows.last['size'], 'M');
    });

    test('T-4: ignores null and non-Map entries in the result list', () {
      final message = <String, dynamic>{
        'columns': [
          {'fieldname': 'item', 'label': 'Item'},
        ],
        'result': [
          null,
          {'item': 'ITEM-001'},
          42,
          {'item': 'ITEM-002'},
        ],
      };
      final result = ApiProvider.parseItemVariantDetailsResponse(message);
      expect(result.rows.length, 2);
      expect(
        result.rows.map((r) => r['item']),
        containsAll(['ITEM-001', 'ITEM-002']),
      );
    });

    test('T-5: returns empty record when columns or result are not Lists', () {
      final message = <String, dynamic>{
        'columns': 'not-a-list',
        'result': 'not-a-list',
      };
      final result = ApiProvider.parseItemVariantDetailsResponse(message);
      expect(result.columns, isEmpty);
      expect(result.rows, isEmpty);
    });
  });
}

DioException _reportError(int status, String type) {
  final options = RequestOptions(
    path: '/api/method/frappe.desk.query_report.run',
  );
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(
      requestOptions: options,
      statusCode: status,
      data: {'exc_type': type},
    ),
  );
}
