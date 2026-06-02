# Item Form Header Standardisation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Standardise the item-entry bottom sheet header across all DocTypes (SE, DN, PR, PS, PO, MR) to show Item Code, Variant Of (pill suffix), Item Group (chip), and Item Name using layout B2.

**Architecture:** Add `itemGroup` and `variantOf` as `RxString` fields on `ItemSheetControllerBase` alongside the existing `itemCode` and `itemName`. Replace the implicit `itemSubtext` param on `GlobalItemFormSheet`/`UniversalItemFormSheet` with explicit `itemGroup` and `variantOf` params. Each DocType controller writes the two new fields where it currently sets `itemCode`. MR is the exception — it uses `GlobalItemFormSheet` directly and manages its own reactive state.

**Tech Stack:** Flutter, GetX (Rx/obs pattern), Dart

---

## Files Modified

| File | Change |
|------|--------|
| `lib/app/data/models/purchase_receipt_model.dart` | Add `itemGroup` field |
| `lib/app/data/models/packing_slip_model.dart` | Add `itemGroup` field |
| `lib/app/data/models/purchase_order_model.dart` | Add `itemGroup` field |
| `lib/app/data/models/material_request_model.dart` | Add `itemGroup` field |
| `lib/app/shared/item_sheet/item_sheet_controller_base.dart` | Add `itemGroup` + `variantOf` RxString fields |
| `lib/app/modules/global_widgets/global_item_form_sheet.dart` | Replace `itemSubtext` → `itemGroup`+`variantOf`; B2 header |
| `lib/app/shared/item_sheet/universal_item_form_sheet.dart` | Remove `itemSubtext`; pass new fields |
| `lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart` | Remove duplicate `itemGroup`; wire `variantOf` |
| `lib/app/modules/stock_entry/form/stock_entry_form_controller.dart` | Remove `itemSubtext:` from sheet call |
| `lib/app/modules/delivery_note/form/delivery_note_item_form_controller.dart` | Replace `itemGroupRx`/`currentVariantOf` with base fields |
| `lib/app/modules/purchase_receipt/form/purchase_receipt_item_form_controller.dart` | Wire `itemGroup` + `variantOf` |
| `lib/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart` | Pass `itemGroup` through call chain |
| `lib/app/modules/packing_slip/form/packing_slip_item_form_controller.dart` | Wire `itemGroup` + `variantOf` |
| `lib/app/modules/packing_slip/form/packing_slip_form_controller.dart` | Pass `itemGroup`+`variantOf`; remove `currentItemVariantOf` |
| `lib/app/modules/purchase_order/form/purchase_order_item_form_controller.dart` | Wire `itemGroup` + `variantOf` |
| `lib/app/modules/purchase_order/form/purchase_order_form_controller.dart` | Pass `itemGroup`+`variantOf` through call chain |
| `lib/app/modules/material_request/form/material_request_form_controller.dart` | Add `bsItemGroup`; wire from item/scan |
| `lib/app/modules/material_request/form/widgets/material_request_item_form_sheet.dart` | Replace `itemSubtext` → `itemGroup`+`variantOf` |

## Files Created

| File | Purpose |
|------|---------|
| `test/unit/item_form_header_test.dart` | Unit tests for model JSON parsing and header widget rendering |

---

## Task 1: Add `itemGroup` to four item models

**Files:**
- Modify: `lib/app/data/models/purchase_receipt_model.dart`
- Modify: `lib/app/data/models/packing_slip_model.dart`
- Modify: `lib/app/data/models/purchase_order_model.dart`
- Modify: `lib/app/data/models/material_request_model.dart`
- Create: `test/unit/item_form_header_test.dart`

- [ ] **Step 1: Write failing tests for model JSON parsing**

