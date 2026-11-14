# Packing Slip Multi-Serial Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Packing Slip item sheet lists all invoice serials whose DN rows match the scanned/tapped item, marks fully-packed serials "Full" (disabled), and re-targets the sheet to the chosen serial's DN row.

**Architecture:** Child-driven re-targeting. A pure option builder (`buildPsSerialOptions`) derives the serial list; the PS sheet child controller exposes it through existing `SerialFieldMixin` hooks; a `Worker` on `selectedSerial` asks the parent to re-seed the sheet session (dnDetail, qty cap, batch) on selection. `SharedInvoiceSerialNumberField` is reused, with one new gate (`supportsAllowFullToggle`) to suppress the Allow Full toggle in PS.

**Tech Stack:** Flutter, GetX, flutter_test. Spec: `docs/superpowers/specs/2026-06-12-ps-multi-serial-picker-design.md`.

**Precondition:** Commit the pending scan auto-advance fix first (working tree contains uncommitted `dn_scan_item_matcher.dart` + controller wiring + tests):

```bash
git add lib/app/modules/packing_slip/form/dn_scan_item_matcher.dart lib/app/modules/packing_slip/form/packing_slip_form_controller.dart test/unit/packing_slip_scan_item_matcher_test.dart
git commit -m "fix(packing-slip): advance scan to next invoice-serial DN row when first is fully packed"
```

---

### Task 1: Pure option builder `buildPsSerialOptions`

**Files:**
- Create: `lib/app/modules/packing_slip/form/ps_serial_options.dart`
- Test: `test/unit/ps_serial_options_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
// test/unit/ps_serial_options_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/modules/packing_slip/form/ps_serial_options.dart';

void main() {
  group('buildPsSerialOptions', () {
    DeliveryNoteItem dnItem({
      required String name,
      required String itemCode,
      String? serial = '1',
      String? batchNo,
      double qty = 12.0,
    }) =>
        DeliveryNoteItem(
          name: name,
          itemCode: itemCode,
          qty: qty,
          rate: 10.0,
          customInvoiceSerialNumber: serial,
          docstatus: 1,
          batchNo: batchNo,
        );

    test('returns one option per matching serial sorted numerically', () {
      final items = [
        dnItem(name: 'r10', itemCode: 'ITEM-A', serial: '10'),
        dnItem(name: 'r2', itemCode: 'ITEM-A', serial: '2'),
        dnItem(name: 'rB', itemCode: 'ITEM-B', serial: '1'),
      ];

      final options = buildPsSerialOptions(
        items: items,
        code: 'ITEM-A',
        batch: null,
        remainingQty: (i) => 12.0,
      );

      expect(options.map((o) => o.serial).toList(), equals(['2', '10']));
      expect(options.first.dnRow.name, equals('r2'));
    });

    test('excludes rows with null, empty, or sentinel "0" serials', () {
      final items = [
        dnItem(name: 'r1', itemCode: 'ITEM-A', serial: '1'),
        dnItem(name: 'r0', itemCode: 'ITEM-A', serial: '0'),
        dnItem(name: 'rEmpty', itemCode: 'ITEM-A', serial: ''),
        dnItem(name: 'rNull', itemCode: 'ITEM-A', serial: null),
      ];

      final options = buildPsSerialOptions(
        items: items,
        code: 'ITEM-A',
        batch: null,
        remainingQty: (i) => 12.0,
      );

      expect(options.map((o) => o.serial).toList(), equals(['1']));
    });

    test('filters by batch when a batch is scanned', () {
      final items = [
        dnItem(name: 'rX', itemCode: 'ITEM-A', serial: '1', batchNo: 'BATCH-X'),
        dnItem(name: 'rY', itemCode: 'ITEM-A', serial: '2', batchNo: 'BATCH-Y'),
      ];

      final options = buildPsSerialOptions(
        items: items,
        code: 'ITEM-A',
        batch: 'BATCH-Y',
        remainingQty: (i) => 12.0,
      );

      expect(options.map((o) => o.serial).toList(), equals(['2']));
    });

    test('carries DN row qty and remaining per option', () {
      final items = [
        dnItem(name: 'r1', itemCode: 'ITEM-A', serial: '1', qty: 12.0),
        dnItem(name: 'r2', itemCode: 'ITEM-A', serial: '2', qty: 5.0),
      ];

      final options = buildPsSerialOptions(
        items: items,
        code: 'ITEM-A',
        batch: null,
        remainingQty: (i) => i.name == 'r1' ? 0.0 : 5.0,
      );

      expect(options[0].qty, equals(12.0));
      expect(options[0].remaining, equals(0.0));
      expect(options[1].qty, equals(5.0));
      expect(options[1].remaining, equals(5.0));
    });

    test('dedupes same-serial rows preferring the one with remaining', () {
      final items = [
        dnItem(name: 'full', itemCode: 'ITEM-A', serial: '1', batchNo: 'X'),
        dnItem(name: 'open', itemCode: 'ITEM-A', serial: '1', batchNo: 'Y'),
      ];

      final options = buildPsSerialOptions(
        items: items,
        code: 'ITEM-A',
        batch: null,
        remainingQty: (i) => i.name == 'open' ? 3.0 : 0.0,
      );

      expect(options, hasLength(1));
      expect(options.single.dnRow.name, equals('open'));
    });

    test('dedupe falls back to first row when all exhausted', () {
      final items = [
        dnItem(name: 'a', itemCode: 'ITEM-A', serial: '1', batchNo: 'X'),
        dnItem(name: 'b', itemCode: 'ITEM-A', serial: '1', batchNo: 'Y'),
      ];

      final options = buildPsSerialOptions(
        items: items,
        code: 'ITEM-A',
        batch: null,
        remainingQty: (i) => 0.0,
      );

      expect(options.single.dnRow.name, equals('a'));
    });

    test('returns empty list when nothing matches', () {
      final options = buildPsSerialOptions(
        items: [dnItem(name: 'r1', itemCode: 'ITEM-A')],
        code: 'ITEM-Z',
        batch: null,
        remainingQty: (i) => 12.0,
      );

      expect(options, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run tests, verify they fail (file/function missing)**

Run: `flutter test test/unit/ps_serial_options_test.dart`
Expected: compile error — `ps_serial_options.dart` does not exist.

- [ ] **Step 3: Implement**

```dart
// lib/app/modules/packing_slip/form/ps_serial_options.dart
import 'package:collection/collection.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';

