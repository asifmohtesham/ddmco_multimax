# Stock Balance Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a standalone Stock Balance report screen to Nav Drawer → Stock → Reports, backed by the ERPNext "Stock Balance" script report endpoint.

**Architecture:** The screen follows the existing Batch-Wise Balance / Item Variant Details pattern: a `GetxController` owns filter state and calls a new `ApiProvider.getStockBalanceReport()` method; a `GetView` screen renders `DocTypeListHeader` + `SliverList` of result tiles; a `Bindings` class wires DI. The static `parseStockBalanceResponse()` helper handles both Map-row and List-row response formats from Frappe and is unit-tested in isolation.

**Tech Stack:** Flutter/Dart, GetX, Dio, ERPNext Frappe REST API (`frappe.desk.query_report.run`)

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `lib/app/modules/stock/reports/stock_balance/stock_balance_binding.dart` | GetX DI registration |
| Create | `lib/app/modules/stock/reports/stock_balance/stock_balance_controller.dart` | Filter state, `runReport()`, active-filter labels |
| Create | `lib/app/modules/stock/reports/stock_balance/stock_balance_screen.dart` | Screen UI, `_BalanceTile`, `_Detail`, `_AttrChip` |
| Create | `test/unit/stock_balance_api_test.dart` | Unit tests for `parseStockBalanceResponse()` |
| Modify | `lib/app/data/routes/app_routes.dart` | Add `STOCK_BALANCE` constant |
| Modify | `lib/app/data/routes/app_pages.dart` | Register `GetPage` |
| Modify | `lib/app/data/constants/permission_entries.dart` | Add Stock Entry report permission to `kStockPermissions` |
| Modify | `lib/app/data/providers/api_provider.dart` | Add `getStockBalanceReport()` + `parseStockBalanceResponse()` |
| Modify | `lib/app/modules/global_widgets/app_nav_drawer.dart` | Add drawer item + expand `_GuardedSection` doctypes |

---

## Task 1: Route, permission, and page registration

**Files:**
- Modify: `lib/app/data/routes/app_routes.dart`
- Modify: `lib/app/data/constants/permission_entries.dart`
- Modify: `lib/app/data/routes/app_pages.dart`

- [ ] **Step 1.1: Add the STOCK_BALANCE route constant**

In `lib/app/data/routes/app_routes.dart`, add one entry to each abstract class.

In `AppRoutes` (after the `ITEM_VARIANT_DETAILS` constant):
```dart
  static const STOCK_BALANCE         = _Paths.STOCK_BALANCE;
```

In `_Paths` (after `ITEM_VARIANT_DETAILS`):
```dart
  static const STOCK_BALANCE         = '/stock/reports/stock-balance';
```

- [ ] **Step 1.2: Add Stock Entry report permission to `kStockPermissions`**

In `lib/app/data/constants/permission_entries.dart`, append to `kStockPermissions`:
```dart
  (doctype: 'Stock Entry', permType: 'report'), // Stock Balance report
```

The constant should now end:
```dart
const List<PermEntry> kStockPermissions = [
  (doctype: 'Item',             permType: 'read'),
  (doctype: 'Batch',            permType: 'read'),
  (doctype: 'Material Request', permType: 'read'),
  (doctype: 'Stock Entry',      permType: 'read'),
  (doctype: 'Delivery Note',    permType: 'read'),
  (doctype: 'Packing Slip',     permType: 'read'),
  (doctype: 'Batch',            permType: 'report'), // Batch-Wise Balance report
  (doctype: 'Item',             permType: 'report'), // Item Variant Details report
  (doctype: 'Stock Entry',      permType: 'report'), // Stock Balance report
];
```

- [ ] **Step 1.3: Register the route in AppPages**

In `lib/app/data/routes/app_pages.dart`, add two import lines after the existing `item_variant_details` imports (after line 68):
```dart
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_binding.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_screen.dart';
```

