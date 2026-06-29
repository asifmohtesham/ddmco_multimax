import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

void main() {
  group('ApiProvider.buildBomStockFilters', () {
    test('omits every filter when all are empty/false', () {
      expect(ApiProvider.buildBomStockFilters(), isEmpty);
    });

    test('includes trimmed customer when set', () {
      final f = ApiProvider.buildBomStockFilters(customer: '  Acme  ');
      expect(f['customer'], 'Acme');
    });

    test('passes customer codes and warehouses through as lists', () {
      final f = ApiProvider.buildBomStockFilters(
        customerCodes: ['5067101', '5067102'],
        warehouses: ['Stores - M'],
      );
      expect(f['customer_code'], ['5067101', '5067102']);
      expect(f['warehouse'], ['Stores - M']);
    });

    test('omits empty code/warehouse lists', () {
      final f = ApiProvider.buildBomStockFilters(
        customerCodes: const [],
        warehouses: const [],
      );
      expect(f.containsKey('customer_code'), isFalse);
      expect(f.containsKey('warehouse'), isFalse);
    });

    test('encodes checkboxes as 1 only when true, omits when false', () {
      final on = ApiProvider.buildBomStockFilters(
        showExplodedView: true,
        hideOutOfStock: true,
      );
      expect(on['show_exploded_view'], 1);
      expect(on['hide_out_of_stock'], 1);

      final off = ApiProvider.buildBomStockFilters();
      expect(off.containsKey('show_exploded_view'), isFalse);
      expect(off.containsKey('hide_out_of_stock'), isFalse);
    });

    test('includes trimmed pos_upload when set', () {
      final f = ApiProvider.buildBomStockFilters(posUpload: ' ML-2026-02011 ');
      expect(f['pos_upload'], 'ML-2026-02011');
    });
  });
}
