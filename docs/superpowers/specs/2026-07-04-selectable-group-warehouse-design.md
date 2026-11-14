# Selectable Group Warehouse for Default Warehouse — Design

**Date:** 2026-07-04
**Status:** Proposed
**Builds on:** `2026-07-04-default-warehouse-stock-balance-search-design.md` and
`2026-07-04-inline-warehouse-balance-search-design.md` (both released in 2.3.0+34).

## Why

The Session Defaults **Default Warehouse** picker currently lists **leaf
warehouses only** (`WarehouseProvider.getWarehouses()` filters `is_group: 0`), so
a **group** warehouse can't be chosen. The user wants to select a group and have
the search stock balance show the **sum across its child warehouses**.

The summing is **already implemented**: selecting any warehouse passes its name to
`getStockBalanceReport(warehouse:)`, ERPNext expands a group-warehouse filter to
its descendant leaf rows, and `GlobalSearchService.aggregateByItem` already sums
`bal_qty` per item across those rows. So the only gap is **making group
warehouses selectable** (and marking them in the picker).

## What changes

1. Group warehouses become selectable in the Session Defaults picker, listed
   alongside leaves in one searchable list; group rows carry a small trailing
   **"Group"** tag.
2. The shared `WarehouseProvider.getWarehouses()` is **not** widened for its other
   callers (Stock Entry, Delivery Note, Purchase Order — all need leaf-only); a
   new opt-in flag exposes groups only where asked.

## Components

### `WarehouseProvider.getWarehouses({bool includeGroups = false})`
(`lib/app/data/providers/warehouse_provider.dart`)

- Add the optional `includeGroups` param. When `false` (default) the filter stays
  `{'is_group': 0, 'disabled': 0}` — **every existing caller is unchanged**. When
  `true`, the filter is `{'disabled': 0}` only (groups included). `is_group` is
  already in the selected fields.

### `SessionDefaultsController` (`.../session_defaults/session_defaults_controller.dart`)

- New `final groupWarehouses = <String>{}.obs;` (RxSet of group warehouse names).
- `_loadWarehouses()` calls `getWarehouses(includeGroups: true)` and splits the
  response via a pure static helper:
  - `static ({List<String> names, Set<String> groups}) partitionWarehouses(List<dynamic> data)`
    — for each row with a non-blank `name`, add the name to `names`; if
    `is_group` is truthy (`1`, `true`, or `'1'`), add the name to `groups`. Skips
    blank names. Pure → unit-testable.
  - `_loadWarehouses` then `warehouses.assignAll(parsed.names)` and
    `groupWarehouses.assignAll(parsed.groups)`.

### `WarehousePickerSheet` (`lib/app/modules/global_widgets/warehouse_picker_sheet.dart`)

- Add `final Set<String> groupNames;` (default `const {}`). For a row whose name
  is in `groupNames`, render a small trailing **"Group"** tag (rounded label using
  the sheet's `colorScheme` — `surfaceContainerHighest` fill / `onSurfaceVariant`
  text, so it's contrast-safe in both themes). Rows not in the set render as
  today. The default empty set means no other behaviour changes.

### `SessionDefaultsScreen._pickWarehouse` (`.../session_defaults/session_defaults_screen.dart`)

- Pass `groupNames: controller.groupWarehouses` into `WarehousePickerSheet` (inside
  the existing `Obx`, so the tags appear once the list loads).

### Summing — no change

`warehouseBalances` / `aggregateByItem` already sum across the rows a group
warehouse expands to. Selecting a group name "just works". Confirm on-device.

## Data flow

```
Session Defaults picker (includeGroups: true)
  → partitionWarehouses → names + groupNames(Set)
  → WarehousePickerSheet tags group rows → user picks a group name
  → saveDefaultWarehouse(groupName)             [device-local string]
Dashboard search → warehouseBalances(codes, groupName)
  → getStockBalanceReport(warehouse: groupName) → descendant leaf rows
  → aggregateByItem sums bal_qty per item       [group total, inline]
```

## Error handling

- Warehouse-list fetch failure stays non-fatal (existing behaviour): picker empty,
  a warning is shown; the setting is optional.
- Everything downstream (persist, search balance) already treats the warehouse as
  an opaque string, so a group name needs no special handling.

## Testing

- **Unit** — `SessionDefaultsController.partitionWarehouses`: splits names and the
  group-name set from raw rows (`is_group` as int `1`/`0`); skips blank names;
  a `true`/`'1'` `is_group` also counts as a group.
- **Widget** — `WarehousePickerSheet` with `groupNames`: a group row shows the
  "Group" tag; a leaf row does not; both names render and are tappable.

(No provider unit test — `WarehouseProvider` wraps a live Dio call with no existing
test seam; the filter change is a one-line flag, verified via the on-device smoke.)

## Files

| Action | File |
|--------|------|
| Modify | `lib/app/data/providers/warehouse_provider.dart` (add `includeGroups`) |
| Modify | `lib/app/modules/session_defaults/session_defaults_controller.dart` (`groupWarehouses` + `partitionWarehouses` + fetch with groups) |
| Modify | `lib/app/modules/global_widgets/warehouse_picker_sheet.dart` (`groupNames` + "Group" tag) |
| Modify | `lib/app/modules/session_defaults/session_defaults_screen.dart` (pass `groupNames`) |
| Modify | `test/unit/session_defaults_controller_test.dart` (add `partitionWarehouses` test) |
| Add    | `test/widget/warehouse_picker_group_tag_test.dart` |

## Out of scope / YAGNI

- Showing the warehouse tree hierarchy / indentation (flat list + tag only).
- Per-child breakdown of a group total (only the summed qty shows).
- Changing the shared leaf-only `getWarehouses()` default (Stock Entry etc. must
  stay leaf-only).

## Versioning

New user-facing capability (group warehouse selectable) → **MINOR** at release
time per `docs/versioning_conventions.md`; not bumped here.
