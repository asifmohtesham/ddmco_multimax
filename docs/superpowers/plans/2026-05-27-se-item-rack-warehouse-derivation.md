# SE Item Form: Rack → Warehouse Derivation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a rack is validated in the Stock Entry Item Form sheet, write the rack's derived warehouse into `itemSourceWarehouse` / `itemTargetWarehouse` so that `submit()` and `DerivedWarehouseLabel` prefer it over the parent document's header warehouse.

**Architecture:** `RackLocation.tryParse(rack)?.warehouseName` already encodes the derivation formula (`KA-WH-DXB1-101A` → `WH-DXB1 - KA`). `itemSourceWarehouse` and `itemTargetWarehouse` (`RxnString`) are already declared in `StockEntryItemFormController` and already consumed by `submit()` and `DerivedWarehouseLabel` — they are simply never written. All changes are confined to four methods in one file: `validateDualRack()`, `resetSourceRackValidation()`, `resetTargetRackValidation()`, and `initForNewItem()`. Warehouse is only derived post-API (after the rack is confirmed valid). On validation failure, error, or reset the field is cleared to `null`, falling back to the header warehouse.

**Tech Stack:** Flutter / Dart, GetX, `flutter_test`

---

## Files

| Action | Path | What changes |
|--------|------|--------------|
| Create | `test/unit/rack_location_warehouse_derivation_test.dart` | Unit tests for `RackLocation.warehouseName` — the pure derivation logic |
| Modify | `lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart` | Four methods updated (see tasks below) |

---

## Task 1: Unit-test `RackLocation.warehouseName`

**Files:**
- Create: `test/unit/rack_location_warehouse_derivation_test.dart`

`RackLocation` is a pure, dependency-free class in `lib/app/shared/item_sheet/rack_location.dart`. It already exists; no implementation is required. These tests establish the contract we rely on for derivation.

- [ ] **Step 1: Create the test file**

```dart
// test/unit/rack_location_warehouse_derivation_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/shared/item_sheet/rack_location.dart';

void main() {
  group('RackLocation.warehouseName', () {
    test('derives warehouse from a standard 4-part rack code', () {
      final loc = RackLocation.tryParse('KA-WH-DXB1-101A');
      expect(loc?.warehouseName, equals('WH-DXB1 - KA'));
    });

    test('derives warehouse when company prefix differs', () {
      final loc = RackLocation.tryParse('ML-WH-DXB2-202B');
      expect(loc?.warehouseName, equals('WH-DXB2 - ML'));
    });

    test('returns null for a rack code with fewer than 4 parts', () {
      expect(RackLocation.tryParse('WH-DXB1-101A'), isNull);
    });

    test('returns null for an empty string', () {
      expect(RackLocation.tryParse(''), isNull);
    });

    test('returns null for a plain item barcode (no dashes)', () {
      expect(RackLocation.tryParse('20003609'), isNull);
    });
  });
}
```

- [ ] **Step 2: Run the tests — expect all to pass (RackLocation already exists)**

```
flutter test test/unit/rack_location_warehouse_derivation_test.dart --reporter expanded
```

Expected output: 5 tests pass. If any fail, the formula in `RackLocation.warehouseName` does not match the expected pattern — investigate before proceeding.

- [ ] **Step 3: Commit**

```
git add test/unit/rack_location_warehouse_derivation_test.dart
git commit -m "test(rack-location): add unit tests for warehouseName derivation"
```

---

## Task 2: Write `derivedSourceWarehouse` / source reset test

**Files:**
- Modify: `test/unit/rack_location_warehouse_derivation_test.dart`

Add a group that verifies the nullable `?.warehouseName` chain — the exact expression used in `validateDualRack()` for both the assignment and the null-on-invalid case.

- [ ] **Step 1: Add the nullable-chain group to the existing test file**

Append inside `main()`, after the existing group:

```dart
  group('RackLocation.tryParse nullable chain', () {
    test('?.warehouseName returns the derived name for a valid rack', () {
      expect(
        RackLocation.tryParse('KA-WH-DXB1-101A')?.warehouseName,
        equals('WH-DXB1 - KA'),
      );
    });

    test('?.warehouseName returns null for a non-conforming rack string', () {
      expect(RackLocation.tryParse('BADRACK')?.warehouseName, isNull);
    });

    test('?.warehouseName returns null for an empty string', () {
      expect(RackLocation.tryParse('')?.warehouseName, isNull);
    });
  });
```

- [ ] **Step 2: Run to confirm all 8 tests pass**

```
flutter test test/unit/rack_location_warehouse_derivation_test.dart --reporter expanded
```

- [ ] **Step 3: Commit**

```
git add test/unit/rack_location_warehouse_derivation_test.dart
git commit -m "test(rack-location): cover nullable warehouseName chain"
```

---

## Task 3: Derive warehouse on successful source rack validation

**Files:**
- Modify: `lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart:501–520`

The source-rack success path in `validateDualRack()` (the `else` branch at line 517) currently sets `isSourceRackValid = true` and clears `rackError`. Add one line to write `itemSourceWarehouse`.

