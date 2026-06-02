# POS Upload Form — Details & Items Tab Fixes

**Date:** 2026-05-20  
**Scope:** `lib/app/modules/pos_upload/form/` + `lib/app/data/models/packing_slip_model.dart`

---

## Overview

Six targeted changes to the POS Upload form screen and its controller:

1. Exclude Cancelled Packing Slips from all counts and logic
2. Rename "items matched" → "items packed" in the PS banner
3. Make Status, Total Amount, and Total Quantity always read-only
4. Fix the Cases chip quantity calculation
5. Add a visual divider between "All Cases" and individual case chips
6. Remove the DN / PS aggregate summary chips from the Items Tab strip

---

## Section 1 — Bug fixes & text changes

### 1a. Exclude Cancelled Packing Slips

**File:** `pos_upload_form_controller.dart` → `_fetchPackingSlips`

After fetching all PS detail responses and building `slips`, filter out cancelled documents before any downstream logic:

```dart
slips = slips.where((ps) => ps.docstatus != 2).toList();
```

This single filter gates:
- `packingSlips.assignAll(slips)` (banner count on Details tab)
- The `idx → PackingSlipInfo` map (serial matching)
- `caseOptions` build (case filter chips)

**Model reference:** `PackingSlip.docstatus == 2` means Cancelled (ERPNext convention).

### 1b. PS Banner text rename

**File:** `pos_upload_form_screen.dart` — `_DetailsTabState.build`, inside the `psBanner` block.

```dart
// before
'$psCount Packing Slip${psCount == 1 ? '' : 's'} · $psMatched / ${ctrl.resolvedSerials.length} items matched'

// after
'$psCount Packing Slip${psCount == 1 ? '' : 's'} · $psMatched / ${ctrl.resolvedSerials.length} items packed'
```

---

## Section 2 — Details Tab: always read-only fields

**Constraint:** Date, Status, Total Amount, and Total Quantity are display-only. No field on this tab is user-editable.

### UI changes (`pos_upload_form_screen.dart`)

- **Status** `DropdownButtonFormField`: always `onChanged: null`; always `filled: true` with `fillColor: cs.surfaceContainerHighest`. Remove the `!_canEditStatus` conditionals.
- **Total Amount** `TextFormField`: always `readOnly: true`; always `filled: true`; always show the lock `suffixIcon`. Remove `!_canEditAmount` conditionals.
- **Total Quantity** `TextFormField`: same as Total Amount. Remove `!_canEditQty` conditionals.
- **Update button**: remove the entire `if (canSave) Obx(...)` block.
- **`_DetailsTabState`**: remove `_canEditStatus`, `_canEditAmount`, `_canEditQty` fields; remove `canSave` local variable. Keep the `_amountCtrl`, `_qtyCtrl` TextEditingControllers and the `ever(ctrl.posUpload, ...)` sync worker — they are still needed to reflect updated values after a pull-to-refresh reload.

### Controller changes (`pos_upload_form_controller.dart`)

Remove all code that existed solely to gate these three fields:
- `_canEditStatus`, `_canEditAmount`, `_canEditQty` cached fields
- `canEditStatus`, `canEditAmount`, `canEditQty` public getters
- `fetchDocTypePermissions()` method
- `_fieldLevels`, `_levelWriteRoles` maps
- `_canEdit(String)` private method
- `permissionsLoaded` observable
- `canEdit(String)` public alias
- Remove `fetchDocTypePermissions()` from the `Future.wait` in `_loadData`

The `ApiProvider` import stays (used elsewhere); the `AuthenticationController` import can be removed if nothing else in this file uses it.

---

## Section 3 — Items Tab: case chips + summary strip

### 3a. Cases chip quantity fix (hotfix)

**File:** `pos_upload_form_controller.dart` → `_fetchPackingSlips`, `caseOptions.assignAll(...)` block.

```dart
// before — sums POS Upload item quantities for items assigned to this PS
final posQty = upload.items
    .where((item) => psMap[item.idx]?.psName == ps.name)
    .fold<double>(0, (s, item) => s + item.quantity);

// after — sums the PS's own item quantities (physical packed qty)
final psQty = ps.items.fold<double>(0, (s, psItem) => s + psItem.qty);
```

Pass `totalQty: psQty` to `CaseOption`.

### 3b. Case chip divider

**File:** `pos_upload_form_screen.dart` → `_ItemsTabState.build`, inside the `Obx` that renders the case filter chip row.

In the `ListView.separated` `itemBuilder`, when `i == 0` (the "All Cases" chip), render it followed by a thin vertical divider as the next logical item. Simplest approach: change the chip row to a `Row` with explicit children rather than a `ListView`, or insert a non-selectable divider item at index 1.

**Recommended:** After the "All Cases" `FilterChip`, insert:
```dart
Container(
  width: 1,
  height: 26,
  color: Theme.of(context).colorScheme.outlineVariant,
)
```
as a non-interactive item between index 0 and index 1 of the scrollable row.

Implementation note: the `ListView.separated`'s `itemCount` currently includes `options.length + 1`. The divider can be handled by returning it as the separator between index 0 and index 1 via `separatorBuilder`, replacing the uniform `SizedBox(width: 8)` with a conditional:

```dart
separatorBuilder: (_, i) => i == 0
    ? Row(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 8),
        Container(width: 1, height: 26, color: cs.outlineVariant),
        const SizedBox(width: 8),
      ])
    : const SizedBox(width: 8),
```

### 3c. Remove DN / PS summary chips

**File:** `pos_upload_form_screen.dart` → `_ItemsTabState.build`, the `Obx` progress summary strip.

Remove:
- The `dnMatched` and `psMatchedCount` local variables
- The `_SummaryChip` for DN
- The `_SummaryChip` for PS
- The `if (hasPS)` guard

Keep:
- The loading state branch (linear progress bar while fetching DN / PSes)
- The active case filter `_SummaryChip` (shows current filter name when a case is selected)

The container (`Container` with `surfaceContainer` background) should only appear when there is something to show. After removing the DN/PS chips, the non-loading branch renders content only when `ctrl.activeCaseFilter.value != null`. Update the guard:

```dart
// Only show the strip during loading OR when a case filter is active
if (!isLoadingLinked && !isLoadingPS && ctrl.activeCaseFilter.value == null) {
  return const SizedBox.shrink();
}
```

The `hasLinkedDoc` check (`resolvedSerials.isNotEmpty`) can be removed since the strip no longer needs linked-doc data to display anything meaningful.

---

## Files Changed

| File | Change |
|------|--------|
| `pos_upload_form_controller.dart` | Remove permission infrastructure; fix PS qty calculation; filter cancelled PSes |
| `pos_upload_form_screen.dart` | Make Status/Amount/Qty read-only; remove Update button; add chip divider; remove DN/PS summary chips |

---

## Out of Scope

- Navigation from the DN/SE banner to the linked document form screen (existing TODO comment left in place)
- Any changes to the list screen (`pos_upload_screen.dart`)
- Packing Slip provider / API filter changes (cancelled PSes are excluded client-side after fetch)
