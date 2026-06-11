import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/modules/pos_upload/form/pos_upload_form_controller.dart';

DeliveryNoteItem _dnItem({
  String? serial,
  String itemCode = 'ITEM-001',
  String? itemName = 'DN Item',
  double qty = 1,
  String? variantOf,
  String? country,
}) =>
    DeliveryNoteItem(
      itemCode: itemCode,
      qty: qty,
      rate: 0,
      itemName: itemName,
      customInvoiceSerialNumber: serial,
      customVariantOf: variantOf,
      countryOfOrigin: country,
    );

void main() {
  group('PosUploadFormController.buildDnRows', () {
    test('maps DN item fields; item name resolves from POS upload by serial',
        () {
      final rows = PosUploadFormController.buildDnRows(
        items: [_dnItem(serial: '3', variantOf: 'VAR-1', country: 'India')],
        itemNameByIdx: {'3': 'POS Item Name'},
        compact: false,
      );
      expect(rows, hasLength(1));
      expect(rows.first.serial, 3);
      expect(rows.first.itemName, 'POS Item Name');
      expect(rows.first.variantOf, 'VAR-1');
      expect(rows.first.itemCode, 'ITEM-001');
      expect(rows.first.country, 'India');
      expect(rows.first.qty, 1);
    });

    test('falls back to DN item name when serial not in POS upload map', () {
      final rows = PosUploadFormController.buildDnRows(
        items: [_dnItem(serial: '9', itemName: 'DN Only Name')],
        itemNameByIdx: {'3': 'POS Item Name'},
        compact: true,
      );
      expect(rows.single.itemName, 'DN Only Name');
    });

    test('falls back to item code when DN item name is also null', () {
      final rows = PosUploadFormController.buildDnRows(
        items: [_dnItem(serial: '9', itemName: null, itemCode: 'ITEM-X')],
        itemNameByIdx: {},
        compact: true,
      );
      expect(rows.single.itemName, 'ITEM-X');
    });

    test('missing serial parses to 0', () {
      final rows = PosUploadFormController.buildDnRows(
        items: [_dnItem(serial: null)],
        itemNameByIdx: {},
        compact: true,
      );
      expect(rows.single.serial, 0);
    });

    test('aggregates qty for rows with an identical key', () {
      final rows = PosUploadFormController.buildDnRows(
        items: [
          _dnItem(serial: '1', qty: 2, country: 'India'),
          _dnItem(serial: '1', qty: 3, country: 'India'),
        ],
        itemNameByIdx: {'1': 'POS Item'},
        compact: false,
      );
      expect(rows, hasLength(1));
      expect(rows.single.qty, 5);
    });

    test('compact mode merges rows differing only by code/variant', () {
      final rows = PosUploadFormController.buildDnRows(
        items: [
          _dnItem(serial: '1', qty: 2, itemCode: 'A', variantOf: 'VA'),
          _dnItem(serial: '1', qty: 3, itemCode: 'B', variantOf: 'VB'),
        ],
        itemNameByIdx: {'1': 'POS Item'},
        compact: true,
      );
      expect(rows, hasLength(1));
      expect(rows.single.qty, 5);
    });

    test('full mode keeps rows with different item codes separate', () {
      final rows = PosUploadFormController.buildDnRows(
        items: [
          _dnItem(serial: '1', qty: 2, itemCode: 'A'),
          _dnItem(serial: '1', qty: 3, itemCode: 'B'),
        ],
        itemNameByIdx: {'1': 'POS Item'},
        compact: false,
      );
      expect(rows, hasLength(2));
    });

    test('sorts by Qty ascending when sortByColumn is Qty', () {
      final rows = PosUploadFormController.buildDnRows(
        items: [
          _dnItem(serial: '1', qty: 5),
          _dnItem(serial: '2', qty: 1),
        ],
        itemNameByIdx: {'1': 'Item A', '2': 'Item B'},
        compact: true,
        sortByColumn: 'Qty',
      );
      expect(rows.map((r) => r.qty).toList(), [1, 5]);
    });

    test('sorts by Invoice Serial #', () {
      final rows = PosUploadFormController.buildDnRows(
        items: [
          _dnItem(serial: '7', itemName: 'B'),
          _dnItem(serial: '2', itemName: 'A'),
        ],
        itemNameByIdx: {},
        compact: true,
        sortByColumn: 'Invoice Serial #',
      );
      expect(rows.map((r) => r.serial).toList(), [2, 7]);
    });
  });
}
