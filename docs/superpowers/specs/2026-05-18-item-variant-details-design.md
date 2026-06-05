# Item Variant Details Report — Design Spec

**Date:** 2026-05-18
**Feature:** Nav Drawer > Stock > Reports > Item Variant Details
**Pattern:** Report View (mirrors BOM Search)

---

## Overview

A new read-only report screen that surfaces the ERPNext "Item Variant Details" script report. The user enters a parent Item (template item) and taps "Run Report" to see all its variants with their attribute values (Colour, Size, Finish, etc.). Tapping a variant navigates to the Item form for that variant.

---

## Module Structure

New files under `lib/app/modules/stock/reports/item_variant_details/`:

```
item_variant_details_binding.dart
item_variant_details_controller.dart
item_variant_details_screen.dart
```

---

## Routing

**`app_routes.dart`**

Add to `AppRoutes`:
```dart
static const ITEM_VARIANT_DETAILS = _Paths.ITEM_VARIANT_DETAILS;
```

Add to `_Paths`:
```dart
static const ITEM_VARIANT_DETAILS = '/stock/reports/item-variant-details';
```

**`app_pages.dart`**

Add one `GetPage` entry pointing to `ItemVariantDetailsScreen` with `ItemVariantDetailsBinding`.

---

## Nav Drawer

In `app_nav_drawer.dart`, under the Stock `_ModuleGroup`, beneath the existing Batch-Wise Balance `_DrawerItem`, add:

```dart
_DrawerItem(
  title:        'Item Variant Details',
  icon:         Icons.style_outlined,
  route:        AppRoutes.ITEM_VARIANT_DETAILS,
  currentRoute: currentRoute,
),
```

No `DocTypeGuard` is needed — this is a report, not a DocType list.

---

## Controller

`ItemVariantDetailsController extends GetxController`

### Filter state

| Field | Type | Notes |
|---|---|---|
| `itemCodeController` | `TextEditingController` | Required filter |
| `filterControllers` | `Map<String, TextEditingController>` | `{'item_code': itemCodeController}` |

### Report state

| Field | Type | Notes |
|---|---|---|
| `isLoading` | `RxBool` | Controls loading indicator |
| `reportData` | `RxList<Map<String,dynamic>>` | Row data from ERPNext |
| `reportColumns` | `RxList<Map<String,dynamic>>` | Column definitions from ERPNext |
| `activeFilters` | `RxMap<String,String>` | Drives filter chips in header |

### Methods

- **`runReport()`** — validates `item_code` non-empty (shows `GlobalSnackbar.warning` otherwise), calls `_api.getItemVariantDetails(itemCode)`, stores columns + rows, rebuilds active filters.
- **`clearFilter(String key)`** — clears one filter field, removes from `activeFilters`.
- **`clearFilters()`** — clears all, empties `reportData` and `reportColumns`.
- **`_rebuildActiveFilters()`** — private helper, standard pattern.

### Lifecycle

`onClose()` disposes `itemCodeController`.

---

## API Method

New method on `ApiProvider`:

```dart
Future<({List<Map<String,dynamic>> columns, List<Map<String,dynamic>> rows})>
    getItemVariantDetails(String itemCode) async { ... }
```

- Calls `GET /api/method/frappe.desk.query_report.run`
- Query params: `report_name=Item Variant Details`, `filters={"item":"<itemCode>"}`, `ignore_prepared_report=true`
- Parses `response.data['message']['columns']` → `columns`
- Parses `response.data['message']['result']` → `rows`
- Returns empty record `(columns: [], rows: [])` on any error (DioException or non-200).

---

## Screen

`ItemVariantDetailsScreen extends GetView<ItemVariantDetailsController>`

Wraps in `AppShellScaffold` (not plain `Scaffold`).

### Filter fields

One field passed to `showReportFilterSheet`:

```dart
ReportFilterField(
  key:         'item_code',
  label:       'Item *',
  type:        ReportFilterType.doctypeLink,
  linkDoctype: 'Item',
  prefixIcon:  Icons.category_outlined,
  required:    true,
)
```

### Layout

```
AppShellScaffold
└── CustomScrollView
    ├── DocTypeListHeader(title: 'Item Variant Details', ...)
    └── SliverFillRemaining (loading) / SliverFillRemaining (empty) / SliverList (results)
```

**Loading state:** centred `CircularProgressIndicator`.

**Empty state:** `Icons.style_outlined` icon + "Enter an Item and tap Run Report" text + "Set Filters" `FilledButton.tonalIcon`.

**Results:** `SliverList` of `_VariantTile` widgets, padded `EdgeInsets.fromLTRB(12, 4, 12, 80)`.

### `_VariantTile`

Receives `row` (Map) and `columns` (List of column defs).

- **Header row:** Item Code (`row['item']`) in bold + Item Name (`row['item_name']`) as subtitle.
- **Attributes section:** iterates `columns`, skipping `item`, `item_name`, `variant_of`; renders each remaining column as a `_Detail(label: col['label'], value: row[col['fieldname']])` — same `_Detail` widget pattern used in Batch-Wise Balance.
- **onTap:** `Get.toNamed(AppRoutes.ITEM_FORM, arguments: {'name': row['item']})`.
- **Trailing:** `Icons.chevron_right`.

---

## Binding

```dart
class ItemVariantDetailsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ItemVariantDetailsController>(
      () => ItemVariantDetailsController(),
    );
  }
}
```

---

## Out of Scope

- No barcode scan routing (item code is a link picker, not a scannable batch/item barcode slot — unlike BOM Search which accepts item barcodes).
- No pagination (ERPNext returns all variants for the item in a single call).
- No DocTypeGuard on the drawer entry (it is a report, not a DocType).
