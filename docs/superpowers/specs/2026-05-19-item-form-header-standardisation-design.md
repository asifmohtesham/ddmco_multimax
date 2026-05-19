# Item Form Header Standardisation — Design Spec

**Date:** 2026-05-19  
**Status:** Approved for implementation

---

## Goal

Standardise the item-entry bottom sheet header across all DocTypes so it always
shows four fields:

| Field        | Source                     | Visibility              |
|--------------|----------------------------|-------------------------|
| Item Code    | `controller.itemCode`      | always                  |
| Variant Of   | `controller.variantOf`     | pill suffix (when set)  |
| Item Group   | `controller.itemGroup`     | chip (when set)         |
| Item Name    | `controller.itemName`      | always                  |

---

## Visual Design — Layout B2 (approved)

```
┌─────────────────────────────────────────────┐
│  Update Item                          [✕]   │
│  [2001267 · PTX-402 Lizard]  [BELTS]        │
│  STRAPS T/X PRINT 40mm                      │
│  ─────────────────────────────────────────  │
│  ...fields...                               │
└─────────────────────────────────────────────┘
```

- **Code pill**: existing style — `ShureTechMono`, `surfaceContainerHighest` bg.
  Variant Of is appended as ` · VARIANT` when non-empty (existing behaviour, unchanged).
- **Group chip**: same row as code pill, `Wrap` so it flows onto the next line on
  small screens.  Style: `Colors.blue.shade50` bg, `Colors.blue.shade700` text,
  `FontWeight.w600`, `BorderRadius.circular(6)`, `padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3)`.
  Hidden (not rendered) when `itemGroup` is empty.
- **Item Name**: body text below the pill row, unchanged.

---

## Architecture

### Invariant: remove `itemSubtext`

`itemSubtext` was an implicit, stringly-typed alias for Variant Of.  It is removed
from both `GlobalItemFormSheet` and `UniversalItemFormSheet` and replaced by an
explicit `variantOf` parameter / controller field.

### How data flows

```
ERPNext document / item scan
        │
        ▼
  Parent form controller
  (SE / DN / PR / PS / PO / MR)
        │  writes group + variantOf when preparing an item
        ▼
  Item form controller (ItemSheetControllerBase subclass)
        │  itemGroup.obs   variantOf.obs
        ▼
  UniversalItemFormSheet / GlobalItemFormSheet
        │  reads values at build time (inside Obx)
        ▼
  GlobalItemFormSheet header widget → renders B2 layout
```

MR is the exception: its form controller does not subclass
`ItemSheetControllerBase` and uses `GlobalItemFormSheet` directly with plain
parameters.

---

## Layer-by-Layer Changes

### 1. `ItemSheetControllerBase`
**File:** `lib/app/shared/item_sheet/item_sheet_controller_base.dart`

Add two new `RxString` fields alongside the existing `itemCode` and `itemName`:

```dart
final RxString itemGroup = ''.obs;
final RxString variantOf = ''.obs;
```

No other changes to the base class.

---

### 2. `GlobalItemFormSheet`
**File:** `lib/app/modules/global_widgets/global_item_form_sheet.dart`

**Constructor changes:**
- Remove `final String? itemSubtext`
- Add `final String? itemGroup`
- Add `final String? variantOf`

**Header widget (`_formChildren`):**

Replace the existing code-pill + item-name block with:

```dart
// Row: code pill + group chip (wraps on overflow)
Wrap(
  spacing:     8,
  runSpacing:  4,
  crossAxisAlignment: WrapCrossAlignment.center,
  children: [
    Container(
      padding:    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color:        colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        variantOf != null && variantOf!.isNotEmpty
            ? '$itemCode · $variantOf'
            : itemCode,
        style: theme.textTheme.labelMedium?.copyWith(
          fontFamily: 'ShureTechMono',
          fontSize:   16,
          color:      colorScheme.onSurfaceVariant,
        ),
      ),
    ),
    if (itemGroup != null && itemGroup!.isNotEmpty)
      Container(
        padding:    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color:        Colors.blue.shade50,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          itemGroup!,
          style: theme.textTheme.labelSmall?.copyWith(
            color:      Colors.blue.shade700,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
  ],
),
const SizedBox(height: 4),
Text(
  itemName,
  style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface),
  maxLines: 2,
  overflow: TextOverflow.ellipsis,
),
```

---

### 3. `UniversalItemFormSheet`
**File:** `lib/app/shared/item_sheet/universal_item_form_sheet.dart`

- Remove `final String? itemSubtext` field and constructor param
- Pass `itemGroup: controller.itemGroup.value` and `variantOf: controller.variantOf.value`
  to `GlobalItemFormSheet` (replacing `itemSubtext: itemSubtext`)

---

### 4. Models — add `itemGroup` field

The following item models currently lack `itemGroup`.  Add the field and parse it
from JSON (`json['item_group']?.toString() ?? ''`):

| Model class            | File                                              |
|------------------------|---------------------------------------------------|
| `PurchaseReceiptItem`  | `lib/app/data/models/purchase_receipt_model.dart` |
| `PackingSlipItem`      | `lib/app/data/models/packing_slip_model.dart`     |
| `PurchaseOrderItem`    | `lib/app/data/models/purchase_order_model.dart`   |

`MaterialRequestItem` already has `variantOf`; add `itemGroup` the same way.

---

### 5. Stock Entry item controller
**File:** `lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart`