Create `test/unit/item_form_header_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/purchase_receipt_model.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/data/models/material_request_model.dart';

void main() {
  group('PurchaseReceiptItem.itemGroup', () {
    test('parses item_group from JSON', () {
      final item = PurchaseReceiptItem.fromJson({
        'item_code': 'ITEM-001',
        'item_group': 'BELTS',
        'qty': 1,
        'warehouse': 'WH-1',
      });
      expect(item.itemGroup, 'BELTS');
    });

    test('defaults to empty string when item_group absent', () {
      final item = PurchaseReceiptItem.fromJson({
        'item_code': 'ITEM-001',
        'qty': 1,
        'warehouse': 'WH-1',
      });
      expect(item.itemGroup, '');
    });
  });

  group('PackingSlipItem.itemGroup', () {
    test('parses item_group from JSON', () {
      final item = PackingSlipItem.fromJson({
        'name': 'PS-ROW-1',
        'dn_detail': 'DN-DETAIL-1',
        'item_code': 'ITEM-001',
        'item_name': 'Test Item',
        'item_group': 'STRAPS',
        'qty': 2.0,
        'uom': 'Nos',
        'batch_no': '',
        'net_weight': 0.0,
        'weight_uom': 0.0,
      });
      expect(item.itemGroup, 'STRAPS');
    });

    test('defaults to empty string when item_group absent', () {
      final item = PackingSlipItem.fromJson({
        'name': 'PS-ROW-1',
        'dn_detail': 'DN-DETAIL-1',
        'item_code': 'ITEM-001',
        'item_name': 'Test Item',
        'qty': 2.0,
        'uom': 'Nos',
        'batch_no': '',
        'net_weight': 0.0,
        'weight_uom': 0.0,
      });
      expect(item.itemGroup, '');
    });
  });

  group('PurchaseOrderItem.itemGroup', () {
    test('parses item_group from JSON', () {
      final item = PurchaseOrderItem.fromJson({
        'item_code': 'ITEM-001',
        'item_name': 'Test Item',
        'item_group': 'RAW MATERIAL',
        'qty': 10,
        'received_qty': 0,
        'rate': 5.0,
        'amount': 50.0,
      });
      expect(item.itemGroup, 'RAW MATERIAL');
    });

    test('defaults to empty string when absent', () {
      final item = PurchaseOrderItem.fromJson({
        'item_code': 'ITEM-001',
        'item_name': 'Test Item',
        'qty': 10,
        'received_qty': 0,
        'rate': 5.0,
        'amount': 50.0,
      });
      expect(item.itemGroup, '');
    });
  });

  group('MaterialRequestItem.itemGroup', () {
    test('parses item_group from JSON', () {
      final item = MaterialRequestItem.fromJson({
        'item_code': 'ITEM-001',
        'variant_of': '',
        'qty': 5,
        'received_qty': 0,
        'ordered_qty': 0,
        'actual_qty': 0,
        'item_group': 'FINISHED GOODS',
      });
      expect(item.itemGroup, 'FINISHED GOODS');
    });

    test('defaults to empty string when absent', () {
      final item = MaterialRequestItem.fromJson({
        'item_code': 'ITEM-001',
        'variant_of': '',
        'qty': 5,
        'received_qty': 0,
        'ordered_qty': 0,
        'actual_qty': 0,
      });
      expect(item.itemGroup, '');
    });
  });
}
```

- [ ] **Step 2: Run tests — expect failures**

```
flutter test test/unit/item_form_header_test.dart
```

Expected: 8 failures because `itemGroup` doesn't exist on these models yet.

- [ ] **Step 3: Add `itemGroup` to `PurchaseReceiptItem`**

In `lib/app/data/models/purchase_receipt_model.dart`, locate the class fields near `customVariantOf`:

Add field after `customVariantOf`:
```dart
final String? itemGroup;
```

In the constructor, add after `this.customVariantOf,`:
```dart
this.itemGroup,
```

In `fromJson`, add after `customVariantOf: json['custom_variant_of'],`:
```dart
itemGroup: json['item_group']?.toString() ?? '',
```

In `copyWith`, add the `itemGroup` param and return value:
```dart
// In copyWith param list (after customVariantOf):
String? itemGroup,

// In the returned object (after customVariantOf: customVariantOf ?? this.customVariantOf):
itemGroup: itemGroup ?? this.itemGroup,
```

- [ ] **Step 4: Add `itemGroup` to `PackingSlipItem`**

In `lib/app/data/models/packing_slip_model.dart`, find `PackingSlipItem` class.

Add field after `customVariantOf`:
```dart
final String? itemGroup;
```

In the constructor (the named constructor, not factory), add after `this.customVariantOf,`:
```dart
this.itemGroup,
```

In `fromJson`, add after `customVariantOf: json['custom_variant_of'],`:
```dart
itemGroup: json['item_group']?.toString() ?? '',
```

In `copyWith`, add `String? itemGroup,` to params and `itemGroup: itemGroup ?? this.itemGroup,` to the returned object.

- [ ] **Step 5: Add `itemGroup` to `PurchaseOrderItem`**

In `lib/app/data/models/purchase_order_model.dart`, find `PurchaseOrderItem` class.

Add field after `customVariantOf`:
```dart
final String? itemGroup;
```

In the constructor, add after `this.customVariantOf,`:
```dart
this.itemGroup,
```

In `fromJson`, add after `customVariantOf: json['custom_variant_of'],`:
```dart
itemGroup: json['item_group']?.toString() ?? '',
```

In `copyWith` (if present), add `String? itemGroup,` to params and return value.

- [ ] **Step 6: Add `itemGroup` to `MaterialRequestItem`**

In `lib/app/data/models/material_request_model.dart`, find `MaterialRequestItem` class.

Add field after `variantOf`:
```dart
final String? itemGroup;
```

In the constructor, add after `required this.variantOf,`:
```dart
this.itemGroup,
```

