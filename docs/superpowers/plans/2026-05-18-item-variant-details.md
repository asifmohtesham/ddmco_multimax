# Item Variant Details Report — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new "Item Variant Details" report screen accessible from Nav Drawer > Stock > Reports that shows all variants of a parent Item with their attribute values, and navigates to the Item form on tap.

**Architecture:** Follows the established Report View pattern (mirrors BOM Search exactly): `AppShellScaffold` + `DocTypeListHeader` + `ReportFilterSheet` + `GetxController`. The ERPNext script report returns dynamic attribute columns, so the controller stores both `reportColumns` and `reportData`; the tile renders attributes generically by iterating the column list at runtime.

**Tech Stack:** Flutter/Dart 3, GetX (state + DI), Dio (HTTP), `frappe.desk.query_report.run` API endpoint.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `lib/app/modules/stock/reports/item_variant_details/item_variant_details_binding.dart` | GetX DI registration |
| Create | `lib/app/modules/stock/reports/item_variant_details/item_variant_details_controller.dart` | Filter state, report data, `runReport()` |
| Create | `lib/app/modules/stock/reports/item_variant_details/item_variant_details_screen.dart` | UI: header, filter sheet, result tiles |
| Modify | `lib/app/data/providers/api_provider.dart` | Add `getItemVariantDetails()` + static parse helper |
| Modify | `lib/app/data/routes/app_routes.dart` | New route constant |
| Modify | `lib/app/data/routes/app_pages.dart` | New `GetPage` entry |
| Modify | `lib/app/modules/global_widgets/app_nav_drawer.dart` | New drawer item under Stock > Reports |
| Create | `test/unit/item_variant_details_api_test.dart` | Unit tests for response-parsing logic |

---

## Task 1: API Method (TDD)

**Files:**
- Modify: `lib/app/data/providers/api_provider.dart` (after line 451, end of `getBatchWiseBalance`)
- Create: `test/unit/item_variant_details_api_test.dart`

- [ ] **Step 1.1 — Create the test file**

Create `test/unit/item_variant_details_api_test.dart` with this content:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

