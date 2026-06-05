# POS Upload – Packing Slip Excel Sort By Column

**Date:** 2026-05-22  
**Status:** Approved

## Problem

The packing slip Excel export always writes rows in natural order (Case # ascending). Users need to sort by any column — e.g. by Item Name to group similar products, or by Country of Origin for customs review.

## Solution

Add a "Sort by" dropdown to the export bottom sheet. The selected column sorts rows ascending and is moved to Column A. Natural order (existing behaviour) remains the default.

---

## Architecture

Two files changed, no new files:

| File | Change |
|------|--------|
| `lib/app/modules/pos_upload/form/pos_upload_form_controller.dart` | `sharePackingSlipExcel` gains `sortByColumn: String?` param; column list and sort logic added |
| `lib/app/modules/pos_upload/form/pos_upload_form_screen.dart` | `_showShareSheet` gains `sortByColumn` state + `DropdownButtonFormField` |

No new tests — sort logic depends on Excel `CellValue` types and is integration-only.

---

## Controller Changes

### Signature

```dart
Future<void> sharePackingSlipExcel({required bool compact, String? sortByColumn})
```

`null` means natural order (no sort applied, no column reordering).

### Row record — add `caseKey` field

The anonymous record used in `rowMap` gains one field:

```dart
({
  CellValue caseCell,
  String    caseKey,   // NEW — _psCaseKey(ps), used by sort comparator
  int       serial,
  String    variantOf,
  String    itemCode,
  String    itemName,
  double    qty,
  String    country,
})
```

`caseKey` is set to `_psCaseKey(ps)` when inserting/updating a row in `rowMap`.

### Column list

After writing the header row, build a mutable column list that replaces the hardcoded `if (compact) { setCell... } else { setCell... }` block:

```dart
typedef _Row = ({CellValue caseCell, String caseKey, int serial,
                 String variantOf, String itemCode, String itemName,
                 double qty, String country});
typedef _Col = (String, CellValue Function(_Row));

var columns = compact
    ? <_Col>[
        ('Case #',            (r) => r.caseCell),
        ('Invoice Serial #',  (r) => IntCellValue(r.serial)),
        ('Item Name',         (r) => TextCellValue(r.itemName)),
        ('Qty',               (r) => DoubleCellValue(r.qty)),
        ('Country of Origin', (r) => TextCellValue(r.country)),
      ]
    : <_Col>[
        ('Case #',            (r) => r.caseCell),
        ('Invoice Serial #',  (r) => IntCellValue(r.serial)),
        ('Variant Of',        (r) => TextCellValue(r.variantOf)),
        ('Item Code',         (r) => TextCellValue(r.itemCode)),
        ('Item Name',         (r) => TextCellValue(r.itemName)),
        ('Qty',               (r) => DoubleCellValue(r.qty)),
        ('Country of Origin', (r) => TextCellValue(r.country)),
      ];
```

The `headers` list for the header row is derived from `columns.map((c) => c.$1)`.

### Sort column reordering

If `sortByColumn != null`:

```dart
final sortIdx = columns.indexWhere((c) => c.$1 == sortByColumn);
if (sortIdx > 0) {
  final col = columns.removeAt(sortIdx);
  columns.insert(0, col);
}
```

### Row sort

```dart
final sortedRows = rowMap.values.toList();
if (sortByColumn != null) {
  sortedRows.sort((a, b) => _rowComparator(sortByColumn!, a, b));
}
```

Per-column comparator:

```dart
static int _rowComparator(String col, _Row a, _Row b) {
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

### Write loop

Replaces both `if (compact)` / `else` blocks:

```dart
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

---

## Screen Changes

### New state variable

In `_showShareSheet`'s `StatefulBuilder`:

```dart
var compact = true;
String? sortByColumn;   // null = natural order
```

### Compact toggle — reset sort on format change

```dart
onChanged: (v) => setState(() { compact = v; sortByColumn = null; }),
```

### Sort dropdown

Added below the `SwitchListTile`, above the `FilledButton`:

```dart
const SizedBox(height: 4),
DropdownButtonFormField<String?>(
  value: sortByColumn,
  decoration: const InputDecoration(
    labelText: 'Sort by',
    border: OutlineInputBorder(),
    isDense: true,
  ),
  items: [
    const DropdownMenuItem(value: null, child: Text('None (natural order)')),
    ..._columnNames(compact).map(
      (name) => DropdownMenuItem(value: name, child: Text(name)),
    ),
  ],
  onChanged: (v) => setState(() => sortByColumn = v),
),
```

Where `_columnNames` is a small static helper on `PosUploadFormScreen`:

```dart
static List<String> _columnNames(bool compact) => compact
    ? ['Case #', 'Invoice Serial #', 'Item Name', 'Qty', 'Country of Origin']
    : ['Case #', 'Invoice Serial #', 'Variant Of', 'Item Code', 'Item Name', 'Qty', 'Country of Origin'];
```

### Share button

```dart
onPressed: () {
  Navigator.of(ctx).pop();
  controller.sharePackingSlipExcel(compact: compact, sortByColumn: sortByColumn);
},
```
