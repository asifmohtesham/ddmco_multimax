import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_fields.dart';

class _EmptySettings {
  T? read<T>(String key) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'dimension-wise Stock Balance encodes the selected warehouses',
    () async {
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => 'build');
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      Get.put(StorageService.withStorage(_EmptySettings()));
      addTearDown(Get.reset);
      final api = ApiProvider();
      await api.initDio();
      final requests = <Map<String, dynamic>>[];
      api.dio.interceptors
        ..clear()
        ..add(
          InterceptorsWrapper(
            onRequest: (request, handler) {
              final query = request.queryParameters;
              if (query['report_name'] == 'Stock Balance') {
                requests.add(
                  jsonDecode(query['filters'] as String)
                      as Map<String, dynamic>,
                );
              }
              handler.resolve(
                Response(
                  requestOptions: request,
                  statusCode: 200,
                  data: {
                    'message': {
                      if (query['report_name'] == 'Stock Balance')
                        'result': <dynamic>[
                          {'rack': 'Rack 1', 'bal_qty': 2.5},
                        ]
                      else
                        'erpnext': {'version': '16.60.0'},
                    },
                  },
                ),
              );
            },
          ),
        );

      final rows = await api.getStockBalanceWithDimension(itemCode: 'Variant');
      await api.getStockBalanceWithDimension(
        itemCode: 'Variant',
        warehouses: ['WH-A'],
      );
      await api.getStockBalanceWithDimension(
        itemCode: 'Variant',
        warehouses: ['WH-A', 'WH-B'],
      );
      await api.getStockBalanceWithDimension(
        itemCode: 'Variant',
        warehouse: 'Legacy WH',
        batchNo: 'Batch 1',
      );

