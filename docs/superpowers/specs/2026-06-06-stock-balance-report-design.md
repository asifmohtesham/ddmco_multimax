# Stock Balance Report — Design Spec

**Date:** 2026-06-06
**Feature:** Nav Drawer → Stock → Reports → Stock Balance

---

## Overview

Add a standalone "Stock Balance" report screen accessible via the nav drawer under Stock > Reports. The screen mirrors the Batch-Wise Balance and Item Variant Details reports in structure: filter sheet, result list, empty/loading states. It calls the ERPNext built-in "Stock Balance" script report via the existing `frappe.desk.query_report.run` endpoint.

---

## Architecture

### Files created (3)

```
lib/app/modules/stock/reports/stock_balance/
  stock_balance_binding.dart      — GetX dependency registration
  stock_balance_controller.dart   — business logic, filter state, API call, row parsing
  stock_balance_screen.dart       — list UI (GetView), result tile, filter chip builder
```

### Files modified (5)

| File | Change |
|------|--------|
| `lib/app/data/routes/app_routes.dart` | Add `STOCK_BALANCE = '/stock/reports/stock-balance'` constant |
| `lib/app/data/routes/app_pages.dart` | Register `GetPage` with `StockBalanceBinding` and `rightToLeftWithFade` transition |
| `lib/app/modules/global_widgets/app_nav_drawer.dart` | Add `DocTypeGuard(doctype: 'Stock Entry', permType: 'report')` item inside the Stock > Reports `_GuardedSection`; add `'Stock Entry'` to the `_GuardedSection` doctypes list |
| `lib/app/data/constants/permission_entries.dart` | Add `(doctype: 'Stock Entry', permType: 'report')` to `kStockPermissions` |
| `lib/app/data/providers/api_provider.dart` | Add `getStockBalanceReport()` method |

---

## Filters

All filters are presented via `showReportFilterSheet`. No filter is required — the report can run on just the date range.

| Key | Type | Default | Required |
|-----|------|---------|----------|
| `from_date` | `ReportFilterType.datePicker` | today | yes (controller-enforced default, not sheet-validated) |
| `to_date` | `ReportFilterType.datePicker` | today | yes |
| `item_code` | `ReportFilterType.doctypeLink` (Item) | — | no |
| `warehouse` | `ReportFilterType.doctypeLink` (Warehouse) | — | no |
| `item_group` | `ReportFilterType.doctypeLink` (Item Group) | — | no |
| `show_dimension_wise` | `ReportFilterChipGroup` — single chip "Dimension-wise" | off (`''`) | — |
| `show_variant_attrs` | `ReportFilterChipGroup` — single chip "Variant Attributes" | off (`''`) | — |

Chip group values: `'1'` when selected, `''` when deselected.

### `clearFilters()` behaviour

Resets `item_code`, `warehouse`, `item_group` to empty; resets `show_dimension_wise` and `show_variant_attrs` to `''`; resets `from_date` and `to_date` to today. Clears `reportData`, `reportColumns`.

---

## API: `getStockBalanceReport()`

**Location:** `lib/app/data/providers/api_provider.dart`

**Signature:**
```dart
Future<({List<Map<String, dynamic>> columns, List<Map<String, dynamic>> rows})>
    getStockBalanceReport({
  required String fromDate,
  required String toDate,
  String? itemCode,
  String? warehouse,
  String? itemGroup,
  bool showDimensionWise    = false,
  bool showVariantAttributes = false,
}) async { ... }
```

**Filter building:**
```dart
final filters = <String, dynamic>{
  'company'  : storage.getCompany(),
  'from_date': fromDate,
  'to_date'  : toDate,
  if (itemCode  != null && itemCode.isNotEmpty)
    'item_code' : await stockBalanceItemCodeFilter(itemCode),
  if (warehouse != null && warehouse.isNotEmpty)
    'warehouse' : warehouse,
  if (itemGroup != null && itemGroup.isNotEmpty)
    'item_group': itemGroup,
  if (showDimensionWise)     'show_dimension_wise_stock': 1,
  if (showVariantAttributes) 'show_variant_attributes'  : 1,
  'valuation_field_type': 'Currency',
};
```

