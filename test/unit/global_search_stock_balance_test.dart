import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/global_search_item.dart';
import 'package:multimax/app/data/services/global_search_service.dart';

void main() {
  group('mapStockLines', () {
    test('maps bal_qty, name, uom; parses legacy/string; skips blank codes', () {
      final rows = <Map<String, dynamic>>[
        {'item_code': 'FG-1', 'item_name': 'Blue Strap', 'bal_qty': 12, 'stock_uom': 'Nos'},
        {'item_code': '', 'item_name': 'ghost', 'bal_qty': 5},
        {'item_code': 'FG-2', 'balance_qty': '3.5', 'stock_uom': 'Mtr'},
      ];
      final lines = GlobalSearchService.mapStockLines(rows);
      expect(lines.length, 2);
      expect(lines[0].itemCode, 'FG-1');
      expect(lines[0].itemName, 'Blue Strap');
      expect(lines[0].balanceQty, 12);
      expect(lines[0].uom, 'Nos');
      expect(lines[1].itemCode, 'FG-2');
      expect(lines[1].balanceQty, 3.5); // legacy balance_qty, string-parsed
      expect(lines[1].itemName, '');
    });

    test('empty rows -> empty lines', () {
      expect(GlobalSearchService.mapStockLines(const []), isEmpty);
    });
  });

  group('itemCodesFrom', () {
    test('drops blanks and caps at kGroupCap', () {
      final items = <GlobalSearchItem>[
        for (var i = 0; i < 12; i++)
          GlobalSearchItem(id: 'C$i', title: 'C$i', rawData: const {}),
        GlobalSearchItem(id: '', title: 'blank', rawData: const {}),
      ];
      final codes = GlobalSearchService.itemCodesFrom(items);
      expect(codes.length, GlobalSearchService.kGroupCap);
      expect(codes.contains(''), isFalse);
    });
  });
}
