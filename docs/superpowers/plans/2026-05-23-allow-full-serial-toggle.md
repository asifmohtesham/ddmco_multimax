# Allow Full Serial Toggle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an inline "Allow Full" toggle to the Invoice Serial No label row so floor workers can select and assign qty to fully-consumed POS serials when operationally necessary.

**Architecture:** `allowFullSerials` is added as an `RxBool` field to `SerialFieldMixin` (which all three DocType item-sheet controllers already adopt). The widget reads it via an existing `is SerialFieldMixin` cast pattern (same as `serialItemsStamp`). The DN and SE controllers guard their POS-cap blocks in `effectiveMaxQty` with `!allowFullSerials.value`. `buildInputGroup` gains an optional `labelTrailing` slot for the toggle widget.

**Tech Stack:** Flutter/Dart, GetX reactivity (`RxBool`, `Obx`), `flutter analyze`, `flutter test`

---

## File Map

| File | Change |
|------|--------|
| `lib/app/shared/item_sheet/serial_field_mixin.dart` | Add `final allowFullSerials = false.obs;` |
| `lib/app/modules/delivery_note/form/delivery_note_item_form_controller.dart` | Reset `allowFullSerials` in `_seedNewItemModeFlags` + `_seedEditModeFlags`; guard POS cap in `effectiveMaxQty` |
| `lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart` | Reset `allowFullSerials` in `initForNewItem` + `_loadExistingItem`; guard POS cap in `effectiveMaxQty` |
| `lib/app/modules/global_widgets/global_item_form_sheet.dart` | Add optional `Widget? labelTrailing` to `buildInputGroup` |
| `lib/app/shared/item_sheet/widgets/shared_invoice_serial_number_field.dart` | Subscribe to `allowFullSerials`; compute `anyFull`; pass `labelTrailing`; override item enabled/opacity; add `_AllowFullToggle` widget |
| `test/unit/allow_full_serial_toggle_test.dart` | Unit tests for `allowFullSerials` default and `SerialDropdownItem.isFull` boundary |

---

## Task 1: Add `allowFullSerials` field to `SerialFieldMixin`

**Files:**
- Modify: `lib/app/shared/item_sheet/serial_field_mixin.dart`
- Create: `test/unit/allow_full_serial_toggle_test.dart`

