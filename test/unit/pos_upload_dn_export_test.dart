import 'package:excel/excel.dart';
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

    test('returns empty list when items is empty', () {
      final rows = PosUploadFormController.buildDnRows(
        items: [],
        itemNameByIdx: {},
        compact: true,
      );
      expect(rows, isEmpty);
    });

    test('unknown sortByColumn leaves order unchanged', () {
      final rows = PosUploadFormController.buildDnRows(
        items: [_dnItem(serial: '2'), _dnItem(serial: '1')],
        itemNameByIdx: {},
        compact: true,
        sortByColumn: 'NonExistentColumn',
      );
      expect(rows.map((r) => r.serial).toList(), [2, 1]);
    });
  });

  group('buildDeliveryNoteExcelBytes', () {
    test('writes header block, compact column headers, and a data row', () {
      final params = DeliveryNoteExcelParams(
        docName: 'DN-001',
        docDate: '2026-06-11',
        itemNameByIdx: {'1': 'POS Item'},
        // Fractional qty: the excel package decodes whole-number doubles
        // back as IntCellValue, so 2.5 keeps the round-trip type stable.
        items: [_dnItem(serial: '1', qty: 2.5, country: 'India')],
        compact: true,
      );
      final bytes = buildDeliveryNoteExcelBytes(params);
      final decoded = Excel.decodeBytes(bytes);
      final sheet = decoded['DN-001'];

      CellValue? cell(int col, int row) => sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
          .value;

      // Document header block (rows 0–2)
      expect((cell(0, 0) as TextCellValue).value.text, 'Delivery Note');
      expect((cell(0, 1) as TextCellValue).value.text, 'DN-001');
      expect((cell(0, 2) as TextCellValue).value.text, '11 Jun 2026');

      // Table headers at row 4 (compact set)
      expect((cell(0, 4) as TextCellValue).value.text, 'Invoice Serial #');
      expect((cell(1, 4) as TextCellValue).value.text, 'Item Name');
      expect((cell(2, 4) as TextCellValue).value.text, 'Qty');
      expect((cell(3, 4) as TextCellValue).value.text, 'Country of Origin');

      // Data row at row 5
      expect((cell(0, 5) as IntCellValue).value, 1);
      expect((cell(1, 5) as TextCellValue).value.text, 'POS Item');
      expect((cell(2, 5) as DoubleCellValue).value, 2.5);
      expect((cell(3, 5) as TextCellValue).value.text, 'India');
    });

    test('full mode includes Variant Of and Item Code columns', () {
      final params = DeliveryNoteExcelParams(
        docName: 'DN-002',
        docDate: '2026-06-11',
        itemNameByIdx: {},
        items: [_dnItem(serial: '1', variantOf: 'VAR', itemCode: 'CODE')],
        compact: false,
      );
      final decoded = Excel.decodeBytes(buildDeliveryNoteExcelBytes(params));
      final sheet = decoded['DN-002'];
      final headers = List.generate(
        6,
        (c) => (sheet
                .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 4))
                .value as TextCellValue)
            .value
            .text,
      );
      expect(headers, [
        'Invoice Serial #',
        'Variant Of',
        'Item Code',
        'Item Name',
        'Qty',
        'Country of Origin',
      ]);
    });

    test('sorted column moves to the first position', () {
      final params = DeliveryNoteExcelParams(
        docName: 'DN-003',
        docDate: '2026-06-11',
        itemNameByIdx: {},
        items: [_dnItem(serial: '1', qty: 1)],
        compact: true,
        sortByColumn: 'Qty',
      );
      final decoded = Excel.decodeBytes(buildDeliveryNoteExcelBytes(params));
      final sheet = decoded['DN-003'];
      final first = (sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 4))
              .value as TextCellValue)
          .value
          .text;
      expect(first, 'Qty');
    });
  });
}
