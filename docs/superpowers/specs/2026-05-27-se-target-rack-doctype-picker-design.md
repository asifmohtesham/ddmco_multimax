# SE Item Form: Target Rack DocType Picker — Design Spec

**Date:** 2026-05-27
**Branch:** release/play-store-beta-1-build-5

---

## Problem

The target rack picker in the Stock Entry Item Form sheet uses `RackPickerController.load()`, which calls `getStockBalanceWithDimension` (Stock Balance report). This only returns racks that already have stock for the scanned item. For a target rack (destination), no stock is expected yet, so the picker shows an empty list or, at best, racks from a different context. The expected behaviour is to list all Rack DocType records filtered by the item-level target warehouse.

Additionally, the current `RackPickerSheet` tile widget marks any entry with `availableQty == 0` as `SufficiencyStatus.empty`, which greys it out and makes it non-tappable (`onTap: null`). All target racks would be untappable in the current design.

---

## Solution

Add `isTargetMode` (`RxBool`) and `loadForTarget(warehouse, currentRack)` to `RackPickerController`. The new method fetches rack names directly from the Rack DocType API filtered by warehouse, builds entries with `requestedQty: 0.0` (→ `SufficiencyStatus.unknown`, grey but **tappable**), and marks `isTargetMode = true`. `RackPickerSheet` reads this flag to suppress stock-centric UI. `TargetRackFieldAdapter.browseRacks()` calls `loadForTarget` instead of `load`.

---

## Architecture

```
TargetRackFieldAdapter.browseRacks()
        │
        │  calls loadForTarget() instead of load()
        ▼
RackPickerController
  ├── isTargetMode: RxBool            (new)
  └── loadForTarget(warehouse, currentRack)
        │
        │  GET /api/resource/Rack
        │  ?filters=[["warehouse","=",wh]]&fields=["name"]&limit=0
        ▼
ApiProvider.getRacksByWarehouse(warehouse) → List<String>
        │
        └── RackPickerEntry(availableQty: 0, requestedQty: 0)
              → SufficiencyStatus.unknown → tappable, grey dot

RackPickerSheet reads ctrl.isTargetMode:
  • empty state  →  'No racks found' (not 'No racks found with stock')
  • per-tile     →  _SufficiencyBar hidden
  • summary row  →  sufficiency badge hidden; replaced with rack count
```

---

## Files Changed

| Action | File | What changes |
|--------|------|-------------|
| Modify | `lib/app/data/providers/api_provider.dart` | Add `getRacksByWarehouse(String warehouse) → Future<List<String>>` |
| Modify | `lib/app/shared/item_sheet/rack_picker_controller.dart` | Add `isTargetMode: RxBool`; add `loadForTarget(warehouse, currentRack)`; add `_compareEntriesByLocation` sort helper |
| Modify | `lib/app/shared/item_sheet/rack_picker_sheet.dart` | Read `isTargetMode` to hide `_SufficiencyBar`, fix empty-state message, hide sufficiency badge |
| Modify | `lib/app/shared/item_sheet/dual_rack_adapters.dart` | `TargetRackFieldAdapter.browseRacks()` calls `loadForTarget` instead of `load` |

---

## Detailed Behaviour

### `ApiProvider.getRacksByWarehouse(String warehouse)`

- Calls `GET /api/resource/Rack?filters=[["warehouse","=","<wh>"]]&fields=["name"]&limit=0`
- Returns `List<String>` of rack `name` values (the rack asset codes, e.g. `KA-WH-DXB1-101A`).
- Returns empty list on any error or empty response.

### `RackPickerController.loadForTarget({required String warehouse, required String currentRack})`

- Sets `isTargetMode.value = true`.
- Sets `_warehouse = warehouse`, `selectedRack.value = currentRack`.
- Clears `_itemCode`, `_batchNo`, `_requestedQty` (header shows warehouse chip only).
- Resets `filterByWarehouse.value = true`, `usedFallback.value = false`.
- If `warehouse` is empty: sets `entries` to empty, returns immediately (no API call).
- Otherwise: calls `getRacksByWarehouse(warehouse)`, builds entries with `availableQty: 0.0, requestedQty: 0.0`.
- Sort: aisle ascending, then shelf ascending (`_compareEntriesByLocation`). The sufficiency-first group is moot (all entries are `SufficiencyStatus.unknown`).
- On API error: `entries` stays empty, `isLoading` cleared.

### `RackPickerSheet` adaptations (driven by `ctrl.isTargetMode`)

| Element | Source mode | Target mode |
|---------|-------------|-------------|
| Empty state icon | `inventory_2_outlined` | `inventory_2_outlined` |
| Empty state text | `'No racks found with stock'` | `'No racks found'` |
| `_SufficiencyBar` | Shown | Hidden |
| Summary badge | `'X/N sufficient'` | `'N racks'` |
| Tile `isDisabled` | `status == empty` | Always `false` (all `unknown`) |

The `_SufficiencyDot` remains visible but renders grey (`unknown` color) for all target entries — this is acceptable as a neutral location indicator.

### `TargetRackFieldAdapter.browseRacks()`

Replace the `ctrl.load(...)` call with:
```dart
unawaited(ctrl.loadForTarget(
  warehouse:   _d.targetRackWarehouse?.value ?? '',
  currentRack: _d.targetRackController.text.trim(),
));
```

No change to `handleRackPicked` — it still calls `onTargetRackChanged(result.rackId)` which runs `validateDualRack(rack, false)`, which now sets `itemTargetWarehouse` via the warehouse-derivation feature.

---

## Error Handling

- `getRacksByWarehouse` throws → `loadForTarget` catches, `entries` empty, `isLoading` cleared. Sheet shows `'No racks found'`.
- `warehouse` is empty string → API call skipped, `entries` empty immediately.
- Rack names that don't parse as 4-part codes → `RackLocation.tryParse` returns null; tile renders rack name verbatim with no location sub-label or warehouse chip.

---

## Testing

- **Unit test `ApiProvider.getRacksByWarehouse` response parsing** — verifies `List<String>` is correctly extracted from `data[*].name`, handles null/empty/malformed responses. Pattern matches existing `parseUploadFileResponse` tests in `test/unit/upload_file_response_test.dart`.
- **Unit test `RackPickerController.loadForTarget`** — inject a fake `ApiProvider` that returns a known list of rack names; verify `isTargetMode == true`, all entries have `requestedQty == 0`, sort order is aisle-ascending. Uses the same in-process unit test pattern as existing controller tests.

---

## Out of Scope

- Source rack picker behaviour — unchanged.
- `RackPickerLauncher.open()` — unchanged (used by non-SE modules; still stock-balance based).
- `_SufficiencyDot` colour change for target mode — acceptable as grey/neutral.
