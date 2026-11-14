import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

void main() {
  group('buildPosDnItemRateFilters', () {
    test('empty inputs produce an empty map (report defaults apply)', () {
      expect(ApiProvider.buildPosDnItemRateFilters(), isEmpty);
    });

    test('multi-select filters pass through as lists', () {
      final f = ApiProvider.buildPosDnItemRateFilters(
        posUploads: ['KA-2025-61960', 'KA-2025-61961'],
        customers: ['MULTI BRAND TRADING'],
        customerGroups: ['Commercial'],
        itemGroups: ['Straps'],
      );
      expect(f['pos_upload'], ['KA-2025-61960', 'KA-2025-61961']);
      expect(f['customer'], ['MULTI BRAND TRADING']);
      expect(f['customer_group'], ['Commercial']);
      expect(f['item_group'], ['Straps']);
    });

    test('dates pass through trimmed; blank dates are omitted', () {
      final f = ApiProvider.buildPosDnItemRateFilters(
        fromDate: '2026-06-03',
        toDate: '  ',
      );
      expect(f['from_date'], '2026-06-03');
      expect(f.containsKey('to_date'), isFalse);
    });

    test('checkboxes encode as 1 only when on', () {
      expect(ApiProvider.buildPosDnItemRateFilters()['show_mapped'], isNull);
      final f = ApiProvider.buildPosDnItemRateFilters(
          showMapped: true, onlyCoded: true);
      expect(f['show_mapped'], 1);
      expect(f['only_coded'], 1);
    });
  });
}
