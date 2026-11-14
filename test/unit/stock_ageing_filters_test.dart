import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

// Wire contract for the "Stock Ageing - Custom" report. The Desk applies the
// report's saved filters only while the user has not changed any filter;
// stockAgeingQuery reproduces that by omitting `are_default_filters` on a
// default run and sending `false` once the user has set filters.
void main() {
  group('ApiProvider.buildStockAgeingFilters', () {
    test('bare call sends only the required keys', () {
      expect(
        ApiProvider.buildStockAgeingFilters(
          company: 'Multimax',
          toDate: '2026-11-14',
          range: '90, 180, 360, 720',
        ),
        {
          'company': 'Multimax',
          'to_date': '2026-11-14',
          'range': '90, 180, 360, 720',
        },
      );
    });

    test('all optionals set', () {
      expect(
        ApiProvider.buildStockAgeingFilters(
          company: 'Multimax',
          toDate: '2026-11-14',
          range: '30, 60, 90',
          warehouseType: 'Transit',
          warehouse: 'Finished Goods - KA',
          itemCode: '1000030',
          brand: 'Acme',
          showWarehouseWiseStock: true,
        ),
        {
          'company': 'Multimax',
          'to_date': '2026-11-14',
          'range': '30, 60, 90',
          'warehouse_type': 'Transit',
          'warehouse': 'Finished Goods - KA',
          'item_code': '1000030',
          'brand': 'Acme',
          'show_warehouse_wise_stock': 1,
        },
      );
    });

    test('blank optionals and an off toggle are omitted', () {
      final f = ApiProvider.buildStockAgeingFilters(
        company: 'Multimax',
        toDate: '2026-11-14',
        range: '30, 60, 90',
        warehouseType: '  ',
        warehouse: '',
        itemCode: null,
        brand: '',
      );
      expect(f.keys, ['company', 'to_date', 'range']);
    });
  });

  group('ApiProvider.stockAgeingQuery', () {
    test('default run sends empty filters and no are_default_filters', () {
      final q = ApiProvider.stockAgeingQuery();
      expect(q, {
        'report_name': 'Stock Ageing - Custom',
        'filters': '{}',
        'ignore_prepared_report': 'true',
      });
      expect(q.containsKey('are_default_filters'), isFalse);
    });

    test('user-filter run sends the filters with are_default_filters=false',
        () {
      final q = ApiProvider.stockAgeingQuery(
        filters: {'company': 'Multimax', 'to_date': '2026-11-14'},
      );
      expect(q['are_default_filters'], 'false');
      expect(json.decode(q['filters'] as String),
          {'company': 'Multimax', 'to_date': '2026-11-14'});
      expect(q['report_name'], 'Stock Ageing - Custom');
    });
  });
}
