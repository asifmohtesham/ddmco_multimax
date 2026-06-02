# POS Upload — Item Tile Expansion & Packing Progress

**Date:** 2026-05-21  
**Scope:** `lib/app/modules/pos_upload/form/pos_upload_form_controller.dart` + `pos_upload_form_screen.dart`

---

## Overview

Two linked enhancements to each item tile in the POS Upload Items tab:

1. **Expandable tile** — tap a tile to reveal the Packing Slip items that reference this POS Upload item (`ps.custom_po_no == posUpload.name` AND `psItem.custom_invoice_serial_number == item.idx.toString()`). Each row shows item name, item code, variant, country of origin, and qty.

2. **Packing progress bar** — for items that are matched in a Delivery Note (`resolvedSerial != null`), replace the static "Matched" label with a `LinearProgressIndicator` showing `Σ psItem.qty Packed / dnItem.qty DN Qty` once PS data has loaded.

---

## Section 1 — Controller

### 1a. New data class

Add `PsItemEntry` to `pos_upload_form_controller.dart` alongside `CaseOption` and `PackingSlipInfo`:

```dart
class PsItemEntry {
  final String psName;
  final int? fromCaseNo;
  final int? toCaseNo;
  final PackingSlipItem item;
  const PsItemEntry({
    required this.psName,
    this.fromCaseNo,
    this.toCaseNo,
    required this.item,
  });
}
```

### 1b. Two new observable maps

```dart
/// idx → DN item qty (null = item not found in DN)
final resolvedDnQty = <int, double?>{}.obs;

/// idx → PS items matching this POS Upload item (empty list = none matched)
final resolvedPsItems = <int, List<PsItemEntry>>{}.obs;
```

### 1c. `_buildDnQtyMap` private method

Add alongside `_buildSerialMap`:

```dart
void _buildDnQtyMap({
  required List<PosUploadItem> posItems,
  required double? Function(int idx) matchQty,
}) {
  final map = <int, double?>{};
  for (final item in posItems) {
    map[item.idx] = matchQty(item.idx);
  }
  resolvedDnQty.value = map;
}
```

### 1d. `_fetchDeliveryNote` — populate `resolvedDnQty`

After the existing `_buildSerialMap(...)` call, add:

```dart
_buildDnQtyMap(
  posItems: upload.items,
  matchQty: (idx) =>
      dn.items.firstWhereOrNull((i) => i.idx == idx)?.qty,
);
```

### 1e. `_fetchPackingSlips` — populate `resolvedPsItems`

After the existing block that populates `resolvedPackingSlips`, add:

```dart
final psItemsMap = <int, List<PsItemEntry>>{};
for (final item in upload.items) {
  final entries = <PsItemEntry>[];
  for (final ps in slips) {
    if (ps.customPoNo != upload.name) continue;
    for (final psItem in ps.items) {
      if (psItem.customInvoiceSerialNumber == item.idx.toString()) {
        entries.add(PsItemEntry(
          psName: ps.name,
          fromCaseNo: ps.fromCaseNo,
          toCaseNo: ps.toCaseNo,
          item: psItem,
        ));
      }
    }
  }
  psItemsMap[item.idx] = entries;
}
resolvedPsItems.value = psItemsMap;
```

`resolvedPsItems` is populated for every POS Upload item: matched items have a non-empty list, unmatched items have an empty list. No null check needed in the UI.

---

## Section 2 — Progress bar

### State machine

For each item card the "status row" (the small row below the item name) uses this logic:

| Condition | Shown |
|---|---|
| `isLoadingLinked == true` | "Checking…" spinner (unchanged) |
| Matched + `isLoadingPS == true` | "Matched" text (PS not yet loaded) |
| Matched + PS loaded + `psItems.isNotEmpty` | `LinearProgressIndicator` + label |
| Matched + PS loaded + `psItems.isEmpty` | "Matched" text (no PS rows for this item) |
| Not matched (`resolvedSerial == null`) | "Not found" (unchanged) |

"Matched" here means `resolvedSerial != null && resolvedSerial!.isNotEmpty`.

### Progress calculation

```dart
final packedQty = psItems.fold(0.0, (s, e) => s + e.item.qty);
final ratio = (dnQty != null && dnQty > 0) ? (packedQty / dnQty).clamp(0.0, 1.0) : null;
```

- `ratio != null` → determinate bar: `LinearProgressIndicator(value: ratio)`
- `ratio == null` → indeterminate bar (dnQty unknown or zero)

### Label

```
"${fmtQty(packedQty)} Packed / ${fmtQty(dnQty ?? 0)} DN Qty"
```

When `dnQty == null` replace the denominator with `"–"`:

```
"${fmtQty(packedQty)} Packed / – DN Qty"
```

### Visual placement

