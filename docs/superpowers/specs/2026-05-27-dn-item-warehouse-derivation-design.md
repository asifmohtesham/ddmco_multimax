# DN Item Form: Per-Item Warehouse Derivation — Design Spec

**Date:** 2026-05-27
**Branch:** release/play-store-beta-1-build-5

---

## Problem

`DeliveryNoteItem` has no `warehouse` field. When a rack is scanned in the DN item form, the warehouse is never derived — each item row is saved with only `rack` + `batch_no`. Frappe falls back to the document-level `set_warehouse` for every item regardless of which rack (and therefore which warehouse) was actually scanned.

Additionally, `bsItemWarehouse` (`RxnString`) exists on `DeliveryNoteFormController` with the comment "derived from rack" but is never written — it is dead code. `resolvedWarehouse` on the item controller reads from it as priority-1 over `setWarehouse`, but since it is always null it has no effect.

---

## Solution

Add `itemWarehouse: RxnString` to `DeliveryNoteItemFormController`. When a rack is applied (`applyRackScan`), derive the warehouse synchronously via `RackLocation.tryParse(code)?.warehouseName` and write it to `itemWarehouse`. At submit time, `_buildItem()` reads `itemWarehouse.value` and passes it into `DeliveryNoteItem.warehouse`, which `toJson()` includes in the item row sent to Frappe. For the direct-scan path (rack scanned from the form screen), the parent form controller's `_buildItem` derives warehouse inline from its `rack` parameter. Remove the now-superseded `bsItemWarehouse` field.

---

## Architecture

```
applyRackScan(code)
    │
    │  RackLocation.tryParse(code)?.warehouseName
    ▼
itemWarehouse: RxnString       (new on DeliveryNoteItemFormController)
    │
    ├── resolvedWarehouse → itemWarehouse.value ?? _parent.setWarehouse.value
    │       (used by rack picker to filter by correct warehouse)
    │
    ├── _buildItem() → DeliveryNoteItem(warehouse: itemWarehouse.value, ...)
    │       └── toJson() → 'warehouse': warehouse  (omitted when null)
    │
    └── DerivedWarehouseLabel in customFields (live reactive label)

DeliveryNoteFormController._buildItem(rack: ...)   [direct-scan path]
    │
    │  RackLocation.tryParse(rack)?.warehouseName  (inline, synchronous)
    ▼
DeliveryNoteItem.warehouse
```

---

## Files Changed

| Action | File | What changes |
|--------|------|-------------|
| Modify | `lib/app/data/models/delivery_note_model.dart` | Add `warehouse: String?` to `DeliveryNoteItem` constructor, `fromJson`, `toJson` (conditional), `copyWith` |
| Modify | `lib/app/modules/delivery_note/form/delivery_note_item_form_controller.dart` | Add `itemWarehouse: RxnString`; update `resolvedWarehouse`; update `applyRackScan`, `_buildItem`, `_seedEditFieldControllers`, reset paths |
| Modify | `lib/app/modules/delivery_note/form/delivery_note_form_controller.dart` | Add `warehouse` to `_buildItem`; remove `bsItemWarehouse`; add `DerivedWarehouseLabel` to `customFields` |
| Move   | `lib/app/modules/stock_entry/form/widgets/item_form_sheet/derived_warehouse_label.dart` → `lib/app/shared/item_sheet/derived_warehouse_label.dart` | Move to shared so both SE and DN can import it; update SE import |

---

## Detailed Behaviour

### `DeliveryNoteItem` model

```dart
// Constructor param
final String? warehouse;

// fromJson
warehouse: json['warehouse'] as String?,

// toJson — omit key entirely when null so Frappe uses set_warehouse as fallback
if (warehouse != null) data['warehouse'] = warehouse;

// copyWith
String? warehouse,
// body:
warehouse: warehouse ?? this.warehouse,
```

### `DeliveryNoteItemFormController`

**New field** (after `rackStockMapRx`):
```dart
final RxnString itemWarehouse = RxnString();
```

**`resolvedWarehouse`** — remove dependency on `_parent.bsItemWarehouse`:
```dart
@override
String? get resolvedWarehouse =>
    itemWarehouse.value ?? _parent.setWarehouse.value;
```