Add the `GetPage` entry at the end of the `routes` list (after the `ITEM_VARIANT_DETAILS` entry, before the closing `]`):
```dart
    GetPage(
      name:       AppRoutes.STOCK_BALANCE,
      page:       () => const StockBalanceScreen(),
      binding:    StockBalanceBinding(),
      transition: Transition.rightToLeftWithFade,
    ),
```

- [ ] **Step 1.4: Verify no analysis errors**

```
flutter analyze lib/app/data/routes/ lib/app/data/constants/
```

Expected: no issues reported for these files.

- [ ] **Step 1.5: Commit**

```
git add lib/app/data/routes/app_routes.dart lib/app/data/routes/app_pages.dart lib/app/data/constants/permission_entries.dart
git commit -m "feat(routes): register Stock Balance report route and permission"
```

---

## Task 2: API parse helper + `getStockBalanceReport()` (TDD)

**Files:**
- Create: `test/unit/stock_balance_api_test.dart`
- Modify: `lib/app/data/providers/api_provider.dart`

- [ ] **Step 2.1: Write the failing tests**

Create `test/unit/stock_balance_api_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

void main() {
  group('ApiProvider.parseStockBalanceResponse', () {
    test('T-1: returns empty record when message is null', () {
      final result = ApiProvider.parseStockBalanceResponse(null);
      expect(result.columns, isEmpty);
      expect(result.rows, isEmpty);
    });

    test('T-2: returns empty record when result list is empty', () {
      final result = ApiProvider.parseStockBalanceResponse({
        'columns': [{'fieldname': 'item_code', 'label': 'Item Code'}],
        'result': <dynamic>[],
      });
      expect(result.columns, isEmpty);
      expect(result.rows, isEmpty);
    });

    test('T-3: parses Map rows correctly', () {
      final result = ApiProvider.parseStockBalanceResponse({
        'columns': [
          {'fieldname': 'item_code',   'label': 'Item Code'},
          {'fieldname': 'warehouse',   'label': 'Warehouse'},
          {'fieldname': 'balance_qty', 'label': 'Balance Qty'},
        ],
        'result': [
          {'item_code': 'ITEM-001', 'warehouse': 'Stores - KA', 'balance_qty': 42},
        ],
      });
      expect(result.rows.length, 1);
      expect(result.rows[0]['item_code'],   'ITEM-001');
      expect(result.rows[0]['warehouse'],   'Stores - KA');
      expect(result.rows[0]['balance_qty'], 42);
    });

    test('T-4: parses List rows using column positions', () {
      final result = ApiProvider.parseStockBalanceResponse({
        'columns': [
          {'fieldname': 'item_code',   'label': 'Item Code'},
          {'fieldname': 'warehouse',   'label': 'Warehouse'},
          {'fieldname': 'balance_qty', 'label': 'Balance Qty'},
        ],
        'result': [
          ['ITEM-001', 'Stores - KA', 15],
        ],
      });
      expect(result.rows.length, 1);
      expect(result.rows[0]['item_code'],   'ITEM-001');
      expect(result.rows[0]['warehouse'],   'Stores - KA');
      expect(result.rows[0]['balance_qty'], 15);
    });

    test('T-5: extracts fieldname from string-format columns', () {
      final result = ApiProvider.parseStockBalanceResponse({
        'columns': ['bin.item_code', 'bin.balance_qty'],
        'result': [
          ['ITEM-001', 50],
        ],
      });
      expect(result.columns[0]['fieldname'], 'item_code');
      expect(result.columns[1]['fieldname'], 'balance_qty');
      expect(result.rows[0]['item_code'],    'ITEM-001');
      expect(result.rows[0]['balance_qty'],  50);
    });

    test('T-6: populates columns list with fieldname and label', () {
      final result = ApiProvider.parseStockBalanceResponse({
        'columns': [
          {'fieldname': 'balance_qty', 'label': 'Balance Qty'},
        ],
        'result': [
          {'balance_qty': 0},
        ],
      });
      expect(result.columns.first['fieldname'], 'balance_qty');
      expect(result.columns.first['label'],     'Balance Qty');
    });
  });
}
```

