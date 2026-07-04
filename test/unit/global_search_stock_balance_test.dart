import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/global_search_service.dart';

void main() {
  group('aggregateByItem', () {
    test('sums bal_qty across warehouses per item (group warehouse case)', () {
      final rows = <Map<String, dynamic>>[
        {'item_code': 'FG-1', 'item_name': 'Blue Strap', 'bal_qty': 12, 'stock_uom': 'Nos', 'warehouse': 'Stores A'},
        {'item_code': 'FG-1', 'bal_qty': 8, 'warehouse': 'Stores B'},
        {'item_code': 'FG-2', 'balance_qty': '3.5', 'stock_uom': 'Mtr'},
        {'item_code': '', 'bal_qty': 99},
      ];
      final map = GlobalSearchService.aggregateByItem(rows);
      expect(map.length, 2);
      expect(map['FG-1']!.balanceQty, 20); // 12 + 8 across two warehouses
      expect(map['FG-1']!.itemName, 'Blue Strap'); // first row carrying it
      expect(map['FG-1']!.uom, 'Nos');
      expect(map['FG-2']!.balanceQty, 3.5); // legacy balance_qty, string-parsed
      expect(map['FG-2']!.itemName, ''); // no name present
      expect(map.containsKey(''), isFalse); // blank code skipped
    });

    test('empty rows -> empty map', () {
      expect(GlobalSearchService.aggregateByItem(const []), isEmpty);
    });

    test('uom/name taken from the first row that carries a value', () {
      final rows = <Map<String, dynamic>>[
        {'item_code': 'X', 'bal_qty': 1}, // no uom, no name
        {'item_code': 'X', 'bal_qty': 2, 'stock_uom': 'Kg', 'item_name': 'Widget'},
      ];
      final map = GlobalSearchService.aggregateByItem(rows);
      expect(map['X']!.balanceQty, 3);
      expect(map['X']!.uom, 'Kg');
      expect(map['X']!.itemName, 'Widget');
    });
  });
}