`StockEntryItemFormController` already has its own `itemGroup = ''.obs` field and
writes it in `initForItem`.  After adding `itemGroup` to the base class:

- Remove the duplicate `itemGroup` field from `StockEntryItemFormController`
  (the base field takes over).
- Add `String variantOf = ''` to `initForItem`'s parameter list.
- Write `this.variantOf.value = variantOf;` in `initForItem`.

**`StockEntryFormController`** (`lib/app/modules/stock_entry/form/stock_entry_form_controller.dart`):
- Pass `variantOf: currentVariantOf` wherever `initForItem` is called.
- Remove `itemSubtext: currentVariantOf` from the `UniversalItemFormSheet` builder.

---

### 6. Delivery Note item controller
**File:** `lib/app/modules/delivery_note/form/delivery_note_item_form_controller.dart`

Replace the two local fields `itemGroupRx` and `currentVariantOf` with the base
class fields `itemGroup` and `variantOf`:

- Delete `final RxString itemGroupRx = ''.obs;`
- Delete `final RxString currentVariantOf = ''.obs;`
- Delete the unused `RxString get itemGroupValue => itemGroupRx;` getter
- Replace all writes `itemGroupRx.value = x` → `itemGroup.value = x`
- Replace all writes `currentVariantOf.value = x` → `variantOf.value = x`
- Replace all reads `itemGroupRx.value` → `itemGroup.value` (in `submit()`)
- Replace all reads `currentVariantOf.value` → `variantOf.value` (in `submit()`)

**`DeliveryNoteFormController`**: no `UniversalItemFormSheet` changes needed
(it never passed `itemSubtext`; variantOf now flows through the item controller).

---

### 7. Purchase Receipt item controller
**File:** `lib/app/modules/purchase_receipt/form/purchase_receipt_item_form_controller.dart`

In `_initAdd` and `_initEdit`:
- Write `itemGroup.value = itemGroup ?? '';`
- Write `variantOf.value = variantOfValue ?? '';`

Source these from the `PurchaseReceiptItem` model (after Layer 4 adds the field)
and the existing `variantOfValue` parameter that is already threaded through the
PR form controller.

---

### 8. Packing Slip item controller
**File:** `lib/app/modules/packing_slip/form/packing_slip_item_form_controller.dart`

Add `String itemGroup = ''` and `String variantOf = ''` params to `_seedItemIdentity`.
Write `this.itemGroup.value = itemGroup;` and `this.variantOf.value = variantOf;`.

**`PackingSlipFormController`**:
- Pass `itemGroup: item.itemGroup ?? ''` and `variantOf: item.customVariantOf ?? ''`
  when calling `_seedItemIdentity`.
- Remove `itemSubtext: currentItemVariantOf` from the `UniversalItemFormSheet` call.
- Remove `String? currentItemVariantOf` field from `PackingSlipFormController` (the item controller's `variantOf` field replaces it).

---

### 9. Purchase Order item controller
**File:** `lib/app/modules/purchase_order/form/purchase_order_item_form_controller.dart`

In the method that sets `itemCode.value = code` and `itemName.value = name`
(the simple two-line init at the top of the controller):
- Add `this.itemGroup.value = itemGroup ?? '';`
- Add `this.variantOf.value = variantOf ?? '';`
- Extend the method signature to accept these two optional String params.

Source from `PurchaseOrderItem.itemGroup` and `PurchaseOrderItem.customVariantOf`
after Layer 4 adds the model field.

---

### 10. Material Request — special case

MR uses `GlobalItemFormSheet` directly (its form controller does not subclass
`ItemSheetControllerBase`).

**`MaterialRequestFormController`**
(`lib/app/modules/material_request/form/material_request_form_controller.dart`):
- Add `final RxnString bsItemGroup = RxnString();` alongside `bsItemVariantOf`.
- In `openItemSheet` (add and edit branches): set `bsItemGroup.value = item.itemGroup ?? ''`
  and `bsItemGroup.value = null` in the reset branch.
- Source from `MaterialRequestItem.itemGroup` after Layer 4 adds the model field.

**`MaterialRequestItemFormSheet`**
(`lib/app/modules/material_request/form/widgets/material_request_item_form_sheet.dart`):
- Read `final itemGroup = controller.bsItemGroup.value;` inside the `Obx`.
- Replace `itemSubtext: variantOf != null … : null` with
  `itemGroup: itemGroup` and `variantOf: variantOf`.

---

## What Does NOT Change

- The `_buildMetadataHeader` (owner / creation / modified) — untouched.
- `buildInputGroup` static helper — untouched.
- All custom fields in every DocType sheet — untouched.
- `QtyFieldDelegate`, `RackFieldDelegate`, `BatchNoFieldDelegate` — untouched.
- `MR item controller` — MR has no `ItemSheetControllerBase` subclass and is
  handled via direct params (Layer 10).

---

## Rollout Order

Build bottom-up so each layer compiles before the next is added:

1. Models (Layer 4)
2. `ItemSheetControllerBase` (Layer 1)
3. `GlobalItemFormSheet` (Layer 2)
4. `UniversalItemFormSheet` (Layer 3)
5. SE item controller + SE form controller (Layer 5)
6. DN item controller (Layer 6)
7. PR item controller (Layer 7)
8. PS item controller + PS form controller (Layer 8)
9. PO item controller (Layer 9)
10. MR form controller + MR sheet (Layer 10)