- [ ] **Step 2.2: Run the tests — expect failure**

```
flutter test test/unit/stock_balance_api_test.dart
```

Expected: compilation error — `parseStockBalanceResponse` not defined yet.

- [ ] **Step 2.3: Add `getStockBalanceReport()` and `parseStockBalanceResponse()` to `api_provider.dart`**

**Location A — instance method:** Insert immediately after `getStockBalance()` ends (after the closing `}` at the end of that method, before the `// getBatchWiseBalance` comment block). Add:

```dart
  /// Fetches the ERPNext "Stock Balance" script report with flexible filters.
  ///
  /// All parameters except [fromDate] and [toDate] are optional. When
  /// [itemCode] is supplied it is passed through [stockBalanceItemCodeFilter]
  /// for ERPNext v15.72+ list-format compatibility.
  Future<({List<Map<String, dynamic>> columns, List<Map<String, dynamic>> rows})>
      getStockBalanceReport({
    required String fromDate,
    required String toDate,
    String? itemCode,
    String? warehouse,
    String? itemGroup,
    bool showDimensionWise     = false,
    bool showVariantAttributes = false,
  }) async {
    if (!_dioInitialised) await _initDio();

    final storage = Get.find<StorageService>();

    final filters = <String, dynamic>{
      'company'             : storage.getCompany(),
      'from_date'           : fromDate,
      'to_date'             : toDate,
      'valuation_field_type': 'Currency',
      if (itemCode  != null && itemCode.isNotEmpty)
        'item_code'         : await stockBalanceItemCodeFilter(itemCode),
      if (warehouse != null && warehouse.isNotEmpty)
        'warehouse'         : warehouse,
      if (itemGroup != null && itemGroup.isNotEmpty)
        'item_group'        : itemGroup,
      if (showDimensionWise)     'show_dimension_wise_stock': 1,
      if (showVariantAttributes) 'show_variant_attributes'  : 1,
    };

    late final Response response;
    try {
      response = await _dio.get(
        '/api/method/frappe.desk.query_report.run',
        queryParameters: {
          'report_name'           : 'Stock Balance',
          'filters'               : json.encode(filters),
          'ignore_prepared_report': 'true',
          '_'                     : DateTime.now().millisecondsSinceEpoch,
        },
      );
    } on DioException {
      return (columns: <Map<String, dynamic>>[], rows: <Map<String, dynamic>>[]);
    } catch (_) {
      return (columns: <Map<String, dynamic>>[], rows: <Map<String, dynamic>>[]);
    }

    if (response.statusCode != 200) {
      return (columns: <Map<String, dynamic>>[], rows: <Map<String, dynamic>>[]);
    }

    return parseStockBalanceResponse(
      response.data['message'] as Map<String, dynamic>?,
    );
  }
```

**Location B — static parse helper:** Insert immediately after `parseItemVariantDetailsResponse()` ends (after its closing `}` around line 657, before `parseUploadFileResponse`). Add:

```dart
  /// Exposed as a public static method so unit tests can exercise the parsing
  /// logic without a live HTTP connection or GetX service registration.
  ///
  /// Handles both Map-row responses (newer ERPNext) and List-row responses
  /// (positional, resolved by column index).
  static ({List<Map<String, dynamic>> columns, List<Map<String, dynamic>> rows})
      parseStockBalanceResponse(Map<String, dynamic>? message) {
    const empty = (columns: <Map<String, dynamic>>[], rows: <Map<String, dynamic>>[]);
    if (message == null) return empty;
    try {
      final rawCols = message['columns'] as List<dynamic>? ?? [];
      final rawRows = message['result']  as List<dynamic>? ?? [];
      if (rawRows.isEmpty) return empty;

      // Resolve each column to a {fieldname, label} map regardless of wire format
      String fn(dynamic col) {
        if (col is Map) return (col['fieldname'] as String? ?? '').toLowerCase();
        final s       = col.toString().toLowerCase();
        final lastDot = s.lastIndexOf('.');
        return lastDot >= 0
            ? s.substring(lastDot + 1).replaceAll('`', '')
            : s;
      }

      String lbl(dynamic col) {
        if (col is Map) return (col['label'] as String? ?? '');
        return col.toString();
      }

      final columns = rawCols
          .map((c) => <String, dynamic>{'fieldname': fn(c), 'label': lbl(c)})
          .toList();

      // Detect row format from the first non-null row
      final firstRow = rawRows.firstWhere((r) => r != null, orElse: () => null);

      if (firstRow is Map) {
        // Map rows — already keyed
        final rows = rawRows
            .whereType<Map>()
            .map((r) => Map<String, dynamic>.from(r))
            .toList();
        return (columns: columns, rows: rows);
      }

      // List rows — positional; resolve by column position
      final fieldnames = rawCols.map(fn).toList();
      final rows = rawRows
          .whereType<List>()
          .map((r) {
            final row = <String, dynamic>{};
            for (var i = 0; i < fieldnames.length && i < r.length; i++) {
              row[fieldnames[i]] = r[i];
            }
            return row;
          })
          .toList();

      return (columns: columns, rows: rows);
    } catch (_) {
      return empty;
    }
  }
```

- [ ] **Step 2.4: Run the tests — expect all pass**

```
flutter test test/unit/stock_balance_api_test.dart --reporter expanded
```

Expected output (6 tests, all green):
```
✓ T-1: returns empty record when message is null
✓ T-2: returns empty record when result list is empty
✓ T-3: parses Map rows correctly
✓ T-4: parses List rows using column positions
✓ T-5: extracts fieldname from string-format columns
✓ T-6: populates columns list with fieldname and label
```

- [ ] **Step 2.5: Commit**

```
git add test/unit/stock_balance_api_test.dart lib/app/data/providers/api_provider.dart
git commit -m "feat(api): add getStockBalanceReport and parseStockBalanceResponse"
```

---

## Task 3: Binding and controller

**Files:**
- Create: `lib/app/modules/stock/reports/stock_balance/stock_balance_binding.dart`
- Create: `lib/app/modules/stock/reports/stock_balance/stock_balance_controller.dart`

- [ ] **Step 3.1: Create the binding**

Create `lib/app/modules/stock/reports/stock_balance/stock_balance_binding.dart`:

```dart
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_controller.dart';

class StockBalanceBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<StockBalanceController>(() => StockBalanceController());
  }
}
```

- [ ] **Step 3.2: Create the controller**

Create `lib/app/modules/stock/reports/stock_balance/stock_balance_controller.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';

class StockBalanceController extends GetxController {
  final ApiProvider _api = Get.find<ApiProvider>();

  // ── Filter controllers ───────────────────────────────────────────────────
  final fromDateController      = TextEditingController();
  final toDateController        = TextEditingController();
  final itemCodeController      = TextEditingController();
  final warehouseController     = TextEditingController();
  final itemGroupController     = TextEditingController();
  final dimensionWiseController = TextEditingController();
  final variantAttrsController  = TextEditingController();

  late final Map<String, TextEditingController> filterControllers;

  // ── State ────────────────────────────────────────────────────────────────
  final isLoading     = false.obs;
  final reportData    = <Map<String, dynamic>>[].obs;
  final reportColumns = <Map<String, dynamic>>[].obs;
  final activeFilters = <String, String>{}.obs;

