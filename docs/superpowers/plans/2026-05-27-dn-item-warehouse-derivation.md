# DN Item Form: Per-Item Warehouse Derivation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `warehouse` field to `DeliveryNoteItem` that is derived from the scanned rack code and included in the Frappe API payload for each item row.

**Architecture:** Add `itemWarehouse: RxnString` to `DeliveryNoteItemFormController`; `applyRackScan` derives the warehouse synchronously via `RackLocation.tryParse(code)?.warehouseName` and writes it to `itemWarehouse`; `_buildItem` reads it when constructing `DeliveryNoteItem`; the parent form controller's `_buildItem` derives it inline for the direct-scan path; `DerivedWarehouseLabel` (moved to shared) shows it in the item sheet UI. Remove the never-wired `bsItemWarehouse` field from the parent controller.

**Tech Stack:** Flutter/Dart, GetX (`RxnString`, `Get.put`), `RackLocation.tryParse`, `flutter_test`

**Spec:** `docs/superpowers/specs/2026-05-27-dn-item-warehouse-derivation-design.md`

---

## File Map

| Action | File |
|--------|------|
| Move   | `lib/app/modules/stock_entry/form/widgets/item_form_sheet/derived_warehouse_label.dart` → `lib/app/shared/item_sheet/derived_warehouse_label.dart` |
| Modify | `lib/app/data/models/delivery_note_model.dart` |
| Create | `test/unit/dn_item_warehouse_field_test.dart` |
| Modify | `lib/app/modules/delivery_note/form/delivery_note_item_form_controller.dart` |
| Create | `test/unit/dn_item_form_controller_warehouse_test.dart` |
| Modify | `lib/app/modules/delivery_note/form/delivery_note_form_controller.dart` |

---

## Task 1: Move `DerivedWarehouseLabel` to shared

The widget currently lives in the SE module folder and is not imported anywhere. Move it to `lib/app/shared/item_sheet/` so DN can use it without a cross-module import.

**Files:**
- Create: `lib/app/shared/item_sheet/derived_warehouse_label.dart`
- Modify: `lib/app/modules/stock_entry/form/widgets/item_form_sheet/derived_warehouse_label.dart` (convert to export stub)

- [ ] **Step 1: Write the new file at the shared path**

Create `lib/app/shared/item_sheet/derived_warehouse_label.dart` with this exact content:

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Priority cascade: itemWarehouse → derivedWarehouse → headerWarehouse.
/// Renders nothing when no warehouse is resolved.
class DerivedWarehouseLabel extends StatelessWidget {
  final RxnString itemWarehouse;
  final RxnString derivedWarehouse;
  final RxnString headerWarehouse;

  const DerivedWarehouseLabel({
    super.key,
    required this.itemWarehouse,
    required this.derivedWarehouse,
    required this.headerWarehouse,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final itemWh    = itemWarehouse.value;
      final derivedWh = derivedWarehouse.value;
      final headerWh  = headerWarehouse.value;

      String? text;
      if (itemWh != null && itemWh.isNotEmpty) {
        text = 'Warehouse: $itemWh (auto from rack)';
      } else if (derivedWh != null && derivedWh.isNotEmpty) {
        text = 'Warehouse: $derivedWh (auto from rack)';
      } else if (headerWh != null && headerWh.isNotEmpty) {
        text = 'Warehouse: $headerWh (from header)';
      }

      if (text == null) return const SizedBox.shrink();

      return Padding(
        padding: const EdgeInsets.only(left: 4.0, bottom: 12.0),
        child: Text(
          text,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
        ),
      );
    });
  }
}
```

- [ ] **Step 2: Convert the old SE file to an export stub**

Replace the entire content of `lib/app/modules/stock_entry/form/widgets/item_form_sheet/derived_warehouse_label.dart` with:

```dart
// Moved to shared — import from the shared path instead.
export 'package:multimax/app/shared/item_sheet/derived_warehouse_label.dart';
```

- [ ] **Step 3: Run analyze to verify no errors**

```
flutter analyze
```

Expected: no new errors or warnings.

- [ ] **Step 4: Commit**

```
git add lib/app/shared/item_sheet/derived_warehouse_label.dart lib/app/modules/stock_entry/form/widgets/item_form_sheet/derived_warehouse_label.dart
git commit -m "refactor(derived-warehouse-label): move widget to shared/item_sheet"
```

---

## Task 2: `DeliveryNoteItem` model — add `warehouse` field

**Files:**
- Modify: `lib/app/data/models/delivery_note_model.dart:127-265`
- Create: `test/unit/dn_item_warehouse_field_test.dart`

**Context:**
`DeliveryNoteItem` starts at line 127 of `delivery_note_model.dart`. Its constructor lists fields starting at line 150, `fromJson` at line 174, `toJson` at line 202, `copyWith` at line 218.

- [ ] **Step 1: Write the failing tests**

Create `test/unit/dn_item_warehouse_field_test.dart`:

```dart
// test/unit/dn_item_warehouse_field_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';

