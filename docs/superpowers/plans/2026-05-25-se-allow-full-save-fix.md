# SE Allow Full — Save-Path Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow the "Allow Full" toggle in the SE item form to propagate through the save path so a fully-consumed POS serial can actually be submitted when the toggle is ON.

**Architecture:** Two additive changes to `StockEntryFormController` and one to `StockEntryItemFormController.submit()`. The `bypassPosCap` named parameter threads `allowFullSerials.value` through the submit path to gate the hard cap check in `addItemLocally`/`updateItemLocally`. A `notifySerialItemsChanged()` call in the `addItem()` coordinator mirrors the Delivery Note pattern.

**Tech Stack:** Flutter/Dart, GetX

---

## File Map

| File | Change |
|------|--------|
| `lib/app/modules/stock_entry/form/stock_entry_form_controller.dart` | Add `{bool bypassPosCap = false}` to `addItemLocally` + `updateItemLocally`; gate cap block with `&& !bypassPosCap`; call `child.notifySerialItemsChanged()` in `addItem()` |
| `lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart` | Pass `bypassPosCap: allowFullSerials.value` in `submit()` |

---

### Task 1: Gate the cap check in `addItemLocally` and `updateItemLocally`

**Files:**
- Modify: `lib/app/modules/stock_entry/form/stock_entry_form_controller.dart`

`addItemLocally` and `updateItemLocally` both have an unconditional `if (resolvedSerial != '0' && posUpload.value != null)` block that shows "Qty Cap Exceeded" and returns early. This block must be skipped when `bypassPosCap` is true.

- [ ] **Step 1: Add `{bool bypassPosCap = false}` to `addItemLocally` and gate the cap block**

In `stock_entry_form_controller.dart`, locate `void addItemLocally(` (currently at line 917). Change the signature and gate:

```dart
  void addItemLocally(
    double qty, String? batch, String? sourceRack, String? targetRack,
    String? sWarehouse, String? tWarehouse, String? serial, {
    bool bypassPosCap = false,
  }) {
    final resolvedSerial = serial ?? '0';

    if (resolvedSerial != '0' && posUpload.value != null && !bypassPosCap) {
```

Only two lines change: the closing `)` of the parameter list becomes `}, {bool bypassPosCap = false,}) {`, and `&& !bypassPosCap` is appended to the `if` condition. Everything inside the block is unchanged.

- [ ] **Step 2: Add `{bool bypassPosCap = false}` to `updateItemLocally` and gate the cap block**

Locate `void updateItemLocally(` (currently at line 860). Change the signature and gate:

```dart
  void updateItemLocally(
    String uniqueId, double qty, String? batch,
    String? sourceRack, String? targetRack,
    String? sWarehouse, String? tWarehouse, String? serial, {
    bool bypassPosCap = false,
  }) {
    final items = stockEntry.value?.items.toList() ?? [];
    final idx   = items.indexWhere((i) => i.name == uniqueId);
    if (idx == -1) return;

    final resolvedSerial = serial ?? '0';
    if (resolvedSerial != '0' && posUpload.value != null && !bypassPosCap) {
```

Same pattern: optional named param appended after the last positional, `&& !bypassPosCap` added to the `if` condition.

- [ ] **Step 3: Verify no analysis errors**

```bash
flutter analyze lib/app/modules/stock_entry/form/stock_entry_form_controller.dart
```

Expected: no errors or warnings related to the changed methods.

- [ ] **Step 4: Commit**

```bash
git add lib/app/modules/stock_entry/form/stock_entry_form_controller.dart
git commit -m "feat(se-form): gate POS cap check in addItemLocally/updateItemLocally with bypassPosCap flag"
```

---

### Task 2: Thread `allowFullSerials` through `submit()` and call `notifySerialItemsChanged()`

**Files:**
- Modify: `lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart`
- Modify: `lib/app/modules/stock_entry/form/stock_entry_form_controller.dart`

`submit()` in `StockEntryItemFormController` calls `_parent.addItemLocally` / `_parent.updateItemLocally`. Pass `bypassPosCap: allowFullSerials.value` so the flag is threaded through. Then, in the `addItem()` coordinator, call `child.notifySerialItemsChanged()` after a successful submit — matching the Delivery Note `_scheduleParentRefresh()` pattern.

