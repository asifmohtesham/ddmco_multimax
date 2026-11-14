# POS Upload Unified DN/PS Export Sheet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the POS Upload form's Packing-Slip-only export sheet with a unified bottom sheet that exports either the linked Delivery Note or the Packing Slips as Excel.

**Architecture:** The controller retains the already-fetched `DeliveryNote` in an `Rxn`, gains a public static row builder (`buildDnRows`, unit-testable) plus a public top-level isolate function (`buildDeliveryNoteExcelBytes`) mirroring the existing private PS pipeline, and a `buildDeliveryNoteExcel` method parallel to `buildPackingSlipExcel`. The screen's `_showShareSheet` is rewritten around a `SegmentedButton<ExportDocType>`.

**Tech Stack:** Flutter/GetX, `excel` package, `compute()` isolates, `share_plus`. Spec: `docs/superpowers/specs/2026-06-11-pos-upload-export-doc-picker-design.md`.

**Verify commands:**
- `flutter test test/unit/pos_upload_dn_export_test.dart` (new tests)
- `flutter test` (full suite)
- `flutter analyze`

---

### Task 1: DN row builder (`buildDnRows`) — TDD

The pure aggregation/sort logic for the Delivery Note export, as a public static on `PosUploadFormController` so tests can call it (same pattern as `psCaseCell` / `matchPsItems` in `test/unit/pos_upload_ps_case_test.dart`).

**Files:**
- Test: `test/unit/pos_upload_dn_export_test.dart` (create)
- Modify: `lib/app/modules/pos_upload/form/pos_upload_form_controller.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/unit/pos_upload_dn_export_test.dart`:

```dart
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/unit/pos_upload_dn_export_test.dart`
Expected: FAIL — compile error, `buildDnRows` / `DnRow` not defined.

- [ ] **Step 3: Implement `DnRow` typedef + `buildDnRows` + comparator**

In `lib/app/modules/pos_upload/form/pos_upload_form_controller.dart`, add below the `_PSCol` typedef (after line 91):

```dart
/// Public record for a single Delivery Note export row.
/// Public (unlike _PSRow) so unit tests can call buildDnRows directly.
typedef DnRow = ({
  int serial,
  String variantOf,
  String itemCode,
  String itemName,
  double qty,
  String country,
});
```

(The companion `_DnCol` column typedef is added in Task 3, where it is first used.)

Inside `PosUploadFormController` (e.g. after `_rowComparator`, line 380), add:

```dart
  /// Builds the aggregated, optionally sorted row set for the DN Excel export.
  /// Mirrors the PS export semantics: rows whose displayed text columns are
  /// identical aggregate their qty; item names resolve from the POS Upload
  /// items by invoice serial, falling back to the DN item's own name/code.
  static List<DnRow> buildDnRows({
    required List<DeliveryNoteItem> items,
    required Map<String, String> itemNameByIdx,
    required bool compact,
    String? sortByColumn,
  }) {
    final rowMap = <String, DnRow>{};
    for (final dnItem in items) {
      final serialStr = dnItem.customInvoiceSerialNumber ?? '';
      final itemName =
          itemNameByIdx[serialStr] ?? dnItem.itemName ?? dnItem.itemCode;
      final serial    = int.tryParse(serialStr) ?? 0;
      final variantOf = dnItem.customVariantOf ?? '';
      final itemCode  = dnItem.itemCode;
      final country   = dnItem.countryOfOrigin ?? '';

      final key = compact
          ? '$serial\x00$itemName\x00$country'
          : '$serial\x00$variantOf\x00$itemCode\x00$itemName\x00$country';

      final existing = rowMap[key];
      rowMap[key] = existing == null
          ? (
              serial:    serial,
              variantOf: variantOf,
              itemCode:  itemCode,
              itemName:  itemName,
              qty:       dnItem.qty,
              country:   country,
            )
          : (
              serial:    existing.serial,
              variantOf: existing.variantOf,
              itemCode:  existing.itemCode,
              itemName:  existing.itemName,
              qty:       existing.qty + dnItem.qty,
              country:   existing.country,
            );
    }

    final rows = rowMap.values.toList();
    if (sortByColumn != null) {
      rows.sort((a, b) => _dnRowComparator(sortByColumn, a, b));
    }
    return rows;
  }

  static int _dnRowComparator(String col, DnRow a, DnRow b) {
    switch (col) {
      case 'Invoice Serial #':
        return a.serial.compareTo(b.serial);
      case 'Qty':
        return a.qty.compareTo(b.qty);
      case 'Item Name':
        return a.itemName.toLowerCase().compareTo(b.itemName.toLowerCase());
      case 'Variant Of':
        return a.variantOf.toLowerCase().compareTo(b.variantOf.toLowerCase());
      case 'Item Code':
        return a.itemCode.toLowerCase().compareTo(b.itemCode.toLowerCase());
      case 'Country of Origin':
        return a.country.toLowerCase().compareTo(b.country.toLowerCase());
      default:
        return 0;
    }
  }
```

