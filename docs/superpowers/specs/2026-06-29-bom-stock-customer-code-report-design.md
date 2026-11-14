# BOM Stock with Customer Code — Report Integration

**Date:** 2026-06-29
**Status:** Approved design, pending implementation plan
**Branch context:** `release/play-store`

## 1. Goal

Integrate the ERPNext Script Report **`BOM Stock with Customer Code`** into the
Flutter app as a new, mobile-friendly report screen, reachable from
**Menu → App Nav Drawer → Manufacturing → Reports**.

The report cross-references customer codes, BOM/sub-assembly stock, and
(optionally) a POS Upload's required quantities to show whether there is enough
stock / enough component parts to build each item.

## 2. Source report facts (from the ERPNext `Report` doc)

- **`report_name`**: `BOM Stock with Customer Code`
- **`report_type`**: `Script Report` → fetched via `frappe.desk.query_report.run`
- **`module`**: Manufacturing
- **`ref_doctype`**: `BOM`
- **`add_total_row`**: `1` — server appends a totals row to `result`
- **Roles** with access: Manufacturing Manager, Manufacturing User, Sales User

### Columns returned by the report script (13)

| fieldname | label | type | notes |
|---|---|---|---|
| `sl_no` | # | Data | running index |
| `image_tag` | Image | HTML | `<img src=…>`; raw `image` field also present in row |
| `customer` | Customer | Link → Customer | |
| `customer_code` | Customer Code | Data | from `Item Customer Detail.ref_code` |
| `item_code` | Item | Link → Item | |
| `item_name` | Item Name | Data | |
| `item_group` | Item Group | Link → Item Group | |
| `parent_item_group` | Parent Item Group | Link → Item Group | |
| `bom` | BOM | Link → BOM | null for traded items |
| `in_stock_qty` | In Stock Qty | Float | |
| `required_qty` | Required Qty | Float | only populated when a POS Upload is selected |
| `running_total` | Running Total | Float | first occurrence of an item carries its stock; repeats are 0 |
| `enough_parts_to_build` | Enough Parts to Build | Int | sub-assemblies only |

The raw result rows also include `image`, `item_group`, `parent_item_group`
even though some are not in the desk's column subset. The app reads raw fields
directly (e.g. `image` for the thumbnail rather than parsing `image_tag`).

### Filters (defined in the report's desk JS; the `Report` doc's `filters` array is empty)

| fieldname | label | desk fieldtype | app handling |
|---|---|---|---|
| `customer` | Customer | Link → Customer | link picker |
| `customer_code` | Customer Codes | MultiSelectList (`get_customer_ref_codes`) | **chips** (see §6) |
| `warehouse` | Warehouses | MultiSelectList (link options) | multiselect of warehouses |
| `pos_upload` | POS Upload | Link → POS Upload | link picker + auto-fill (see §6) |
| `show_exploded_view` | Show Exploded View | Check | switch |
| `hide_out_of_stock` | Hide Out of Stock | Check | switch |

### Desk UI behaviors to mirror

- Red **shortfall** highlight on a row when `required_qty` is set and
  `running_total < required_qty`.
- A red **banner** listing customer codes from a selected POS Upload that were
  not found in the system ("N Customer Code(s) … were not found: …").
- A **Clear Filters** action.
- A **totals row** at the bottom (from `add_total_row`).

## 3. Key backend constraint discovered

Querying `Item Customer Detail` directly returns **403** for the app's session
user (documented at `api_provider.dart:103`). The existing
`resolveItemsByCustomerCode` works around this by listing the readable parent
`Item` with a child-table join filter — but that returns parent **item names**,
not the distinct child `ref_code` **values**. `getList` (`api_provider.dart:427`)
lists the parent doctype and its `fields` are parent fields; the join filter
only *filters*. Therefore **there is no standard-REST way to enumerate the
distinct `ref_code` values**, so a server-backed typeahead for the Customer
Codes filter is not possible without the report-private whitelisted method —
which we are deliberately not depending on.

This only affects how the user *picks* customer codes; the report only needs the
list of code strings passed in the `customer_code` filter. See §6.