In `fromJson`, add after `variantOf: json['variant_of']?.toString() ?? '',`:
```dart
itemGroup: json['item_group']?.toString() ?? '',
```

- [ ] **Step 7: Run tests — expect all 8 pass**

```
flutter test test/unit/item_form_header_test.dart
```

Expected: 8 tests pass.

- [ ] **Step 8: Verify no analysis errors**

```
flutter analyze
```

Expected: no errors (warnings about `itemGroup` being unused in some models are fine at this stage).

- [ ] **Step 9: Commit**

```
git add lib/app/data/models/purchase_receipt_model.dart \
        lib/app/data/models/packing_slip_model.dart \
        lib/app/data/models/purchase_order_model.dart \
        lib/app/data/models/material_request_model.dart \
        test/unit/item_form_header_test.dart
git commit -m "feat: add itemGroup field to PR, PS, PO, MR item models"
```

---

## Task 2: Add `itemGroup` and `variantOf` to `ItemSheetControllerBase`

**Files:**
- Modify: `lib/app/shared/item_sheet/item_sheet_controller_base.dart`

- [ ] **Step 1: Add the two fields**

In `lib/app/shared/item_sheet/item_sheet_controller_base.dart`, find the block:

```dart
  var itemCode = ''.obs;
```

That line is around line 237. Add two fields immediately after it:

```dart
  var itemCode   = ''.obs;
  final RxString itemGroup = ''.obs;
  final RxString variantOf = ''.obs;
```

No other changes to this file.

- [ ] **Step 2: Verify analysis**

```
flutter analyze
```

Expected: no new errors.

- [ ] **Step 3: Commit**

```
git add lib/app/shared/item_sheet/item_sheet_controller_base.dart
git commit -m "feat: add itemGroup and variantOf fields to ItemSheetControllerBase"
```

---

## Task 3: Update `GlobalItemFormSheet` — B2 header, replace `itemSubtext`

**Files:**
- Modify: `lib/app/modules/global_widgets/global_item_form_sheet.dart`

- [ ] **Step 1: Replace constructor fields**

Find these three lines in the class fields section:

```dart
  final String itemCode;
  final String itemName;
  final String? itemSubtext;
```

Replace with:

```dart
  final String itemCode;
  final String itemName;
  final String? itemGroup;
  final String? variantOf;
```

- [ ] **Step 2: Update the constructor parameter list**

Find in the constructor body (inside the `GlobalItemFormSheet({...})` signature):

```dart
    required this.itemCode,
    required this.itemName,
    this.itemSubtext,
```

Replace with:

```dart
    required this.itemCode,
    required this.itemName,
    this.itemGroup,
    this.variantOf,
```

- [ ] **Step 3: Replace the header widget in `_formChildren`**

Find this block (starts after the `Text(title, ...)` widget, spans the code pill + SizedBox + itemName Text):

```dart
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$itemCode'
                    '${itemSubtext != null && itemSubtext!.isNotEmpty ? ' • $itemSubtext' : ''}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontFamily: 'ShureTechMono',
                      fontSize: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  itemName,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: colorScheme.onSurface),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
```

Replace with:

```dart
                Wrap(
                  spacing:             8,
                  runSpacing:          4,
                  crossAxisAlignment:  WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: colorScheme.onSurface),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
```

- [ ] **Step 4: Run analysis**

```
flutter analyze
```

Expected: errors on the two callers of `GlobalItemFormSheet` that still pass `itemSubtext` — `material_request_item_form_sheet.dart` and `stock_entry_form_controller.dart`. These are fixed in later tasks. For now, note the exact error locations; this is expected.

Actually: the MR sheet passes `itemSubtext:` and the SE form controller passes `itemSubtext:` via `UniversalItemFormSheet` which still has the old `itemSubtext` field. So at this step only the MR sheet will break (it passes directly to `GlobalItemFormSheet`). Confirm errors are only in those two files then continue.

- [ ] **Step 5: Commit**

```
git add lib/app/modules/global_widgets/global_item_form_sheet.dart
git commit -m "feat: replace itemSubtext with itemGroup+variantOf on GlobalItemFormSheet, B2 header layout"
```

---

## Task 4: Update `UniversalItemFormSheet` — remove `itemSubtext`

**Files:**
- Modify: `lib/app/shared/item_sheet/universal_item_form_sheet.dart`

- [ ] **Step 1: Remove `itemSubtext` field and constructor param**

Find:

```dart
  final String? itemSubtext;
```

Delete that line.

Find in the constructor:

```dart
    this.itemSubtext,
```

Delete that line.

- [ ] **Step 2: Replace `itemSubtext` with `itemGroup` and `variantOf` in the `GlobalItemFormSheet` call**

Find:

```dart
        itemCode:         controller.itemCode.value,
        itemName:         controller.itemName.value,
        itemSubtext:      itemSubtext,
```