**`applyRackScan`** — derive before the API round-trip so `resolvedWarehouse` is
correct for the async `validateRack` call:
```dart
@override
void applyRackScan(String code) {
  itemWarehouse.value = RackLocation.tryParse(code)?.warehouseName;
  softResetRack();
  rackController.text = code;
  unawaited(validateRack(code));
}
```

**`_buildItem`** — pass warehouse:
```dart
return DeliveryNoteItem(
  // existing fields …
  warehouse: itemWarehouse.value,
);
```

**`_seedEditFieldControllers`** — restore when editing an existing item:
```dart
itemWarehouse.value = item.warehouse;
```

**Reset paths** — add `itemWarehouse.value = null;` to:
- Full item reset (the block at ~line 1033 that clears `rackController`, `qtyController`, etc.)
- `_resetValidationState()` (called from `initForNewItem` and `initForEdit`)

### `DeliveryNoteFormController`

**`_buildItem`** — inline derivation for direct-scan path:
```dart
DeliveryNoteItem _buildItem({
  // existing params …
}) {
  return DeliveryNoteItem(
    // existing fields …
    warehouse: RackLocation.tryParse(rack)?.warehouseName,
  );
}
```

**Remove `bsItemWarehouse`** — delete the field declaration and its comment block (lines 94–95). No other code in `delivery_note_form_controller.dart` reads it; `resolvedWarehouse` in the item controller has already been updated to not use it.

**`_openItemSheet` customFields** — add `DerivedWarehouseLabel` as first entry:
```dart
customFields: [
  DerivedWarehouseLabel(
    itemWarehouse:    child.itemWarehouse,
    derivedWarehouse: RxnString(),   // no picker-header warehouse in DN
    headerWarehouse:  setWarehouse,
  ),
  _CheckWoButton(itemCode: itemCode),
],
```

### `DerivedWarehouseLabel` — move to shared

Move from `lib/app/modules/stock_entry/form/widgets/item_form_sheet/derived_warehouse_label.dart`
to `lib/app/shared/item_sheet/derived_warehouse_label.dart`.

Update the import in SE's item form sheet file (whichever file currently imports it) from the old path to the new shared path.

No logic changes — the widget is moved verbatim.

---

## Error Handling

- **Non-standard rack code** (e.g. does not parse as a 4-part code): `RackLocation.tryParse` returns null → `itemWarehouse.value` is null → `toJson` omits `warehouse` → Frappe uses document-level `set_warehouse`. No error shown; rack validation proceeds as normal.
- **Empty rack**: `applyRackScan` is not called; `itemWarehouse` stays null.
- **Rack clears** (user deletes rack text): the explicit reset paths (`_resetValidationState`, full reset block) clear `itemWarehouse.value = null`, so the label disappears.
- **Edit existing item**: `_seedEditFieldControllers` restores `itemWarehouse.value = item.warehouse` so the label shows the previously-saved warehouse.

---

## Testing

- **`test/unit/dn_item_warehouse_field_test.dart`** — model parser tests:
  - T-1: `fromJson` reads `warehouse` when present
  - T-2: `fromJson` returns null `warehouse` when key absent
  - T-3: `toJson` includes `'warehouse'` key when non-null
  - T-4: `toJson` omits `'warehouse'` key when null

- **`test/unit/dn_item_form_controller_warehouse_test.dart`** — controller tests (fake `ApiProvider`, same pattern as `rack_picker_controller_target_mode_test.dart`):
  - T-1: `applyRackScan` with parseable rack → `itemWarehouse.value` equals derived warehouse
  - T-2: `applyRackScan` with non-parseable rack → `itemWarehouse.value` is null
  - T-3: full reset → `itemWarehouse.value` is null

---

## Out of Scope

- Purchase Receipt: already has `itemWarehouse: RxnString` (uses Rack DocType API in `validateRack`); no change.
- Other modules (Job Card, Work Order, Packing Slip): no rack-to-warehouse derivation needed.
- Moving `bsItemWarehouse` removal to a separate PR: this field has no callers once `resolvedWarehouse` is updated; remove it in the same commit.