Note: `DeliveryNoteItem` is already imported in this file via `delivery_note_model.dart` (line 11).

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/unit/pos_upload_dn_export_test.dart`
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add test/unit/pos_upload_dn_export_test.dart lib/app/modules/pos_upload/form/pos_upload_form_controller.dart
git commit -m "feat(pos-upload): add DN export row builder with aggregation and sort"
```

---

### Task 2: Parameterise the Excel table name

`_injectExcelTable` hardcodes `PackingSlipTable`; the DN export needs `DeliveryNoteTable`.

**Files:**
- Modify: `lib/app/modules/pos_upload/form/pos_upload_form_controller.dart:725-752`

- [ ] **Step 1: Add the `tableName` parameter**

Change the signature of `_injectExcelTable` (line 725):

```dart
  static List<int> _injectExcelTable(
    List<int> xlsxBytes,
    List<String> columnNames,
    int dataRowCount, {
    int tableStartRow = 0,
    String tableName = 'PackingSlipTable',
  }) {
```

And in `tableXml` (line 744), replace the hardcoded name:

```dart
    final tableXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<table xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
        ' id="1" name="$tableName" displayName="$tableName"'
        ' ref="$ref" totalsRowShown="0">'
        '<autoFilter ref="$ref"/>'
        '<tableColumns count="$colCount">$colsBuffer</tableColumns>'
        '<tableStyleInfo name="TableStyleMedium9" showFirstColumn="0"'
        ' showLastColumn="0" showRowStripes="1" showColumnStripes="0"/>'
        '</table>';
```

The existing PS call site in `_buildPackingSlipExcel` (line 244) needs no change — the default preserves its behaviour.

- [ ] **Step 2: Verify nothing broke**

Run: `flutter analyze && flutter test`
Expected: analyze clean (no new issues); all existing tests PASS.

- [ ] **Step 3: Commit**

```bash
git add lib/app/modules/pos_upload/form/pos_upload_form_controller.dart
git commit -m "refactor(pos-upload): parameterise injected Excel table name"
```

---

### Task 3: DN Excel pipeline — isolate function, controller state, builder method

**Files:**
- Modify: `lib/app/modules/pos_upload/form/pos_upload_form_controller.dart`
- Test: `test/unit/pos_upload_dn_export_test.dart` (extend)

- [ ] **Step 1: Write the failing test for the xlsx bytes**

Append to `test/unit/pos_upload_dn_export_test.dart` (add `import 'package:excel/excel.dart';` at the top):

```dart
  group('buildDeliveryNoteExcelBytes', () {
    test('writes header block, compact column headers, and a data row', () {
      final params = DeliveryNoteExcelParams(
        docName: 'DN-001',
        docDate: '2026-06-11',
        itemNameByIdx: {'1': 'POS Item'},
        items: [_dnItem(serial: '1', qty: 2, country: 'India')],
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
      expect((cell(2, 5) as DoubleCellValue).value, 2);
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
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/unit/pos_upload_dn_export_test.dart`
Expected: FAIL — `DeliveryNoteExcelParams` / `buildDeliveryNoteExcelBytes` not defined.