The progress bar row replaces the match status `Row` (icon + text) when the bar should be shown. It sits in the same vertical slot (below the item name, above the `Divider`):

```
[item_name]                              [chevron?]
[LinearProgressIndicator]
[label text — labelSmall, onSurfaceVariant]
────────────────────────────────────────────
[Qty]   [Rate]   [Amount]
[chips]
[expanded content — if open]
```

---

## Section 3 — Expandable tile

### `_ItemCard` → `StatefulWidget`

Convert from `StatelessWidget` to `StatefulWidget`. Add local state:

```dart
bool _expanded = false;
```

### New constructor params

```dart
final double? dnQty;
final List<PsItemEntry> psItems;
```

### Tap behaviour

The card is wrapped in `InkWell` **only** when `psItems.isNotEmpty`. When `psItems.isEmpty` the card is not interactive and shows no chevron.

```dart
Widget card = Card(...);
if (psItems.isNotEmpty) {
  card = InkWell(
    onTap: () => setState(() => _expanded = !_expanded),
    borderRadius: BorderRadius.circular(12),
    child: card,
  );
}
return card;
```

### Expand chevron

When `psItems.isNotEmpty`, show an `AnimatedRotation` chevron in the top-right of the header `Row`:

```dart
AnimatedRotation(
  turns: _expanded ? 0.5 : 0.0,
  duration: const Duration(milliseconds: 200),
  child: Icon(Icons.expand_more, size: 18, color: cs.onSurfaceVariant),
)
```

### Expanded content

Rendered below the chips row. Wrapped in `AnimatedSize` for height animation:

```dart
AnimatedSize(
  duration: const Duration(milliseconds: 200),
  curve: Curves.easeInOut,
  child: _expanded ? _buildPsItemsPanel(context) : const SizedBox.shrink(),
)
```

`_buildPsItemsPanel` returns a `Container` with:
- `margin: EdgeInsets.only(top: 8)`
- `padding: EdgeInsets.all(10)`
- `decoration`: `surfaceContainerHighest` fill, `outlineVariant` border, `BorderRadius.circular(8)`

Each `PsItemEntry` produces one row. Multiple entries may come from different PSes (e.g., the same serial split across Cases 1–3 and Cases 4–6), so the case label is shown **per-row**, not as a shared header.

Row layout:
```
[Cases 1–3 chip]  Item Name                    qty (tertiary)
                  item_code · variant · country  (labelSmall, onSurfaceVariant)
```

- Leading: `_InfoChip`-style case label (`fromCaseNo`–`toCaseNo` if both present, else `psName`), 14 dp height, `secondaryContainer` fill.
- Middle: `Column` with `itemName` (bodyMedium w600) and a subline of `itemCode`, `customVariantOf` (if non-null), `customCountryOfOrigin` (if non-null), joined with ` · ` separator.
- Trailing: `fmtQty(psItem.qty)` (bodyMedium, tertiary colour).

Where `variantPart = psItem.customVariantOf != null ? ' · ${psItem.customVariantOf}' : ''`  
And `countryPart = psItem.customCountryOfOrigin != null ? ' · ${psItem.customCountryOfOrigin}' : ''`

Rows are separated by `Divider(height: 16, thickness: 0.5)`. First row has no leading divider.

### `_ItemsTabState` — pass new params

In the `itemBuilder`:

```dart
return Obx(() => _ItemCard(
  item: item,
  displayIndex: item.idx,
  isLoadingLinked: ctrl.isLoadingLinked.value,
  isLoadingPS: ctrl.isLoadingPackingSlips.value,
  linkedDocType: ctrl.linkedDocType.value,
  resolvedSerial: ctrl.resolvedSerials[item.idx],
  packingSlipInfo: ctrl.resolvedPackingSlips[item.idx],
  hasLinkedDoc: ctrl.resolvedSerials.isNotEmpty,
  // NEW
  dnQty: ctrl.resolvedDnQty[item.idx],
  psItems: ctrl.resolvedPsItems[item.idx] ?? [],
));
```

---

## Files Changed

| File | Change |
|---|---|
| `pos_upload_form_controller.dart` | Add `PsItemEntry`; add `resolvedDnQty`, `resolvedPsItems`; add `_buildDnQtyMap`; extend `_fetchDeliveryNote` and `_fetchPackingSlips` |
| `pos_upload_form_screen.dart` | Convert `_ItemCard` to `StatefulWidget`; add progress bar; add expandable panel; pass new params from `_ItemsTabState` |

---

## Out of Scope

- Navigation to Packing Slip form from the expanded panel
- Expansion persistence across list rebuilds (local `_expanded` resets on widget disposal)
- SE (Stock Entry) prefix items — expansion only applies to ML/KA items that have a DN and PSes