void main() {
  group('DeliveryNoteItem.warehouse field', () {
    test('T-1: fromJson reads warehouse when present', () {
      final item = DeliveryNoteItem.fromJson({
        'item_code': 'ITEM-001',
        'qty': 1.0,
        'rate': 0.0,
        'warehouse': 'WH-DXB1 - KA',
      });
      expect(item.warehouse, equals('WH-DXB1 - KA'));
    });

    test('T-2: fromJson returns null warehouse when key is absent', () {
      final item = DeliveryNoteItem.fromJson({
        'item_code': 'ITEM-001',
        'qty': 1.0,
        'rate': 0.0,
      });
      expect(item.warehouse, isNull);
    });

    test('T-3: toJson includes warehouse key when non-null', () {
      final item = DeliveryNoteItem(
        itemCode: 'ITEM-001',
        qty: 1.0,
        rate: 0.0,
        warehouse: 'WH-DXB1 - KA',
      );
      expect(item.toJson()['warehouse'], equals('WH-DXB1 - KA'));
    });

    test('T-4: toJson omits warehouse key when null', () {
      final item = DeliveryNoteItem(
        itemCode: 'ITEM-001',
        qty: 1.0,
        rate: 0.0,
      );
      expect(item.toJson().containsKey('warehouse'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```
flutter test test/unit/dn_item_warehouse_field_test.dart -v
```

Expected: 4 failures — `The named parameter 'warehouse' isn't defined` or similar.

- [ ] **Step 3: Add `warehouse` to the class field declaration (line 148, after `docstatus`)**

In `lib/app/data/models/delivery_note_model.dart`, add `final String? warehouse;` after `final int docstatus;` (line 148):

```dart
  final int docstatus;
  final String? warehouse;
```

- [ ] **Step 4: Add `warehouse` to the constructor (line 171, after `docstatus = 0`)**

```dart
    this.docstatus = 0,
    this.warehouse,
  });
```

- [ ] **Step 5: Add `warehouse` to `fromJson` (line 199, after the `docstatus` line)**

```dart
      docstatus: DeliveryNote._parseInt(json['docstatus']),
      warehouse: json['warehouse'] as String?,
    );
```

- [ ] **Step 6: Add conditional `warehouse` write to `toJson` (line 212, after the existing `name` guard)**

```dart
    if (name != null && !name!.startsWith('local_')) {
      data['name'] = name;
    }
    if (warehouse != null) {
      data['warehouse'] = warehouse;
    }
    return data;
```

- [ ] **Step 7: Add `warehouse` to `copyWith` parameter list (line 239, after `docstatus`)**

```dart
    int? docstatus,
    String? warehouse,
  }) {
```

- [ ] **Step 8: Add `warehouse` to `copyWith` body (line 264, after `docstatus` line)**

```dart
      docstatus: docstatus ?? this.docstatus,
      warehouse: warehouse ?? this.warehouse,
    );
```

- [ ] **Step 9: Run tests to verify they pass**

```
flutter test test/unit/dn_item_warehouse_field_test.dart -v
```

Expected: `+4: All tests passed!`

- [ ] **Step 10: Run the full suite to catch regressions**

```
flutter test
```

Expected: all tests pass (count increases by 4).

- [ ] **Step 11: Commit**

```
git add lib/app/data/models/delivery_note_model.dart test/unit/dn_item_warehouse_field_test.dart
git commit -m "feat(dn-model): add warehouse field to DeliveryNoteItem"
```

---

## Task 3: `DeliveryNoteItemFormController` — add `itemWarehouse`

**Files:**
- Modify: `lib/app/modules/delivery_note/form/delivery_note_item_form_controller.dart`
- Create: `test/unit/dn_item_form_controller_warehouse_test.dart`

**Context:**
- `resolvedWarehouse` getter: lines 107–109
- `_resetValidationState`: lines 544–556
- `_seedEditFieldControllers`: lines 631–637
- `_buildItem` (item controller): lines 803–819
- `applyRackScan`: lines 1025–1029
- `clearAll`: lines 1031–1040
- `rackStockMapRx` field declaration: line 93 (add `itemWarehouse` after this)
- Imports block: lines 1–26 (add `rack_location.dart` import)

- [ ] **Step 1: Write the failing tests**

Create `test/unit/dn_item_form_controller_warehouse_test.dart`:

```dart
// test/unit/dn_item_form_controller_warehouse_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_item_form_controller.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Stub path_provider so ApiProvider._initDio() does not throw in
    // the headless test environment (no platform plugins available).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => '/tmp/test_cookies',
    );
  });

  tearDown(() => Get.deleteAll(force: true));

  group('DeliveryNoteItemFormController.itemWarehouse', () {
    test('T-1: applyRackScan sets itemWarehouse for a parseable rack code', () {
      final ctrl = Get.put(DeliveryNoteItemFormController());
      ctrl.applyRackScan('KA-WH-DXB1-101A');
      expect(ctrl.itemWarehouse.value, equals('WH-DXB1 - KA'));
    });

    test('T-2: applyRackScan sets itemWarehouse to null for a non-parseable rack code', () {
      final ctrl = Get.put(DeliveryNoteItemFormController());
      ctrl.applyRackScan('BADRACK');
      expect(ctrl.itemWarehouse.value, isNull);
    });

    test('T-3: clearAll resets itemWarehouse to null', () {
      final ctrl = Get.put(DeliveryNoteItemFormController());
      ctrl.applyRackScan('KA-WH-DXB1-101A');
      expect(ctrl.itemWarehouse.value, isNotNull);
      ctrl.clearAll();
      expect(ctrl.itemWarehouse.value, isNull);
    });

  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```
flutter test test/unit/dn_item_form_controller_warehouse_test.dart -v
```

Expected: 3 failures — `The getter 'itemWarehouse' isn't defined` or similar.

- [ ] **Step 3: Add `rack_location.dart` import**

In `lib/app/modules/delivery_note/form/delivery_note_item_form_controller.dart`, add after the existing `rack_picker_result.dart` import (line 15):

```dart
import 'package:multimax/app/shared/item_sheet/rack_picker_result.dart';
import 'package:multimax/app/shared/item_sheet/rack_location.dart';
```

- [ ] **Step 4: Add `itemWarehouse` field after `rackStockMapRx` (line 93)**

```dart
  final RxMap<String, double> rackStockMapRx = <String, double>{}.obs;
  final RxnString itemWarehouse = RxnString();
```

- [ ] **Step 5: Update `resolvedWarehouse` getter (lines 107–109)**

Replace:
```dart
  @override
  String? get resolvedWarehouse =>
      _parent.bsItemWarehouse.value ?? _parent.setWarehouse.value;
```
With:
```dart
  @override
  String? get resolvedWarehouse =>
      itemWarehouse.value ?? _parent.setWarehouse.value;
```

- [ ] **Step 6: Update `applyRackScan` (lines 1025–1029)**

Replace:
```dart
  @override
  void applyRackScan(String code) {
    softResetRack();      // zero isRackValid before listener fires
    rackController.text = code;
    unawaited(validateRack(code)); // API round-trip — sets isRackValid + rackBalance
  }
```
With:
```dart
  @override
  void applyRackScan(String code) {
    itemWarehouse.value = RackLocation.tryParse(code)?.warehouseName;
    softResetRack();
    rackController.text = code;
    unawaited(validateRack(code));
  }
```

- [ ] **Step 7: Update `_resetValidationState` (line 546, add after `resetRack()`)**

```dart
  void _resetValidationState() {
    resetBatch();
    resetRack();
    itemWarehouse.value   = null;
    liveRemaining.value   = 0.0;
    rackStockMapRx.clear();
    isSheetValid.value = false;
    isQtyValid.value   = false;
    qtyError.value     = '';
  }
```

- [ ] **Step 8: Update `initForEdit` to re-seed `itemWarehouse` after `_resetValidationState` (lines 585–589)**

`_seedEditFieldControllers` runs before `_resetValidationState`, so `itemWarehouse` set there would immediately be cleared. Follow the same pattern as `rackController.text` — re-seed after the reset. Replace:

```dart
    _resetValidationState();
    // Re-seed rack text after _resetValidationState() which calls resetRack()
    // and clears rackController. The validation round-trip happens later in
    // _triggerEditValidations(), so the text must survive until then.
    rackController.text = existingRack;
```
With:
```dart
    _resetValidationState();
    // Re-seed rack text and itemWarehouse after _resetValidationState() which
    // calls resetRack() and clears both rackController and itemWarehouse.
    rackController.text = existingRack;
    itemWarehouse.value = item.warehouse;
```

- [ ] **Step 9: Update `_buildItem` in the item form controller (lines 803–819)**

Add `warehouse: itemWarehouse.value,` to the `DeliveryNoteItem(...)` constructor call:

```dart
  DeliveryNoteItem _buildItem({required double qty}) {
    final rack         = rackController.text.trim();
    final variantOfStr = variantOf.value.trim();

    return DeliveryNoteItem(
      itemCode:                  itemCode.value,
      itemName:                  itemNameRx.value,
      uom:                       itemUomRx.value,
      qty:                       qty,
      rate:                      0.0,
      batchNo:                   batchController.text.trim(),
      rack:                      rack.isEmpty         ? null : rack,
      warehouse:                 itemWarehouse.value,
      itemGroup:                 itemGroup.value,
      customVariantOf:           variantOfStr.isEmpty ? null : variantOfStr,
      customInvoiceSerialNumber: selectedSerial.value,
    );
  }
```

- [ ] **Step 10: Update `clearAll` (lines 1031–1040, add `itemWarehouse.value = null;`)**

```dart
  void clearAll() {
    batchController.clear();
    rackController.clear();
    qtyController.clear();
    resetBatch();
    resetRack();
    itemWarehouse.value   = null;
    selectedSerial.value  = null;
    liveRemaining.value   = 0.0;
    rackStockMapRx.clear();
  }
```

- [ ] **Step 11: Run tests to verify they pass**

```
flutter test test/unit/dn_item_form_controller_warehouse_test.dart -v
```

Expected: `+3: All tests passed!`

- [ ] **Step 12: Run the full suite**

```
flutter test
```

Expected: all tests pass (count increases by 3).

- [ ] **Step 13: Commit**

```
git add lib/app/modules/delivery_note/form/delivery_note_item_form_controller.dart test/unit/dn_item_form_controller_warehouse_test.dart
git commit -m "feat(dn-item-form): add itemWarehouse RxnString, derive from rack in applyRackScan"
```

---

## Task 4: `DeliveryNoteFormController` — wire warehouse into parent `_buildItem`, remove `bsItemWarehouse`, add UI label

**Files:**
- Modify: `lib/app/modules/delivery_note/form/delivery_note_form_controller.dart`

**Context:**
- Imports block: lines 1–33
- `bsItemWarehouse` field: lines 94–95
- `_buildItem` (parent factory): lines 622–653
- `_openItemSheet` `customFields` list: lines 338–391 (specifically the closing `],` at line 391)

No new tests — `RackLocation.tryParse` is tested in `rack_location_warehouse_derivation_test.dart`, and the model field is tested in Task 2.

- [ ] **Step 1: Add imports for `RackLocation` and `DerivedWarehouseLabel`**

In `delivery_note_form_controller.dart`, add these two imports after the `rack_picker_sheet.dart` import (line 30):

```dart
import 'package:multimax/app/shared/item_sheet/rack_picker_sheet.dart';
import 'package:multimax/app/shared/item_sheet/rack_location.dart';
import 'package:multimax/app/shared/item_sheet/derived_warehouse_label.dart';
```

- [ ] **Step 2: Remove `bsItemWarehouse` field (lines 94–95)**

Delete both lines:
```dart
  // ── Item warehouse (derived from rack) ────────────────────────────────────
  var bsItemWarehouse = RxnString();
```

- [ ] **Step 3: Add `warehouse` derivation to the parent `_buildItem` factory**

In `_buildItem` (lines 638–652), add `warehouse: RackLocation.tryParse(rack)?.warehouseName,` to the `DeliveryNoteItem(...)` call:

```dart
    return DeliveryNoteItem(
      name:                      existingName,
      itemCode:                  itemCode,
      itemName:                  itemName,
      qty:                       qty,
      rate:                      rate,
      rack:                      rack.isEmpty  ? null : rack,
      batchNo:                   batch.isEmpty ? null : batch,
      uom:                       uom,
      warehouse:                 RackLocation.tryParse(rack)?.warehouseName,
      customInvoiceSerialNumber: serial,
      owner:                     owner,
      creation:                  creation,
      modified:                  modified,
      modifiedBy:                modifiedBy,
    );
```

- [ ] **Step 4: Add `DerivedWarehouseLabel` to `customFields` in `_openItemSheet`**

After the closing `)` of `SharedRackField` (line 390), add the `DerivedWarehouseLabel` widget before the `],` (line 391):

```dart
          ),   // ← closing ) of SharedRackField
          DerivedWarehouseLabel(
            itemWarehouse:    child.itemWarehouse,
            derivedWarehouse: RxnString(),
            headerWarehouse:  setWarehouse,
          ),
        ],       // ← closing ] of customFields
```

- [ ] **Step 5: Run `flutter analyze`**

```
flutter analyze
```

Expected: no errors. If there is a `The getter 'bsItemWarehouse' isn't defined` error, check that `delivery_note_item_form_controller.dart` no longer references it (it should not — Task 3 already updated `resolvedWarehouse`).

- [ ] **Step 6: Run the full test suite**

```
flutter test
```

Expected: all tests pass (same count as after Task 3).

- [ ] **Step 7: Commit**

```
git add lib/app/modules/delivery_note/form/delivery_note_form_controller.dart
git commit -m "feat(dn-form): derive warehouse in _buildItem, wire DerivedWarehouseLabel, remove bsItemWarehouse"
```

---

## Self-Review Checklist (for the implementer)

After all 4 tasks are committed:

- [ ] `flutter analyze` — zero errors/warnings
- [ ] `flutter test` — all tests pass
- [ ] Smoke test on device: scan a rack in DN item sheet → warehouse label appears below the rack field showing `Warehouse: WH-DXB1 - KA (auto from rack)`
- [ ] Smoke test: submit item → inspect saved item in ERPNext → `warehouse` field is populated per item row
- [ ] Smoke test: edit an existing item that has `warehouse` saved → label shows correct warehouse on open
- [ ] Source rack picker (SE) — unchanged behavior (regression check)