Replace with:

```dart
        itemCode:         controller.itemCode.value,
        itemName:         controller.itemName.value,
        itemGroup:        controller.itemGroup.value,
        variantOf:        controller.variantOf.value,
```

- [ ] **Step 3: Run analysis**

```
flutter analyze
```

Expected: errors only in the callers of `UniversalItemFormSheet` that still pass `itemSubtext:` — currently `stock_entry_form_controller.dart` and `packing_slip_form_controller.dart`. These are fixed in Tasks 5 and 8. Continue.

- [ ] **Step 4: Commit**

```
git add lib/app/shared/item_sheet/universal_item_form_sheet.dart
git commit -m "feat: remove itemSubtext from UniversalItemFormSheet, read itemGroup+variantOf from controller"
```

---

## Task 5: Stock Entry — remove duplicate `itemGroup`, wire `variantOf`

**Files:**
- Modify: `lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart`
- Modify: `lib/app/modules/stock_entry/form/stock_entry_form_controller.dart`

- [ ] **Step 1: Remove duplicate `itemGroup` field from `StockEntryItemFormController`**

In `lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart`, find (around line 693):

```dart
  var itemGroup        = ''.obs;
```

Delete that line. The base class field `ItemSheetControllerBase.itemGroup` takes over.

- [ ] **Step 2: Wire `variantOf` in `initialise()`**

In the same file, find the `initialise()` method. After the `await prepareForItem(...)` call (around line 1125-1135), add:

```dart
    this.variantOf.value = variantOf;
```

The full block after the change looks like:

```dart
    await prepareForItem(
      itemCode:         code,
      itemName:         itemName,
      uom:              uomValue,
      itemGroup:        group,
      hasBatch:         hasBatch,
      hasSerial:        hasSerial,
      existingItem:     editingItem,
      mrReferenceItems: mrReferenceItems,
      scannedBatch:     batchNo,
    );

    this.variantOf.value = variantOf;  // ← add this line

    if (scannedEan8.isNotEmpty) currentScannedEan = scannedEan8;
```

- [ ] **Step 3: Wire `variantOf` in `_loadExistingItem()`**

In the same file, find `_loadExistingItem(StockEntryItem item, ...)`. After `editingItemName.value = item.name;` (around line 961), add:

```dart
    this.variantOf.value = item.customVariantOf ?? '';
```

- [ ] **Step 4: Remove `itemSubtext` from SE form controller sheet call**

In `lib/app/modules/stock_entry/form/stock_entry_form_controller.dart`, find (around line 1179):

```dart
            itemSubtext:      currentVariantOf,
```

Delete that line. `variantOf` now flows through the child controller's `variantOf` field.

- [ ] **Step 5: Run analysis**

```
flutter analyze
```

Expected: no errors in SE files. `packing_slip_form_controller.dart` still has `itemSubtext:` — that's OK, fixed in Task 8.

- [ ] **Step 6: Commit**

```
git add lib/app/modules/stock_entry/form/stock_entry_item_form_controller.dart \
        lib/app/modules/stock_entry/form/stock_entry_form_controller.dart
git commit -m "feat: wire variantOf on SE item controller, remove itemSubtext from SE sheet call"
```

---

## Task 6: Delivery Note item controller — migrate to base fields

**Files:**
- Modify: `lib/app/modules/delivery_note/form/delivery_note_item_form_controller.dart`

- [ ] **Step 1: Delete the two local duplicate fields and the unused getter**

Find and delete these three items:

```dart
  final RxString itemGroupRx      = ''.obs;
  final RxString currentVariantOf = ''.obs;
```

```dart
  RxString get itemGroupValue => itemGroupRx;
```

- [ ] **Step 2: Replace all writes to `itemGroupRx` with `itemGroup` (base field)**

There are two write sites. Find:

```dart
    itemGroupRx.value      = itemGroup;
```
Replace with:
```dart
    this.itemGroup.value   = itemGroup;
```

Find:
```dart
    itemGroupRx.value      = item.itemGroup ?? '';
```
Replace with:
```dart
    this.itemGroup.value   = item.itemGroup ?? '';
```

- [ ] **Step 3: Replace all writes to `currentVariantOf` with `variantOf` (base field)**

There are two write sites. Find:

```dart
    currentVariantOf.value = variantOf;
```
(appears twice — in `_seedItemIdentityFromBase` and `_seedItemIdentityFromItem`)

Replace both with:
```dart
    this.variantOf.value   = variantOf;
```

- [ ] **Step 4: Replace reads of `itemGroupRx.value` and `currentVariantOf.value` in `submit()`**

Find in `submit()` or `_buildSubmitPayload()` (around line 810-820):

```dart
    final variantOf = currentVariantOf.value.trim();
```
Replace with:
```dart
    final variantOf = this.variantOf.value.trim();
```