/// One selectable invoice serial in the Packing Slip item sheet dropdown.
class PsSerialOption {
  /// Invoice serial string (DropdownMenuItem value).
  final String serial;

  /// Representative DN row for this serial — the row the sheet re-targets
  /// to when this serial is selected.
  final DeliveryNoteItem dnRow;

  /// DN row qty (the "×N" shown in the dropdown row).
  final double qty;

  /// Remaining unpacked qty for [dnRow]; <= 0 marks the row Full.
  final double remaining;

  const PsSerialOption({
    required this.serial,
    required this.dnRow,
    required this.qty,
    required this.remaining,
  });
}

/// Builds the ordered serial options for the item sheet.
///
/// Filtering: rows must match [code], match [batch] when one was scanned,
/// and carry a real serial (non-null, non-empty, not the '0' sentinel).
/// Dropdown values must be unique, so same-serial rows are deduped: the
/// first row with remaining > 0 wins, else the first row — mirroring
/// [findScannedDnItem]. Sorted ascending by numeric serial (non-numeric
/// serials sort last, matching _allDnSerials).
List<PsSerialOption> buildPsSerialOptions({
  required List<DeliveryNoteItem> items,
  required String code,
  required String? batch,
  required double Function(DeliveryNoteItem) remainingQty,
}) {
  final matches = items.where((item) {
    final serial = item.customInvoiceSerialNumber;
    final codeMatch = item.itemCode == code;
    final batchMatch = (batch == null) || (item.batchNo == batch);
    final serialValid = serial != null && serial.isNotEmpty && serial != '0';
    return codeMatch && batchMatch && serialValid;
  });

  final bySerial =
      groupBy(matches, (DeliveryNoteItem i) => i.customInvoiceSerialNumber!);

  return bySerial.entries.map((entry) {
    final rows = entry.value;
    final row = rows.firstWhereOrNull((r) => remainingQty(r) > 0) ?? rows.first;
    return PsSerialOption(
      serial: entry.key,
      dnRow: row,
      qty: row.qty,
      remaining: remainingQty(row),
    );
  }).toList()
    ..sort((a, b) => (int.tryParse(a.serial) ?? 9999)
        .compareTo(int.tryParse(b.serial) ?? 9999));
}
```

- [ ] **Step 4: Run tests, verify they pass**

Run: `flutter test test/unit/ps_serial_options_test.dart`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/packing_slip/form/ps_serial_options.dart test/unit/ps_serial_options_test.dart
git commit -m "feat(packing-slip): pure serial-option builder for multi-serial item sheet"
```