      expect(rows, [
        {'rack': 'Rack 1', 'qty': 2.5},
      ]);
      expect(requests.first.containsKey('warehouse'), isFalse);
      expect(requests.map((filters) => filters['warehouse']), [
        null,
        'WH-A',
        ['WH-A', 'WH-B'],
        'Legacy WH',
      ]);
      expect(requests.last['batch_no'], 'Batch 1');
      for (final filters in requests) {
        expect(filters['item_code'], ['Variant']);
        expect(filters['show_dimension_wise_stock'], 1);
        expect(filters['show_variant_attributes'], 1);
      }
    },
  );

  group('ApiProvider.parseStockBalanceResponse', () {
    test('T-1: returns empty record when message is null', () {
      final result = ApiProvider.parseStockBalanceResponse(null);
      expect(result.columns, isEmpty);
      expect(result.rows, isEmpty);
    });

    test('T-2: retains the schema when result list is empty', () {
      final result = ApiProvider.parseStockBalanceResponse({
        'columns': [{'fieldname': 'item_code', 'label': 'Item Code'}],
        'result': <dynamic>[],
      });
      expect(result.columns.single['label'], 'Item Code');
      expect(result.rows, isEmpty);
    });

    test('T-3: parses Map rows correctly', () {
      final result = ApiProvider.parseStockBalanceResponse({
        'columns': [
          {'fieldname': 'item_code',   'label': 'Item Code'},
          {'fieldname': 'warehouse',   'label': 'Warehouse'},
          {'fieldname': 'balance_qty', 'label': 'Balance Qty'},
        ],
        'result': [
          {'item_code': 'ITEM-001', 'warehouse': 'Stores - KA', 'balance_qty': 42},
        ],
      });
      expect(result.rows.length, 1);
      expect(result.rows[0]['item_code'],   'ITEM-001');
      expect(result.rows[0]['warehouse'],   'Stores - KA');
      expect(result.rows[0]['balance_qty'], 42);
    });

    test('T-4: parses List rows using column positions', () {
      final result = ApiProvider.parseStockBalanceResponse({
        'columns': [
          {'fieldname': 'item_code',   'label': 'Item Code'},
          {'fieldname': 'warehouse',   'label': 'Warehouse'},
          {'fieldname': 'balance_qty', 'label': 'Balance Qty'},
        ],
        'result': [
          ['ITEM-001', 'Stores - KA', 15],
        ],
      });
      expect(result.rows.length, 1);
      expect(result.rows[0]['item_code'],   'ITEM-001');
      expect(result.rows[0]['warehouse'],   'Stores - KA');
      expect(result.rows[0]['balance_qty'], 15);
    });

    test('T-5: extracts fieldname from string-format columns', () {
      final result = ApiProvider.parseStockBalanceResponse({
        'columns': ['bin.item_code', 'bin.balance_qty'],
        'result': [
          ['ITEM-001', 50],
        ],
      });
      expect(result.columns[0]['fieldname'], 'item_code');
      expect(result.columns[1]['fieldname'], 'balance_qty');
      expect(result.rows[0]['item_code'],    'ITEM-001');
      expect(result.rows[0]['balance_qty'],  50);
    });

    test('T-6: populates columns list with fieldname and label', () {
      final result = ApiProvider.parseStockBalanceResponse({
        'columns': [
          {'fieldname': 'balance_qty', 'label': 'Balance Qty'},
        ],
        'result': [
          {'balance_qty': 0},
        ],
      });
      expect(result.columns.first['fieldname'], 'balance_qty');
      expect(result.columns.first['label'],     'Balance Qty');
    });

    test('retains case-distinct attributes and the prior lookup default', () {
      final columns = [
        {'fieldname': 'item_code', 'label': 'Item'},
        {'fieldname': 'warehouse', 'label': 'Warehouse'},
        {'fieldname': 'Model', 'label': 'Modelo'},
        {'fieldname': 'model', 'label': 'Model (lowercase)'},
        {'fieldname': 'Brand', 'label': 'Marca'},
      ];
      final maps = ApiProvider.parseStockBalanceResponse({
        'columns': columns,
        'result': [
          {'item_code': 'A', 'warehouse': 'W', 'Model': 'A', 'model': 'B'},
        ],
      });
      final lists = ApiProvider.parseStockBalanceResponse({
        'columns': columns,
        'result': [
          ['A', 'W', 'A', 'B', 'C'],
        ],
      });
      final mapFields = stockBalanceFields(maps.columns);
      final listFields = stockBalanceFields(lists.columns);
      expect(mapFields.field('Model')!.defaultVisible, isFalse);
      expect(mapFields.field('model')!.defaultVisible, isTrue);
      expect(listFields.field('Model')!.defaultVisible, isTrue);
      expect(listFields.field('Brand')!.defaultVisible, isFalse);
      expect(mapFields.label('Model'), 'Modelo');
      for (final result in [maps, lists]) {
        expect(result.rows.single['Model'], 'A');
        expect(result.rows.single['model'], 'B');
      }
    });

    test('excludes the appended total while retaining zero and Total names', () {
      final report = ApiProvider.parseStockBalanceResponse({
        'columns': [
          'Item:Link/Item:100', 'Warehouse:Link/Warehouse:100',
          'Balance Qty:Float:100',
        ],
        'result': [
          ['Total Tools', 'W', 0],
          ['Total', 'W', 1],
          ['Somme', '', 1],
        ],
        'add_total_row': true,
      });
      expect(report.rows.map((row) => row['item_code']), ['Total Tools', 'Total']);
      expect(report.rows.first['balance_qty'], 0);
      expect(report.columns.last['label'], 'Balance Qty');
    });
  });

  group('ApiProvider.parseStockLedgerEntries', () {
    test('null / empty message → empty list', () {
      expect(ApiProvider.parseStockLedgerEntries(null), isEmpty);
      expect(
        ApiProvider.parseStockLedgerEntries(
            {'columns': <dynamic>[], 'result': <dynamic>[]}),
        isEmpty,
      );
    });

    test('positional (List) rows are normalised to ledger entries', () {
      final entries = ApiProvider.parseStockLedgerEntries({
        'columns': [
          {'fieldname': 'posting_date'},
          {'fieldname': 'voucher_type'},
          {'fieldname': 'voucher_no'},
          {'fieldname': 'actual_qty'},
          {'fieldname': 'qty_after_transaction'},
        ],
        'result': [
          ['2026-06-21', 'Purchase Receipt', 'MAT-PRE-0142', 64, 244],
          ['2026-06-21', 'Delivery Note', 'MAT-DN-0391', -24, 220],
        ],
      });
      expect(entries.length, 2);
      expect(entries.first['voucher_no'], 'MAT-PRE-0142');
      expect(entries.first['qty'], 64.0);
      expect(entries.last['qty'], -24.0);
      expect(entries.last['balance'], 220.0); // reconciles with tile balance
    });

    test('map rows are read by fieldname', () {
      final entries = ApiProvider.parseStockLedgerEntries({
        'columns': [
          {'fieldname': 'voucher_no'},
          {'fieldname': 'actual_qty'},
          {'fieldname': 'qty_after_transaction'},
        ],
        'result': [
          {
            'posting_date': '2026-06-21',
            'voucher_type': 'Stock Entry',
            'voucher_no': 'SE-0001',
            'actual_qty': '5',
            'qty_after_transaction': '17',
          },
        ],
      });
      expect(entries.single['voucher_no'], 'SE-0001');
      expect(entries.single['qty'], 5.0);
      expect(entries.single['balance'], 17.0);
    });

    test('projects positional In Qty and Out Qty without treating blanks as zero', () {
      final report = ApiProvider.parseStockLedgerReport({
        'columns': [
          for (final key in [
            'date', 'voucher_no', 'voucher_type', 'stock_uom', 'in_qty',
            'out_qty', 'qty_after_transaction',
          ])
            {'fieldname': key, 'label': key == 'date' ? 'Date' : ''},
        ],
        'result': [
          ['', '', '', 'Each', 0, 0, 180],
          ['2026-06-21', 'PRE', 'Purchase Receipt', 'Each', 64, 0, 244],
          ['2026-06-21', 'DN', 'Delivery Note', 'Each', 0, -24, 220],
          ['2026-06-21', 'EXPLICIT-ZERO', 'Stock Entry', 'Each', 0, 0, 220],
          ['2026-06-21', '', 'Stock Entry', '', null, null, null],
          ['Total', '', '', '', 64, -24, 684],
        ],
      });
      expect(report.columns.first.label, 'Date');
      expect(report.rows.map((row) => row['qty']), [64, -24, 0, null]);
      expect(report.rows.map((row) => row['balance']), [244, 220, 220, null]);
      expect(report.rows.first['stock_uom'], 'Each');
    });

    test('keeps reconciliation split even with zero raw signed movement', () {
      final report = ApiProvider.parseStockLedgerReport({
        'result': [
          {
            'name': 'SLE-0001', 'date': '2026-06-21 13:40:01',
            'voucher_no': 'SR-1', 'voucher_type': 'Stock Reconciliation',
            'actual_qty': 0, 'in_qty': 4, 'out_qty': 0,
            'qty_after_transaction': 10, 'stock_uom': 'Each',
          },
        ],
      });
      final row = report.rows.single;
      expect(row['qty'], 0);
      expect(row['in_qty'], 4);
      expect(row['name'], 'SLE-0001');
      expect(row['timestamp'], '2026-06-21 13:40:01');
    });
  });
}