- [ ] **Step 1: Pass `bypassPosCap` in `StockEntryItemFormController.submit()`**

In `stock_entry_item_form_controller.dart`, locate `Future<void> submit()` (currently around line 1165). Change the two parent calls:

```dart
  @override
  Future<void> submit() async {
    final qty = double.tryParse(qtyController.text);
    if (qty == null || qty <= 0) throw Exception('Invalid quantity');

    final batch      = isBatchValid.value ? batchController.text : null;
    final srcRack    = isSourceRackValid.value ? sourceRackController.text : null;
    final tgtRack    = isTargetRackValid.value ? targetRackController.text : null;
    final serial     = selectedSerial.value;

    final sWh = itemSourceWarehouse.value ?? _parent.fromWarehouse.value;
    final tWh = itemTargetWarehouse.value ?? _parent.toWarehouse.value;

    final rowId = editingItemName.value;
    if (rowId != null) {
      _parent.updateItemLocally(
        rowId, qty, batch, srcRack, tgtRack, sWh, tWh, serial,
        bypassPosCap: allowFullSerials.value,
      );
    } else {
      _parent.addItemLocally(
        qty, batch, srcRack, tgtRack, sWh, tWh, serial,
        bypassPosCap: allowFullSerials.value,
      );
    }
  }
```

Only the two `bypassPosCap:` lines are new. All other lines are unchanged.

- [ ] **Step 2: Call `child.notifySerialItemsChanged()` in `addItem()`**

In `stock_entry_form_controller.dart`, locate `Future<void> addItem() async {` (currently around line 976). Add the call immediately after the `if (!success) return;` guard:

```dart
    final success = await child.submitWithFeedback();
    if (!success) return; // button already shows error state for 1.5 s then resets
    child.notifySerialItemsChanged();
```

This is the only line added. Everything below (`triggerHighlight`, `FocusManager`, `saveStockEntry`, `Get.back()`) is unchanged.

- [ ] **Step 3: Run the full test suite**

```bash
flutter test
```

Expected: all tests pass (55 tests passing as of last session). Any failure here indicates a regression unrelated to this change — investigate before continuing.

- [ ] **Step 4: Run analyzer on both changed files**

```bash
flutter analyze lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart lib/app/modules/stock_entry/form/stock_entry_form_controller.dart
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart
git add lib/app/modules/stock_entry/form/stock_entry_form_controller.dart
git commit -m "feat(se-item-form): thread allowFullSerials through submit to bypass POS cap; notify serial items changed"
```

---

### Task 3: Smoke test on device

**Files:** none — verification only

- [ ] **Step 1: Build and run on device**

```bash
flutter run -d <device_id>
```

- [ ] **Step 2: Navigate to a Stock Entry linked to a KX or MX POS Upload**

Open a Stock Entry with `stock_entry_type == 'Material Issue'` and `custom_reference_no` starting with `KX` or `MX`. Confirm the POS Upload serials load (progress completes, items show in the PosUploadItemsView).

- [ ] **Step 3: Bring a serial to Full**

If no serial is already Full: scan items into one serial until its POS cap is fully consumed. After each item save, the "Full" sub-label and red text appear in the dropdown for that serial.

- [ ] **Step 4: Open a new item form and verify the toggle appears**

Scan any barcode (or tap an existing item). The Invoice Serial No field label row should show "Allow Full  ○" when at least one serial is Full.

- [ ] **Step 5: Enable Allow Full and select the Full serial**

Toggle ON. The previously-grayed Full serial should become enabled and selectable. Select it.

- [ ] **Step 6: Enter a qty and save**

Enter any qty within batch/rack balance limits. Tap "Add Item" / "Update Item". Verify:
- No "Qty Cap Exceeded" dialog appears.
- Item is committed to the SE.
- Sheet closes normally.

- [ ] **Step 7: Verify batch and rack caps still enforce**

Toggle ON, select a Full serial, but enter a qty that exceeds the batch or rack balance. Verify the form still blocks (qty field shows error or save button stays disabled). The bypass is POS-cap-only.
