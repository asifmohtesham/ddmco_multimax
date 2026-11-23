import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';

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

    test('T-2: returns empty record when result list is empty', () {
      final result = ApiProvider.parseStockBalanceResponse({
        'columns': [{'fieldname': 'item_code', 'label': 'Item Code'}],
        'result': <dynamic>[],
      });
      expect(result.columns, isEmpty);
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
  });
}