Find:
```dart
      itemGroup:                 itemGroupRx.value,
```
Replace with:
```dart
      itemGroup:                 this.itemGroup.value,
```

- [ ] **Step 5: Run analysis**

```
flutter analyze
```

Expected: no errors.

- [ ] **Step 6: Commit**

```
git add lib/app/modules/delivery_note/form/delivery_note_item_form_controller.dart
git commit -m "feat: replace DN itemGroupRx/currentVariantOf with base class fields"
```

---

## Task 7: Purchase Receipt — wire `itemGroup` and `variantOf`

**Files:**
- Modify: `lib/app/modules/purchase_receipt/form/purchase_receipt_item_form_controller.dart`
- Modify: `lib/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart`

- [ ] **Step 1: Wire fields in `initForCreate()`**

In `lib/app/modules/purchase_receipt/form/purchase_receipt_item_form_controller.dart`, find `initForCreate()`. After `itemName.value = name;`, add:

```dart
    itemGroup.value = '';
    variantOf.value = '';
```

These are reset to empty for a new item; the actual values are set in `initialise()` (next step).

- [ ] **Step 2: Wire fields in `initForEdit()`**

In the same file, find `initForEdit()`. After `itemName.value = item.itemName ?? '';`, add:

```dart
    itemGroup.value = item.itemGroup ?? '';
    variantOf.value = item.customVariantOf ?? '';
```

- [ ] **Step 3: Wire `variantOf` in `initialise()`**

In the same file, find `initialise()`. After the `if (editingItem != null) { ... } else { ... }` block, add:

```dart
    // Set variantOf from caller for add-mode; edit-mode already set it in initForEdit.
    if (editingItem == null) {
      this.variantOf.value = variantOfValue ?? '';
    }
```

- [ ] **Step 4: Add `itemGroup` param to `_openItemSheet()` in PR form controller**

In `lib/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart`, find `_openItemSheet({...})` and add an optional param:

```dart
  Future<void> _openItemSheet({
    required String itemCode,
    required String itemName,
    String?  batchNo,
    String?  scannedEan,
    String?  variantOf,
    String?  itemGroup,      // ← add this
    String?  uom,
    PurchaseReceiptItem? editingItem,
  }) async {
```

Pass it to `child.initialise()`:

```dart
    child.initialise(
      parent:         this,
      code:           itemCode,
      name:           itemName,
      batchNo:        batchNo,
      scannedEan:     scannedEan,
      variantOfValue: variantOf,
      uomValue:       uom,
      editingItem:    editingItem,
    );
```

(itemGroup is handled inside initForEdit/initForCreate — no need to thread it further since initForEdit reads it from the item model directly, and initForCreate resets it to empty; the scan path will pass it via a separate mechanism in Step 5.)

Actually, there is an issue: `initForCreate` always sets `itemGroup.value = ''`, but the scan path (when calling `openSheetForNewItem`) might know the itemGroup. The simplest fix: add `String? itemGroup` to `initialise()` and set it after the if/else block:

```dart
  void initialise({
    required PurchaseReceiptFormController parent,
    required String code,
    required String name,
    String?  batchNo,
    String?  scannedEan,
    String?  variantOfValue,
    String?  itemGroupValue,   // ← add this
    String?  uomValue,
    PurchaseReceiptItem? editingItem,
  }) {
    _parent = parent;
    currentScannedEan = scannedEan ?? '';

    if (editingItem != null) {
      final items  = parent.purchaseReceipt.value?.items ?? [];
      final idx    = items.indexWhere((i) => i.name == editingItem.name);
      initForEdit(index: idx >= 0 ? idx : 0, item: editingItem);
    } else {
      initForCreate(code: code, name: name, uom: uomValue ?? 'Nos', batchNo: batchNo);
      this.itemGroup.value = itemGroupValue ?? '';
      this.variantOf.value = variantOfValue ?? '';
    }

    _parent.linkToPurchaseOrder(code, this);
    validateSheet();
  }
```

Remove the separate "Step 3" from above — this `initialise()` change handles it. Remove `itemGroup.value = '';` from `initForCreate()` as well (no longer needed as a reset since `initialise` handles it for create mode).

- [ ] **Step 5: Pass `itemGroup` from PR form controller callers**

In `lib/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart`:

**In `openSheetForNewItem`**, add `itemGroup` param and pass it to `_openItemSheet`:

```dart
  void openSheetForNewItem({
    required String itemCode,
    required String itemName,
    String?  batchNo,
    String?  scannedEan,
    String?  variantOf,
    String?  itemGroup,      // ← add
    String?  uom,
  }) {
    _openItemSheet(
      itemCode:   itemCode,
      itemName:   itemName,
      batchNo:    batchNo,
      scannedEan: scannedEan,
      variantOf:  variantOf,
      itemGroup:  itemGroup,  // ← add
      uom:        uom,
    );
  }
```