  // ── Filter field descriptors (passed to ReportFilterSheet) ───────────────
  List<ReportFilterField> get filterFields => [
    const ReportFilterField(
      key:        'from_date',
      label:      'From Date',
      type:       ReportFilterType.datePicker,
      prefixIcon: Icons.calendar_today_outlined,
    ),
    const ReportFilterField(
      key:        'to_date',
      label:      'To Date',
      type:       ReportFilterType.datePicker,
      prefixIcon: Icons.calendar_today_outlined,
    ),
    const ReportFilterField(
      key:         'item_code',
      label:       'Item',
      type:        ReportFilterType.doctypeLink,
      linkDoctype: 'Item',
      prefixIcon:  Icons.category_outlined,
    ),
    const ReportFilterField(
      key:         'warehouse',
      label:       'Warehouse',
      type:        ReportFilterType.doctypeLink,
      linkDoctype: 'Warehouse',
      prefixIcon:  Icons.warehouse_outlined,
    ),
    const ReportFilterField(
      key:         'item_group',
      label:       'Item Group',
      type:        ReportFilterType.doctypeLink,
      linkDoctype: 'Item Group',
      prefixIcon:  Icons.folder_outlined,
    ),
  ];

  // ── Chip group descriptors (passed to ReportFilterSheet) ─────────────────
  List<ReportFilterChipGroup> get chipGroups => [
    const ReportFilterChipGroup(
      key:   'show_dimension_wise',
      label: 'Display Options',
      options: [
        ReportFilterChipOption(
          value: '1',
          label: 'Dimension-wise',
          icon:  Icons.shelves,
        ),
      ],
    ),
    const ReportFilterChipGroup(
      key:   'show_variant_attrs',
      label: 'Variant Options',
      options: [
        ReportFilterChipOption(
          value: '1',
          label: 'Variant Attributes',
          icon:  Icons.style_outlined,
        ),
      ],
    ),
  ];

  // ── Lifecycle ────────────────────────────────────────────────────────────
  @override
  void onInit() {
    super.onInit();
    filterControllers = {
      'from_date'          : fromDateController,
      'to_date'            : toDateController,
      'item_code'          : itemCodeController,
      'warehouse'          : warehouseController,
      'item_group'         : itemGroupController,
      'show_dimension_wise': dimensionWiseController,
      'show_variant_attrs' : variantAttrsController,
    };
    final today = _formatDate(DateTime.now());
    fromDateController.text = today;
    toDateController.text   = today;
    _rebuildActiveFilters();
  }

  @override
  void onClose() {
    for (final c in filterControllers.values) c.dispose();
    super.onClose();
  }

  // ── Public API ───────────────────────────────────────────────────────────
  int get activeFilterCount =>
      filterControllers.values.where((c) => c.text.trim().isNotEmpty).length;

  void clearFilter(String key) {
    filterControllers[key]?.clear();
    if (key == 'from_date' || key == 'to_date') {
      filterControllers[key]!.text = _formatDate(DateTime.now());
    }
    _rebuildActiveFilters();
  }

  void clearFilters() {
    itemCodeController.clear();
    warehouseController.clear();
    itemGroupController.clear();
    dimensionWiseController.clear();
    variantAttrsController.clear();
    final today = _formatDate(DateTime.now());
    fromDateController.text = today;
    toDateController.text   = today;
    _rebuildActiveFilters();
    reportData.clear();
    reportColumns.clear();
  }