## 4. Architecture

Follows the existing report module pattern (BOM Search / Job Card Summary).
New module folder:

```
lib/app/modules/manufacturing/reports/bom_stock_customer_code/
  bom_stock_customer_code_binding.dart
  bom_stock_customer_code_controller.dart
  bom_stock_customer_code_screen.dart
  widgets/
    bom_stock_tile.dart           # one card per result row
    bom_stock_filter_sheet.dart   # bottom-sheet filter editor
    bom_stock_totals_footer.dart  # sticky totals footer
```

Plus:
- a route constant in `lib/app/data/routes/app_routes.dart`
  (`_Paths` + `AppRoutes`),
- a `GetPage` in `lib/app/data/routes/app_pages.dart`,
- new methods on the shared `ApiProvider`,
- one drawer entry in `app_nav_drawer.dart`.

No structural change to existing code.

### Route

- `_Paths.BOM_STOCK_CUSTOMER_CODE = '/manufacturing/reports/bom-stock-customer-code'`
- `AppRoutes.BOM_STOCK_CUSTOMER_CODE = _Paths.BOM_STOCK_CUSTOMER_CODE`
- `GetPage(name: …, page: () => const BomStockCustomerCodeScreen(), binding: BomStockCustomerCodeBinding(), transition: Transition.rightToLeftWithFade)`

### Binding

```dart
class BomStockCustomerCodeBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ApiProvider>(() => ApiProvider());
    Get.lazyPut<BomStockCustomerCodeController>(
        () => BomStockCustomerCodeController());
  }
}
```

## 5. API layer (`ApiProvider`, all GET unless noted)

1. **`runBomStockWithCustomerCode({String? customer, List<String> customerCodes,
   List<String> warehouses, String? posUpload, bool showExplodedView,
   bool hideOutOfStock})`**
   → `GET /api/method/frappe.desk.query_report.run` with
   `report_name: 'BOM Stock with Customer Code'`,
   `filters: json.encode({…only non-empty…})`,
   `ignore_prepared_report: 'true'`, cache-buster `_`.
   Returns the raw `Response`; controller parses `data['message']`
   (`{columns, result}`).

2. **`getPosUploadRefCodes(String posUpload)`** → reuse `getPosUpload(name)`
   (`GET /api/resource/POS Upload/{name}`), read the embedded child table
   `items[].ref_code`, return the distinct non-empty codes. *(Replaces the
   server `get_pos_upload_codes`; the found/missing split is computed in the
   controller — see §6.)*

3. **Warehouse options** — reuse an existing warehouse list helper if present;
   otherwise add `getWarehouses({String? txt})` →
   `getList(doctype: 'Warehouse', fields: ['name'], filters: {if txt: name like},
   orderBy: 'name asc', limit: 0)`. (Implementation to confirm whether a helper
   already exists; do not duplicate.)

4. **POS Upload picker list** — reuse existing `getDocumentList('POS Upload', …)`
   (`api_provider.dart:1669`).

No new whitelisted-method dependency is introduced.

## 6. Controller (`BomStockCustomerCodeController`)

### Reactive state

- Filters: `RxnString customer`, `RxList<String> customerCodes`,
  `RxList<String> warehouses`, `RxnString posUpload`,
  `RxBool showExplodedView`, `RxBool hideOutOfStock`.
- Results: `RxList<Map<String,dynamic>> reportRows` (cards),
  `Rxn<Map<String,dynamic>> totalRow` (footer),
  `RxList<String> posMissingCodes` (banner),
  `RxList<String> discoveredCodes` (distinct `customer_code` from last run,
  offered as quick-pick chips).
- Busy: `RxBool isRunning`.

### Behaviors

- **`runReport()`** — re-entrancy guarded (`if (isRunning.value) return;`),
  sets `isRunning = true`, calls `runBomStockWithCustomerCode`, parses
  `message.result`, **separates the appended total row** (identified by an
  empty/null `item_code`) into `totalRow`, assigns the remaining rows to
  `reportRows`, refreshes `discoveredCodes` from the distinct `customer_code`
  values, clears `isRunning` in a `finally`.