- [ ] **Step 3: Implement params class + isolate function**

In `pos_upload_form_controller.dart`, add the `_DnCol` typedef from Task 1's note (below `DnRow`):

```dart
typedef _DnCol = (String, CellValue Function(DnRow));
```

Then, below the existing `_buildPackingSlipExcel` top-level function (after line 250), add:

```dart
/// Params for the DN export isolate. Public (with the function below) so
/// unit tests can exercise the full xlsx pipeline; compute() also requires
/// a top-level or static function.
class DeliveryNoteExcelParams {
  final String docName;
  final String docDate;
  final Map<String, String> itemNameByIdx;
  final List<DeliveryNoteItem> items;
  final bool compact;
  final String? sortByColumn;

  const DeliveryNoteExcelParams({
    required this.docName,
    required this.docDate,
    required this.itemNameByIdx,
    required this.items,
    required this.compact,
    this.sortByColumn,
  });
}

// Top-level function — required by compute(). Runs in a background isolate.
// Mirrors _buildPackingSlipExcel: Consolas font, autofit, Excel Table injected.
List<int> buildDeliveryNoteExcelBytes(DeliveryNoteExcelParams p) {
  final safeName = p.docName.replaceAll('/', '_');
  final excelFile = Excel.createExcel();
  excelFile.rename('Sheet1', safeName);
  final sheet = excelFile[safeName];

  var columns = p.compact
      ? <_DnCol>[
          ('Invoice Serial #',  (r) => IntCellValue(r.serial)),
          ('Item Name',         (r) => TextCellValue(r.itemName)),
          ('Qty',               (r) => DoubleCellValue(r.qty)),
          ('Country of Origin', (r) => TextCellValue(r.country)),
        ]
      : <_DnCol>[
          ('Invoice Serial #',  (r) => IntCellValue(r.serial)),
          ('Variant Of',        (r) => TextCellValue(r.variantOf)),
          ('Item Code',         (r) => TextCellValue(r.itemCode)),
          ('Item Name',         (r) => TextCellValue(r.itemName)),
          ('Qty',               (r) => DoubleCellValue(r.qty)),
          ('Country of Origin', (r) => TextCellValue(r.country)),
        ];

  final sortedRows = PosUploadFormController.buildDnRows(
    items: p.items,
    itemNameByIdx: p.itemNameByIdx,
    compact: p.compact,
    sortByColumn: p.sortByColumn,
  );

  // Move the sorted column to the front, matching the PS export behaviour.
  if (p.sortByColumn != null) {
    final sortIdx = columns.indexWhere((c) => c.$1 == p.sortByColumn);
    if (sortIdx > 0) {
      final col = columns.removeAt(sortIdx);
      columns.insert(0, col);
    }
  }

  // ── Document header (rows 0–3, row 3 is blank) ───────────────────────
  const tableStartRow = 4;

  CellIndex idx(int c, int r) =>
      CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r);

  sheet.cell(idx(0, 0))
    ..value = TextCellValue('Delivery Note')
    ..cellStyle = CellStyle(fontFamily: 'Consolas', fontSize: 20, bold: true);

  sheet.cell(idx(0, 1))
    ..value = TextCellValue(p.docName)
    ..cellStyle = CellStyle(fontFamily: 'Consolas', fontSize: 13);

  String formattedDate;
  try {
    formattedDate =
        DateFormat('dd MMM yyyy').format(DateTime.parse(p.docDate));
  } catch (_) {
    formattedDate = p.docDate;
  }
  sheet.cell(idx(0, 2))
    ..value = TextCellValue(formattedDate)
    ..cellStyle = CellStyle(fontFamily: 'Consolas', fontSize: 11);

  // ── Table column headers ──────────────────────────────────────────────
  final bodyStyle = CellStyle(fontFamily: 'Consolas', fontSize: 11);

  for (int c = 0; c < columns.length; c++) {
    sheet.cell(idx(c, tableStartRow))
      ..value = TextCellValue(columns[c].$1)
      ..cellStyle = bodyStyle;
  }

  // ── Data rows ─────────────────────────────────────────────────────────
  int row = tableStartRow + 1;
  for (final r in sortedRows) {
    for (int c = 0; c < columns.length; c++) {
      sheet.cell(idx(c, row))
        ..value = columns[c].$2(r)
        ..cellStyle = bodyStyle;
    }
    row++;
  }

  // ── Autofit ───────────────────────────────────────────────────────────
  for (int c = 0; c < columns.length; c++) {
    sheet.setColumnAutoFit(c);
  }

  final rawBytes = excelFile.encode()!;
  return PosUploadFormController._injectExcelTable(
    rawBytes,
    columns.map((col) => col.$1).toList(),
    sortedRows.length,
    tableStartRow: tableStartRow,
    tableName: 'DeliveryNoteTable',
  );
}
```