**In `editItem`**, pass itemGroup from the model (available after Task 1):

```dart
      await _openItemSheet(
        itemCode:    item.itemCode,
        itemName:    item.itemName ?? '',
        variantOf:   item.customVariantOf,
        itemGroup:   item.itemGroup,         // ← add
        uom:         item.uom,
        editingItem: item,
      );
```

**In the scan path** (around line 759-766), pass itemGroup from `itemData`:

```dart
        openSheetForNewItem(
          itemCode:   itemData.itemCode,
          itemName:   itemData.itemName,
          batchNo:    result.batchNo,
          scannedEan: currentScannedEan,
          variantOf:  itemData.variantOf,
          itemGroup:  itemData.itemGroup,   // ← add
          uom:        itemData.stockUom,
        );
```

(`itemData` here is `ItemModel` which has `itemGroup` field.)

- [ ] **Step 6: Update `_openItemSheet` to thread `itemGroup` to `initialise()`**

In `_openItemSheet`, update the `child.initialise()` call to pass `itemGroupValue`:

```dart
    child.initialise(
      parent:          this,
      code:            itemCode,
      name:            itemName,
      batchNo:         batchNo,
      scannedEan:      scannedEan,
      variantOfValue:  variantOf,
      itemGroupValue:  itemGroup,   // ← add
      uomValue:        uom,
      editingItem:     editingItem,
    );
```

- [ ] **Step 7: Run analysis**

```
flutter analyze
```

Expected: no errors.

- [ ] **Step 8: Commit**

```
git add lib/app/modules/purchase_receipt/form/purchase_receipt_item_form_controller.dart \
        lib/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart
git commit -m "feat: wire itemGroup+variantOf on PR item controller"
```

---

## Task 8: Packing Slip — wire `itemGroup` and `variantOf`, remove `currentItemVariantOf`

**Files:**
- Modify: `lib/app/modules/packing_slip/form/packing_slip_item_form_controller.dart`
- Modify: `lib/app/modules/packing_slip/form/packing_slip_form_controller.dart`

- [ ] **Step 1: Add params to `_seedItemIdentity` in PS item controller**

In `lib/app/modules/packing_slip/form/packing_slip_item_form_controller.dart`, find:

```dart
  void _seedItemIdentity({
    required String itemCode,
    required String itemName,
  }) {
    this.itemCode.value = itemCode;
    this.itemName.value = itemName;
  }
```

Replace with:

```dart
  void _seedItemIdentity({
    required String itemCode,
    required String itemName,
    String itemGroup = '',
    String variantOf = '',
  }) {
    this.itemCode.value   = itemCode;
    this.itemName.value   = itemName;
    this.itemGroup.value  = itemGroup;
    this.variantOf.value  = variantOf;
  }
```

- [ ] **Step 2: Add params to `initialise()` in PS item controller**

Find:

```dart
  void initialise({
    required PackingSlipFormController parent,
    required String itemCode,
    required String itemName,
    PackingSlipItem? editingItem,
  }) {
    _bindParent(parent);
    _seedItemIdentity(itemCode: itemCode, itemName: itemName);
```

