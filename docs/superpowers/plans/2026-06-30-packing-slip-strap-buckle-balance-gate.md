# Packing Slip Strap/Buckle Balance Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Block packing a Straps/Buckles item for an Invoice Serial Number whose linked Delivery Note has mismatched delivered Strap vs Buckle quantities.

**Architecture:** A pure predicate helper (`ps_serial_balance.dart`) computes per-serial Strap/Buckle balance from the linked DN's rows. Two enforcement points consume it: the in-sheet serial dropdown disables unbalanced serials (via a new `SerialDropdownItem.blockedReason`), and the scan resolver (`findScannedDnItem`) skips unbalanced serials, rejecting only when all matching serials are blocked.

**Tech Stack:** Flutter, GetX, Dart. Tests via `flutter_test`.

## Global Constraints

- Item-group leaf names are exact, case-sensitive, **plural**: `'Straps'` and `'Buckles'`.
- A serial is **unbalanced** only when `strapQty > 0 && buckleQty > 0 && (strapQty - buckleQty).abs() > 1e-9` (epsilon tolerance — qty is `double`). Either-side-zero is balanced ("or 0" rule).
- The gate applies only when the item being packed is a Straps/Buckles item; all other item groups pack freely.
- Comparison uses DN **delivered** quantities (not packed-so-far, not remaining).
- No change to the Delivery Note form, no backend validation, no configurable group names beyond the two centralized constants.
- Lint must stay clean: `flutter analyze` reports 0 errors after each task.

---

### Task 1: Pure balance helper + unit tests

**Files:**
- Create: `lib/app/modules/packing_slip/form/ps_serial_balance.dart`
- Test: `test/unit/ps_serial_balance_test.dart`

**Interfaces:**
- Consumes: `DeliveryNoteItem` from `lib/app/data/models/delivery_note_model.dart` (fields used: `itemGroup` `String?`, `qty` `double`, `customInvoiceSerialNumber` `String?`).
- Produces:
  - `const String kStrapItemGroup = 'Straps';`
  - `const String kBuckleItemGroup = 'Buckles';`
  - `bool isPairedItemGroup(String? itemGroup)`
  - `({double strap, double buckle}) strapBuckleQtyFor(List<DeliveryNoteItem> items, String serial)`
  - `bool isSerialStrapBuckleUnbalanced(List<DeliveryNoteItem> items, String serial)`

- [ ] **Step 1: Write the failing test**

Create `test/unit/ps_serial_balance_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/modules/packing_slip/form/ps_serial_balance.dart';

DeliveryNoteItem _dn({
  required String name,
  required String itemCode,
  required String itemGroup,
  String serial = '1',
  double qty = 10.0,
}) =>
    DeliveryNoteItem(
      name: name,
      itemCode: itemCode,
      qty: qty,
      rate: 1.0,
      itemGroup: itemGroup,
      customInvoiceSerialNumber: serial,
      docstatus: 1,
    );

void main() {
  group('isPairedItemGroup', () {
    test('true for Straps and Buckles, false otherwise', () {
      expect(isPairedItemGroup('Straps'), isTrue);
      expect(isPairedItemGroup('Buckles'), isTrue);
      expect(isPairedItemGroup('Boxes'), isFalse);
      expect(isPairedItemGroup(''), isFalse);
      expect(isPairedItemGroup(null), isFalse);
    });
  });

  group('strapBuckleQtyFor', () {
    test('sums each group only for the requested serial', () {
      final items = [
        _dn(name: 'a', itemCode: 'S1', itemGroup: 'Straps', serial: '5', qty: 6),
        _dn(name: 'b', itemCode: 'S2', itemGroup: 'Straps', serial: '5', qty: 4),
        _dn(name: 'c', itemCode: 'B1', itemGroup: 'Buckles', serial: '5', qty: 8),
        _dn(name: 'd', itemCode: 'S3', itemGroup: 'Straps', serial: '6', qty: 99),
      ];
      final r = strapBuckleQtyFor(items, '5');
      expect(r.strap, 10.0);
      expect(r.buckle, 8.0);
    });
  });

  group('isSerialStrapBuckleUnbalanced', () {
    test('balanced when equal qty', () {
      final items = [
        _dn(name: 'a', itemCode: 'S', itemGroup: 'Straps', serial: '1', qty: 10),
        _dn(name: 'b', itemCode: 'B', itemGroup: 'Buckles', serial: '1', qty: 10),
      ];
      expect(isSerialStrapBuckleUnbalanced(items, '1'), isFalse);
    });

    test('balanced when one side absent (the "or 0" rule)', () {
      final items = [
        _dn(name: 'a', itemCode: 'S', itemGroup: 'Straps', serial: '1', qty: 10),
      ];
      expect(isSerialStrapBuckleUnbalanced(items, '1'), isFalse);
    });

    test('unbalanced when both present and differ', () {
      final items = [
        _dn(name: 'a', itemCode: 'S', itemGroup: 'Straps', serial: '1', qty: 10),
        _dn(name: 'b', itemCode: 'B', itemGroup: 'Buckles', serial: '1', qty: 8),
      ];
      expect(isSerialStrapBuckleUnbalanced(items, '1'), isTrue);
    });

    test('balanced when serial has no paired rows at all', () {
      final items = [
        _dn(name: 'a', itemCode: 'X', itemGroup: 'Boxes', serial: '1', qty: 3),
      ];
      expect(isSerialStrapBuckleUnbalanced(items, '1'), isFalse);
    });

    test('equal within epsilon is balanced', () {
      final items = [
        _dn(name: 'a', itemCode: 'S', itemGroup: 'Straps', serial: '1', qty: 0.1 + 0.2),
        _dn(name: 'b', itemCode: 'B', itemGroup: 'Buckles', serial: '1', qty: 0.3),
      ];
      expect(isSerialStrapBuckleUnbalanced(items, '1'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/ps_serial_balance_test.dart`