- [ ] **Step 4: Add controller state + `buildDeliveryNoteExcel`**

In `PosUploadFormController`:

(a) Below the `linkedDocName` / `isLoadingLinked` declarations (line 288), add:

```dart
  /// The full linked Delivery Note, retained for the DN Excel export.
  final deliveryNote = Rxn<DeliveryNote>();
```

(b) In `_fetchDeliveryNote`, after `final dn = DeliveryNote.fromJson(detailResp.data['data']);` (line 447), add:

```dart
          deliveryNote.value = dn;
```

(c) Still in `_fetchDeliveryNote`, clear the DN in both failure paths. In the `else` branch (after `linkedDocType.value = LinkedDocType.none;`, line 471) and in the `catch (_)` branch (after `linkedDocType.value = LinkedDocType.none;`, line 475), add:

```dart
        deliveryNote.value = null;
```

(d) Below `buildPackingSlipExcel` (after line 719), add:

```dart
  // Builds the DN xlsx and writes it to the temp directory.
  // Returns the file path on success; throws on failure.
  // The caller is responsible for opening the share sheet and handling errors.
  Future<String> buildDeliveryNoteExcel({
    required bool compact,
    String? sortByColumn,
  }) async {
    final upload = posUpload.value;
    final dn = deliveryNote.value;
    if (upload == null || dn == null) {
      throw Exception('No delivery note data available');
    }

    final params = DeliveryNoteExcelParams(
      docName: dn.name,
      docDate: dn.postingDate,
      itemNameByIdx: {
        for (final item in upload.items) item.idx.toString(): item.itemName,
      },
      items: dn.items,
      compact: compact,
      sortByColumn: sortByColumn,
    );

    // Runs in a background isolate — caller's UI stays responsive.
    final fileBytes = await compute(buildDeliveryNoteExcelBytes, params);

    final timestamp = DateFormat('yyyyMMdd HHmmss').format(DateTime.now());
    final safeName  = upload.name.replaceAll('/', '_');
    final fileName  = 'POS Upload - $safeName - Delivery Note - $timestamp';
    final tempDir   = await getTemporaryDirectory();
    final filePath  = '${tempDir.path}/$fileName.xlsx';
    await File(filePath).writeAsBytes(Uint8List.fromList(fileBytes));

    return filePath;
  }
```

(e) Per the spec, the PS filename also gains its doc-type label. In `buildPackingSlipExcel` (line 713), change:

```dart
    final fileName  = 'POS Upload - $safeName - Packing Slip - $timestamp';
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/unit/pos_upload_dn_export_test.dart && flutter analyze`
Expected: all tests PASS; analyze clean.