---

### Task 2: `supportsAllowFullToggle` gate in mixin + widget

**Files:**
- Modify: `lib/app/shared/item_sheet/serial_field_mixin.dart` (after the `allowFullSerials` field, ~line 129)
- Modify: `lib/app/shared/item_sheet/widgets/shared_invoice_serial_number_field.dart:223-237`
- Test: `test/widget/shared_invoice_serial_field_toggle_test.dart`

- [ ] **Step 1: Write the failing widget test**

```dart
// test/widget/shared_invoice_serial_field_toggle_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/shared/item_sheet/serial_field_mixin.dart';
import 'package:multimax/app/shared/item_sheet/serial_number_field_delegate.dart';
import 'package:multimax/app/shared/item_sheet/widgets/shared_invoice_serial_number_field.dart';

class _FakeSerialController extends GetxController with SerialFieldMixin {
  _FakeSerialController({this.supportsToggle = true});

  final bool supportsToggle;

  @override
  bool get supportsAllowFullToggle => supportsToggle;

  @override
  List<String> get availableSerialNos => ['1', '2'];

  @override
  double posItemQtyForSerial(String serial) => 10.0;

  @override
  SerialDropdownItem? posDropdownItemFor(String serial) => SerialDropdownItem(
        serial: serial,
        itemName: 'Item $serial',
        qty: 10.0,
        remaining: serial == '1' ? 0.0 : 10.0, // serial 1 is Full
        used: serial == '1' ? 10.0 : 0.0,
      );
}

Widget _host(SerialNumberFieldDelegate c) => MaterialApp(
      home: Scaffold(
        body: SharedInvoiceSerialNumberField(c: c),
      ),
    );

void main() {
  testWidgets('Allow Full toggle shown for default adopters with a Full row',
      (tester) async {
    final c = _FakeSerialController(supportsToggle: true);
    await tester.pumpWidget(_host(c));
    expect(find.text('Allow Full'), findsOneWidget);
  });

  testWidgets('Allow Full toggle hidden when supportsAllowFullToggle is false',
      (tester) async {
    final c = _FakeSerialController(supportsToggle: false);
    await tester.pumpWidget(_host(c));
    expect(find.text('Allow Full'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test — first expectation passes, second fails**

Run: `flutter test test/widget/shared_invoice_serial_field_toggle_test.dart`
Expected: compile error — `supportsAllowFullToggle` is not defined on the mixin
(correct failure: feature missing).

- [ ] **Step 3: Implement mixin getter + widget gate**

In `serial_field_mixin.dart`, after the `allowFullSerials` field:

```dart
  /// Whether [SharedInvoiceSerialNumberField] should offer the "Allow Full"
  /// override toggle when a Full serial exists.
  ///
  /// DN/SE keep the default (true). Packing Slip overrides to false: its qty
  /// cap treats 0 remaining as "uncapped", so selecting a Full serial could
  /// over-pack the DN row. Full rows stay hard-disabled there.
  bool get supportsAllowFullToggle => true;