The negative-balance failure path (the `if (rackBalance.value < 0)` block at lines 511–516) must clear `itemSourceWarehouse` so a stale value is never committed.

The `catch` block (line 529) must also clear `itemSourceWarehouse` on API error.

- [ ] **Step 1: Locate the source-rack try block in `validateDualRack()`**

File: `lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart`

Find the block starting at `if (isSource) {` inside the `try`. It currently reads:

```dart
      if (isSource) {
        isLoadingRackBalance.value = true;
        if (_rackStockMap.containsKey(rack)) {
          rackBalance.value = _rackStockMap[rack]!;
        } else {
          await fetchRackBalance(rack);
        }
        isLoadingRackBalance.value = false;
        // FIX: only mark source rack valid when balance is non-negative
        if (rackBalance.value < 0) {
          isSourceRackValid.value = rackBalance.value >= 0;
          if (rackBalance.value < 0) {
            rackError.value =
            'Rack balance is ${rackBalance.value.toStringAsFixed(0)} — cannot issue from this rack.';
          }
        } else {
          isSourceRackValid.value = true;
          rackError.value = '';          // cleared on success (existing commit-7 rule)
        }
      } else {
```

- [ ] **Step 2: Replace the source-rack block with the updated version**

Replace the `if (isSource) {` block (everything from `if (isSource) {` through the closing `} else {` that begins the target section) with:

```dart
      if (isSource) {
        isLoadingRackBalance.value = true;
        if (_rackStockMap.containsKey(rack)) {
          rackBalance.value = _rackStockMap[rack]!;
        } else {
          await fetchRackBalance(rack);
        }
        isLoadingRackBalance.value = false;
        if (rackBalance.value < 0) {
          isSourceRackValid.value   = false;
          itemSourceWarehouse.value = null;
          rackError.value =
              'Rack balance is ${rackBalance.value.toStringAsFixed(0)} — cannot issue from this rack.';
        } else {
          isSourceRackValid.value   = true;
          itemSourceWarehouse.value = RackLocation.tryParse(rack)?.warehouseName;
          rackError.value = '';
        }
      } else {
```

- [ ] **Step 3: Update the `catch` block to clear `itemSourceWarehouse` on API error**

Find the `catch` block inside `validateDualRack()`:

```dart
    } catch (e) {
      rackError.value = 'Rack validation error: $e';
      log('[SE-Item] validateDualRack error: $e', name: 'SE-Item');
      isLoadingRackBalance.value = false;
    } finally {
```

Replace with:

```dart
    } catch (e) {
      rackError.value = 'Rack validation error: $e';
      log('[SE-Item] validateDualRack error: $e', name: 'SE-Item');
      isLoadingRackBalance.value = false;
      if (isSource) itemSourceWarehouse.value = null;
      else          itemTargetWarehouse.value  = null;
    } finally {
```

- [ ] **Step 4: Verify `RackLocation` is already imported**

Search for the import in the same file:

```
grep -n "rack_location" lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart
```

`RackLocation` is used by `_preloadRackStockMap` indirectly via `RackPickerController`, but `rack_location.dart` itself may not be directly imported. Check the import list. If the import is absent, add it:

```dart
import 'package:multimax/app/shared/item_sheet/rack_location.dart';
```

Add it alongside the other shared item-sheet imports near the top of the file.

- [ ] **Step 5: Run the existing tests to confirm nothing is broken**

```
flutter test test/unit/ --reporter expanded
```

Expected: all existing unit tests pass.

- [ ] **Step 6: Commit**

```
git add lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart
git commit -m "feat(se-item-form): derive itemSourceWarehouse from rack on validation"
```

---

## Task 4: Derive warehouse on successful target rack validation

**Files:**
- Modify: `lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart:521–528`

The target-rack path in `validateDualRack()` (the `else` block after the `if (isSource)`) currently sets `isTargetRackValid = true`. Add `itemTargetWarehouse`.

- [ ] **Step 1: Locate the target-rack block inside `validateDualRack()`**

After the `if (isSource) { ... }` block you updated in Task 3, find:

```dart
      } else {
        isTargetRackValid.value = true;
        // Only clear rackError if source rack has no active error.
        // Preserving source-side negative-balance error message.
        if (isSourceRackValid.value) {
          rackError.value = '';
        }
      }
```

- [ ] **Step 2: Add `itemTargetWarehouse` assignment**

Replace the target block with:

```dart
      } else {
        isTargetRackValid.value   = true;
        itemTargetWarehouse.value = RackLocation.tryParse(rack)?.warehouseName;
        if (isSourceRackValid.value) {
          rackError.value = '';
        }
      }
```

- [ ] **Step 3: Run tests**

```
flutter test test/unit/ --reporter expanded
```

- [ ] **Step 4: Commit**

```
git add lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart
git commit -m "feat(se-item-form): derive itemTargetWarehouse from rack on validation"
```

---

