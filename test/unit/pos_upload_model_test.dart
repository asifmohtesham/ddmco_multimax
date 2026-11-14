import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';

void main() {
  group('PosUploadItem.fromJson', () {
    test('parses ref_code alongside the existing fields', () {
      final item = PosUploadItem.fromJson({
        'idx': 3,
        'ref_code': 'CUST-REF-9',
        'item_name': 'Strap 20mm',
        'qty': 4,
        'rate': 1.5,
        'amount': 6.0,
      });
      expect(item.idx, 3);
      expect(item.refCode, 'CUST-REF-9');
      expect(item.itemName, 'Strap 20mm');
      expect(item.quantity, 4);
    });

    test('parses uom, the unit the rate is quoted in', () {
      final item = PosUploadItem.fromJson({
        'idx': 1,
        'item_name': 'WALLETS GOAT HQ',
        'rate': 220,
        'uom': 'Doz',
        'quantity': 120,
        'amount': 2200,
      });
      expect(item.uom, 'Doz');
    });

    test('missing or null uom defaults to empty string', () {
      expect(PosUploadItem.fromJson({'idx': 1, 'item_name': 'X'}).uom, '');
      expect(
        PosUploadItem.fromJson({'idx': 1, 'item_name': 'X', 'uom': null}).uom,
        '',
      );
    });

    test('missing ref_code defaults to empty string', () {
      final item = PosUploadItem.fromJson({'idx': 1, 'item_name': 'X'});
      expect(item.refCode, '');
    });
  });
}
