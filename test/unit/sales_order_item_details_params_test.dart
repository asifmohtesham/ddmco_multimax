import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/sales_order_provider.dart';

void main() {
  group('SalesOrderProvider.itemDetailsParams', () {
    final args = {
      'item_code': 'ITEM-0001',
      'customer': 'CUST-0001',
      'doctype': 'Sales Order',
      'qty': 2,
    };

    test('sends the payload under args (ERPNext v15)', () {
      final params = SalesOrderProvider.itemDetailsParams(args);
      expect(jsonDecode(params['args'] as String), args);
    });

    test('sends the payload under ctx (ERPNext v16)', () {
      final params = SalesOrderProvider.itemDetailsParams(args);
      expect(jsonDecode(params['ctx'] as String), args);
    });

    test('sends nothing else', () {
      expect(
        SalesOrderProvider.itemDetailsParams(args).keys,
        unorderedEquals(['args', 'ctx']),
      );
    });
  });
}