  Future<void> runReport() async {
    _rebuildActiveFilters();
    isLoading.value = true;
    reportData.clear();
    reportColumns.clear();

    try {
      final itemCode  = itemCodeController.text.trim();
      final warehouse = warehouseController.text.trim();
      final itemGroup = itemGroupController.text.trim();

      final result = await _api.getStockBalanceReport(
        fromDate:              fromDateController.text.trim(),
        toDate:                toDateController.text.trim(),
        itemCode:              itemCode.isEmpty  ? null : itemCode,
        warehouse:             warehouse.isEmpty ? null : warehouse,
        itemGroup:             itemGroup.isEmpty ? null : itemGroup,
        showDimensionWise:     dimensionWiseController.text == '1',
        showVariantAttributes: variantAttrsController.text  == '1',
      );

      reportColumns.assignAll(result.columns);
      reportData.assignAll(result.rows);
    } catch (e) {
      GlobalSnackbar.error(
        title:   'Report Error',
        message: 'Failed to fetch Stock Balance: $e',
      );
    } finally {
      isLoading.value = false;
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  static const _filterLabels = <String, String>{
    'from_date'          : 'From',
    'to_date'            : 'To',
    'item_code'          : 'Item',
    'warehouse'          : 'Warehouse',
    'item_group'         : 'Group',
    'show_dimension_wise': 'Dimension-wise',
    'show_variant_attrs' : 'Variant Attrs',
  };

  void _rebuildActiveFilters() {
    activeFilters.clear();
    filterControllers.forEach((key, ctrl) {
      final v = ctrl.text.trim();
      if (v.isNotEmpty) {
        final label = _filterLabels[key] ?? key;
        // Chip group keys have boolean meaning — display label only, not value
        activeFilters[key] =
            key.startsWith('show_') ? label : '$label: $v';
      }
    });
  }

  String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
```

- [ ] **Step 3.3: Verify**

```
flutter analyze lib/app/modules/stock/reports/stock_balance/
```

Expected: no issues.

- [ ] **Step 3.4: Commit**

```
git add lib/app/modules/stock/reports/stock_balance/stock_balance_binding.dart lib/app/modules/stock/reports/stock_balance/stock_balance_controller.dart
git commit -m "feat(stock-balance): add binding and controller"
```

---

## Task 4: Screen

**Files:**
- Create: `lib/app/modules/stock/reports/stock_balance/stock_balance_screen.dart`

- [ ] **Step 4.1: Create the screen**

Create `lib/app/modules/stock/reports/stock_balance/stock_balance_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_controller.dart';

class StockBalanceScreen extends GetView<StockBalanceController> {
  const StockBalanceScreen({super.key});

  // ── Filter chip builder ──────────────────────────────────────────────────
  List<Widget> _buildFilterChips(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget chip(String key, String label) => InputChip(
      avatar: Icon(Icons.filter_alt_outlined,
          size: 14, color: cs.onSecondaryContainer),
      label: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: cs.onSecondaryContainer, fontWeight: FontWeight.w600),
      ),
      backgroundColor: cs.secondaryContainer,
      deleteIconColor: cs.onSecondaryContainer,
      onDeleted:       () => controller.clearFilter(key),
      side:            BorderSide.none,
      padding:         const EdgeInsets.symmetric(horizontal: 4),
    );
    final chips = <Widget>[];
    controller.activeFilters.forEach((key, label) => chips.add(chip(key, label)));
    return chips;
  }

  void _openFilters(BuildContext context) => showReportFilterSheet(
    context:     context,
    title:       'Stock Balance Filters',
    fields:      controller.filterFields,
    controllers: controller.filterControllers,
    chipGroups:  controller.chipGroups,
    onRun:       controller.runReport,
    onClear:     controller.clearFilters,
  );

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AppShellScaffold(
      body: Obx(() {
        return RefreshIndicator(
          onRefresh:       controller.runReport,
          color:           cs.primary,
          backgroundColor: cs.surfaceContainerHighest,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── Header ────────────────────────────────────────────────────
              DocTypeListHeader(
                title:                     'Stock Balance',
                automaticallyImplyLeading: false,
                activeFilters: controller.activeFilters
                    .map((k, v) => MapEntry(k, v as dynamic))
                    .obs,
                onFilterTap:        () => _openFilters(context),
                filterChipsBuilder: _buildFilterChips,
                onClearAllFilters:  controller.clearFilters,
              ),

              // ── Loading ───────────────────────────────────────────────────
              if (controller.isLoading.value)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )

              // ── Empty state ───────────────────────────────────────────────
              else if (controller.reportData.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              size: 64, color: cs.outlineVariant),
                          const SizedBox(height: 16),
                          Text(
                            'Set filters and run the report',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.tonalIcon(
                            onPressed: () => _openFilters(context),
                            icon:  const Icon(Icons.filter_alt_outlined),
                            label: const Text('Set Filters'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )

              // ── Results ───────────────────────────────────────────────────
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final row = controller.reportData[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _BalanceTile(
                            row:     row,
                            columns: controller.reportColumns,
                          ),
                        );
                      },
                      childCount: controller.reportData.length,
                    ),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}

// ── Result tile ────────────────────────────────────────────────────────────────

class _BalanceTile extends StatelessWidget {
  final Map<String, dynamic>       row;
  final List<Map<String, dynamic>> columns;

  const _BalanceTile({required this.row, required this.columns});

  // Standard Stock Balance fieldnames — anything outside this set is an
  // extra attribute column rendered as a chip when show_variant_attributes=1.
  static const _skipFields = <String>{
    'item_code', 'item_name', 'warehouse', 'item_group', 'stock_uom',
    'opening_qty', 'in_qty', 'out_qty', 'balance_qty',
    'opening_val', 'in_val',  'out_val',  'balance_val', 'valuation_rate',
  };

  static bool _isEmpty(dynamic v) {
    if (v == null) return true;
    final s = v.toString().trim();
    return s.isEmpty || s == '—' || s == '-';
  }

  static num _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  static String _fmtQty(num qty) => qty.toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final itemCode  = row['item_code']?.toString()  ?? '—';
    final itemName  = row['item_name']?.toString()  ?? '';
    final warehouse = row['warehouse']?.toString()  ?? '—';
    final balQty    = _toNum(row['balance_qty']);
    final openQty   = _toNum(row['opening_qty']);
    final inQty     = _toNum(row['in_qty']);
    final outQty    = _toNum(row['out_qty']);

    final balBgColor   = balQty < 0 ? cs.errorContainer   : cs.tertiaryContainer;
    final balTextColor = balQty < 0 ? cs.onErrorContainer : cs.onTertiaryContainer;

    final attrCols = columns.where((c) {
      final fn = (c['fieldname'] as String? ?? '').toLowerCase();
      return !_skipFields.contains(fn);
    }).toList();

    return Material(
      color:        cs.surface,
      elevation:    1,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header: item code + balance badge ──────────────────────────
            Row(
              mainAxisAlignment:  MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        itemCode,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      if (itemName.isNotEmpty && itemName != itemCode)
                        Text(
                          itemName,
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color:        balBgColor,
                    borderRadius: BorderRadius.circular(8),
                    border:       Border.all(
                        color: balTextColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _fmtQty(balQty),
                    style: TextStyle(
                        color:      balTextColor,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            // ── Warehouse ─────────────────────────────────────────────────
            _Detail(label: 'Warehouse', value: warehouse),
            const SizedBox(height: 8),
            // ── Opening / In / Out quantities ─────────────────────────────
            Row(
              children: [
                Expanded(child: _Detail(label: 'Opening', value: _fmtQty(openQty))),
                Expanded(child: _Detail(label: 'In',      value: _fmtQty(inQty))),
                Expanded(child: _Detail(label: 'Out',     value: _fmtQty(outQty))),
              ],
            ),
            // ── Attribute chips (only when show_variant_attributes=1) ──────
            if (attrCols.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6, runSpacing: 6,
                children: [
                  for (final col in attrCols)
                    Builder(builder: (ctx) {
                      final fn  = col['fieldname'] as String? ?? '';
                      final lbl = col['label']     as String? ?? fn;
                      final val = row[fn];
                      if (_isEmpty(val)) return const SizedBox.shrink();
                      return _AttrChip(label: lbl, value: val.toString());
                    }),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── _Detail — label + value column ────────────────────────────────────────────

class _Detail extends StatelessWidget {
  final String  label;
  final dynamic value;
  const _Detail({required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(
          value?.toString().isNotEmpty == true ? value.toString() : '—',
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

// ── _AttrChip — attribute pill for variant attribute columns ──────────────────

class _AttrChip extends StatelessWidget {
  final String label;
  final String value;
  const _AttrChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color:        cs.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$label: $value',
        style: text.labelSmall?.copyWith(
          color:      cs.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
```

- [ ] **Step 4.2: Verify**

```
flutter analyze lib/app/modules/stock/reports/stock_balance/stock_balance_screen.dart
```

Expected: no issues.

- [ ] **Step 4.3: Verify the full module builds**

```
flutter build apk --debug 2>&1 | head -20
```

Expected: exits with code 0 (or only lint warnings, no errors).

- [ ] **Step 4.4: Commit**

```
git add lib/app/modules/stock/reports/stock_balance/stock_balance_screen.dart
git commit -m "feat(stock-balance): add report screen"
```

---

## Task 5: Nav drawer entry + final verification

**Files:**
- Modify: `lib/app/modules/global_widgets/app_nav_drawer.dart`

- [ ] **Step 5.1: Extend the Stock > Reports `_GuardedSection`**

In `lib/app/modules/global_widgets/app_nav_drawer.dart`, locate the `_GuardedSection` inside the Stock `_ModuleGroup` (currently around line 296–324). Make two changes:

**Change 1** — add `'Stock Entry'` to `doctypes`:
```dart
// Before
_GuardedSection(
  doctypes: ['Batch', 'Item'],
  permType: 'report',

// After
_GuardedSection(
  doctypes: ['Batch', 'Item', 'Stock Entry'],
  permType: 'report',
```

**Change 2** — add a new `DocTypeGuard` entry after the `Item Variant Details` item (after its closing `,`):
```dart
                          DocTypeGuard(
                            doctype: 'Stock Entry',
                            permType: 'report',
                            loading: skeleton,
                            child: _DrawerItem(
                              title:        'Stock Balance',
                              icon:         Icons.account_balance_wallet_outlined,
                              route:        AppRoutes.STOCK_BALANCE,
                              currentRoute: currentRoute,
                            ),
                          ),
```

No new imports are needed — `AppRoutes` is already imported in this file.

- [ ] **Step 5.2: Run full analyze**

```
flutter analyze
```

Expected: no new errors (pre-existing warnings are acceptable as long as no new ones appeared).

- [ ] **Step 5.3: Run all unit tests**

```
flutter test test/unit/
```

Expected: all tests pass, including the 6 new `stock_balance_api_test.dart` tests.

- [ ] **Step 5.4: Commit**

```
git add lib/app/modules/global_widgets/app_nav_drawer.dart
git commit -m "feat(nav): add Stock Balance report to Stock > Reports drawer section"
```

---

## Self-Review Checklist (completed)

| Spec requirement | Task |
|-----------------|------|
| Route `/stock/reports/stock-balance` | Task 1 |
| `STOCK_BALANCE` constant in `AppRoutes` / `_Paths` | Task 1 |
| `GetPage` with `rightToLeftWithFade` | Task 1 |
| `(doctype: 'Stock Entry', permType: 'report')` in `kStockPermissions` | Task 1 |
| `getStockBalanceReport()` with v15.72 item_code compat | Task 2 |
| `parseStockBalanceResponse()` handles Map and List rows | Task 2 |
| Unit tests for the parse helper (6 cases) | Task 2 |
| Binding wires `StockBalanceController` | Task 3 |
| Filters: from/to date, item, warehouse, item_group | Task 3 |
| Chip groups: dimension-wise, variant attributes | Task 3 |
| `clearFilters()` resets dates to today, clears data | Task 3 |
| `runReport()` passes all filter values including booleans | Task 3 |
| `AppShellScaffold` (drawer support) | Task 4 |
| `DocTypeListHeader` with `automaticallyImplyLeading: false` | Task 4 |
| Loading / empty / results states | Task 4 |
| `_BalanceTile`: item code, name, warehouse, Open/In/Out, balance badge | Task 4 |
| Negative balance: `errorContainer` colors | Task 4 |
| Extra attribute chips via `reportColumns` skip-list | Task 4 |
| Empty state: `inventory_2_outlined` + "Set filters" CTA | Task 4 |
| Nav drawer: `DocTypeGuard(Stock Entry, report)` item added | Task 5 |
| `_GuardedSection` doctypes extended to include `'Stock Entry'` | Task 5 |
