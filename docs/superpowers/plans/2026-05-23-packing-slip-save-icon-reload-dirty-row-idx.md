# Packing Slip: Save Icon, Reload Dirty State, and Row # Display

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix three UX issues on the Packing Slip form: always show the Save icon for draft documents, mark the document dirty after `_refreshDnDetails` patches stale DN references on reload, and display the ERPNext row index (`idx`) alongside each DN item in the checklist.

**Architecture:** Three independent, targeted changes — one is a one-line UI condition fix, one is a one-line controller side-effect addition, and one adds a single `Text` widget to a checklist row. No new files, no abstraction changes.

**Tech Stack:** Flutter / GetX, Dart

---

## Files to Modify

| File | Change |
|------|--------|
| `lib/app/modules/packing_slip/form/packing_slip_form_screen.dart` | Issue 1: fix `onSave` condition; Issue 3: add row `idx` to checklist |
| `lib/app/modules/packing_slip/form/packing_slip_form_controller.dart` | Issue 2: call `_checkForChanges()` after patching DN details |

---

## Task 1: Always show the Save icon for draft documents

**Context:** `DocTypeFormHeader` renders `SaveIconButton` only when `onSave != null`. The current condition `(slip?.docstatus == 0 && isDirty)` hides the button entirely when the form is clean, giving the user no visible cue that saving is possible. `SaveIconButton` already greys itself out when `isDirty` is false (line 99 of `save_icon_button.dart`: `onPressed: widget.isDirty ? widget.onPressed : null`), so the icon just needs to be always present.

**Files:**
- Modify: `lib/app/modules/packing_slip/form/packing_slip_form_screen.dart:40-42`

- [ ] **Step 1: Locate the `onSave` wiring in `packing_slip_form_screen.dart`**

Open `lib/app/modules/packing_slip/form/packing_slip_form_screen.dart`. The relevant block is around line 40:

```dart
onSave: (slip?.docstatus == 0 && isDirty)
    ? controller.savePackingSlip
    : null,
```

- [ ] **Step 2: Remove the `isDirty` guard from `onSave`**

Replace just the `onSave` line. The `canSave: isDirty` (line 38, unchanged) continues to drive grey-out state inside `SaveIconButton`. Only pass `null` when the document is submitted/cancelled (docstatus ≠ 0).

```dart
onSave: slip?.docstatus == 0
    ? controller.savePackingSlip
    : null,
```

After the edit lines 36–45 should read:

```dart
DocTypeFormHeader(
  title:     slip?.name ?? 'Packing Slip',
  canSave:   isDirty,
  docStatus: slip?.docstatus ?? 0,
  isSaving:  isSaving,
  onSave: slip?.docstatus == 0
      ? controller.savePackingSlip
      : null,
  onReload: (controller.mode != 'new' && !isDirty)
      ? controller.reloadDocument
      : null,
```

- [ ] **Step 3: Verify with `flutter analyze`**

Run:
```bash
flutter analyze lib/app/modules/packing_slip/form/packing_slip_form_screen.dart
```
Expected: no new warnings or errors.

- [ ] **Step 4: Commit**

```bash
git add lib/app/modules/packing_slip/form/packing_slip_form_screen.dart
git commit -m "fix(packing-slip): always show Save icon for draft documents"
```

---

## Task 2: Mark document dirty after `_refreshDnDetails` patches stale DN references

**Context:** After a reload, `_hydratePackingSlip` anchors `_originalJson` from the raw server data (before any DN detail repair), then `_refreshDnDetails` patches items with empty/stale `dn_detail` links. The patched `packingSlip.value` now differs from `_originalJson`, but `_checkForChanges()` is never called, so `isDirty` stays `false` and the Save icon stays greyed out. The user has no way to persist the repaired references without manually touching another field.

**Files:**
- Modify: `lib/app/modules/packing_slip/form/packing_slip_form_controller.dart:372`

- [ ] **Step 1: Write the failing test**

