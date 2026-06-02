# POS Upload – Packing Slip Excel Sort By Column Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Sort by" dropdown to the packing slip export sheet; the selected column sorts rows ascending and moves to Column A in the generated Excel file.

**Architecture:** Two file-level typedefs (`_PSRow`, `_PSCol`) are added before the controller class to give the anonymous row record a stable name used by a new `_rowComparator` static method. `sharePackingSlipExcel` gains a `sortByColumn: String?` parameter and replaces the hardcoded header/write blocks with a column-list pattern that supports reordering. The screen's `_showShareSheet` gains `sortByColumn` state and a `DropdownButtonFormField<String?>`.

**Tech Stack:** Dart 3 record typedefs, existing `excel ^4.0.6`, `share_plus`, Flutter Material widgets.

---

## File Map

| File | Change |
|------|--------|
| `lib/app/modules/pos_upload/form/pos_upload_form_controller.dart` | Add `_PSRow`/`_PSCol` typedefs, `_rowComparator` static method, refactor `sharePackingSlipExcel` |
| `lib/app/modules/pos_upload/form/pos_upload_form_screen.dart` | Add `_columnNames` helper, update `_showShareSheet` with sort state + dropdown |

No new test files — sort logic is integration-only (depends on `CellValue` types from `excel` package; private types cannot be accessed from test files).

---

### Task 1: Add typedefs and `_rowComparator` to the controller

**Files:**
- Modify: `lib/app/modules/pos_upload/form/pos_upload_form_controller.dart`

- [ ] **Step 1: Add file-level typedefs before the class declaration**

Find the blank line between `PsItemEntry`'s closing brace and `class PosUploadFormController` (around line 76):

```dart
}

class PosUploadFormController extends GetxController
```

Replace with:

```dart
}

// Stable names for the anonymous row record and column tuple used in
// sharePackingSlipExcel and _rowComparator.
typedef _PSRow = ({
  CellValue caseCell,
  String    caseKey,
  int       serial,
  String    variantOf,
  String    itemCode,
  String    itemName,
  double    qty,
  String    country,
});

typedef _PSCol = (String, CellValue Function(_PSRow));

class PosUploadFormController extends GetxController
```

- [ ] **Step 2: Add `_rowComparator` static method**

Find the closing brace of `psCaseCell` (around line 170):

```dart
  static CellValue psCaseCell(PackingSlip ps) {
    if (ps.fromCaseNo == null) return TextCellValue(ps.name);
    if (ps.toCaseNo != null && ps.toCaseNo != ps.fromCaseNo) {
      return TextCellValue('${ps.fromCaseNo}-${ps.toCaseNo}');
    }
    return IntCellValue(ps.fromCaseNo!);
  }
```

Add `_rowComparator` immediately after it:

```dart
  static CellValue psCaseCell(PackingSlip ps) {
    if (ps.fromCaseNo == null) return TextCellValue(ps.name);
    if (ps.toCaseNo != null && ps.toCaseNo != ps.fromCaseNo) {
      return TextCellValue('${ps.fromCaseNo}-${ps.toCaseNo}');
    }
    return IntCellValue(ps.fromCaseNo!);
  }

  static int _rowComparator(String col, _PSRow a, _PSRow b) {
    switch (col) {
      case 'Case #':
        final an = int.tryParse(a.caseKey.split('-').first);
        final bn = int.tryParse(b.caseKey.split('-').first);
        if (an != null && bn != null) return an.compareTo(bn);
        return a.caseKey.compareTo(b.caseKey);
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

- [ ] **Step 3: Verify no lint errors**

```bash
flutter analyze lib/app/modules/pos_upload/form/pos_upload_form_controller.dart
```

Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/app/modules/pos_upload/form/pos_upload_form_controller.dart
git commit -m "feat: add _PSRow typedef and _rowComparator to PosUploadFormController"
```

---

### Task 2: Refactor `sharePackingSlipExcel` with column list and sort

**Files:**
- Modify: `lib/app/modules/pos_upload/form/pos_upload_form_controller.dart`

- [ ] **Step 1: Update the method signature**

Find:

```dart
  Future<void> sharePackingSlipExcel({required bool compact}) async {
```

Replace with:

```dart
  Future<void> sharePackingSlipExcel({required bool compact, String? sortByColumn}) async {
```

- [ ] **Step 2: Replace headers block + rowMap declaration + write block**

Find the entire section from `final headers` through the closing brace of the data-write `for` loop:

```dart
      final headers = compact
          ? ['Case #', 'Invoice Serial #', 'Item Name', 'Qty', 'Country of Origin']
          : ['Case #', 'Invoice Serial #', 'Variant Of', 'Item Code', 'Item Name', 'Qty', 'Country of Origin'];

      for (int c = 0; c < headers.length; c++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
            .value = TextCellValue(headers[c]);
      }

      // ── Aggregate: sum Qty for rows with identical non-qty columns ──────
      final rowMap = <String, ({
        CellValue caseCell,
        int serial,
        String variantOf,
        String itemCode,
        String itemName,
        double qty,
        String country,
      })>{};

      for (final ps in packingSlips.where((p) => p.customPoNo == upload.name)) {
        final caseCell = psCaseCell(ps);
        final caseKey  = _psCaseKey(ps);
        for (final psItem in ps.items) {
          final posItemName =
              itemNameByIdx[psItem.customInvoiceSerialNumber] ?? psItem.itemName;
          final serial   = int.tryParse(psItem.customInvoiceSerialNumber ?? '') ?? 0;
          final variantOf = psItem.customVariantOf ?? '';
          final itemCode  = psItem.itemCode;
          final country   = psItem.customCountryOfOrigin ?? '';

          final key = compact
              ? '$caseKey\x00$serial\x00$posItemName\x00$country'
              : '$caseKey\x00$serial\x00$variantOf\x00$itemCode\x00$posItemName\x00$country';

          final existing = rowMap[key];
          rowMap[key] = existing == null
              ? (
                  caseCell: caseCell,
                  serial: serial,
                  variantOf: variantOf,
                  itemCode: itemCode,
                  itemName: posItemName,
                  qty: psItem.qty,
                  country: country,
                )
              : (
                  caseCell: existing.caseCell,
                  serial: existing.serial,
                  variantOf: existing.variantOf,
                  itemCode: existing.itemCode,
                  itemName: existing.itemName,
                  qty: existing.qty + psItem.qty,
                  country: existing.country,
                );
        }
      }

      // ── Write aggregated rows ─────────────────────────────────────────
      int row = 1;
      void setCell(int col, CellValue v) => sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
          .value = v;

      for (final r in rowMap.values) {
        if (compact) {
          setCell(0, r.caseCell);
          setCell(1, IntCellValue(r.serial));
          setCell(2, TextCellValue(r.itemName));
          setCell(3, DoubleCellValue(r.qty));
          setCell(4, TextCellValue(r.country));
        } else {
          setCell(0, r.caseCell);
          setCell(1, IntCellValue(r.serial));
          setCell(2, TextCellValue(r.variantOf));
          setCell(3, TextCellValue(r.itemCode));
          setCell(4, TextCellValue(r.itemName));
          setCell(5, DoubleCellValue(r.qty));
          setCell(6, TextCellValue(r.country));
        }
        row++;
      }
```

Replace with:

```dart
      // ── Column list — order determines Excel column positions ─────────
      var columns = compact
          ? <_PSCol>[
              ('Case #',            (r) => r.caseCell),
              ('Invoice Serial #',  (r) => IntCellValue(r.serial)),
              ('Item Name',         (r) => TextCellValue(r.itemName)),
              ('Qty',               (r) => DoubleCellValue(r.qty)),
              ('Country of Origin', (r) => TextCellValue(r.country)),
            ]
          : <_PSCol>[
              ('Case #',            (r) => r.caseCell),
              ('Invoice Serial #',  (r) => IntCellValue(r.serial)),
              ('Variant Of',        (r) => TextCellValue(r.variantOf)),
              ('Item Code',         (r) => TextCellValue(r.itemCode)),
              ('Item Name',         (r) => TextCellValue(r.itemName)),
              ('Qty',               (r) => DoubleCellValue(r.qty)),
              ('Country of Origin', (r) => TextCellValue(r.country)),
            ];

      // ── Aggregate: sum Qty for rows with identical non-qty columns ────
      final rowMap = <String, _PSRow>{};

      for (final ps in packingSlips.where((p) => p.customPoNo == upload.name)) {
        final caseCell = psCaseCell(ps);
        final caseKey  = _psCaseKey(ps);
        for (final psItem in ps.items) {
          final posItemName =
              itemNameByIdx[psItem.customInvoiceSerialNumber] ?? psItem.itemName;
          final serial    = int.tryParse(psItem.customInvoiceSerialNumber ?? '') ?? 0;
          final variantOf = psItem.customVariantOf ?? '';
          final itemCode  = psItem.itemCode;
          final country   = psItem.customCountryOfOrigin ?? '';

          final key = compact
              ? '$caseKey\x00$serial\x00$posItemName\x00$country'
              : '$caseKey\x00$serial\x00$variantOf\x00$itemCode\x00$posItemName\x00$country';

          final existing = rowMap[key];
          rowMap[key] = existing == null
              ? (
                  caseCell:  caseCell,
                  caseKey:   caseKey,
                  serial:    serial,
                  variantOf: variantOf,
                  itemCode:  itemCode,
                  itemName:  posItemName,
                  qty:       psItem.qty,
                  country:   country,
                )
              : (
                  caseCell:  existing.caseCell,
                  caseKey:   existing.caseKey,
                  serial:    existing.serial,
                  variantOf: existing.variantOf,
                  itemCode:  existing.itemCode,
                  itemName:  existing.itemName,
                  qty:       existing.qty + psItem.qty,
                  country:   existing.country,
                );
        }
      }

      // ── Sort rows; move sort column to Column A ───────────────────────
      final sortedRows = rowMap.values.toList();
      if (sortByColumn != null) {
        sortedRows.sort((a, b) => _rowComparator(sortByColumn, a, b));
        final sortIdx = columns.indexWhere((c) => c.$1 == sortByColumn);
        if (sortIdx > 0) {
          final col = columns.removeAt(sortIdx);
          columns.insert(0, col);
        }
      }

      // ── Header row ────────────────────────────────────────────────────
      for (int c = 0; c < columns.length; c++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
            .value = TextCellValue(columns[c].$1);
      }

      // ── Data rows ─────────────────────────────────────────────────────
      int row = 1;
      void setCell(int col, CellValue v) => sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
          .value = v;

      for (final r in sortedRows) {
        for (int c = 0; c < columns.length; c++) {
          setCell(c, columns[c].$2(r));
        }
        row++;
      }
```