```

In `shared_invoice_serial_number_field.dart`, replace lines 223-237 block:

```dart
      final serialMixin = c is SerialFieldMixin ? c as SerialFieldMixin : null;
      final supportsToggle = serialMixin?.supportsAllowFullToggle ?? false;
      final allowFull =
          supportsToggle && (serialMixin?.allowFullSerials.value ?? false);
      final anyFull = dropdownItems.any((i) => i.isFull);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Serial dropdown inside its own tinted container ─────────────
          GlobalItemFormSheet.buildInputGroup(
            label: label,
            color: accentColor,
            labelTrailing: anyFull && serialMixin != null && supportsToggle
                ? _AllowFullToggle(c: serialMixin, accentColor: accentColor)
                : null,
```

(The `allowFull` local already feeds `_buildItems(dropdownItems, allowFull: allowFull)` — unchanged below this point. The old `if (c is SerialFieldMixin) { (c as SerialFieldMixin).serialItemsStamp.value; }` reactive read becomes `serialMixin?.serialItemsStamp.value;`.)

- [ ] **Step 4: Run the widget test + existing suite for regressions**

Run: `flutter test test/widget/shared_invoice_serial_field_toggle_test.dart test/unit/allow_full_serial_toggle_test.dart`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add lib/app/shared/item_sheet/serial_field_mixin.dart lib/app/shared/item_sheet/widgets/shared_invoice_serial_number_field.dart test/widget/shared_invoice_serial_field_toggle_test.dart
git commit -m "feat(item-sheet): supportsAllowFullToggle gate on serial field"
```

---

### Task 3: Parent controller — session context + retarget

**Files:**
- Modify: `lib/app/modules/packing_slip/form/packing_slip_form_controller.dart`

No isolated unit test (controller constructs GetX services in field initializers);
covered by Task 1 unit tests, `flutter analyze`, and existing suite.

- [ ] **Step 1: Add import + session fields**

Import (with the other module imports):

```dart
import 'package:multimax/app/modules/packing_slip/form/ps_serial_options.dart';
```

Near `currentSerial` (~line 97), add:

```dart
  /// Batch from the scan result that opened the sheet; null for tap-to-add.
  /// Narrows the serial options to rows of the scanned batch.
  String? currentScannedBatch;

  /// Reactive batch for the sheet's BatchDisplayTile — re-seeded when the
  /// sheet is re-targeted to a different serial's DN row.
  final bsBatchNo = RxnString();
```

- [ ] **Step 2: Seed `bsBatchNo` in `_populateItemDetails`**

```dart
  void _populateItemDetails(DeliveryNoteItem item) {
    currentItemDnDetail  = item.name;
    currentItemCode      = item.itemCode;
    currentItemName      = item.itemName;
    currentBatchNo       = item.batchNo;
    bsBatchNo.value      = item.batchNo;
    currentUom           = item.uom;
    currentSerial        = item.customInvoiceSerialNumber;
    currentNetWeight     = 0.0;
    currentWeightUom     = 0.0;
  }
```

- [ ] **Step 3: Thread `scannedBatch` through `prepareSheetForAdd`**

```dart
  void prepareSheetForAdd(DeliveryNoteItem item, {String? scannedBatch}) {
    if (_isSheetAlreadyOpen()) return;
    currentScannedBatch = scannedBatch;
    _resetSessionForAdd(item);
    final remaining = _calcRemainingQtyForDnItem(item);
    _seedSheetQty(maxQty: remaining);
    final child = _wireChildForAdd(item);
    _openItemSheet(child);
  }
```

In `_handleScanResult`, pass the scanned batch:

```dart
    if (match != null) {
      prepareSheetForAdd(match, scannedBatch: result.batchNo);
    } else {
```

In `editItem`, clear it (edit mode never filters by scan):

```dart
      _resetSessionForEdit(item, dnItem);
      currentScannedBatch = null;
```

- [ ] **Step 4: Add `serialOptionsForSheet` and `retargetSheetToSerial`**

Place after `posQtyCapForSerial`:

```dart
  // ── Multi-serial sheet options ─────────────────────────────────────────────

  /// Ordered serial options for the open item sheet — one per invoice serial
  /// whose DN row matches the current item (and scanned batch, when present).
  ///
  /// In edit mode the row being edited is excluded from "packed" so its own
  /// qty does not mark its serial Full (mirrors the DN dropdown semantics).
  List<PsSerialOption> serialOptionsForSheet() {
    final dn = linkedDeliveryNote.value;
    final code = currentItemCode;
    if (dn == null || code == null) return const [];
    return buildPsSerialOptions(
      items: dn.items,
      code: code,
      batch: currentScannedBatch,
      remainingQty: (row) => _calcRemainingQtyForDnItem(
        row,
        excludeSlipItemName: isEditing.value ? currentItemNameKey : null,
      ),
    );
  }

  /// Re-seeds the open add-mode sheet session to [serial]'s DN row:
  /// dnDetail, batch, uom, serial context, and the qty cap. The child
  /// controller re-prefills its qty field afterwards.
  void retargetSheetToSerial(String serial) {
    final option = serialOptionsForSheet()
        .firstWhereOrNull((o) => o.serial == serial);
    if (option == null) return;
    _populateItemDetails(option.dnRow);
    bsMaxQty.value = option.remaining;
  }
```

- [ ] **Step 5: Reactive custom fields in `_buildItemSheetCustomFields`**

```dart
  List<Widget> _buildItemSheetCustomFields(
      PackingSlipItemFormController child,
      ) {
    final fields = <Widget>[];

    // Reactive: re-targeting the sheet to another serial's DN row can change
    // (or clear) the batch — the tile follows bsBatchNo.
    fields.add(Obx(() {
      final batch = bsBatchNo.value;
      if (batch == null || batch.isEmpty) return const SizedBox.shrink();
      return BatchDisplayTile(batchNo: batch);
    }));

    if (_shouldShowSerialBadge()) {
      final serial = currentSerial!;
      fields.add(
        SharedInvoiceSerialNumberField(
          c:           child,
          accentColor: Colors.teal,
          label:       'Invoice Serial No',
          hint:        serial,
          // Read the live selection — the open-time serial is only the
          // fallback before anything is selected.
          posItemQtyOverride: () =>
              posQtyCapForSerial(child.selectedSerial.value ?? serial),
        ),
      );
    }

    return fields;
  }
```

- [ ] **Step 6: Analyze**

Run: `flutter analyze 2>&1 | Select-String -Pattern 'packing_slip|ps_serial'`
Expected: only the four pre-existing warnings in `packing_slip_form_controller.dart`
(unused `_storageService`, unused `_isQtyInvalid`, invalid_null_aware_operator ~483,
dead_null_aware_expression ~664). No new diagnostics.

- [ ] **Step 7: Commit**

```bash
git add lib/app/modules/packing_slip/form/packing_slip_form_controller.dart
git commit -m "feat(packing-slip): serial-option session context and sheet re-targeting"
```

---

### Task 4: Child controller — multi-serial hooks + retarget worker

**Files:**
- Modify: `lib/app/modules/packing_slip/form/packing_slip_item_form_controller.dart`

- [ ] **Step 1: Add imports**

```dart
import 'package:collection/collection.dart';
import 'package:multimax/app/modules/packing_slip/form/ps_serial_options.dart';
import 'package:multimax/app/shared/item_sheet/serial_number_field_delegate.dart';
```

- [ ] **Step 2: Suppress Allow Full + worker field**

In the class body (near the parent reference):

```dart
  /// PS hard-disables Full serials — see SerialFieldMixin.supportsAllowFullToggle.
  @override
  bool get supportsAllowFullToggle => false;

  /// Retargets the parent sheet session when the user picks another serial.
  /// Stored so it can be cancelled in [onClose] (project Worker rule).
  Worker? _serialRetargetWorker;
```

- [ ] **Step 3: Replace `availableSerialNos` and add `posDropdownItemFor`**

```dart
  @override
  List<String> get availableSerialNos {
    if (_parent.posUpload.value == null) return [];
    if (editingItemName.value != null) {
      // Edit mode: locked to the existing row's serial.
      final serial = _parent.currentSerial;
      if (serial == null || serial.isEmpty || serial == '0') return [];
      return [serial];
    }
    return _parent.serialOptionsForSheet().map((o) => o.serial).toList();
  }

  // ── SerialFieldMixin: rich dropdown row metadata ───────────────────────────
  //
  // qty/remaining describe the serial's DN row (not the POS cap): a serial is
  // "Full" when its DN row is fully packed across current + related slips.
  @override
  SerialDropdownItem? posDropdownItemFor(String serial) {
    final option = _parent
        .serialOptionsForSheet()
        .firstWhereOrNull((o) => o.serial == serial);
    if (option == null) return null;

    final posName = _parent.getPosItemName(serial);
    return SerialDropdownItem(
      serial:    serial,
      itemName:  posName.isNotEmpty ? posName : option.dnRow.itemName,
      qty:       option.qty,
      remaining: option.remaining,
      used:      option.qty - option.remaining,
    );
  }
```

- [ ] **Step 4: Retarget worker + qty prefill helper + onClose**

```dart
  // ── Serial retarget wiring ─────────────────────────────────────────────────

  /// Add-mode only: when the user selects a different serial, re-seed the
  /// parent session to that serial's DN row and re-prefill qty with the new
  /// remaining. Safe against auto-submit: programmatic qty writes reset
  /// saveButtonState to idle via _resetSaveStateOnEdit.
  void _wireSerialRetarget() {
    _serialRetargetWorker = ever(selectedSerial, (String? serial) {
      if (serial == null || serial.isEmpty) return;
      if (serial == _parent.currentSerial) return;
      _parent.retargetSheetToSerial(serial);
      _prefillQtyFromRemaining();
      notifySerialItemsChanged();
      validateSheet();
    });
  }

  /// Pre-fills qty with the parent's current remaining cap (same formatting
  /// as _populateAddFields).
  void _prefillQtyFromRemaining() {
    final remaining = _parent.bsMaxQty.value;
    qtyController.text = remaining > 0
        ? (remaining % 1 == 0
            ? remaining.toInt().toString()
            : remaining.toString())
        : '0';
  }

  @override
  void onClose() {
    _serialRetargetWorker?.dispose();
    super.onClose();
  }
```

In `initialise`, wire the worker after `_populateFields` (so the seed in
`_seedSerial` and the editing flag are already set) and only in add mode:

```dart
  void initialise({
    required PackingSlipFormController parent,
    required String itemCode,
    required String itemName,
    String itemGroup = '',
    String variantOf = '',
    PackingSlipItem? editingItem,
  }) {
    _bindParent(parent);
    _seedItemIdentity(
      itemCode:  itemCode,
      itemName:  itemName,
      itemGroup: itemGroup,
      variantOf: variantOf,
    );
    _seedSerial(parent);
    _populateFields(editingItem: editingItem, parent: parent);
    if (editingItem == null) _wireSerialRetarget();
    _finaliseInit();
  }
```

Also reuse `_prefillQtyFromRemaining` inside `_populateAddFields` (DRY):

```dart
  void _populateAddFields(PackingSlipFormController parent) {
    editingItemName.value = null;
    itemOwner.value       = null;
    itemCreation.value    = null;
    itemModified.value    = null;
    itemModifiedBy.value  = null;
    _prefillQtyFromRemaining();
  }
```

- [ ] **Step 5: Analyze + full packing-slip and serial test files**

Run: `flutter analyze 2>&1 | Select-String -Pattern 'packing_slip|ps_serial|serial_field|shared_invoice'`
Expected: only the four pre-existing controller warnings.

Run: `flutter test test/unit/ps_serial_options_test.dart test/unit/packing_slip_scan_item_matcher_test.dart test/unit/packing_slip_refresh_dn_details_test.dart test/unit/allow_full_serial_toggle_test.dart test/widget/shared_invoice_serial_field_toggle_test.dart`
Expected: All pass.

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/packing_slip/form/packing_slip_item_form_controller.dart
git commit -m "feat(packing-slip): multi-serial dropdown with Full-row lockout in item sheet"
```

---

### Task 5: Full verification

- [ ] **Step 1: Full test suite**

Run: `flutter test`
Expected: same pass/fail profile as branch HEAD — the only failures are the 8
pre-existing ones in `test/unit/status_pill_colour_test.dart` (7) and
`test/widget/doctype_form_header_test.dart` (1), confirmed unrelated on 2026-06-12.

- [ ] **Step 2: Commit docs**

```bash
git add docs/superpowers/specs/2026-06-12-ps-multi-serial-picker-design.md docs/superpowers/plans/2026-06-12-ps-multi-serial-picker.md
git commit -m "docs(packing-slip): multi-serial picker spec and implementation plan"
```

(Device smoke test — scan item with 2+ serials, switch serial in sheet, verify
Full row disabled and packed row lands on the chosen serial — tracked in memory
as pending.)