Create `test/unit/packing_slip_refresh_dn_details_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';

// Pure-logic helper extracted for testing: given a slip and a DN,
// returns the patched items list and whether any items changed.
// Mirrors the algorithm in PackingSlipFormController._refreshDnDetails.
({List<PackingSlipItem> items, bool changed}) refreshDnDetails(
  PackingSlip slip,
  DeliveryNote dn,
) {
  final validNames = {
    for (final d in dn.items)
      if (d.name != null && d.name!.isNotEmpty) d.name!,
  };

  bool changed = false;
  final patched = slip.items.map((item) {
    if (item.dnDetail.isNotEmpty && validNames.contains(item.dnDetail)) {
      return item;
    }
    final itemSerial = item.customInvoiceSerialNumber ?? '0';
    final match = dn.items
        .where((d) => d.name != null && d.name!.isNotEmpty)
        .where((d) => d.itemCode == item.itemCode)
        .where((d) => (d.customInvoiceSerialNumber ?? '0') == itemSerial)
        .where((d) => item.batchNo.isEmpty || d.batchNo == item.batchNo)
        .cast<DeliveryNoteItem?>()
        .followedBy([null])
        .first;

    if (match == null) return item;
    changed = true;
    return item.copyWith(dnDetail: match.name!);
  }).toList();

  return (items: patched, changed: changed);
}

void main() {
  group('refreshDnDetails', () {
    PackingSlipItem _slipItem({
      required String dnDetail,
      required String itemCode,
      String serial = '1',
    }) =>
        PackingSlipItem(
          name: 'PS-ROW-1',
          dnDetail: dnDetail,
          itemCode: itemCode,
          itemName: 'Test Item',
          qty: 1.0,
          uom: 'Nos',
          batchNo: '',
          netWeight: 0.0,
          weightUom: 0.0,
          customInvoiceSerialNumber: serial,
        );

    DeliveryNoteItem _dnItem({
      required String name,
      required String itemCode,
      String serial = '1',
    }) =>
        DeliveryNoteItem(
          name: name,
          itemCode: itemCode,
          qty: 5.0,
          rate: 10.0,
          customInvoiceSerialNumber: serial,
          docstatus: 1,
        );

    test('returns changed=false when all dn_detail values are already valid', () {
      final dn = DeliveryNote(
        name: 'DN-001', customer: '', grandTotal: 0, postingDate: '',
        modified: '', creation: '', status: 'Submitted', currency: 'AED',
        totalQty: 5, docstatus: 1,
        items: [_dnItem(name: 'existing-row', itemCode: 'ITEM-A')],
      );
      final slip = PackingSlip(
        name: 'PS-001', deliveryNote: 'DN-001', modified: '', creation: '',
        docstatus: 0, status: 'Draft',
        items: [_slipItem(dnDetail: 'existing-row', itemCode: 'ITEM-A')],
      );

      final result = refreshDnDetails(slip, dn);

      expect(result.changed, isFalse);
      expect(result.items.first.dnDetail, equals('existing-row'));
    });

    test('returns changed=true and patches empty dn_detail when a match is found', () {
      final dn = DeliveryNote(
        name: 'DN-001', customer: '', grandTotal: 0, postingDate: '',
        modified: '', creation: '', status: 'Submitted', currency: 'AED',
        totalQty: 5, docstatus: 1,
        items: [_dnItem(name: 'new-row-name', itemCode: 'ITEM-A')],
      );
      final slip = PackingSlip(
        name: 'PS-001', deliveryNote: 'DN-001', modified: '', creation: '',
        docstatus: 0, status: 'Draft',
        items: [_slipItem(dnDetail: '', itemCode: 'ITEM-A')],
      );

      final result = refreshDnDetails(slip, dn);

      expect(result.changed, isTrue);
      expect(result.items.first.dnDetail, equals('new-row-name'));
    });

    test('returns changed=true and patches stale dn_detail', () {
      final dn = DeliveryNote(
        name: 'DN-001', customer: '', grandTotal: 0, postingDate: '',
        modified: '', creation: '', status: 'Submitted', currency: 'AED',
        totalQty: 5, docstatus: 1,
        items: [_dnItem(name: 'new-row-name', itemCode: 'ITEM-A')],
      );
      final slip = PackingSlip(
        name: 'PS-001', deliveryNote: 'DN-001', modified: '', creation: '',
        docstatus: 0, status: 'Draft',
        items: [_slipItem(dnDetail: 'stale-old-row', itemCode: 'ITEM-A')],
      );

      final result = refreshDnDetails(slip, dn);

      expect(result.changed, isTrue);
      expect(result.items.first.dnDetail, equals('new-row-name'));
    });

    test('returns changed=false when no match is found for an empty dn_detail', () {
      final dn = DeliveryNote(
        name: 'DN-001', customer: '', grandTotal: 0, postingDate: '',
        modified: '', creation: '', status: 'Submitted', currency: 'AED',
        totalQty: 5, docstatus: 1,
        items: [_dnItem(name: 'row-B', itemCode: 'ITEM-B')],
      );
      final slip = PackingSlip(
        name: 'PS-001', deliveryNote: 'DN-001', modified: '', creation: '',
        docstatus: 0, status: 'Draft',
        items: [_slipItem(dnDetail: '', itemCode: 'ITEM-A')],
      );

      final result = refreshDnDetails(slip, dn);

      expect(result.changed, isFalse);
      expect(result.items.first.dnDetail, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they pass (pure-logic tests, no GetX)**

Run:
```bash
flutter test test/unit/packing_slip_refresh_dn_details_test.dart -v
```
Expected: all 4 tests PASS (pure Dart logic — no GetX dependency).

- [ ] **Step 3: Add `_checkForChanges()` call in `_refreshDnDetails`**

In `lib/app/modules/packing_slip/form/packing_slip_form_controller.dart`, find the end of `_refreshDnDetails` (around line 372). The current last block is:

```dart
    if (changed) packingSlip.value = slip.copyWith(items: patched);
  }