(If `Excel.decodeBytes` fails on the table-injected bytes — it shouldn't, the output is valid xlsx — that is a real bug to debug with superpowers:systematic-debugging, not a reason to delete the test.)

- [ ] **Step 6: Commit**

```bash
git add test/unit/pos_upload_dn_export_test.dart lib/app/modules/pos_upload/form/pos_upload_form_controller.dart
git commit -m "feat(pos-upload): DN Excel export pipeline (isolate builder + controller method)"
```

---

### Task 4: Unified export bottom sheet UI

Rewrite `_showShareSheet` around a `SegmentedButton<ExportDocType>` and widen the share-icon enablement.

**Files:**
- Modify: `lib/app/modules/pos_upload/form/pos_upload_form_controller.dart` (enum)
- Modify: `lib/app/modules/pos_upload/form/pos_upload_form_screen.dart:24,35,75-189`

- [ ] **Step 1: Add the `ExportDocType` enum**

In `pos_upload_form_controller.dart`, next to `enum LinkedDocType` (line 21):

```dart
enum ExportDocType { deliveryNote, packingSlip }
```

- [ ] **Step 2: Widen the share-icon enablement**

In `pos_upload_form_screen.dart`, replace line 24:

```dart
      final hasPackingSlips = controller.packingSlips.isNotEmpty;
```

with:

```dart
      final canShare = controller.deliveryNote.value != null ||
          controller.packingSlips.isNotEmpty;
```

and line 35:

```dart
                onShare: hasPackingSlips ? () => _showShareSheet(context) : null,
```

with:

```dart
                onShare: canShare ? () => _showShareSheet(context) : null,
```

(The outer `Obx` already wraps this, so both observables are reactive. MX/KX uploads never set `deliveryNote` or `packingSlips`, so their icon stays disabled — unchanged.)

- [ ] **Step 3: Replace `_columnNames` and `_showShareSheet`**

Replace lines 75–189 of `pos_upload_form_screen.dart` (the `_columnNames` helper and the whole `_showShareSheet` method) with:

```dart
  // Must match the column names in the controller's export builders
  // (_buildPackingSlipExcel / buildDeliveryNoteExcelBytes).
  static List<String> _columnNames(ExportDocType docType, bool compact) {
    final base = compact
        ? ['Invoice Serial #', 'Item Name', 'Qty', 'Country of Origin']
        : [
            'Invoice Serial #',
            'Variant Of',
            'Item Code',
            'Item Name',
            'Qty',
            'Country of Origin',
          ];
    return docType == ExportDocType.packingSlip ? ['Case #', ...base] : base;
  }

  static const _shortLabels = {
    'Case #': 'Case',
    'Invoice Serial #': 'Serial',
    'Variant Of': 'Variant',
    'Item Code': 'Code',
    'Item Name': 'Item',
    'Qty': 'Qty',
    'Country of Origin': 'Country',
  };

  void _showShareSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final hasDn = controller.deliveryNote.value != null;
        final hasPs = controller.packingSlips.isNotEmpty;
        // Default to the most-used export when available.
        var docType =
            hasPs ? ExportDocType.packingSlip : ExportDocType.deliveryNote;
        var compact = true;
        String? sortByColumn;
        var isExporting = false;
        return StatefulBuilder(
          builder: (ctx, setState) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Export as Excel',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<ExportDocType>(
                    segments: [
                      ButtonSegment(
                        value: ExportDocType.deliveryNote,
                        icon: const Icon(Icons.local_shipping_outlined),
                        label: const Text('Delivery Note'),
                        enabled: hasDn,
                      ),
                      ButtonSegment(
                        value: ExportDocType.packingSlip,
                        icon: const Icon(Icons.inventory_outlined),
                        label: const Text('Packing Slip'),
                        enabled: hasPs,
                      ),
                    ],
                    selected: {docType},
                    onSelectionChanged: isExporting
                        ? null
                        : (selection) => setState(() {
                              docType = selection.first;
                              // Reset sort only if the column doesn't exist
                              // for the new doc type (Case # is PS-only).
                              if (sortByColumn != null &&
                                  !_columnNames(docType, compact)
                                      .contains(sortByColumn)) {
                                sortByColumn = null;
                              }
                            }),
                  ),
                  if (!hasPs || !hasDn) ...[
                    const SizedBox(height: 6),
                    Text(
                      !hasPs
                          ? 'No packing slips yet'
                          : 'Delivery note not available',
                      style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Compact'),
                    subtitle: Text(
                      _columnNames(docType, compact)
                          .map((c) => _shortLabels[c]!)
                          .join(' · '),
                    ),
                    value: compact,
                    onChanged: isExporting
                        ? null
                        : (v) => setState(() {
                              compact = v;
                              sortByColumn = null;
                            }),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    // ignore: deprecated_member_use
                    value: sortByColumn,
                    decoration: const InputDecoration(
                      labelText: 'Sort by',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('None (natural order)'),
                      ),
                      ..._columnNames(docType, compact).map(
                        (name) =>
                            DropdownMenuItem(value: name, child: Text(name)),
                      ),
                    ],
                    onChanged: isExporting
                        ? null
                        : (v) => setState(() => sortByColumn = v),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: isExporting
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(ctx).colorScheme.onPrimary,
                            ),
                          )
                        : const Icon(Icons.table_view_outlined),
                    label: Text(isExporting ? 'Exporting…' : 'Share as Excel'),
                    onPressed: isExporting
                        ? () {}
                        : () async {
                            setState(() => isExporting = true);
                            final docLabel =
                                docType == ExportDocType.packingSlip
                                    ? 'Packing Slip'
                                    : 'Delivery Note';
                            try {
                              final filePath =
                                  docType == ExportDocType.packingSlip
                                      ? await controller.buildPackingSlipExcel(
                                          compact: compact,
                                          sortByColumn: sortByColumn,
                                        )
                                      : await controller.buildDeliveryNoteExcel(
                                          compact: compact,
                                          sortByColumn: sortByColumn,
                                        );
                              if (ctx.mounted) Navigator.of(ctx).pop();
                              await Share.shareXFiles(
                                [
                                  XFile(
                                    filePath,
                                    mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                                  ),
                                ],
                                subject:
                                    '${controller.posUpload.value?.name} – $docLabel',
                              );
                            } catch (e) {
                              if (ctx.mounted) {
                                setState(() => isExporting = false);
                              }
                              GlobalSnackbar.error(
                                  message: 'Export failed: $e');
                            }
                          },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
```

- [ ] **Step 4: Verify**

Run: `flutter analyze && flutter test`
Expected: analyze clean; full suite PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/pos_upload/form/pos_upload_form_screen.dart lib/app/modules/pos_upload/form/pos_upload_form_controller.dart
git commit -m "feat(pos-upload): unified DN/PS export bottom sheet with segmented picker"
```

---

### Task 5: Final verification + device smoke checklist

- [ ] **Step 1: Full suite + analyze**

Run: `flutter analyze && flutter test`
Expected: clean / all PASS.

- [ ] **Step 2: Device smoke test (manual, ML/KA POS Upload)**

On a connected device (`flutter run -d <device_id>`):

1. Open an ML/KA POS Upload **with** packing slips → Share icon enabled → sheet opens with **Packing Slip preselected**; PS export works as before (file name now includes "Packing Slip").
2. Switch segment to Delivery Note → options stay; if sort was "Case #", it resets to "None (natural order)"; export produces a DN xlsx whose header reads "Delivery Note" + DN name + posting date, table name `DeliveryNoteTable`.
3. Open an ML/KA POS Upload **without** packing slips → Share icon enabled once the DN banner appears → sheet opens with **Delivery Note preselected**, PS segment disabled with "No packing slips yet" helper.
4. Open an MX/KX (Stock Entry) POS Upload → Share icon disabled.
5. Verify both exported files open in Excel/Sheets with the structured table styling intact.

- [ ] **Step 3: Commit any remaining changes and report results**

Report the smoke-test outcomes; the feature ships per the team's usual release-branch flow.