- [ ] **Step 3: Verify no lint errors**

```bash
flutter analyze lib/app/modules/pos_upload/form/pos_upload_form_controller.dart
```

Expected: `No issues found!`

- [ ] **Step 4: Run all unit tests**

```bash
flutter test test/unit/
```

Expected: 43 tests, all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/pos_upload/form/pos_upload_form_controller.dart
git commit -m "feat: add sort-by-column support to sharePackingSlipExcel"
```

---

### Task 3: Add sort dropdown to `_showShareSheet` in the screen

**Files:**
- Modify: `lib/app/modules/pos_upload/form/pos_upload_form_screen.dart`

- [ ] **Step 1: Add `_columnNames` static helper to `PosUploadFormScreen`**

Find the `_showShareSheet` method declaration on `PosUploadFormScreen`:

```dart
  void _showShareSheet(BuildContext context) {
```

Insert `_columnNames` immediately before it:

```dart
  static List<String> _columnNames(bool compact) => compact
      ? ['Case #', 'Invoice Serial #', 'Item Name', 'Qty', 'Country of Origin']
      : ['Case #', 'Invoice Serial #', 'Variant Of', 'Item Code', 'Item Name', 'Qty', 'Country of Origin'];

  void _showShareSheet(BuildContext context) {
```

**Important:** These strings must exactly match the column header strings in `PosUploadFormController.sharePackingSlipExcel`'s `columns` list. Any mismatch will cause sorting to silently produce natural-order output for that column.

- [ ] **Step 2: Update `_showShareSheet` state and UI**

Find the entire `_showShareSheet` method body:

```dart
  void _showShareSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        var compact = true;
        return StatefulBuilder(
          builder: (ctx, setState) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Export Packing Slip',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Compact'),
                    subtitle: Text(
                      compact
                          ? 'Case · Serial · Item · Qty · Country'
                          : 'Case · Serial · Variant · Code · Item · Qty · Country',
                    ),
                    value: compact,
                    onChanged: (v) => setState(() => compact = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.table_view_outlined),
                    label: const Text('Share as Excel'),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      controller.sharePackingSlipExcel(compact: compact);
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

Replace with:

```dart
  void _showShareSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        var compact = true;
        String? sortByColumn;
        return StatefulBuilder(
          builder: (ctx, setState) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Export Packing Slip',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Compact'),
                    subtitle: Text(
                      compact
                          ? 'Case · Serial · Item · Qty · Country'
                          : 'Case · Serial · Variant · Code · Item · Qty · Country',
                    ),
                    value: compact,
                    onChanged: (v) => setState(() {
                      compact = v;
                      sortByColumn = null;
                    }),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
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
                      ..._columnNames(compact).map(
                        (name) => DropdownMenuItem(value: name, child: Text(name)),
                      ),
                    ],
                    onChanged: (v) => setState(() => sortByColumn = v),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.table_view_outlined),
                    label: const Text('Share as Excel'),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      controller.sharePackingSlipExcel(
                        compact: compact,
                        sortByColumn: sortByColumn,
                      );
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

- [ ] **Step 3: Verify no lint errors**

```bash
flutter analyze lib/app/modules/pos_upload/form/pos_upload_form_screen.dart
```

Expected: `No issues found!`

- [ ] **Step 4: Run full test suite**

```bash
flutter test
```

Expected: 50 tests, all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/pos_upload/form/pos_upload_form_screen.dart
git commit -m "feat: add sort-by-column dropdown to packing slip export sheet"
```
