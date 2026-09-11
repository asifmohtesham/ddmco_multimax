// test/unit/se_invoice_serial_required_test.dart
//
// Invoice Serial Number is mandatory ONLY for a POS Upload-sourced
// Material Issue. Everywhere else a blank serial is fine (saved as 0).
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/mr_item_row.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_item_form_controller.dart';

void main() {
  bool ok(StockEntrySource src, String type, String? serial) =>
      StockEntryItemFormController.isInvoiceSerialSatisfied(
          source: src, stockEntryType: type, serial: serial);

  group('isInvoiceSerialSatisfied', () {
    test('POS Upload Material Issue with no serial is blocked', () {
      expect(ok(StockEntrySource.posUpload, 'Material Issue', null), isFalse);
      expect(ok(StockEntrySource.posUpload, 'Material Issue', ''), isFalse);
      expect(ok(StockEntrySource.posUpload, 'Material Issue', '0'), isFalse);
    });

    test('POS Upload Material Issue with a serial passes', () {
      expect(ok(StockEntrySource.posUpload, 'Material Issue', '4'), isTrue);
    });

    test('every other source/type ignores the serial', () {
      for (final src in StockEntrySource.values) {
        if (src == StockEntrySource.posUpload) continue;
        expect(ok(src, 'Material Issue', null), isTrue, reason: '$src');
      }
      expect(ok(StockEntrySource.posUpload, 'Material Transfer', null), isTrue);
    });
  });
}