Replace with:

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
```

- [ ] **Step 3: Update `_wireChildForAdd` in PS form controller**

In `lib/app/modules/packing_slip/form/packing_slip_form_controller.dart`, find:

```dart
  PackingSlipItemFormController _wireChildForAdd(DeliveryNoteItem item) {
    final child = Get.put(PackingSlipItemFormController());
    child.initialise(
      parent:   this,
      itemCode: item.itemCode,
      itemName: item.itemName ?? '',
    );
```

Replace with:

```dart
  PackingSlipItemFormController _wireChildForAdd(DeliveryNoteItem item) {
    final child = Get.put(PackingSlipItemFormController());
    child.initialise(
      parent:    this,
      itemCode:  item.itemCode,
      itemName:  item.itemName ?? '',
      itemGroup: item.itemGroup ?? '',
      variantOf: item.customVariantOf ?? '',
    );
```

- [ ] **Step 4: Update `_wireChildForEdit` in PS form controller**

Find:

```dart
  PackingSlipItemFormController _wireChildForEdit(
      DeliveryNoteItem dnItem,
      PackingSlipItem  slipItem,
      ) {
    final child = Get.put(PackingSlipItemFormController());
    child.initialise(
      parent:      this,
      itemCode:    dnItem.itemCode,
      itemName:    dnItem.itemName ?? '',
      editingItem: slipItem,
    );
```

Replace with:

```dart
  PackingSlipItemFormController _wireChildForEdit(
      DeliveryNoteItem dnItem,
      PackingSlipItem  slipItem,
      ) {
    final child = Get.put(PackingSlipItemFormController());
    child.initialise(
      parent:      this,
      itemCode:    dnItem.itemCode,
      itemName:    dnItem.itemName ?? '',
      itemGroup:   dnItem.itemGroup ?? '',
      variantOf:   slipItem.customVariantOf ?? '',
      editingItem: slipItem,
    );
```

- [ ] **Step 5: Remove `itemSubtext` from `UniversalItemFormSheet` call and `currentItemVariantOf` field**

In `packing_slip_form_controller.dart`, find the `UniversalItemFormSheet` call (around line 726). It contains:

```dart
            itemSubtext:      currentItemVariantOf,
```

Delete that line.

Then find the field declaration (around line 85):

```dart
  String? currentItemVariantOf;
```

Delete that line.

Then find where `currentItemVariantOf` is assigned (around line 1013):

```dart
    currentItemVariantOf = item.customVariantOf;
```

Delete that line.

- [ ] **Step 6: Run analysis**

```
flutter analyze
```

Expected: no errors.

- [ ] **Step 7: Commit**

```
git add lib/app/modules/packing_slip/form/packing_slip_item_form_controller.dart \
        lib/app/modules/packing_slip/form/packing_slip_form_controller.dart
git commit -m "feat: wire itemGroup+variantOf on PS item controller, remove currentItemVariantOf"
```

---

## Task 9: Purchase Order — wire `itemGroup` and `variantOf`

**Files:**
- Modify: `lib/app/modules/purchase_order/form/purchase_order_item_form_controller.dart`
- Modify: `lib/app/modules/purchase_order/form/purchase_order_form_controller.dart`

- [ ] **Step 1: Add `itemGroup` and `variantOf` params to `initialise()` in PO item controller**

In `lib/app/modules/purchase_order/form/purchase_order_item_form_controller.dart`, find `initialise(...)`. Its current signature ends with `String? modifiedBy`. Add two optional params:

```dart
  void initialise({
    required PurchaseOrderFormController parentController,
    required String code,
    required String name,
    required String uom,
    required double qty,
    required double rate,
    String? rowId,
    String? scheduleDate,
    String? owner,
    String? creation,
    String? modified,
    String? modifiedBy,
    String? itemGroupValue,   // ← add
    String? variantOfValue,   // ← add
  }) {
```

After `itemName.value = name;` (around line 135), add:

```dart
    itemGroup.value = itemGroupValue ?? '';
    variantOf.value = variantOfValue ?? '';
```

- [ ] **Step 2: Add params to `_openItemSheet()` in PO form controller**

In `lib/app/modules/purchase_order/form/purchase_order_form_controller.dart`, find `_openItemSheet({...})`:

```dart
  Future<void> _openItemSheet({
    required String code,
    required String name,
    required String uom,
    required double rate,
    required double qty,
    String? rowId,
    String? scheduleDate,
    String? owner,
    String? creation,
    String? modified,
    String? modifiedBy,
  }) async {
```

Add two optional params at the end:

```dart
    String? itemGroupValue,
    String? variantOfValue,
```

Pass them in the `sheetCtrl.initialise()` call:

```dart
    sheetCtrl.initialise(
      parentController: this,
      code:         code,
      name:         name,
      uom:          uom,
      qty:          qty,
      rate:         rate,
      rowId:        rowId,
      scheduleDate: scheduleDate,
      owner:        owner,
      creation:     creation,
      modified:     modified,
      modifiedBy:   modifiedBy,
      itemGroupValue: itemGroupValue,   // ← add
      variantOfValue: variantOfValue,   // ← add
    );
```

- [ ] **Step 3: Pass values at the two `_openItemSheet` call sites**

**Scan path** (around line 496-502):

```dart
        _openItemSheet(
          code:           item.itemCode,
          name:           item.itemName,
          uom:            item.stockUom ?? 'Nos',
          rate:           0.0,
          qty:            1.0,
          itemGroupValue: item.itemGroup,      // ← add
          variantOfValue: item.variantOf,      // ← add
        );
```

(Both in the direct scan hit and the `MultiItemSelectionSheet.onItemSelected` callback — there are two similar call sites, both use `item` which is `ItemModel`.)

**Edit path** (around line 540-552):

```dart
      _openItemSheet(
        code:           item.itemCode,
        name:           item.itemName,
        uom:            item.uom ?? '',
        rate:           item.rate,
        qty:            item.qty,
        rowId:          item.name,
        scheduleDate:   item.scheduleDate,
        owner:          item.owner,
        creation:       item.creation,
        modified:       item.modified,
        modifiedBy:     item.modifiedBy,
        itemGroupValue: item.itemGroup,          // ← add (PurchaseOrderItem after Task 1)
        variantOfValue: item.customVariantOf,    // ← add
      );
```

- [ ] **Step 4: Run analysis**

```
flutter analyze
```

Expected: no errors.

- [ ] **Step 5: Commit**

```
git add lib/app/modules/purchase_order/form/purchase_order_item_form_controller.dart \
        lib/app/modules/purchase_order/form/purchase_order_form_controller.dart
git commit -m "feat: wire itemGroup+variantOf on PO item controller"
```

---

## Task 10: Material Request — add `bsItemGroup`, replace `itemSubtext`

**Files:**
- Modify: `lib/app/modules/material_request/form/material_request_form_controller.dart`
- Modify: `lib/app/modules/material_request/form/widgets/material_request_item_form_sheet.dart`

- [ ] **Step 1: Add `bsItemGroup` field to MR form controller**

In `lib/app/modules/material_request/form/material_request_form_controller.dart`, find:

```dart
  var bsItemVariantOf = RxnString();
```

Add immediately after:

```dart
  var bsItemGroup     = RxnString();
```

- [ ] **Step 2: Populate `bsItemGroup` in `openItemSheet()`**

In `openItemSheet()`, find the reset block at the top:

```dart
    bsItemVariantOf.value = null;
```

Add immediately after:

```dart
    bsItemGroup.value = null;
```

Find the edit-mode branch (item != null):

```dart
      bsItemVariantOf.value = variantOf ?? item.variantOf;
```

Add immediately after:

```dart
      bsItemGroup.value = item.itemGroup ?? '';
```

Find the add-mode branch (newCode != null):

```dart
      bsItemVariantOf.value = variantOf;
```

Add immediately after (the itemGroup for scan path is passed via `_openItemSheet` callers — see Step 3):

```dart
      // bsItemGroup is set by the caller via the itemGroup param
```

Actually, to pass itemGroup from the scan path, add `String? itemGroup` to `openItemSheet()` params:

```dart
  void openItemSheet({
    MaterialRequestItem? item,
    String? newCode,
    String? newName,
    String? variantOf,
    String? itemGroup,        // ← add
  }) {
```

Then in the add-mode branch, add:

```dart
      bsItemGroup.value = itemGroup;
```

And in the scan path (around line 587-591) that calls `openItemSheet`, pass `itemGroup`:

```dart
        openItemSheet(
          newCode:   result.itemData!.itemCode,
          newName:   result.itemData!.itemName,
          variantOf: result.itemData!.variantOf,
          itemGroup: result.itemData!.itemGroup,   // ← add
        );
```

For the existing-item callers that pass `item:`, the group comes from `item.itemGroup` (handled above in the edit branch).

- [ ] **Step 3: Replace `itemSubtext` in `MaterialRequestItemFormSheet`**

In `lib/app/modules/material_request/form/widgets/material_request_item_form_sheet.dart`, find:

```dart
      final variantOf  = controller.bsItemVariantOf.value;
```

Add immediately after:

```dart
      final itemGroup  = controller.bsItemGroup.value;
```

Find:

```dart
        itemSubtext:  (variantOf != null && variantOf.isNotEmpty)
                          ? variantOf
                          : null,
```

Replace with:

```dart
        itemGroup:  (itemGroup != null && itemGroup.isNotEmpty) ? itemGroup : null,
        variantOf:  (variantOf != null && variantOf.isNotEmpty) ? variantOf : null,
```

- [ ] **Step 4: Run analysis**

```
flutter analyze
```

Expected: no errors. This is the last task — the codebase should be fully clean.

- [ ] **Step 5: Run all tests**

```
flutter test
```

Expected: all tests pass including the 8 new model tests from Task 1.

- [ ] **Step 6: Commit**

```
git add lib/app/modules/material_request/form/material_request_form_controller.dart \
        lib/app/modules/material_request/form/widgets/material_request_item_form_sheet.dart
git commit -m "feat: wire bsItemGroup on MR form controller, replace itemSubtext on MR sheet"
```

---

## Self-Review Checklist (done before saving)

- [x] Spec Layer 1 (base class): Task 2 ✓
- [x] Spec Layer 2 (GlobalItemFormSheet): Task 3 ✓
- [x] Spec Layer 3 (UniversalItemFormSheet): Task 4 ✓
- [x] Spec Layer 4 (models): Task 1 ✓
- [x] Spec Layer 5 (SE): Task 5 ✓
- [x] Spec Layer 6 (DN): Task 6 ✓
- [x] Spec Layer 7 (PR): Task 7 ✓
- [x] Spec Layer 8 (PS): Task 8 ✓
- [x] Spec Layer 9 (PO): Task 9 ✓
- [x] Spec Layer 10 (MR): Task 10 ✓
- [x] Rollout order matches spec (models → base → global widgets → DocTypes) ✓
- [x] `itemSubtext` removed from all callers ✓ (SE: Task 5, PS: Task 8, MR: Task 10)
- [x] No placeholder text in steps ✓
- [x] Field name `itemGroup` consistent across all tasks ✓
- [x] Field name `variantOf` consistent across all tasks ✓