- [ ] **Step 1: Write the failing test**

  Create `test/unit/allow_full_serial_toggle_test.dart`:

  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:multimax/app/shared/item_sheet/serial_number_field_delegate.dart';

  void main() {
    group('SerialDropdownItem.isFull', () {
      test('is true when remaining <= 0 and qty is finite', () {
        const item = SerialDropdownItem(serial: '1', qty: 10, remaining: 0);
        expect(item.isFull, isTrue);
      });

      test('is false when remaining > 0', () {
        const item = SerialDropdownItem(serial: '1', qty: 10, remaining: 3);
        expect(item.isFull, isFalse);
      });

      test('is false when qty is null', () {
        const item = SerialDropdownItem(serial: '1', qty: null, remaining: 0);
        expect(item.isFull, isFalse);
      });

      test('is false when qty is infinity', () {
        const item = SerialDropdownItem(
            serial: '1', qty: double.infinity, remaining: 0);
        expect(item.isFull, isFalse);
      });
    });
  }
  ```

- [ ] **Step 2: Run test to confirm it passes (it tests existing logic)**

  ```
  flutter test test/unit/allow_full_serial_toggle_test.dart -v
  ```

  Expected: all 4 tests PASS — this confirms the baseline before our changes.

- [ ] **Step 3: Add `allowFullSerials` to `SerialFieldMixin`**

  In `lib/app/shared/item_sheet/serial_field_mixin.dart`, directly after the existing `serialItemsStamp` field (around line 116), add:

  ```dart
  /// Whether the user has overridden the Full-serial lock for this sheet session.
  ///
  /// When `true`:
  ///   - Full serials are selectable in the dropdown (widget un-disables them).
  ///   - The POS qty cap is bypassed in `effectiveMaxQty` so the user can enter
  ///     any qty (batch and rack balance caps remain enforced).
  ///
  /// Reset to `false` at every sheet open via `_seedNewItemModeFlags` /
  /// `_seedEditModeFlags` (DN) and `initForNewItem` / `_loadExistingItem` (SE).
  final allowFullSerials = false.obs;
  ```

- [ ] **Step 4: Run analyze**

  ```
  flutter analyze lib/app/shared/item_sheet/serial_field_mixin.dart
  ```

  Expected: No issues found.

- [ ] **Step 5: Commit**

  ```
  git add lib/app/shared/item_sheet/serial_field_mixin.dart test/unit/allow_full_serial_toggle_test.dart
  git commit -m "feat: add allowFullSerials RxBool to SerialFieldMixin"
  ```

---

## Task 2: Reset `allowFullSerials` in DN controller on sheet open

**Files:**
- Modify: `lib/app/modules/delivery_note/form/delivery_note_item_form_controller.dart`

The controller is registered via `Get.lazyPut` and reused across sheet opens, so `allowFullSerials` must be explicitly reset each time.

- [ ] **Step 1: Add reset to `_seedNewItemModeFlags`**

  Locate `_seedNewItemModeFlags()` (around line 506). Current:

  ```dart
  void _seedNewItemModeFlags() {
    isExistingItem.value  = false;
    editingIndex.value    = -1;
    editingItemName.value = null;
    docStatus.value       = _parent.deliveryNote.value?.docstatus ?? 0;
  }
  ```

  Replace with:

  ```dart
  void _seedNewItemModeFlags() {
    isExistingItem.value  = false;
    editingIndex.value    = -1;
    editingItemName.value = null;
    docStatus.value       = _parent.deliveryNote.value?.docstatus ?? 0;
    allowFullSerials.value = false;
  }
  ```

- [ ] **Step 2: Add reset to `_seedEditModeFlags`**

  Locate `_seedEditModeFlags()` (around line 599). Current:

  ```dart
  void _seedEditModeFlags({
    required int index,
    required DeliveryNoteItem item,
  }) {
    isExistingItem.value  = true;
    editingIndex.value    = index;
    editingItemName.value = item.name;
    docStatus.value       = _parent.deliveryNote.value?.docstatus ?? 0;
  }
  ```

  Replace with:

  ```dart
  void _seedEditModeFlags({
    required int index,
    required DeliveryNoteItem item,
  }) {
    isExistingItem.value  = true;
    editingIndex.value    = index;
    editingItemName.value = item.name;
    docStatus.value       = _parent.deliveryNote.value?.docstatus ?? 0;
    allowFullSerials.value = false;
  }
  ```

- [ ] **Step 3: Run analyze**

  ```
  flutter analyze lib/app/modules/delivery_note/form/delivery_note_item_form_controller.dart
  ```

  Expected: No issues found.

- [ ] **Step 4: Commit**

  ```
  git add lib/app/modules/delivery_note/form/delivery_note_item_form_controller.dart
  git commit -m "fix(dn-item-form): reset allowFullSerials on each sheet open"
  ```

---

## Task 3: Bypass POS cap in DN `effectiveMaxQty`

**Files:**
- Modify: `lib/app/modules/delivery_note/form/delivery_note_item_form_controller.dart`

- [ ] **Step 1: Guard the POS serial block**

  Locate `effectiveMaxQty` (around line 141). The POS cap block currently reads:

  ```dart
  final serial = selectedSerial.value ?? '';
  if (serial.isNotEmpty) {
    final posQty = posItemQtyForSerial(serial);
    if (posQty != double.infinity) {
      final used = sumQtyUsedForSerial(serial, excludeRowId: editingItemName.value);
      final allowedByPos = (posQty - used).clamp(0.0, posQty);
      ceil = _applyConstraint(ceil, allowedByPos);
    }
  }
  ```

  Change the `if` condition to:

  ```dart
  final serial = selectedSerial.value ?? '';
  if (serial.isNotEmpty && !allowFullSerials.value) {
    final posQty = posItemQtyForSerial(serial);
    if (posQty != double.infinity) {
      final used = sumQtyUsedForSerial(serial, excludeRowId: editingItemName.value);
      final allowedByPos = (posQty - used).clamp(0.0, posQty);
      ceil = _applyConstraint(ceil, allowedByPos);
    }
  }
  ```

  Only the condition on the outer `if` changes. Batch and rack constraints above this block are untouched.

- [ ] **Step 2: Run analyze**

  ```
  flutter analyze lib/app/modules/delivery_note/form/delivery_note_item_form_controller.dart
  ```

  Expected: No issues found.

- [ ] **Step 3: Commit**

  ```
  git add lib/app/modules/delivery_note/form/delivery_note_item_form_controller.dart
  git commit -m "feat(dn-item-form): bypass POS qty cap when allowFullSerials is active"
  ```

---

## Task 4: Reset and bypass POS cap in SE `effectiveMaxQty`

**Files:**
- Modify: `lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart`

The SE controller uses `_posSerialCeiling` (a computed getter returning `double?`) instead of the inline block used in DN. The bypass is applied at the point of reading the ceiling.

- [ ] **Step 1: Add reset to `initForNewItem`**

  Locate `initForNewItem()` (around line 903). After the existing resets (e.g., after `liveRemaining.value = 0.0;`), add:

  ```dart
  allowFullSerials.value = false;
  ```

- [ ] **Step 2: Add reset to `_loadExistingItem`**

  Locate `_loadExistingItem()` (around line 950). After the `if (isClosed) return;` guard and before or after `isEditingExisting.value = true;`, add:

  ```dart
  allowFullSerials.value = false;
  ```

- [ ] **Step 3: Guard POS cap in SE `effectiveMaxQty`**

  Locate `effectiveMaxQty` (around line 639). The POS cap block currently reads:

  ```dart
  final serial = _posSerialCeiling;
  if (serial != null) {
    debugPrint(
      '[effectiveMaxQty] POS serial ceiling=$serial '
          'batch=${batchBalance.value} rack=${rackBalance.value}',
    );
    // When serial ceiling is 0, short-circuit immediately — no other
    // balance can override a fully-consumed serial.
    if (serial == 0.0) return 0.0;
    ceil = serial;
  }
  ```

  Replace the first line only:

  ```dart
  final serial = allowFullSerials.value ? null : _posSerialCeiling;
  if (serial != null) {
    debugPrint(
      '[effectiveMaxQty] POS serial ceiling=$serial '
          'batch=${batchBalance.value} rack=${rackBalance.value}',
    );
    // When serial ceiling is 0, short-circuit immediately — no other
    // balance can override a fully-consumed serial.
    if (serial == 0.0) return 0.0;
    ceil = serial;
  }
  ```

  When `allowFullSerials` is `true`, `serial` is forced to `null` and the entire block — including the `return 0.0` short-circuit — is skipped. Batch, rack, and MR blocks below are untouched.

- [ ] **Step 4: Run analyze**

  ```
  flutter analyze lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart
  ```

  Expected: No issues found.

- [ ] **Step 5: Commit**

  ```
  git add lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart
  git commit -m "feat(se-item-form): bypass POS qty cap when allowFullSerials is active"
  ```

---

## Task 5: Add `labelTrailing` slot to `buildInputGroup`

**Files:**
- Modify: `lib/app/modules/global_widgets/global_item_form_sheet.dart`

- [ ] **Step 1: Add `labelTrailing` parameter**

  Locate `buildInputGroup` (around line 238). Current signature:

  ```dart
  static Widget buildInputGroup({
    required String label,
    required Color color,
    required Widget child,
    Color? bgColor,
  }) {
  ```

  Replace with:

  ```dart
  static Widget buildInputGroup({
    required String label,
    required Color color,
    required Widget child,
    Color? bgColor,
    Widget? labelTrailing,
  }) {
  ```

- [ ] **Step 2: Update the label row rendering**

  Locate the `Padding` that renders the label (around line 247):

  ```dart
  Padding(
    padding: const EdgeInsets.only(left: 4.0, bottom: 6.0),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.bold,
        fontSize: 12,
        letterSpacing: 0.5,
      ),
    ),
  ),
  ```

  Replace with:

  ```dart
  Padding(
    padding: const EdgeInsets.only(left: 4.0, bottom: 6.0),
    child: labelTrailing == null
        ? Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
              labelTrailing,
            ],
          ),
  ),
  ```

- [ ] **Step 3: Run analyze**

  ```
  flutter analyze lib/app/modules/global_widgets/global_item_form_sheet.dart
  ```

  Expected: No issues found.

- [ ] **Step 4: Commit**

  ```
  git add lib/app/modules/global_widgets/global_item_form_sheet.dart
  git commit -m "feat(global-widgets): add optional labelTrailing slot to buildInputGroup"
  ```

---

## Task 6: Add "Allow Full" toggle to `SharedInvoiceSerialNumberField`

**Files:**
- Modify: `lib/app/shared/item_sheet/widgets/shared_invoice_serial_number_field.dart`

- [ ] **Step 1: Subscribe to `allowFullSerials` inside `Obx` and compute `anyFull`**

  In the `build` method, inside the `Obx(() { ... })` closure, add two lines after the existing reactive reads (the `serialItemsStamp` read and `dropdownItems` build):

  Current (around line 213):

  ```dart
  if (c is SerialFieldMixin) {
    (c as SerialFieldMixin).serialItemsStamp.value; // reactive read
  }

  final dropdownItems = c.serialDropdownItems;
  ```

  Replace with:

  ```dart
  if (c is SerialFieldMixin) {
    (c as SerialFieldMixin).serialItemsStamp.value; // reactive read
  }

  final dropdownItems = c.serialDropdownItems;

  final allowFull = (c is SerialFieldMixin)
      ? (c as SerialFieldMixin).allowFullSerials.value
      : false;
  final anyFull = dropdownItems.any((i) => i.isFull);
  ```

- [ ] **Step 2: Pass `labelTrailing` to `buildInputGroup`**

  Locate the `buildInputGroup` call (around line 227):

  ```dart
  GlobalItemFormSheet.buildInputGroup(
    label: label,
    color: accentColor,
    child: DropdownButtonFormField<String>(
  ```

  Replace with:

  ```dart
  GlobalItemFormSheet.buildInputGroup(
    label: label,
    color: accentColor,
    labelTrailing: anyFull
        ? _AllowFullToggle(c: c, accentColor: accentColor)
        : null,
    child: DropdownButtonFormField<String>(
  ```

- [ ] **Step 3: Override enabled/opacity in `_buildItems` for Full rows**

  Locate the `return DropdownMenuItem<String>(...)` near the end of `_buildItems` (around line 172):

  ```dart
  return DropdownMenuItem<String>(
    value: item.serial,
    enabled: !item.isFull,
    child: Opacity(
      opacity: item.isFull ? 0.4 : 1.0,
      child: tile,
    ),
  );
  ```

  `_buildItems` currently takes a `List<SerialDropdownItem>` parameter. Add a second `bool allowFull` parameter:

  Change the method signature from:

  ```dart
  List<DropdownMenuItem<String>> _buildItems(
      List<SerialDropdownItem> items) {
  ```

  to:

  ```dart
  List<DropdownMenuItem<String>> _buildItems(
      List<SerialDropdownItem> items, {bool allowFull = false}) {
  ```

  Then update the `DropdownMenuItem` at the bottom of the method:

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

  Update the call site in `build` where `_buildItems` is invoked (around line 243):

  ```dart
  items: _buildItems(dropdownItems, allowFull: allowFull),
  ```

- [ ] **Step 4: Add the private `_AllowFullToggle` widget**

  At the bottom of the file, after the closing `}` of `_PosCapChip`, add:

  ```dart
  /// Inline toggle rendered in the "Invoice Serial No" label row when at
  /// least one serial in the dropdown is Full. Toggles [SerialFieldMixin.allowFullSerials].
  class _AllowFullToggle extends StatelessWidget {
    final SerialNumberFieldDelegate c;
    final Color accentColor;

    const _AllowFullToggle({required this.c, required this.accentColor});

    @override
    Widget build(BuildContext context) {
      final mixin = c as SerialFieldMixin;
      return Obx(() => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Allow Full',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(width: 4),
              Transform.scale(
                scale: 0.7,
                child: Switch(
                  value: mixin.allowFullSerials.value,
                  onChanged: (v) => mixin.allowFullSerials.value = v,
                  activeColor: accentColor,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ));
    }
  }
  ```

  Note: `Transform.scale(scale: 0.7)` shrinks the switch to match the compact label row height without clipping.

- [ ] **Step 5: Run analyze**

  ```
  flutter analyze lib/app/shared/item_sheet/widgets/shared_invoice_serial_number_field.dart
  ```

  Expected: No issues found.

- [ ] **Step 6: Run all tests**

  ```
  flutter test
  ```

  Expected: All tests pass.

- [ ] **Step 7: Commit**

  ```
  git add lib/app/shared/item_sheet/widgets/shared_invoice_serial_number_field.dart
  git commit -m "feat: add Allow Full toggle to Invoice Serial No label row"
  ```

---

## Task 7: Manual smoke test

- [ ] **Step 1: Run the app on a connected device**

  ```
  flutter run -d <device_id>
  ```

  Use a device with an active Delivery Note that has a POS Upload attached containing at least one serial where all qty is already scanned (remaining = 0, `isFull = true`).

- [ ] **Step 2: Verify toggle is hidden when no Full serials exist**

  Open a Delivery Note where no serial is Full → open an item form → confirm the label row shows `"Invoice Serial No"` with no toggle.

- [ ] **Step 3: Verify toggle appears when a serial is Full**

  Open a Delivery Note where at least one serial is Full → open an item form → confirm the label row shows `"Invoice Serial No"` with an `Allow Full` switch on the right.

- [ ] **Step 4: Verify Full serial is blocked by default**

  With toggle OFF, open the dropdown → confirm Full serials are dimmed and non-selectable.

- [ ] **Step 5: Verify toggle enables Full serials**

  Switch the toggle ON → confirm Full serials are no longer dimmed and are selectable. Confirm the "Full" sub-label and red colour remain visible.

- [ ] **Step 6: Verify POS cap bypass**

  Select a Full serial with the toggle ON → enter a qty greater than 0 → confirm the sheet becomes valid (green submit button) and no POS-cap qty error appears.

- [ ] **Step 7: Verify batch and rack caps still enforce**

  With the toggle ON and a Full serial selected, enter a qty exceeding the batch balance → confirm a batch-balance error appears and the sheet remains invalid.

- [ ] **Step 8: Verify toggle resets between sheet opens**

  Enable the toggle in one item sheet, close it, then open a new item sheet → confirm the toggle starts in the OFF position.