- **`onPosUploadSelected(String? posUpload)`** — if cleared, reset
  `customerCodes`/`posMissingCodes` and re-run. If set:
  fetch `getPosUploadRefCodes(posUpload)` → these are the upload's codes; the
  found/missing split is determined by the subsequent report run (a code is
  "found" if it appears in any result `customer_code`; "missing" otherwise),
  set `customerCodes = uploadCodes`, run, then compute
  `posMissingCodes = uploadCodes − distinct(result.customer_code)`, update
  banner. *(Faithfully reproduces the desk's auto-fill + missing banner using
  only readable data.)*
- **`addCustomerCode(String) / removeCustomerCode(String)`** — chip management.
- **`clearFilters()`** — reset all filters + banner + discovered codes
  (mirrors desk "Clear Filters").
- **`shortfall(Map row)`** — `row['required_qty'] != null &&
  (row['running_total'] ?? 0) < row['required_qty']`.

## 7. Screen (card-tile UI)

- **Header** — maroon list/form header titled "BOM Stock with Customer Code"
  with a **Filters** action and an `AsyncIconButton` **Run/Refresh** bound to
  `isRunning` (visible `onPrimary` spinner — per the Async-feedback convention
  in CLAUDE.md; wrap the reactive control in its own `Obx`).
- **Filter bottom sheet** (`bom_stock_filter_sheet.dart`):
  - Customer — link picker.
  - Customer Codes — **chip input**: type/paste a code, comma/Enter adds a chip;
    a "From results" row offers `discoveredCodes` as quick-pick chips; selecting
    a POS Upload auto-fills chips.
  - Warehouses — multiselect.
  - POS Upload — link picker → `onPosUploadSelected`.
  - Show Exploded View — switch.
  - Hide Out of Stock — switch.
  - **Clear Filters** + **Apply/Run**.
- **Active-filters chip row** above the list + the red **POS missing-codes
  banner** when `posMissingCodes` is non-empty.
- **`BomStockTile`** per row: thumbnail (`image`, placeholder fallback),
  `item_name` + `item_code`, customer / customer_code, item_group /
  parent_item_group, BOM (when present), and a metrics block — In Stock,
  Required (only when a POS Upload is active), Running Total, Enough to Build.
  **Red shortfall accent** when `shortfall(row)` is true.
- **Sticky totals footer** (`bom_stock_totals_footer.dart`) from `totalRow`
  (In Stock / Required / Running Total).
- **States**: skeletons while `isRunning`; shared empty-state when no rows;
  shared error-state on failure.

## 8. Drawer wiring (`app_nav_drawer.dart`)

Add inside the Manufacturing `_GuardedSection` Reports block (after Job Card
Summary). The section's `doctypes` list already includes `'BOM'`, so no change
there.

```dart
DocTypeGuard(
  doctype: 'BOM', permType: 'report', loading: skeleton,
  child: _DrawerItem(
    title: 'BOM Stock with Customer Code',
    icon: Icons.inventory_2_outlined,
    route: AppRoutes.BOM_STOCK_CUSTOMER_CODE,
    currentRoute: currentRoute,
  ),
),
```

## 9. Tests

- **Controller test**: `runReport()` parses `message.result`, separates the
  total row, populates `discoveredCodes`, and `shortfall()` flags the right
  rows; `onPosUploadSelected` produces the correct found/missing split.
- **Widget test**: `BomStockTile` shows the red accent only on shortfall; the
  Run action shows its spinner while `isRunning` is true (the Async-feedback
  verification the convention requires — verified by toggling the flag, not by
  `flutter analyze`).

## 10. Scope (YAGNI)

- No CSV/PDF export, no column reordering, no in-app drilldown to BOM/Item docs
  in v1.
- Total row is taken from the server (`add_total_row`), not recomputed.
- Customer Codes blank-slate server typeahead is intentionally omitted (blocked
  by the 403; covered by chips + discover-from-results + POS auto-fill).