Expected: FAIL — `ps_serial_balance.dart` does not exist (compile error / URI doesn't exist).

- [ ] **Step 3: Write minimal implementation**

Create `lib/app/modules/packing_slip/form/ps_serial_balance.dart`:

```dart
import 'package:multimax/app/data/models/delivery_note_model.dart';

/// Item-group leaf names whose quantities must match per Invoice Serial Number.
/// Exact, case-sensitive, plural ERPNext group names.
const String kStrapItemGroup = 'Straps';
const String kBuckleItemGroup = 'Buckles';

/// Quantities within [1e-9] of each other are treated as equal (qty is double).
const double _kQtyEpsilon = 1e-9;

/// True when [itemGroup] participates in the strap/buckle pairing rule.
bool isPairedItemGroup(String? itemGroup) =>
    itemGroup == kStrapItemGroup || itemGroup == kBuckleItemGroup;

/// Delivered Strap and Buckle totals for [serial] across all [items].
({double strap, double buckle}) strapBuckleQtyFor(
    List<DeliveryNoteItem> items, String serial) {
  double strap = 0.0;
  double buckle = 0.0;
  for (final item in items) {
    if (item.customInvoiceSerialNumber != serial) continue;
    if (item.itemGroup == kStrapItemGroup) {
      strap += item.qty;
    } else if (item.itemGroup == kBuckleItemGroup) {
      buckle += item.qty;
    }
  }
  return (strap: strap, buckle: buckle);
}

/// True when [serial]'s delivered Strap/Buckle quantities are mismatched.
///
/// Balanced (false) when either group is absent (the "or 0" rule) or the two
/// group totals are equal within [_kQtyEpsilon].
bool isSerialStrapBuckleUnbalanced(
    List<DeliveryNoteItem> items, String serial) {
  final q = strapBuckleQtyFor(items, serial);
  if (q.strap <= 0 || q.buckle <= 0) return false;
  return (q.strap - q.buckle).abs() > _kQtyEpsilon;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/ps_serial_balance_test.dart`
Expected: PASS (all tests green).

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/packing_slip/form/ps_serial_balance.dart test/unit/ps_serial_balance_test.dart
git commit -m "feat(packing-slip): pure Strap/Buckle serial balance helper"
```

---

### Task 2: `SerialDropdownItem.blockedReason` + dropdown disable rendering

**Files:**
- Modify: `lib/app/shared/item_sheet/serial_number_field_delegate.dart`
- Modify: `lib/app/shared/item_sheet/widgets/shared_invoice_serial_number_field.dart`
- Test: `test/widget/shared_invoice_serial_field_blocked_test.dart` (new)

**Interfaces:**
- Consumes: `SerialDropdownItem` (existing), `SharedInvoiceSerialNumberField` (existing).
- Produces: `SerialDropdownItem.blockedReason` (`String?`, optional, default `null`). When non-null the dropdown row is non-selectable, dimmed, and shows the reason text.

- [ ] **Step 1: Write the failing test**

Create `test/widget/shared_invoice_serial_field_blocked_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/shared/item_sheet/serial_field_mixin.dart';
import 'package:multimax/app/shared/item_sheet/serial_number_field_delegate.dart';
import 'package:multimax/app/shared/item_sheet/widgets/shared_invoice_serial_number_field.dart';

class _FakeBlockedController extends GetxController with SerialFieldMixin {
  @override
  List<String> get availableSerialNos => ['1', '2'];

  @override
  double posItemQtyForSerial(String serial) => 10.0;

  @override
  SerialDropdownItem? posDropdownItemFor(String serial) => SerialDropdownItem(
        serial: serial,
        itemName: 'Item $serial',
        qty: 10.0,
        remaining: 10.0,
        blockedReason: serial == '2' ? 'Strap ≠ Buckle' : null,
      );
}

Widget _host(SerialNumberFieldDelegate c) => MaterialApp(
      home: Scaffold(body: SharedInvoiceSerialNumberField(c: c)),
    );

void main() {
  testWidgets('blocked serial row is disabled and shows the reason', (tester) async {
    final c = _FakeBlockedController();
    await tester.pumpWidget(_host(c));
    // Open the dropdown.
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    // The reason text renders for the blocked row.
    expect(find.text('Strap ≠ Buckle'), findsOneWidget);

    // The blocked DropdownMenuItem is disabled.
    final blockedItem = tester.widgetList<DropdownMenuItem<String>>(
      find.byType(DropdownMenuItem<String>),
    ).firstWhere((i) => i.value == '2');
    expect(blockedItem.enabled, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/shared_invoice_serial_field_blocked_test.dart`
Expected: FAIL — `blockedReason` is not a parameter of `SerialDropdownItem` (compile error).

- [ ] **Step 3a: Add the field to `SerialDropdownItem`**

In `lib/app/shared/item_sheet/serial_number_field_delegate.dart`, add the field and constructor param (place after `used`):

```dart
  /// Total qty already committed across all rows for this serial.
  ///
  /// Computed at list-build time as `cap − remaining`.
  /// Displayed in the cap chip as "Used: N".
  final double used;

  /// Non-null marks this serial non-selectable in the dropdown; the string is
  /// the reason shown in the row (e.g. "Strap ≠ Buckle"). Null = selectable.
  final String? blockedReason;

  const SerialDropdownItem({
    required this.serial,
    this.itemName,
    this.qty,
    required this.remaining,
    this.used = 0.0,
    this.blockedReason,
  });
```

- [ ] **Step 3b: Render disable + reason in the widget**

In `lib/app/shared/item_sheet/widgets/shared_invoice_serial_number_field.dart`, update `_buildItems`. Replace the sub-label `if (hasQty) Text(...)` block and the returned `DropdownMenuItem` so a `blockedReason` takes priority:

Replace this existing block:

```dart
                  if (hasQty)
                    Text(
                      item.isFull
                          ? '×${SerialFieldMixin.fmtQty(item.qty!)}  —  Full'
                          : '×${SerialFieldMixin.fmtQty(item.qty!)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: item.isFull
                            ? Colors.red.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
```

with:

```dart
                  if (item.blockedReason != null)
                    Text(
                      item.blockedReason!,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.red.shade400,
                      ),
                    )
                  else if (hasQty)
                    Text(
                      item.isFull
                          ? '×${SerialFieldMixin.fmtQty(item.qty!)}  —  Full'
                          : '×${SerialFieldMixin.fmtQty(item.qty!)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: item.isFull
                            ? Colors.red.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
```

Then replace the returned `DropdownMenuItem` block:

```dart
      return DropdownMenuItem<String>(
        value: item.serial,
        enabled: !item.isFull || allowFull,
        child: Opacity(
          opacity: (item.isFull && !allowFull) ? 0.4 : 1.0,
          child: tile,
        ),
      );
```

with:

```dart
      final isBlocked = item.blockedReason != null;
      return DropdownMenuItem<String>(
        value: item.serial,
        enabled: (!item.isFull || allowFull) && !isBlocked,
        child: Opacity(
          opacity: (isBlocked || (item.isFull && !allowFull)) ? 0.4 : 1.0,
          child: tile,
        ),
      );
```

Note: the badge-only fallback (`tile = badge` when no name/qty) does not show the reason, but blocked serials in the PS flow always carry an `itemName`, so the reason renders. No change needed to the `else` branch.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/shared_invoice_serial_field_blocked_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the existing serial-field widget test to confirm no regression**

Run: `flutter test test/widget/shared_invoice_serial_field_toggle_test.dart`
Expected: PASS (both tests still green).

- [ ] **Step 6: Commit**

```bash
git add lib/app/shared/item_sheet/serial_number_field_delegate.dart lib/app/shared/item_sheet/widgets/shared_invoice_serial_number_field.dart test/widget/shared_invoice_serial_field_blocked_test.dart
git commit -m "feat(item-sheet): blockedReason disables a serial dropdown row"
```

---

### Task 3: Wire `blockedReason` in the Packing Slip item-form controller

**Files:**
- Modify: `lib/app/modules/packing_slip/form/packing_slip_item_form_controller.dart` (`posDropdownItemFor`, ~lines 129-143)

**Interfaces:**
- Consumes: `isPairedItemGroup`, `isSerialStrapBuckleUnbalanced` (Task 1); `SerialDropdownItem.blockedReason` (Task 2); `_parent.linkedDeliveryNote.value` (`Rx<DeliveryNote?>`), `itemGroup` (`RxString` on this controller).
- Produces: nothing new consumed downstream — this is the dropdown integration.

- [ ] **Step 1: Add the import**

At the top of `packing_slip_item_form_controller.dart`, add:

```dart
import 'package:multimax/app/modules/packing_slip/form/ps_serial_balance.dart';
```

- [ ] **Step 2: Set `blockedReason` in `posDropdownItemFor`**

Replace the existing `return SerialDropdownItem(...)` inside `posDropdownItemFor`:

```dart
    final posName = _parent.getPosItemName(serial);
    return SerialDropdownItem(
      serial:    serial,
      itemName:  posName.isNotEmpty ? posName : option.dnRow.itemName,
      qty:       option.qty,
      remaining: option.remaining,
      used:      option.qty - option.remaining,
    );
```

with:

```dart
    final posName = _parent.getPosItemName(serial);
    final dnItems = _parent.linkedDeliveryNote.value?.items ?? const [];
    final blocked = isPairedItemGroup(itemGroup.value) &&
            isSerialStrapBuckleUnbalanced(dnItems, serial)
        ? 'Strap ≠ Buckle'
        : null;
    return SerialDropdownItem(
      serial:       serial,
      itemName:     posName.isNotEmpty ? posName : option.dnRow.itemName,
      qty:          option.qty,
      remaining:    option.remaining,
      used:         option.qty - option.remaining,
      blockedReason: blocked,
    );
```

- [ ] **Step 3: Verify it compiles and lints clean**

Run: `flutter analyze lib/app/modules/packing_slip/form/packing_slip_item_form_controller.dart`
Expected: "No issues found!" (0 errors).

- [ ] **Step 4: Run the full packing-slip + serial test suites to confirm no regression**

Run: `flutter test test/unit/ps_serial_options_test.dart test/widget/shared_invoice_serial_field_blocked_test.dart test/widget/shared_invoice_serial_field_toggle_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/packing_slip/form/packing_slip_item_form_controller.dart
git commit -m "feat(packing-slip): disable unbalanced serials in item-sheet dropdown"
```

---

### Task 4: `findScannedDnItem` skip predicate + unit tests

**Files:**
- Modify: `lib/app/modules/packing_slip/form/dn_scan_item_matcher.dart`
- Test: `test/unit/packing_slip_scan_item_matcher_test.dart` (extend)

**Interfaces:**
- Consumes: existing `findScannedDnItem` signature.
- Produces: `findScannedDnItem(..., bool Function(DeliveryNoteItem)? skipRow)` — rows for which `skipRow` returns true are excluded from both the remaining-pick and the fallback. Returns null when no code/batch match exists OR when every match is skipped. `skipRow` defaults to null (legacy behaviour unchanged).

- [ ] **Step 1: Write the failing tests**

Append inside the existing `group('findScannedDnItem', ...)` in `test/unit/packing_slip_scan_item_matcher_test.dart` (before the closing `});` of the group):

```dart
    test('skips rows flagged by skipRow and advances to the next packable row',
        () {
      final items = [
        dnItem(name: 'row-1', itemCode: 'ITEM-A', serial: '1'),
        dnItem(name: 'row-2', itemCode: 'ITEM-A', serial: '2'),
      ];

      final match = findScannedDnItem(
        items: items,
        code: 'ITEM-A',
        batch: null,
        remainingQty: (item) => 12.0,
        skipRow: (item) => item.name == 'row-1',
      );

      expect(match?.name, equals('row-2'));
    });

    test('returns null when every matching row is skipped', () {
      final items = [
        dnItem(name: 'row-1', itemCode: 'ITEM-A', serial: '1'),
        dnItem(name: 'row-2', itemCode: 'ITEM-A', serial: '2'),
      ];

      final match = findScannedDnItem(
        items: items,
        code: 'ITEM-A',
        batch: null,
        remainingQty: (item) => 12.0,
        skipRow: (item) => true,
      );

      expect(match, isNull);
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/unit/packing_slip_scan_item_matcher_test.dart`
Expected: FAIL — `skipRow` is not a named parameter of `findScannedDnItem`.

- [ ] **Step 3: Add the `skipRow` parameter**

Replace the body of `dn_scan_item_matcher.dart`'s `findScannedDnItem` (keep the doc comment):

```dart
DeliveryNoteItem? findScannedDnItem({
  required List<DeliveryNoteItem> items,
  required String code,
  required String? batch,
  required double Function(DeliveryNoteItem) remainingQty,
  bool Function(DeliveryNoteItem)? skipRow,
}) {
  final matches = items.where((item) {
    final codeMatch = item.itemCode == code;
    final batchMatch = (batch == null) || (item.batchNo == batch);
    return codeMatch && batchMatch;
  }).toList();

  if (matches.isEmpty) return null;

  final packable = skipRow == null
      ? matches
      : matches.where((item) => !skipRow(item)).toList();
  if (packable.isEmpty) return null;

  return packable.firstWhereOrNull((item) => remainingQty(item) > 0) ??
      packable.first;
}
```

- [ ] **Step 4: Run the full matcher suite to verify all pass**

Run: `flutter test test/unit/packing_slip_scan_item_matcher_test.dart`
Expected: PASS (all legacy tests + 2 new tests green — legacy tests pass null `skipRow`).

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/packing_slip/form/dn_scan_item_matcher.dart test/unit/packing_slip_scan_item_matcher_test.dart
git commit -m "feat(packing-slip): findScannedDnItem skipRow predicate"
```

---

### Task 5: Wire scan path — skip unbalanced serials, reject when all blocked

**Files:**
- Modify: `lib/app/modules/packing_slip/form/packing_slip_form_controller.dart` (`_findItemInDN` ~lines 824-830, `_handleScanResult` ~lines 756-771)

**Interfaces:**
- Consumes: `isPairedItemGroup`, `isSerialStrapBuckleUnbalanced` (Task 1); `findScannedDnItem(..., skipRow:)` (Task 4); `linkedDeliveryNote.value` (`Rx<DeliveryNote?>`), `GlobalSnackbar.error`.
- Produces: nothing downstream — terminal integration.

- [ ] **Step 1: Add the import**

At the top of `packing_slip_form_controller.dart`, add (if not already present from a sibling task — this controller is separate from the item-form controller, so add it here too):

```dart
import 'package:multimax/app/modules/packing_slip/form/ps_serial_balance.dart';
```

- [ ] **Step 2: Pass `skipRow` from `_findItemInDN`**

Replace `_findItemInDN`:

```dart
  DeliveryNoteItem? _findItemInDN(String code, String? batch) =>
      findScannedDnItem(
        items:        linkedDeliveryNote.value!.items,
        code:         code,
        batch:        batch,
        remainingQty: _calcRemainingQtyForDnItem,
      );
```

with:

```dart
  DeliveryNoteItem? _findItemInDN(String code, String? batch) {
    final dnItems = linkedDeliveryNote.value!.items;
    return findScannedDnItem(
      items:        dnItems,
      code:         code,
      batch:        batch,
      remainingQty: _calcRemainingQtyForDnItem,
      skipRow: (row) =>
          isPairedItemGroup(row.itemGroup) &&
          isSerialStrapBuckleUnbalanced(
              dnItems, row.customInvoiceSerialNumber ?? ''),
    );
  }
```

- [ ] **Step 3: Distinguish blocked-by-balance from not-found in `_handleScanResult`**

Replace the `else` branch of `_handleScanResult`:

```dart
    if (match != null) {
      prepareSheetForAdd(match, scannedBatch: result.batchNo);
    } else {
      GlobalSnackbar.error(
        message:
        'Item ${result.itemData!.itemCode} not found in Delivery Note'
            ' or Batch mismatch.',
      );
    }
```

with:

```dart
    if (match != null) {
      prepareSheetForAdd(match, scannedBatch: result.batchNo);
    } else {
      final code = result.itemData!.itemCode;
      final batch = result.batchNo;
      final dnItems = linkedDeliveryNote.value?.items ?? const [];
      final hasAnyMatch = dnItems.any((i) =>
          i.itemCode == code && (batch == null || i.batchNo == batch));
      if (hasAnyMatch) {
        GlobalSnackbar.error(
          message:
              'All serials for $code have mismatched Strap/Buckle quantities. '
              'Packing blocked until the Delivery Note is balanced.',
        );
      } else {
        GlobalSnackbar.error(
          message: 'Item $code not found in Delivery Note or Batch mismatch.',
        );
      }
    }
```

- [ ] **Step 4: Verify it compiles and lints clean**

Run: `flutter analyze lib/app/modules/packing_slip/form/packing_slip_form_controller.dart`
Expected: "No issues found!" (0 errors).

- [ ] **Step 5: Run the full test suite to confirm no regression**

Run: `flutter test`
Expected: PASS (no new failures vs. the pre-existing baseline noted in memory; the new Task 1/2/4 tests are green).

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/packing_slip/form/packing_slip_form_controller.dart
git commit -m "feat(packing-slip): scan skips unbalanced serials, rejects when all blocked"
```

---

## Manual / on-device smoke (after all tasks)

Verify on a Packing Slip linked to a DN that has at least one unbalanced serial
(e.g. serial #5 = 10 Straps + 8 Buckles) and one balanced serial:

1. **Dropdown:** open the item sheet for a Straps item present in serial #5 — serial #5 appears greyed-out with "Strap ≠ Buckle" and cannot be selected; balanced serials are selectable.
2. **Dropdown (non-paired):** open the sheet for a non-Strap/Buckle item in serial #5 — no serials are blocked.
3. **Scan skip:** scan a Straps barcode whose first remaining serial is #5 (unbalanced) but which also exists in a balanced serial — the sheet opens targeting the balanced serial, not #5.
4. **Scan reject:** scan a Straps barcode that exists *only* in unbalanced serials — a snackbar reports "All serials for {code} have mismatched Strap/Buckle quantities…" and no sheet opens.

---

## Self-Review

**Spec coverage:**
- Gate predicate (DN-delivered, both>0, epsilon, "or 0") → Task 1. ✓
- Plural group names `'Straps'`/`'Buckles'` constants → Task 1. ✓
- Dropdown disable + reason → Tasks 2 & 3. ✓
- Scan skip-to-next-balanced + reject-if-all-blocked → Tasks 4 & 5. ✓
- Tests: pure balance, scan matcher skip, widget disable → Tasks 1, 4, 2. ✓
- Out-of-scope items (DN form, backend, configurable names) → untouched. ✓

**Type consistency:** `blockedReason` (`String?`) defined in Task 2, consumed in Task 3. `skipRow` (`bool Function(DeliveryNoteItem)?`) defined in Task 4, consumed in Task 5. `isPairedItemGroup`/`isSerialStrapBuckleUnbalanced`/`strapBuckleQtyFor` defined in Task 1, consumed in Tasks 3 & 5. `linkedDeliveryNote` is `Rx<DeliveryNote?>` (confirmed). Names consistent across tasks. ✓