## Task 5: Clear derived warehouses on rack reset

**Files:**
- Modify: `lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart:474–486`

`resetSourceRackValidation()` and `resetTargetRackValidation()` are called when the rack field is cleared (empty string passed to `validateDualRack`, or the edit-icon reset). They must also null out the corresponding derived warehouse so `submit()` falls back to the header.

- [ ] **Step 1: Locate both reset methods**

Find `resetSourceRackValidation()`:

```dart
  @override
  void resetSourceRackValidation() {
    sourceRackController.clear();
    isSourceRackValid.value      = false;
    isValidatingSourceRack.value = false;
  }
```

And `resetTargetRackValidation()`:

```dart
  @override
  void resetTargetRackValidation() {
    targetRackController.clear();
    isTargetRackValid.value      = false;
    isValidatingTargetRack.value = false;
  }
```

- [ ] **Step 2: Add warehouse clears to both methods**

Replace `resetSourceRackValidation()` with:

```dart
  @override
  void resetSourceRackValidation() {
    sourceRackController.clear();
    isSourceRackValid.value      = false;
    isValidatingSourceRack.value = false;
    itemSourceWarehouse.value    = null;
  }
```

Replace `resetTargetRackValidation()` with:

```dart
  @override
  void resetTargetRackValidation() {
    targetRackController.clear();
    isTargetRackValid.value      = false;
    isValidatingTargetRack.value = false;
    itemTargetWarehouse.value    = null;
  }
```

- [ ] **Step 3: Run tests**

```
flutter test test/unit/ --reporter expanded
```

- [ ] **Step 4: Commit**

```
git add lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart
git commit -m "fix(se-item-form): clear derived warehouses on rack reset"
```

---

## Task 6: Clear derived warehouses in `initForNewItem()`

**Files:**
- Modify: `lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart:887–923`

`initForNewItem()` resets all sheet state for a new item session. `itemSourceWarehouse` and `itemTargetWarehouse` are `RxnString(null)` at field declaration, but an explicit reset here keeps `initForNewItem()` the single authoritative clear for all sheet state.

- [ ] **Step 1: Locate the rack-state block in `initForNewItem()`**

Find this block inside `initForNewItem()`:

```dart
    isSourceRackValid.value      = false;
    isValidatingSourceRack.value = false;
    isTargetRackValid.value      = false;
    isValidatingTargetRack.value = false;
    isLoadingRackBalance.value   = false;
```

- [ ] **Step 2: Add warehouse clears immediately after**

```dart
    isSourceRackValid.value      = false;
    isValidatingSourceRack.value = false;
    isTargetRackValid.value      = false;
    isValidatingTargetRack.value = false;
    isLoadingRackBalance.value   = false;
    itemSourceWarehouse.value    = null;
    itemTargetWarehouse.value    = null;
```

- [ ] **Step 3: Run tests**

```
flutter test test/unit/ --reporter expanded
```

- [ ] **Step 4: Commit**

```
git add lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart
git commit -m "fix(se-item-form): explicitly clear derived warehouses in initForNewItem"
```

---

## Task 7: Smoke-test on device

Manual verification — run the app on a physical device with DataWedge and scan through the following scenarios.

- [ ] **Scenario A — Source rack only (Material Issue)**
  1. Open a Material Issue Stock Entry form.
  2. Scan an item → sheet opens.
  3. Scan a valid source rack (e.g. `KA-WH-DXB1-101A`).
  4. Verify `DerivedWarehouseLabel` below the source rack field reads `Warehouse: WH-DXB1 - KA (auto from rack)`.
  5. Tap **Add Item**.
  6. In the items list, verify the item's warehouse column shows `WH-DXB1 - KA` (not the header warehouse if different).

- [ ] **Scenario B — Both racks (Material Transfer)**
  1. Open a Material Transfer form.
  2. Scan an item → sheet opens.
  3. Scan source rack → `DerivedWarehouseLabel` shows source warehouse `(auto from rack)`.
  4. Scan target rack from a different warehouse (e.g. `KA-WH-DXB2-202B`) → target label shows `WH-DXB2 - KA (auto from rack)`.
  5. Tap **Add Item** and verify both warehouses on the committed item row.

- [ ] **Scenario C — Rack cleared mid-session**
  1. Scan a rack, observe label shows `(auto from rack)`.
  2. Tap the edit (pencil) icon on the source rack field to re-enter edit mode.
  3. Clear the rack field entirely.
  4. Verify the label falls back to `Warehouse: <header warehouse> (from header)`.

- [ ] **Scenario D — Non-conforming rack string**
  1. Type a rack ID that is not 4-part (e.g. `SHELF-01`) into the source rack field and confirm.
  2. Verify the label shows `(from header)` — the non-parseable rack produces no derived warehouse.

- [ ] **Scenario E — Edit existing item**
  1. Open a saved Stock Entry, tap edit on an item that has a rack.
  2. Verify the sheet opens with the source warehouse label showing `(auto from rack)` (derived from the pre-populated rack value).