```

Replace it with:

```dart
    if (changed) {
      packingSlip.value = slip.copyWith(items: patched);
      _checkForChanges();
    }
  }
```

This triggers the dirty-state check immediately after patching so `isDirty` reflects that `packingSlip.value` now differs from `_originalJson` (which was anchored to the raw server data before the DN detail repair).

- [ ] **Step 4: Run `flutter analyze`**

```bash
flutter analyze lib/app/modules/packing_slip/form/packing_slip_form_controller.dart
```
Expected: no new warnings or errors.

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/packing_slip/form/packing_slip_form_controller.dart \
        test/unit/packing_slip_refresh_dn_details_test.dart
git commit -m "fix(packing-slip): mark dirty after _refreshDnDetails patches stale dn_detail on reload"
```

---

## Task 3: Show ERPNext row index (`idx`) in the checklist row

**Context:** Each `DeliveryNoteItem` carries an `idx` field (the ERPNext 1-based row number from the DN items child table). The `_buildChecklistRow` in `packing_slip_form_screen.dart` shows `itemCode` and `itemName` but omits `idx`, making it hard to cross-reference the app row with the ERPNext document row for support/traceability.

**Files:**
- Modify: `lib/app/modules/packing_slip/form/packing_slip_form_screen.dart:361-381`

- [ ] **Step 1: Locate the "Details" column in `_buildChecklistRow`**

Open `lib/app/modules/packing_slip/form/packing_slip_form_screen.dart`. Find the `Expanded` child of the `Row` inside `_buildChecklistRow` — this is the column that shows `itemCode`, `itemName`, and optionally `batchNo`:

```dart
// Details
Expanded(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        dnItem.itemCode,
        style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14),
      ),
      Text(
        dnItem.itemName,
        style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      if (dnItem.batchNo != null)
        Text(
          'Batch: ${dnItem.batchNo}',
          style: TextStyle(
              fontSize: 11,
              color: Colors.blueGrey.shade700),
        ),
    ],
  ),
),
```

- [ ] **Step 2: Add the `idx` row below `itemName`**

Add a `Text` widget for the row index immediately after the `itemName` Text. `idx` can be null for items fetched before the field was added; show nothing when it is.

Replace the entire `Expanded` block above with:

```dart
// Details
Expanded(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        dnItem.itemCode,
        style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14),
      ),
      Text(
        dnItem.itemName,
        style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      if (dnItem.idx != null)
        Text(
          'Row #${dnItem.idx}',
          style: TextStyle(
              fontSize: 11,
              color: Colors.indigo.shade400),
        ),
      if (dnItem.batchNo != null)
        Text(
          'Batch: ${dnItem.batchNo}',
          style: TextStyle(
              fontSize: 11,
              color: Colors.blueGrey.shade700),
        ),
    ],
  ),
),
```

- [ ] **Step 3: Verify with `flutter analyze`**

Run:
```bash
flutter analyze lib/app/modules/packing_slip/form/packing_slip_form_screen.dart
```
Expected: no new warnings or errors.

- [ ] **Step 4: Commit**

```bash
git add lib/app/modules/packing_slip/form/packing_slip_form_screen.dart
git commit -m "feat(packing-slip): show ERPNext row idx in checklist row for traceability"
```

---

## Self-Review

### Spec coverage

| Requirement | Task |
|-------------|------|
| Show Save icon for existing (non-dirty) draft documents | Task 1 |
| After reload: fix missing DN reference, mark dirty, enable Save | Task 2 |
| Show ERPNext Row # in expanded group card checklist rows | Task 3 |

All three requirements are covered.

### Placeholder scan

No TBD/TODO/placeholder content present.

### Type consistency

- `dnItem` in `_buildChecklistRow` is typed as `dynamic` in the method signature but is always a `DeliveryNoteItem` at call sites. `dnItem.idx` is `int?` on `DeliveryNoteItem` — `if (dnItem.idx != null)` is correct.
- `_refreshDnDetails` is a `void` method; `_checkForChanges()` is also `void`. The call compiles without any type mismatch.
- Task 2 test file uses a top-level `refreshDnDetails` helper that mirrors the controller's private algorithm — no shared types to drift.