void main() {
  group('ApiProvider.parseItemVariantDetailsResponse', () {
    test('T-1: returns empty record when message is null', () {
      final result = ApiProvider.parseItemVariantDetailsResponse(null);
      expect(result.columns, isEmpty);
      expect(result.rows, isEmpty);
    });

    test('T-2: returns empty record when message lacks columns/result keys', () {
      final result = ApiProvider.parseItemVariantDetailsResponse({'other': 'data'});
      expect(result.columns, isEmpty);
      expect(result.rows, isEmpty);
    });

    test('T-3: parses columns and rows from a well-formed message', () {
      final message = <String, dynamic>{
        'columns': [
          {'fieldname': 'item',   'label': 'Item'},
          {'fieldname': 'colour', 'label': 'Colour'},
          {'fieldname': 'size',   'label': 'Size'},
        ],
        'result': [
          {'item': 'BLUE-T-S', 'colour': 'Blue', 'size': 'S'},
          {'item': 'BLUE-T-M', 'colour': 'Blue', 'size': 'M'},
        ],
      };
      final result = ApiProvider.parseItemVariantDetailsResponse(message);
      expect(result.columns.length, 3);
      expect(result.rows.length, 2);
      expect(result.columns.first['fieldname'], 'item');
      expect(result.rows.first['item'], 'BLUE-T-S');
      expect(result.rows.last['size'], 'M');
    });

    test('T-4: ignores null and non-Map entries in the result list', () {
      final message = <String, dynamic>{
        'columns': [{'fieldname': 'item', 'label': 'Item'}],
        'result': [
          null,
          {'item': 'ITEM-001'},
          42,
          {'item': 'ITEM-002'},
        ],
      };
      final result = ApiProvider.parseItemVariantDetailsResponse(message);
      expect(result.rows.length, 2);
      expect(result.rows.map((r) => r['item']),
          containsAll(['ITEM-001', 'ITEM-002']));
    });

    test('T-5: returns empty record when columns or result are not Lists', () {
      final message = <String, dynamic>{
        'columns': 'not-a-list',
        'result':  'not-a-list',
      };
      final result = ApiProvider.parseItemVariantDetailsResponse(message);
      expect(result.columns, isEmpty);
      expect(result.rows, isEmpty);
    });
  });
}
```

- [ ] **Step 1.2 — Run tests to confirm they fail (method does not exist yet)**

```
flutter test test/unit/item_variant_details_api_test.dart -v
```

Expected output contains:
```
Error: Method not found: 'ApiProvider.parseItemVariantDetailsResponse'
```

- [ ] **Step 1.3 — Add the static parse helper and `getItemVariantDetails` instance method to `api_provider.dart`**

Insert the following block immediately after the closing `}` of `getBatchWiseBalance` (after line 451):

```dart

  // ---------------------------------------------------------------------------
  // getItemVariantDetails
  // ---------------------------------------------------------------------------

  /// Fetches all variants of [itemCode] (the template/parent item) via the
  /// ERPNext "Item Variant Details" script report.
  ///
  /// Returns both column definitions (dynamic per item template) and row data
  /// so the UI can render attribute columns generically at runtime.
  Future<({List<Map<String, dynamic>> columns, List<Map<String, dynamic>> rows})>
      getItemVariantDetails(String itemCode) async {
    if (!_dioInitialised) await _initDio();

    late final Response response;
    try {
      response = await _dio.get(
        '/api/method/frappe.desk.query_report.run',
        queryParameters: {
          'report_name'           : 'Item Variant Details',
          'filters'               : json.encode({'item': itemCode}),
          'ignore_prepared_report': 'true',
          '_'                     : DateTime.now().millisecondsSinceEpoch,
        },
      );
    } on DioException {
      return (columns: [], rows: []);
    } catch (_) {
      return (columns: [], rows: []);
    }

    if (response.statusCode != 200) return (columns: [], rows: []);

    return parseItemVariantDetailsResponse(
      response.data['message'] as Map<String, dynamic>?,
    );
  }

  /// Exposed as a public static method so unit tests can exercise the parsing
  /// logic without a live HTTP connection or GetX service registration.
  static ({List<Map<String, dynamic>> columns, List<Map<String, dynamic>> rows})
      parseItemVariantDetailsResponse(Map<String, dynamic>? message) {
    if (message == null) return (columns: [], rows: []);
    try {
      final rawCols = message['columns'] as List<dynamic>? ?? [];
      final rawRows = message['result']  as List<dynamic>? ?? [];
      final columns = rawCols
          .whereType<Map>()
          .map((c) => Map<String, dynamic>.from(c))
          .toList();
      final rows = rawRows
          .whereType<Map>()
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
      return (columns: columns, rows: rows);
    } catch (_) {
      return (columns: [], rows: []);
    }
  }
```

- [ ] **Step 1.4 — Run tests to confirm all five pass**

```
flutter test test/unit/item_variant_details_api_test.dart -v
```

Expected output:
```
00:0X +5: All tests passed!
```

- [ ] **Step 1.5 — Commit**

```
git add lib/app/data/providers/api_provider.dart test/unit/item_variant_details_api_test.dart
git commit -m "feat(api): add getItemVariantDetails method and parse helper"
```

---

## Task 2: Binding and Controller

**Files:**
- Create: `lib/app/modules/stock/reports/item_variant_details/item_variant_details_binding.dart`
- Create: `lib/app/modules/stock/reports/item_variant_details/item_variant_details_controller.dart`

- [ ] **Step 2.1 — Create the binding**

Create `lib/app/modules/stock/reports/item_variant_details/item_variant_details_binding.dart`:

```dart
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock/reports/item_variant_details/item_variant_details_controller.dart';

class ItemVariantDetailsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ItemVariantDetailsController>(
      () => ItemVariantDetailsController(),
    );
  }
}
```

- [ ] **Step 2.2 — Create the controller**

Create `lib/app/modules/stock/reports/item_variant_details/item_variant_details_controller.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class ItemVariantDetailsController extends GetxController {
  final ApiProvider _api = Get.find<ApiProvider>();

  // ── Filter state ───────────────────────────────────────────────────────────
  final itemCodeController = TextEditingController();
  late final Map<String, TextEditingController> filterControllers;

  // ── Report state ───────────────────────────────────────────────────────────
  final isLoading     = false.obs;
  final reportData    = <Map<String, dynamic>>[].obs;
  final reportColumns = <Map<String, dynamic>>[].obs;
  final activeFilters = <String, String>{}.obs;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void onInit() {
    super.onInit();
    filterControllers = {'item_code': itemCodeController};
  }

  @override
  void onClose() {
    itemCodeController.dispose();
    super.onClose();
  }

  // ── Public API ─────────────────────────────────────────────────────────────
  int get activeFilterCount =>
      filterControllers.values.where((c) => c.text.trim().isNotEmpty).length;

  void clearFilter(String key) {
    filterControllers[key]?.clear();
    activeFilters.remove(key);
    if (key == 'item_code') {
      reportData.clear();
      reportColumns.clear();
    }
  }

  void clearFilters() {
    for (final c in filterControllers.values) c.clear();
    activeFilters.clear();
    reportData.clear();
    reportColumns.clear();
  }

  Future<void> runReport() async {
    final itemCode = itemCodeController.text.trim();

    if (itemCode.isEmpty) {
      GlobalSnackbar.warning(
        title:   'Filter Required',
        message: 'Please select an Item to run the report.',
      );
      return;
    }

    _rebuildActiveFilters();
    isLoading.value = true;
    reportData.clear();
    reportColumns.clear();

    try {
      final result = await _api.getItemVariantDetails(itemCode);
      reportColumns.assignAll(result.columns);
      reportData.assignAll(result.rows);
    } catch (e) {
      GlobalSnackbar.error(
        title:   'Report Error',
        message: 'Failed to fetch Item Variant Details: $e',
      );
    } finally {
      isLoading.value = false;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  static const _labels = {'item_code': 'Item'};

  void _rebuildActiveFilters() {
    activeFilters.clear();
    filterControllers.forEach((key, ctrl) {
      final v = ctrl.text.trim();
      if (v.isNotEmpty) activeFilters[key] = '${_labels[key] ?? key}: $v';
    });
  }
}
```

- [ ] **Step 2.3 — Run analyzer**

```
flutter analyze lib/app/modules/stock/reports/item_variant_details/
```

Expected: no errors or warnings.

- [ ] **Step 2.4 — Commit**

```
git add lib/app/modules/stock/reports/item_variant_details/item_variant_details_binding.dart lib/app/modules/stock/reports/item_variant_details/item_variant_details_controller.dart
git commit -m "feat(stock-reports): add ItemVariantDetails binding and controller"
```

---

## Task 3: Screen

**Files:**
- Create: `lib/app/modules/stock/reports/item_variant_details/item_variant_details_screen.dart`

- [ ] **Step 3.1 — Create the screen**

Create `lib/app/modules/stock/reports/item_variant_details/item_variant_details_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';
import 'package:multimax/app/modules/stock/reports/item_variant_details/item_variant_details_controller.dart';

class ItemVariantDetailsScreen extends GetView<ItemVariantDetailsController> {
  const ItemVariantDetailsScreen({super.key});

  // ── Filter field descriptors ───────────────────────────────────────────────
  List<ReportFilterField> get _fields => [
    const ReportFilterField(
      key:         'item_code',
      label:       'Item *',
      type:        ReportFilterType.doctypeLink,
      linkDoctype: 'Item',
      prefixIcon:  Icons.category_outlined,
      required:    true,
    ),
  ];

  // ── Filter chip builder ────────────────────────────────────────────────────
  List<Widget> _buildFilterChips(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget chip(String key, String label) => Chip(
          avatar: Icon(Icons.filter_alt_outlined,
              size: 14, color: cs.onSecondaryContainer),
          label: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cs.onSecondaryContainer,
                fontWeight: FontWeight.w600),
          ),
          backgroundColor: cs.secondaryContainer,
          deleteIconColor: cs.onSecondaryContainer,
          onDeleted: () => controller.clearFilter(key),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          side: BorderSide.none,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        );

    final chips = <Widget>[];
    controller.activeFilters.forEach((key, label) {
      chips.add(chip(key, label));
    });
    return chips;
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AppShellScaffold(
      body: Obx(() {
        return RefreshIndicator(
          onRefresh: controller.runReport,
          color: cs.primary,
          backgroundColor: cs.surfaceContainerHighest,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── Unified header ─────────────────────────────────────────────
              DocTypeListHeader(
                title:                    'Item Variant Details',
                automaticallyImplyLeading: false,
                activeFilters: controller.activeFilters
                    .map((k, v) => MapEntry(k, v as dynamic))
                    .obs,
                onFilterTap: () => showReportFilterSheet(
                  context:     context,
                  title:       'Item Variant Details Filters',
                  fields:      _fields,
                  controllers: controller.filterControllers,
                  onRun:       controller.runReport,
                  onClear:     controller.clearFilters,
                ),
                filterChipsBuilder: _buildFilterChips,
                onClearAllFilters:  controller.clearFilters,
              ),

              // ── Results ────────────────────────────────────────────────────
              if (controller.isLoading.value)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (controller.reportData.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.style_outlined,
                            size: 64,
                            color: cs.outlineVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Enter an Item and tap Run Report',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.tonalIcon(
                            onPressed: () => showReportFilterSheet(
                              context:     context,
                              title:       'Item Variant Details Filters',
                              fields:      _fields,
                              controllers: controller.filterControllers,
                              onRun:       controller.runReport,
                              onClear:     controller.clearFilters,
                            ),
                            icon: const Icon(Icons.filter_alt_outlined),
                            label: const Text('Set Filters'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final row = controller.reportData[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _VariantTile(
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

// ── Result tile ───────────────────────────────────────────────────────────────

class _VariantTile extends StatelessWidget {
  final Map<String, dynamic>       row;
  final List<Map<String, dynamic>> columns;

  const _VariantTile({required this.row, required this.columns});

  static const _skipFields = {'item', 'item_name', 'variant_of'};

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final itemCode = row['item']?.toString()      ?? '—';
    final itemName = row['item_name']?.toString() ?? '';

    final attrColumns = columns
        .where((c) => !_skipFields.contains(c['fieldname'] as String? ?? ''))
        .toList();

    return Material(
      color: cs.surface,
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Get.toNamed(
          AppRoutes.ITEM_FORM,
          arguments: {'name': itemCode},
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          itemCode,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (itemName.isNotEmpty && itemName != itemCode)
                          Text(
                            itemName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: cs.outlineVariant),
                ],
              ),
              if (attrColumns.isNotEmpty) ...[
                const Divider(height: 20),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: attrColumns.map((col) {
                    final fieldname = col['fieldname'] as String? ?? '';
                    final label     = col['label']     as String? ?? fieldname;
                    return _Detail(label: label, value: row[fieldname]);
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

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
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
```

- [ ] **Step 3.2 — Run analyzer**

```
flutter analyze lib/app/modules/stock/reports/item_variant_details/
```

Expected: no errors or warnings.

- [ ] **Step 3.3 — Commit**

```
git add lib/app/modules/stock/reports/item_variant_details/item_variant_details_screen.dart
git commit -m "feat(stock-reports): add ItemVariantDetailsScreen"
```

---

## Task 4: Routing and Nav Drawer

**Files:**
- Modify: `lib/app/data/routes/app_routes.dart`
- Modify: `lib/app/data/routes/app_pages.dart`
- Modify: `lib/app/modules/global_widgets/app_nav_drawer.dart`

- [ ] **Step 4.1 — Add route constants to `app_routes.dart`**

In `AppRoutes`, after the `JOB_CARD_SUMMARY` line, add:

```dart
  static const ITEM_VARIANT_DETAILS  = _Paths.ITEM_VARIANT_DETAILS;
```

In `_Paths`, after the `JOB_CARD_SUMMARY` line, add:

```dart
  static const ITEM_VARIANT_DETAILS  = '/stock/reports/item-variant-details';
```

The relevant section of `app_routes.dart` after the edit:

```dart
abstract class AppRoutes {
  // ... existing constants ...
  static const BATCH_WISE_BALANCE    = _Paths.BATCH_WISE_BALANCE;
  static const JOB_CARD_SUMMARY      = _Paths.JOB_CARD_SUMMARY;
  static const ITEM_VARIANT_DETAILS  = _Paths.ITEM_VARIANT_DETAILS;  // ← NEW
}

abstract class _Paths {
  // ... existing paths ...
  static const BATCH_WISE_BALANCE    = '/stock/batch-wise-balance';
  static const JOB_CARD_SUMMARY      = '/manufacturing/reports/job-card-summary';
  static const ITEM_VARIANT_DETAILS  = '/stock/reports/item-variant-details';  // ← NEW
}
```

- [ ] **Step 4.2 — Add `GetPage` entry to `app_pages.dart`**

Add the following two import lines near the other stock-report imports at the top of `app_pages.dart`:

```dart
import 'package:multimax/app/modules/stock/reports/item_variant_details/item_variant_details_binding.dart';
import 'package:multimax/app/modules/stock/reports/item_variant_details/item_variant_details_screen.dart';
```

Then add the `GetPage` entry at the end of the `routes` list, immediately before the closing `];`:

```dart
    GetPage(
      name:       AppRoutes.ITEM_VARIANT_DETAILS,
      page:       () => const ItemVariantDetailsScreen(),
      binding:    ItemVariantDetailsBinding(),
      transition: Transition.rightToLeftWithFade,
    ),
```

- [ ] **Step 4.3 — Add nav drawer entry to `app_nav_drawer.dart`**

In the Stock `_ModuleGroup` children, after the Batch-Wise Balance `_DrawerItem`:

```dart
// ── Stock > Reports ──────────────────────────────────────
const _NavSubheading('Reports'),
_DrawerItem(
  title:        'Batch-Wise Balance',
  icon:         Icons.history_toggle_off_rounded,
  route:        AppRoutes.BATCH_WISE_BALANCE,
  currentRoute: currentRoute,
),
_DrawerItem(                                   // ← NEW
  title:        'Item Variant Details',
  icon:         Icons.style_outlined,
  route:        AppRoutes.ITEM_VARIANT_DETAILS,
  currentRoute: currentRoute,
),
```

- [ ] **Step 4.4 — Run full analyzer**

```
flutter analyze lib/
```

Expected: no errors or warnings.

- [ ] **Step 4.5 — Run all tests**

```
flutter test
```

Expected:
```
00:0X +5: All tests passed!
```

- [ ] **Step 4.6 — Commit**

```
git add lib/app/data/routes/app_routes.dart lib/app/data/routes/app_pages.dart lib/app/modules/global_widgets/app_nav_drawer.dart
git commit -m "feat(stock-reports): wire Item Variant Details route and nav drawer entry"
```

---

## Smoke Test Checklist (manual, on device)

After all four tasks are committed:

- [ ] Open Nav Drawer → Stock → Reports section shows both "Batch-Wise Balance" and "Item Variant Details"
- [ ] Tap "Item Variant Details" → screen opens with empty state icon and "Set Filters" button
- [ ] Tap "Set Filters" → filter sheet opens with a single "Item \*" doctypeLink picker
- [ ] Select a parent item that has variants (e.g. a clothing template) → tap "Run Report" → tiles appear
- [ ] Each tile shows Item Code, Item Name subtitle, attribute key-value pairs (Colour, Size, etc.)
- [ ] Active filter chip appears in the header showing "Item: <selected code>"
- [ ] Tap a variant tile → navigates to the Item form for that variant
- [ ] Tap the delete icon on the filter chip → filter cleared, results cleared
- [ ] "Clear All" button in filter sheet → all filters and results cleared
- [ ] Select a parent item that has no variants → empty state is shown (no crash)
- [ ] Pull-to-refresh re-runs the report