`stockBalanceItemCodeFilter(itemCode)` already handles the v15.72+ list-format requirement.

**Response parsing:**
- Read `response.data['message']` → `Map<String, dynamic>? message`
- `columns` = `message['columns']` (list of maps or strings)
- `result`  = `message['result']` (list of maps or lists)

Handle both row formats:
- **Map rows** (newer ERPNext): return as-is (already keyed by fieldname)
- **List rows** (positional): resolve field positions from `columns` to produce keyed maps

Standard fields normalised in both cases: `item_code`, `item_name`, `warehouse`, `opening_qty`, `in_qty`, `out_qty`, `balance_qty`. Unknown extra columns (from `show_variant_attributes`) are preserved under their original keys.

Returns `(columns: [...], rows: [...])` record. Returns empty lists on network errors.

---

## Controller: `StockBalanceController`

**Observables:**
```dart
final isLoading    = false.obs;
final reportData   = <Map<String, dynamic>>[].obs;
final reportColumns = <Map<String, dynamic>>[].obs;   // for dynamic attribute cols
final activeFilters = <String, String>{}.obs;
```

**Filter controllers (7):** `from_date`, `to_date`, `item_code`, `warehouse`, `item_group`, `show_dimension_wise`, `show_variant_attrs`.

**`onInit()`:** Pre-fill `from_date` and `to_date` to today; call `_rebuildActiveFilters()`.

**`runReport()`:** Reads all filter controllers, calls `_apiProvider.getStockBalanceReport(...)`, assigns results. No required filter validation — user may run with just dates.

**`_rebuildActiveFilters()`:** Builds display labels for the active filter chips shown in the header.

---

## Screen: `StockBalanceScreen`

**Structure:**
```
AppShellScaffold   (provides drawer)
  RefreshIndicator (calls runReport)
    CustomScrollView
      DocTypeListHeader (title: 'Stock Balance', filter icon, filter chips)
      SliverFillRemaining if isLoading → CircularProgressIndicator
      SliverFillRemaining if reportData.isEmpty → empty state
      SliverPadding + SliverList of _BalanceTile
```

**`_BalanceTile` layout:**

```
┌─────────────────────────────────────────────┐
│ item_code (bold, 15sp)       [balance_qty]  │
│ item_name (muted, 12sp)      tertiaryContainer badge │
│ ──────────────────────────────────────────  │
│ Warehouse: <warehouse>                      │
│ Open: <X>  │  In: <Y>  │  Out: <Z>         │
│ [Attr: Val] [Attr: Val]  ← if extra cols   │
└─────────────────────────────────────────────┘
```

- Balance badge: `cs.tertiaryContainer` / `cs.onTertiaryContainer` (matches Batch-Wise Balance)
- Attribute chips: only rendered when `reportColumns` contains non-standard fields and the row has a non-empty value for them. Skip fields: `item_code`, `item_name`, `warehouse`, `opening_qty`, `in_qty`, `out_qty`, `balance_qty`, `opening_val`, `balance_val`, `in_val`, `out_val`.
- Negative balance qty: chip color `cs.errorContainer` / `cs.onErrorContainer`.

**Empty state:**
- Icon: `Icons.inventory_2_outlined`
- Text: "Set filters and run the report"
- CTA: `FilledButton.tonalIcon` → opens filter sheet

**Nav drawer entry:**
```dart
DocTypeGuard(
  doctype: 'Stock Entry',
  permType: 'report',
  loading: skeleton,
  child: _DrawerItem(
    title: 'Stock Balance',
    icon: Icons.account_balance_wallet_outlined,
    route: AppRoutes.STOCK_BALANCE,
    currentRoute: currentRoute,
  ),
),
```

---

## Permission

`kStockPermissions` in `permission_entries.dart`:
```dart
(doctype: 'Stock Entry', permType: 'report'), // Stock Balance report
```

`_GuardedSection` in the nav drawer has its `doctypes` list extended to include `'Stock Entry'`.

---

## Out of Scope

- Pagination (ERPNext report endpoint returns all matching rows in one call)
- Export / share
- Drill-down to Stock Ledger entries
