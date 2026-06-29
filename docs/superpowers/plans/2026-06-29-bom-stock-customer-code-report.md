# BOM Stock with Customer Code — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the ERPNext Script Report **`BOM Stock with Customer Code`** as a card-tile mobile report under **Menu → App Nav Drawer → Manufacturing → Reports**, with all six report filters driven entirely by standard Frappe REST (no report-private whitelisted-method dependency).

**Architecture:** Mirror the existing report module pattern (BOM Search / Job Card Summary): a GetX binding + controller + screen under `lib/app/modules/manufacturing/reports/bom_stock_customer_code/`, a route constant + `GetPage`, new methods on the shared `ApiProvider` (all parsing extracted into static, unit-tested helpers), and one `DocTypeGuard` + `_DrawerItem` in the drawer. Filters and the customer-code chips read data via `getList` / `getPosUpload`; the report runs via `frappe.desk.query_report.run`.

**Tech Stack:** Flutter, GetX (state + DI), Dio (`ApiProvider`), `flutter_test`. Reused widgets: `DocTypeListHeader`, `AsyncIconButton`, `LinkFieldWidget`, `WarehousePickerSheet`, `DocCardSkeletonList`, `FilterChipWidget`.

## Global Constraints

- Report name string is **exactly** `BOM Stock with Customer Code` (capitalisation/spacing matter).
- Endpoint for running the report: `GET /api/method/frappe.desk.query_report.run` with `report_name`, JSON-encoded `filters`, `ignore_prepared_report: 'true'`, `are_default_filters: 'false'`, cache-buster `_`.
- **No** dependency on `get_customer_ref_codes` / `get_pos_upload_codes`. Reading `Item Customer Detail` directly returns 403 — never query it.
- Route path convention: `'/manufacturing/reports/<kebab-name>'`. Route constant name: `BOM_STOCK_CUSTOMER_CODE`.
- Drawer item is gated `DocTypeGuard(doctype: 'BOM', permType: 'report')`; the Manufacturing reports `_GuardedSection` `doctypes` list already contains `'BOM'` — do not change it.
- Async feedback: the Run/Refresh control uses `AsyncIconButton` driven by the controller `RxBool isRunning`; `runReport()` is re-entrancy guarded (`if (isRunning.value) return;`) and clears the flag in a `finally`.
- All new public types/methods carry the exact names in the **Interfaces** blocks below.
- Commit after every task. Run `flutter analyze` before each commit; it must report no new errors.

---

## File Structure

**Create:**
- `lib/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_binding.dart`
- `lib/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart`
- `lib/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_screen.dart`
- `lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_tile.dart`
- `lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_totals_footer.dart`
- `lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_filter_sheet.dart`
- `test/unit/bom_stock_customer_code_api_test.dart`
- `test/unit/bom_stock_customer_code_controller_test.dart`
- `test/widget/bom_stock_tile_test.dart`
- `test/widget/bom_stock_totals_footer_test.dart`

**Modify:**
- `lib/app/data/providers/api_provider.dart` — add report-run + helper methods.
- `lib/app/data/routes/app_routes.dart` — add route constant.
- `lib/app/data/routes/app_pages.dart` — add `GetPage` + imports.
- `lib/app/modules/global_widgets/app_nav_drawer.dart` — add drawer item.

---

## Task 1: ApiProvider — report filter builder + run method

**Files:**
- Modify: `lib/app/data/providers/api_provider.dart` (add after the BOM Search block, ~line 1356)
- Test: `test/unit/bom_stock_customer_code_api_test.dart`

**Interfaces:**
- Produces: `static Map<String, dynamic> ApiProvider.buildBomStockFilters({String? customer, List<String> customerCodes = const [], List<String> warehouses = const [], String? posUpload, bool showExplodedView = false, bool hideOutOfStock = false})`
- Produces: `Future<Response> ApiProvider.runBomStockWithCustomerCode({String? customer, List<String> customerCodes = const [], List<String> warehouses = const [], String? posUpload, bool showExplodedView = false, bool hideOutOfStock = false})`

- [ ] **Step 1: Write the failing test**

Create `test/unit/bom_stock_customer_code_api_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

void main() {
  group('ApiProvider.buildBomStockFilters', () {
    test('omits every filter when all are empty/false', () {
      expect(ApiProvider.buildBomStockFilters(), isEmpty);
    });

    test('includes trimmed customer when set', () {
      final f = ApiProvider.buildBomStockFilters(customer: '  Acme  ');
      expect(f['customer'], 'Acme');
    });

    test('passes customer codes and warehouses through as lists', () {
      final f = ApiProvider.buildBomStockFilters(
        customerCodes: ['5067101', '5067102'],
        warehouses: ['Stores - M'],
      );
      expect(f['customer_code'], ['5067101', '5067102']);
      expect(f['warehouse'], ['Stores - M']);
    });

    test('omits empty code/warehouse lists', () {
      final f = ApiProvider.buildBomStockFilters(
        customerCodes: const [],
        warehouses: const [],
      );
      expect(f.containsKey('customer_code'), isFalse);
      expect(f.containsKey('warehouse'), isFalse);
    });

    test('encodes checkboxes as 1 only when true, omits when false', () {
      final on = ApiProvider.buildBomStockFilters(
        showExplodedView: true,
        hideOutOfStock: true,
      );
      expect(on['show_exploded_view'], 1);
      expect(on['hide_out_of_stock'], 1);

      final off = ApiProvider.buildBomStockFilters();
      expect(off.containsKey('show_exploded_view'), isFalse);
      expect(off.containsKey('hide_out_of_stock'), isFalse);
    });

    test('includes trimmed pos_upload when set', () {
      final f = ApiProvider.buildBomStockFilters(posUpload: ' ML-2026-02011 ');
      expect(f['pos_upload'], 'ML-2026-02011');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/bom_stock_customer_code_api_test.dart`
Expected: FAIL — `buildBomStockFilters` is not defined.

- [ ] **Step 3: Write minimal implementation**

In `lib/app/data/providers/api_provider.dart`, add immediately after the `searchBom` method (after line 1356, before the `// JOB CARD SUMMARY` divider):

```dart
  // ---------------------------------------------------------------------------
  // BOM STOCK WITH CUSTOMER CODE
  // ---------------------------------------------------------------------------

  /// Builds the `frappe.desk.query_report.run` filter map for the
  /// "BOM Stock with Customer Code" report. Empty/false filters are omitted so
  /// the report applies its own defaults. Checkboxes are encoded as `1` when on.
  static Map<String, dynamic> buildBomStockFilters({
    String? customer,
    List<String> customerCodes = const [],
    List<String> warehouses = const [],
    String? posUpload,
    bool showExplodedView = false,
    bool hideOutOfStock = false,
  }) {
    final f = <String, dynamic>{};
    if (customer != null && customer.trim().isNotEmpty) {
      f['customer'] = customer.trim();
    }
    if (customerCodes.isNotEmpty) f['customer_code'] = customerCodes;
    if (warehouses.isNotEmpty) f['warehouse'] = warehouses;
    if (posUpload != null && posUpload.trim().isNotEmpty) {
      f['pos_upload'] = posUpload.trim();
    }
    if (showExplodedView) f['show_exploded_view'] = 1;
    if (hideOutOfStock) f['hide_out_of_stock'] = 1;
    return f;
  }

  /// Runs the "BOM Stock with Customer Code" scripted report.
  ///
  /// Returns the raw [Response] so the controller can parse
  /// `message.result` (a List of row dicts; the last row is the appended
  /// `add_total_row` total).
  Future<Response> runBomStockWithCustomerCode({
    String? customer,
    List<String> customerCodes = const [],
    List<String> warehouses = const [],
    String? posUpload,
    bool showExplodedView = false,
    bool hideOutOfStock = false,
  }) async {
    if (!_dioInitialised) await _initDio();

    final filters = buildBomStockFilters(
      customer: customer,
      customerCodes: customerCodes,
      warehouses: warehouses,
      posUpload: posUpload,
      showExplodedView: showExplodedView,
      hideOutOfStock: hideOutOfStock,
    );

    return await _dio.get(
      '/api/method/frappe.desk.query_report.run',
      queryParameters: {
        'report_name'           : 'BOM Stock with Customer Code',
        'filters'               : json.encode(filters),
        'ignore_prepared_report': 'true',
        'are_default_filters'   : 'false',
        '_'                     : DateTime.now().millisecondsSinceEpoch,
      },
    );
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/bom_stock_customer_code_api_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/app/data/providers/api_provider.dart test/unit/bom_stock_customer_code_api_test.dart
git commit -m "feat(manufacturing): add BOM Stock w/ Customer Code report-run API"
```

---

## Task 2: ApiProvider — POS Upload ref-code parser + link-search helpers

**Files:**
- Modify: `lib/app/data/providers/api_provider.dart` (continue the BOM Stock block from Task 1)
- Test: `test/unit/bom_stock_customer_code_api_test.dart` (append a group)

**Interfaces:**
- Consumes (Task 1): the `// BOM STOCK WITH CUSTOMER CODE` section anchor.
- Produces: `static List<String> ApiProvider.parsePosUploadRefCodes(dynamic docData)` — distinct, non-empty `ref_code`s from a `GET /api/resource/POS Upload/{name}` response body.
- Produces: `Future<List<String>> ApiProvider.getPosUploadRefCodes(String posUpload)`
- Produces: `Future<List<String>> ApiProvider.searchLinkOptions(String doctype, {String query = '', int limit = 20})` — distinct `name`s of a doctype filtered by `name like %query%`.
- Produces: `Future<List<String>> ApiProvider.getWarehouseNames()` — all Warehouse names.

- [ ] **Step 1: Write the failing test**

Append to `test/unit/bom_stock_customer_code_api_test.dart` (inside `main`, after the existing group):

```dart
  group('ApiProvider.parsePosUploadRefCodes', () {
    test('returns empty list when body is null or wrong shape', () {
      expect(ApiProvider.parsePosUploadRefCodes(null), isEmpty);
      expect(ApiProvider.parsePosUploadRefCodes('nope'), isEmpty);
      expect(ApiProvider.parsePosUploadRefCodes({'data': 'nope'}), isEmpty);
      expect(ApiProvider.parsePosUploadRefCodes({'data': {'items': 'nope'}}), isEmpty);
    });

    test('extracts distinct non-empty ref_codes from the items child table', () {
      final body = {
        'data': {
          'name': 'ML-2026-02011',
          'items': [
            {'ref_code': '5067101', 'quantity': 240},
            {'ref_code': '5067102', 'quantity': 240},
            {'ref_code': '5067101', 'quantity': 120}, // duplicate
            {'ref_code': '',        'quantity': 0},    // empty
            {'quantity': 5},                            // missing ref_code
          ],
        },
      };
      expect(
        ApiProvider.parsePosUploadRefCodes(body),
        ['5067101', '5067102'],
      );
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/bom_stock_customer_code_api_test.dart`
Expected: FAIL — `parsePosUploadRefCodes` is not defined.

- [ ] **Step 3: Write minimal implementation**

In `api_provider.dart`, append to the `// BOM STOCK WITH CUSTOMER CODE` section (after `runBomStockWithCustomerCode`):

```dart
  /// Parses the distinct, non-empty `ref_code` values out of a
  /// `GET /api/resource/POS Upload/{name}` response body (`data.items[]`).
  static List<String> parsePosUploadRefCodes(dynamic docData) {
    if (docData is! Map) return [];
    final doc = docData['data'];
    if (doc is! Map) return [];
    final items = doc['items'];
    if (items is! List) return [];
    final codes = <String>[];
    for (final it in items) {
      if (it is! Map) continue;
      final code = (it['ref_code'] ?? '').toString().trim();
      if (code.isNotEmpty && !codes.contains(code)) codes.add(code);
    }
    return codes;
  }

  /// Returns the distinct customer ref-codes contained in [posUpload], read
  /// from the POS Upload document's `items` child table. Empty on any failure.
  Future<List<String>> getPosUploadRefCodes(String posUpload) async {
    if (posUpload.isEmpty) return [];
    try {
      final resp = await getPosUpload(posUpload);
      if (resp.statusCode == 200) return parsePosUploadRefCodes(resp.data);
    } catch (_) {
      // Picker convenience only — never block the report on this.
    }
    return [];
  }

  /// Searches a doctype's `name` field (`like %query%`) and returns the
  /// matching names, sorted ascending. Used to drive the Customer / POS Upload
  /// pickers without prefetching the whole table.
  Future<List<String>> searchLinkOptions(
    String doctype, {
    String query = '',
    int limit = 20,
  }) async {
    final rows = await getList(
      null,
      doctype: doctype,
      fields: ['name'],
      filters: query.trim().isEmpty ? null : {'name': ['like', '%${query.trim()}%']},
      limit: limit,
      orderBy: 'name asc',
    );
    return rows
        .map((r) => (r['name'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
  }

  /// All Warehouse names (the warehouse list is small enough to prefetch and
  /// filter client-side in [WarehousePickerSheet]).
  Future<List<String>> getWarehouseNames() =>
      searchLinkOptions('Warehouse', limit: 0);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/bom_stock_customer_code_api_test.dart`
Expected: PASS (8 tests total).

- [ ] **Step 5: Commit**

```bash
git add lib/app/data/providers/api_provider.dart test/unit/bom_stock_customer_code_api_test.dart
git commit -m "feat(manufacturing): add POS-upload ref-code + link-search helpers"
```

---

## Task 3: Controller static parsers

**Files:**
- Create: `lib/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart` (statics only this task; instance members added in Task 4)
- Test: `test/unit/bom_stock_customer_code_controller_test.dart`

**Interfaces:**
- Produces (all `static` on `BomStockCustomerCodeController`):
  - `List<Map<String, dynamic>> parseDataRows(dynamic message)` — result rows **excluding** the appended total row (rows with a non-empty `item_code`).
  - `Map<String, dynamic>? extractTotalRow(dynamic message)` — the first result row with an empty/absent `item_code` (the `add_total_row` total), or null.
  - `bool isShortfall(Map<String, dynamic> row)` — true when `required_qty` is a non-zero number and `running_total < required_qty`.
  - `List<String> distinctCustomerCodes(List<Map<String, dynamic>> rows)`
  - `(List<String> found, List<String> missing) splitPosCodes(List<String> uploadCodes, List<Map<String, dynamic>> resultRows)`

- [ ] **Step 1: Write the failing test**

Create `test/unit/bom_stock_customer_code_controller_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';

void main() {
  const message = {
    'columns': [
      {'fieldname': 'item_code', 'label': 'Item'},
    ],
    'result': [
      {'item_code': 'A', 'customer_code': '5067101', 'in_stock_qty': 10, 'required_qty': 5,  'running_total': 10},
      {'item_code': 'B', 'customer_code': '5067102', 'in_stock_qty': 2,  'required_qty': 8,  'running_total': 2},
      {'item_code': 'A', 'customer_code': '5067101', 'in_stock_qty': 10, 'required_qty': 5,  'running_total': 0},
      {'item_code': '',  'item_name': 'Total', 'in_stock_qty': 22, 'running_total': 12}, // total row
    ],
  };

  group('parseDataRows', () {
    test('returns empty for null / wrong-shape message', () {
      expect(BomStockCustomerCodeController.parseDataRows(null), isEmpty);
      expect(BomStockCustomerCodeController.parseDataRows({'result': 'x'}), isEmpty);
    });

    test('keeps only rows with a non-empty item_code (drops the total row)', () {
      final rows = BomStockCustomerCodeController.parseDataRows(message);
      expect(rows.length, 3);
      expect(rows.every((r) => (r['item_code'] as String).isNotEmpty), isTrue);
    });
  });

  group('extractTotalRow', () {
    test('returns the row whose item_code is empty', () {
      final total = BomStockCustomerCodeController.extractTotalRow(message);
      expect(total, isNotNull);
      expect(total!['in_stock_qty'], 22);
    });

    test('returns null when there is no total row', () {
      final t = BomStockCustomerCodeController.extractTotalRow({
        'result': [
          {'item_code': 'A'},
        ],
      });
      expect(t, isNull);
    });
  });

  group('isShortfall', () {
    test('true when required_qty is non-zero and running_total is below it', () {
      expect(
        BomStockCustomerCodeController.isShortfall(
          {'required_qty': 8, 'running_total': 2}),
        isTrue,
      );
    });

    test('false when running_total meets or exceeds required_qty', () {
      expect(
        BomStockCustomerCodeController.isShortfall(
          {'required_qty': 5, 'running_total': 10}),
        isFalse,
      );
    });

    test('false when required_qty is null or zero', () {
      expect(BomStockCustomerCodeController.isShortfall({'running_total': 0}), isFalse);
      expect(
        BomStockCustomerCodeController.isShortfall(
          {'required_qty': 0, 'running_total': 0}),
        isFalse,
      );
    });
  });

  group('distinctCustomerCodes', () {
    test('returns distinct non-empty codes in first-seen order', () {
      final rows = BomStockCustomerCodeController.parseDataRows(message);
      expect(
        BomStockCustomerCodeController.distinctCustomerCodes(rows),
        ['5067101', '5067102'],
      );
    });
  });

  group('splitPosCodes', () {
    test('splits upload codes into found (present in results) and missing', () {
      final rows = BomStockCustomerCodeController.parseDataRows(message);
      final (found, missing) = BomStockCustomerCodeController.splitPosCodes(
        ['5067101', '5067102', '9999999'],
        rows,
      );
      expect(found, ['5067101', '5067102']);
      expect(missing, ['9999999']);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/bom_stock_customer_code_controller_test.dart`
Expected: FAIL — controller file / statics not defined.

- [ ] **Step 3: Write minimal implementation**

Create `lib/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart`:

```dart
import 'package:get/get.dart';

/// Controller for the "BOM Stock with Customer Code" report.
///
/// Parsing logic is exposed as pure static helpers so it can be unit-tested
/// without the network or GetX. Instance members (reactive state + actions)
/// are added on top of these.
class BomStockCustomerCodeController extends GetxController {
  // ── Static parsers (pure) ───────────────────────────────────────────────

  /// Data rows from a `query_report.run` `message`, excluding the appended
  /// `add_total_row` total (identified by an empty/absent `item_code`).
  static List<Map<String, dynamic>> parseDataRows(dynamic message) {
    if (message is! Map) return [];
    final result = message['result'];
    if (result is! List) return [];
    return result
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((r) => (r['item_code'] ?? '').toString().trim().isNotEmpty)
        .toList();
  }

  /// The appended total row (first result row with an empty `item_code`), or
  /// null when the report returned no total row.
  static Map<String, dynamic>? extractTotalRow(dynamic message) {
    if (message is! Map) return null;
    final result = message['result'];
    if (result is! List) return null;
    for (final e in result.whereType<Map>()) {
      final m = Map<String, dynamic>.from(e);
      if ((m['item_code'] ?? '').toString().trim().isEmpty) return m;
    }
    return null;
  }

  /// True when [row] is short of its POS-required quantity, mirroring the
  /// desk's red highlight: `required_qty` truthy and `running_total` below it.
  static bool isShortfall(Map<String, dynamic> row) {
    final req = row['required_qty'];
    if (req is! num || req == 0) return false;
    final rt = (row['running_total'] as num?)?.toDouble() ?? 0;
    return rt < req.toDouble();
  }

  /// Distinct, non-empty `customer_code` values in first-seen order.
  static List<String> distinctCustomerCodes(List<Map<String, dynamic>> rows) {
    final out = <String>[];
    for (final r in rows) {
      final c = (r['customer_code'] ?? '').toString().trim();
      if (c.isNotEmpty && !out.contains(c)) out.add(c);
    }
    return out;
  }

  /// Splits [uploadCodes] into codes present in [resultRows] (found) and codes
  /// absent from them (missing) — reproduces the desk's POS missing-codes
  /// banner using only readable result data.
  static (List<String>, List<String>) splitPosCodes(
    List<String> uploadCodes,
    List<Map<String, dynamic>> resultRows,
  ) {
    final present = distinctCustomerCodes(resultRows).toSet();
    final found = <String>[];
    final missing = <String>[];
    for (final raw in uploadCodes) {
      final code = raw.trim();
      if (code.isEmpty) continue;
      if (present.contains(code)) {
        if (!found.contains(code)) found.add(code);
      } else {
        if (!missing.contains(code)) missing.add(code);
      }
    }
    return (found, missing);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/bom_stock_customer_code_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart test/unit/bom_stock_customer_code_controller_test.dart
git commit -m "feat(manufacturing): add BOM Stock report parsing helpers"
```

---

## Task 4: Controller — reactive state + actions

**Files:**
- Modify: `lib/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart` (add instance members)
- Test: `test/unit/bom_stock_customer_code_controller_test.dart` (append a group)

**Interfaces:**
- Consumes: `ApiProvider.runBomStockWithCustomerCode`, `ApiProvider.getPosUploadRefCodes`, `ApiProvider.getWarehouseNames` (Tasks 1–2); the static helpers (Task 3); `GlobalSnackbar.error`.
- Produces (instance, on `BomStockCustomerCodeController`):
  - Filter state: `RxnString customer`, `RxList<String> customerCodes`, `RxList<String> warehouses`, `RxnString posUpload`, `RxBool showExplodedView`, `RxBool hideOutOfStock`.
  - Result state: `RxList<Map<String, dynamic>> reportRows`, `Rxn<Map<String, dynamic>> totalRow`, `RxList<String> posMissingCodes`, `RxList<String> discoveredCodes`, `RxBool isRunning`.
  - Picker state: `RxList<String> warehouseOptions`, `RxBool isLoadingWarehouses`.
  - Chip state: `RxMap<String, String> activeFilters`.
  - Methods: `Future<void> runReport()`, `Future<void> onPosUploadSelected(String? name)`, `void addCustomerCode(String code)`, `void removeCustomerCode(String code)`, `void addWarehouse(String wh)`, `void removeWarehouse(String wh)`, `Future<void> loadWarehouseOptions()`, `void clearFilters()`, `void clearFilter(String key)`.

- [ ] **Step 1: Write the failing test**

Append to `test/unit/bom_stock_customer_code_controller_test.dart` (inside `main`):

```dart
  group('controller mutations (no network)', () {
    test('addCustomerCode dedupes and trims; removeCustomerCode removes', () {
      final c = BomStockCustomerCodeController();
      c.addCustomerCode('  5067101 ');
      c.addCustomerCode('5067101'); // duplicate
      c.addCustomerCode('5067102');
      expect(c.customerCodes, ['5067101', '5067102']);
      c.removeCustomerCode('5067101');
      expect(c.customerCodes, ['5067102']);
    });

    test('addWarehouse dedupes; clearFilters resets everything', () {
      final c = BomStockCustomerCodeController();
      c.customer.value = 'Acme';
      c.addWarehouse('Stores - M');
      c.addWarehouse('Stores - M');
      c.addCustomerCode('5067101');
      c.showExplodedView.value = true;
      c.posMissingCodes.add('9999999');
      expect(c.warehouses, ['Stores - M']);

      c.clearFilters();
      expect(c.customer.value, isNull);
      expect(c.customerCodes, isEmpty);
      expect(c.warehouses, isEmpty);
      expect(c.showExplodedView.value, isFalse);
      expect(c.hideOutOfStock.value, isFalse);
      expect(c.posUpload.value, isNull);
      expect(c.posMissingCodes, isEmpty);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/bom_stock_customer_code_controller_test.dart`
Expected: FAIL — instance members not defined.

- [ ] **Step 3: Write minimal implementation**

Add the imports at the top of `bom_stock_customer_code_controller.dart`:

```dart
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
```

Inside the class, **above** the `// ── Static parsers` section, add:

```dart
  final ApiProvider _api = Get.find<ApiProvider>();

  // ── Filter state ────────────────────────────────────────────────────────
  final customer          = RxnString();
  final customerCodes     = <String>[].obs;
  final warehouses        = <String>[].obs;
  final posUpload         = RxnString();
  final showExplodedView  = false.obs;
  final hideOutOfStock    = false.obs;

  // ── Result state ────────────────────────────────────────────────────────
  final reportRows      = <Map<String, dynamic>>[].obs;
  final totalRow        = Rxn<Map<String, dynamic>>();
  final posMissingCodes = <String>[].obs;
  final discoveredCodes = <String>[].obs;
  final isRunning       = false.obs;

  // ── Warehouse picker state ──────────────────────────────────────────────
  final warehouseOptions    = <String>[].obs;
  final isLoadingWarehouses = false.obs;

  // ── Active-filter chips ─────────────────────────────────────────────────
  final activeFilters = <String, String>{}.obs;

  // ── Actions ─────────────────────────────────────────────────────────────

  Future<void> runReport() async {
    if (isRunning.value) return;
    isRunning.value = true;
    _rebuildActiveFilters();
    try {
      final resp = await _api.runBomStockWithCustomerCode(
        customer:         customer.value,
        customerCodes:    customerCodes.toList(),
        warehouses:       warehouses.toList(),
        posUpload:        posUpload.value,
        showExplodedView: showExplodedView.value,
        hideOutOfStock:   hideOutOfStock.value,
      );
      if (resp.statusCode == 200) {
        final message = resp.data['message'];
        reportRows.assignAll(parseDataRows(message));
        totalRow.value = extractTotalRow(message);
        discoveredCodes.assignAll(distinctCustomerCodes(reportRows));
      }
    } catch (e) {
      GlobalSnackbar.error(
        title:   'Report Error',
        message: 'Failed to run BOM Stock with Customer Code: $e',
      );
    } finally {
      isRunning.value = false;
    }
  }

  /// Selecting a POS Upload auto-fills [customerCodes] from its items, runs the
  /// report, then flags codes not present in the results as missing (banner).
  Future<void> onPosUploadSelected(String? name) async {
    final value = (name ?? '').trim();
    if (value.isEmpty) {
      posUpload.value = null;
      posMissingCodes.clear();
      customerCodes.clear();
      await runReport();
      return;
    }
    posUpload.value = value;
    final uploadCodes = await _api.getPosUploadRefCodes(value);
    customerCodes.assignAll(uploadCodes);
    await runReport();
    final (_, missing) = splitPosCodes(uploadCodes, reportRows.toList());
    posMissingCodes.assignAll(missing);
  }

  void addCustomerCode(String code) {
    final c = code.trim();
    if (c.isEmpty || customerCodes.contains(c)) return;
    customerCodes.add(c);
  }

  void removeCustomerCode(String code) => customerCodes.remove(code);

  void addWarehouse(String wh) {
    if (wh.isEmpty || warehouses.contains(wh)) return;
    warehouses.add(wh);
  }

  void removeWarehouse(String wh) => warehouses.remove(wh);

  Future<void> loadWarehouseOptions() async {
    if (warehouseOptions.isNotEmpty || isLoadingWarehouses.value) return;
    isLoadingWarehouses.value = true;
    try {
      warehouseOptions.assignAll(await _api.getWarehouseNames());
    } finally {
      isLoadingWarehouses.value = false;
    }
  }

  void clearFilters() {
    customer.value = null;
    customerCodes.clear();
    warehouses.clear();
    posUpload.value = null;
    showExplodedView.value = false;
    hideOutOfStock.value = false;
    posMissingCodes.clear();
    activeFilters.clear();
  }

  void clearFilter(String key) {
    switch (key) {
      case 'customer':           customer.value = null; break;
      case 'customer_code':      customerCodes.clear(); break;
      case 'warehouse':          warehouses.clear(); break;
      case 'pos_upload':         posUpload.value = null; posMissingCodes.clear(); break;
      case 'show_exploded_view': showExplodedView.value = false; break;
      case 'hide_out_of_stock':  hideOutOfStock.value = false; break;
    }
    activeFilters.remove(key);
  }

  void _rebuildActiveFilters() {
    final m = <String, String>{};
    if ((customer.value ?? '').isNotEmpty) m['customer'] = 'Customer: ${customer.value}';
    if (customerCodes.isNotEmpty) m['customer_code'] = 'Codes: ${customerCodes.length}';
    if (warehouses.isNotEmpty) m['warehouse'] = 'Warehouses: ${warehouses.length}';
    if ((posUpload.value ?? '').isNotEmpty) m['pos_upload'] = 'POS: ${posUpload.value}';
    if (showExplodedView.value) m['show_exploded_view'] = 'Exploded';
    if (hideOutOfStock.value) m['hide_out_of_stock'] = 'Hide OOS';
    activeFilters.assignAll(m);
  }
```

> Note: the mutation test constructs the controller directly. `Get.find<ApiProvider>()` runs in the field initializer; under `flutter test` no `ApiProvider` is registered, so register a throwaway one in the test's `setUp` if construction throws. Add at the top of the `controller mutations (no network)` group:
> ```dart
> setUp(() {
>   Get.testMode = true;
>   if (!Get.isRegistered<ApiProvider>()) Get.put(ApiProvider());
> });
> tearDown(Get.reset);
> ```
> and add `import 'package:get/get.dart';` + `import 'package:multimax/app/data/providers/api_provider.dart';` to the test file. (Constructing `ApiProvider` does not open a network connection; `_initDio` is lazy.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/bom_stock_customer_code_controller_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart test/unit/bom_stock_customer_code_controller_test.dart
git commit -m "feat(manufacturing): add BOM Stock report controller state + actions"
```

---

## Task 5: Binding + route + page registration

**Files:**
- Create: `lib/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_binding.dart`
- Modify: `lib/app/data/routes/app_routes.dart`
- Modify: `lib/app/data/routes/app_pages.dart`

**Interfaces:**
- Consumes: `BomStockCustomerCodeController` (Task 4), `BomStockCustomerCodeScreen` (Task 10 — a placeholder screen is created here so routing compiles; replaced in Task 10).
- Produces: `class BomStockCustomerCodeBinding extends Bindings`; `AppRoutes.BOM_STOCK_CUSTOMER_CODE`.

- [ ] **Step 1: Create the binding**

Create `bom_stock_customer_code_binding.dart`:

```dart
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';

class BomStockCustomerCodeBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ApiProvider>(() => ApiProvider());
    Get.lazyPut<BomStockCustomerCodeController>(
        () => BomStockCustomerCodeController());
  }
}
```

- [ ] **Step 2: Create a temporary placeholder screen (replaced in Task 10)**

Create `bom_stock_customer_code_screen.dart` so the route compiles now:

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';

class BomStockCustomerCodeScreen
    extends GetView<BomStockCustomerCodeController> {
  const BomStockCustomerCodeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('BOM Stock with Customer Code')),
    );
  }
}
```

- [ ] **Step 3: Add the route constant**

In `lib/app/data/routes/app_routes.dart`, add to the `AppRoutes` class (after `STOCK_BALANCE`, line 39):

```dart
  static const BOM_STOCK_CUSTOMER_CODE = _Paths.BOM_STOCK_CUSTOMER_CODE;
```

and to the `_Paths` class (after `STOCK_BALANCE`, line 77):

```dart
  static const BOM_STOCK_CUSTOMER_CODE = '/manufacturing/reports/bom-stock-customer-code';
```

- [ ] **Step 4: Register the GetPage**

In `lib/app/data/routes/app_pages.dart`, add the imports near the other report imports:

```dart
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_binding.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_screen.dart';
```

and add the `GetPage` immediately after the `JOB_CARD_SUMMARY` page (after line 215):

```dart
    GetPage(
      name: AppRoutes.BOM_STOCK_CUSTOMER_CODE,
      page: () => const BomStockCustomerCodeScreen(),
      binding: BomStockCustomerCodeBinding(),
      transition: Transition.rightToLeftWithFade,
    ),
```

- [ ] **Step 5: Verify it compiles**

Run: `flutter analyze lib/app/data/routes/app_pages.dart lib/app/modules/manufacturing/reports/bom_stock_customer_code`
Expected: No errors.

- [ ] **Step 6: Commit**

```bash
git add lib/app/data/routes/app_routes.dart lib/app/data/routes/app_pages.dart lib/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_binding.dart lib/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_screen.dart
git commit -m "feat(manufacturing): route + binding for BOM Stock w/ Customer Code"
```

---

## Task 6: BomStockTile widget

**Files:**
- Create: `lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_tile.dart`
- Test: `test/widget/bom_stock_tile_test.dart`

**Interfaces:**
- Consumes: `BomStockCustomerCodeController.isShortfall` (Task 3).
- Produces: `class BomStockTile extends StatelessWidget` with `const BomStockTile({super.key, required Map<String, dynamic> row})`.

- [ ] **Step 1: Write the failing test**

Create `test/widget/bom_stock_tile_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_tile.dart';

Widget _wrap(Map<String, dynamic> row) =>
    MaterialApp(home: Scaffold(body: BomStockTile(row: row)));

void main() {
  testWidgets('renders item name, code, and customer code', (tester) async {
    await tester.pumpWidget(_wrap({
      'item_name': 'BELTS PU HQ',
      'item_code': '2002843',
      'customer_code': '5067101',
      'in_stock_qty': 396,
      'running_total': 396,
    }));

    expect(find.text('BELTS PU HQ'), findsOneWidget);
    expect(find.text('2002843'), findsOneWidget);
    expect(find.text('5067101'), findsOneWidget);
  });

  testWidgets('shows the Required metric only when required_qty is present',
      (tester) async {
    await tester.pumpWidget(_wrap({
      'item_name': 'X',
      'item_code': 'X1',
      'in_stock_qty': 10,
      'running_total': 10,
    }));
    expect(find.text('Required'), findsNothing);

    await tester.pumpWidget(_wrap({
      'item_name': 'X',
      'item_code': 'X1',
      'in_stock_qty': 10,
      'required_qty': 5,
      'running_total': 10,
    }));
    expect(find.text('Required'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/bom_stock_tile_test.dart`
Expected: FAIL — `BomStockTile` not defined.

- [ ] **Step 3: Write minimal implementation**

Create `widgets/bom_stock_tile.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';

/// One card per row of the BOM Stock with Customer Code report.
class BomStockTile extends StatelessWidget {
  final Map<String, dynamic> row;
  const BomStockTile({super.key, required this.row});

  static String _fmt(num? v) {
    if (v == null) return '—';
    final d = v.toDouble();
    return d == d.roundToDouble()
        ? d.toStringAsFixed(0)
        : d.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final shortfall = BomStockCustomerCodeController.isShortfall(row);

    final image     = (row['image'] ?? '').toString();
    final itemName  = (row['item_name'] ?? '').toString();
    final itemCode  = (row['item_code'] ?? '').toString();
    final custCode  = (row['customer_code'] ?? '').toString();
    final customer  = (row['customer'] ?? '').toString();
    final bom       = (row['bom'] ?? '').toString();
    final inStock   = row['in_stock_qty'] as num?;
    final reqRaw    = row['required_qty'];
    final hasReq    = reqRaw is num;
    final running   = row['running_total'] as num?;
    final enough    = row['enough_parts_to_build'];

    return Material(
      color: cs.surface,
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: shortfall ? cs.error : cs.outlineVariant.withValues(alpha: 0.4),
            width: shortfall ? 1.5 : 1,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _thumb(cs, image),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        itemName.isEmpty ? itemCode : itemName,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (itemCode.isNotEmpty)
                        Text(
                          itemCode,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (custCode.isNotEmpty)
                            _chip(cs, Icons.qr_code_2, custCode),
                          if (customer.isNotEmpty)
                            _chip(cs, Icons.person_outline, customer),
                          if (bom.isNotEmpty)
                            _chip(cs, Icons.account_tree_outlined, bom),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _metric(theme, cs, 'In Stock', _fmt(inStock), false),
                if (hasReq)
                  _metric(theme, cs, 'Required', _fmt(reqRaw), shortfall),
                _metric(theme, cs, 'Running', _fmt(running), shortfall),
                if (enough != null)
                  _metric(theme, cs, 'Can Build', enough.toString(), false),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumb(ColorScheme cs, String image) => Container(
        width: 56,
        height: 56,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: image.isEmpty
            ? Icon(Icons.image_not_supported_outlined,
                size: 22, color: cs.outline)
            : Image.network(
                image,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(
                    Icons.broken_image_outlined, size: 22, color: cs.outline),
              ),
      );

  Widget _chip(ColorScheme cs, IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ],
        ),
      );

  Widget _metric(
      ThemeData theme, ColorScheme cs, String label, String value, bool alert) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: alert ? cs.error : cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
```

> Note: `withValues(alpha:)` is the current Flutter API (replacing the deprecated `withOpacity`). If `flutter analyze` flags it as undefined on this SDK, use `cs.outlineVariant.withOpacity(0.4)` instead.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/bom_stock_tile_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_tile.dart test/widget/bom_stock_tile_test.dart
git commit -m "feat(manufacturing): add BomStockTile card with shortfall accent"
```

---

## Task 7: BomStockTotalsFooter widget

**Files:**
- Create: `lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_totals_footer.dart`
- Test: `test/widget/bom_stock_totals_footer_test.dart`

**Interfaces:**
- Produces: `class BomStockTotalsFooter extends StatelessWidget` with `const BomStockTotalsFooter({super.key, required Map<String, dynamic>? total})`. Renders `SizedBox.shrink()` when `total` is null.

- [ ] **Step 1: Write the failing test**

Create `test/widget/bom_stock_totals_footer_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_totals_footer.dart';

void main() {
  testWidgets('renders nothing when total is null', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: BomStockTotalsFooter(total: null)),
    ));
    expect(find.text('Total'), findsNothing);
  });

  testWidgets('renders the total figures when present', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: BomStockTotalsFooter(total: {
          'in_stock_qty': 16239,
          'required_qty': 7644,
          'running_total': 16239,
        }),
      ),
    ));
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('16239'), findsWidgets);
    expect(find.text('7644'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/bom_stock_totals_footer_test.dart`
Expected: FAIL — `BomStockTotalsFooter` not defined.

- [ ] **Step 3: Write minimal implementation**

Create `widgets/bom_stock_totals_footer.dart`:

```dart
import 'package:flutter/material.dart';

/// Sticky footer showing the report's server-computed total row.
class BomStockTotalsFooter extends StatelessWidget {
  final Map<String, dynamic>? total;
  const BomStockTotalsFooter({super.key, required this.total});

  static String _fmt(num? v) {
    if (v == null) return '—';
    final d = v.toDouble();
    return d == d.roundToDouble()
        ? d.toStringAsFixed(0)
        : d.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final t = total;
    if (t == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Material(
      elevation: 8,
      color: cs.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Text('Total',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              _cell(theme, cs, 'In Stock', _fmt(t['in_stock_qty'] as num?)),
              _cell(theme, cs, 'Required', _fmt(t['required_qty'] as num?)),
              _cell(theme, cs, 'Running', _fmt(t['running_total'] as num?)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(ThemeData theme, ColorScheme cs, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
          Text(value,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/bom_stock_totals_footer_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_totals_footer.dart test/widget/bom_stock_totals_footer_test.dart
git commit -m "feat(manufacturing): add BOM Stock totals footer"
```

---

## Task 8: Filter sheet

**Files:**
- Create: `lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_filter_sheet.dart`

**Interfaces:**
- Consumes: `BomStockCustomerCodeController` (Tasks 3–4), `LinkFieldWidget`, `WarehousePickerSheet`, `ApiProvider.searchLinkOptions`.
- Produces: `void showBomStockFilterSheet(BuildContext context, BomStockCustomerCodeController c)`.

This task has no automated test (it is composed entirely of already-tested controller actions and reused, separately-tested widgets); it is verified by `flutter analyze` and the on-device smoke in Task 11.

- [ ] **Step 1: Create the filter sheet**

Create `widgets/bom_stock_filter_sheet.dart`:

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/link_field_widget.dart';
import 'package:multimax/app/modules/global_widgets/warehouse_picker_sheet.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';

/// Opens the BOM Stock with Customer Code filter editor as a scrollable
/// bottom sheet. Reads/writes the controller's reactive filter state.
void showBomStockFilterSheet(
    BuildContext context, BomStockCustomerCodeController c) {
  c.loadWarehouseOptions();
  Get.bottomSheet(
    _BomStockFilterSheet(c: c),
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
  );
}

class _BomStockFilterSheet extends StatefulWidget {
  final BomStockCustomerCodeController c;
  const _BomStockFilterSheet({required this.c});

  @override
  State<_BomStockFilterSheet> createState() => _BomStockFilterSheetState();
}

class _BomStockFilterSheetState extends State<_BomStockFilterSheet> {
  late final TextEditingController _customerCtrl;
  late final TextEditingController _posCtrl;
  final TextEditingController _codeInput = TextEditingController();

  BomStockCustomerCodeController get c => widget.c;

  @override
  void initState() {
    super.initState();
    _customerCtrl = TextEditingController(text: c.customer.value ?? '');
    _posCtrl = TextEditingController(text: c.posUpload.value ?? '');
  }

  @override
  void dispose() {
    _customerCtrl.dispose();
    _posCtrl.dispose();
    _codeInput.dispose();
    super.dispose();
  }

  Future<void> _pickLink({
    required String doctype,
    required String title,
    required ValueChanged<String?> onSelected,
  }) async {
    await Get.bottomSheet(
      _LinkSearchSheet(
        title: title,
        onSearch: (q) => Get.find<ApiProvider>().searchLinkOptions(doctype, query: q),
        onSelected: onSelected,
      ),
      isScrollControlled: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Filters',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const Spacer(),
              TextButton(
                onPressed: () {
                  c.clearFilters();
                  _customerCtrl.clear();
                  _posCtrl.clear();
                  setState(() {});
                },
                child: const Text('Clear Filters'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                // ── Customer ────────────────────────────────────────────
                LinkFieldWidget(
                  controller: _customerCtrl,
                  labelText: 'Customer',
                  hintText: 'Select Customer',
                  prefixIcon: Icons.person_outline,
                  onTap: () => _pickLink(
                    doctype: 'Customer',
                    title: 'Select Customer',
                    onSelected: (v) {
                      c.customer.value = v;
                      _customerCtrl.text = v ?? '';
                      setState(() {});
                    },
                  ),
                  onClear: () {
                    c.customer.value = null;
                    _customerCtrl.clear();
                    setState(() {});
                  },
                ),
                const SizedBox(height: 16),

                // ── Customer Codes (chips) ──────────────────────────────
                _label('Customer Codes'),
                Obx(() => Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: c.customerCodes
                          .map((code) => InputChip(
                                label: Text(code),
                                onDeleted: () => c.removeCustomerCode(code),
                              ))
                          .toList(),
                    )),
                TextField(
                  controller: _codeInput,
                  decoration: const InputDecoration(
                    hintText: 'Type a code, press Enter to add',
                    isDense: true,
                  ),
                  onSubmitted: (v) {
                    for (final part in v.split(',')) {
                      c.addCustomerCode(part);
                    }
                    _codeInput.clear();
                  },
                ),
                Obx(() => c.discoveredCodes.isEmpty
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _hint('From results — tap to add'),
                            Wrap(
                              spacing: 6,
                              children: c.discoveredCodes
                                  .map((code) => ActionChip(
                                        label: Text(code),
                                        onPressed: () => c.addCustomerCode(code),
                                      ))
                                  .toList(),
                            ),
                          ],
                        ),
                      )),
                const SizedBox(height: 16),

                // ── Warehouses (chips) ──────────────────────────────────
                _label('Warehouses'),
                Obx(() => Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: c.warehouses
                          .map((wh) => InputChip(
                                label: Text(wh),
                                onDeleted: () => c.removeWarehouse(wh),
                              ))
                          .toList(),
                    )),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add warehouse'),
                    onPressed: () => Get.bottomSheet(
                      Obx(() => WarehousePickerSheet(
                            warehouses: c.warehouseOptions.toList(),
                            isLoading: c.isLoadingWarehouses.value,
                            onSelected: c.addWarehouse,
                          )),
                      isScrollControlled: true,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── POS Upload ──────────────────────────────────────────
                LinkFieldWidget(
                  controller: _posCtrl,
                  labelText: 'POS Upload',
                  hintText: 'Select POS Upload',
                  prefixIcon: Icons.cloud_upload_outlined,
                  onTap: () => _pickLink(
                    doctype: 'POS Upload',
                    title: 'Select POS Upload',
                    onSelected: (v) async {
                      _posCtrl.text = v ?? '';
                      setState(() {});
                      await c.onPosUploadSelected(v);
                    },
                  ),
                  onClear: () async {
                    _posCtrl.clear();
                    setState(() {});
                    await c.onPosUploadSelected(null);
                  },
                ),
                const SizedBox(height: 8),

                // ── Switches ────────────────────────────────────────────
                Obx(() => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show Exploded View'),
                      value: c.showExplodedView.value,
                      onChanged: (v) => c.showExplodedView.value = v,
                    )),
                Obx(() => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Hide Out of Stock'),
                      value: c.hideOutOfStock.value,
                      onChanged: (v) => c.hideOutOfStock.value = v,
                    )),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Run Report'),
              onPressed: () {
                Navigator.of(context).pop();
                c.runReport();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(s,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      );

  Widget _hint(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(s, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      );
}

/// A searchable, debounced single-select picker backed by an async name search.
class _LinkSearchSheet extends StatefulWidget {
  final String title;
  final Future<List<String>> Function(String query) onSearch;
  final ValueChanged<String?> onSelected;
  const _LinkSearchSheet({
    required this.title,
    required this.onSearch,
    required this.onSelected,
  });

  @override
  State<_LinkSearchSheet> createState() => _LinkSearchSheetState();
}

class _LinkSearchSheetState extends State<_LinkSearchSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<String> _options = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _run('');
    _searchCtrl.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 300),
          () => _run(_searchCtrl.text));
    });
  }

  Future<void> _run(String q) async {
    setState(() => _loading = true);
    final results = await widget.onSearch(q);
    if (!mounted) return;
    setState(() {
      _options = results;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Text(widget.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _options.isEmpty
                    ? const Center(child: Text('No matches'))
                    : ListView.separated(
                        itemCount: _options.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) => ListTile(
                          title: Text(_options[i]),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            widget.onSelected(_options[i]);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_filter_sheet.dart`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_filter_sheet.dart
git commit -m "feat(manufacturing): add BOM Stock filter sheet (chips + pickers)"
```

---

## Task 9: Screen assembly

**Files:**
- Modify: `lib/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_screen.dart` (replace the Task-5 placeholder)
- Test: extend `test/widget/bom_stock_tile_test.dart`? No — add `test/widget/bom_stock_screen_test.dart`.

**Interfaces:**
- Consumes: `BomStockCustomerCodeController`, `BomStockTile`, `BomStockTotalsFooter`, `showBomStockFilterSheet`, `DocTypeListHeader`, `AsyncIconButton`, `DocCardSkeletonList`, `FilterChipWidget`, `AppShellScaffold`.

- [ ] **Step 1: Write the failing test**

Create `test/widget/bom_stock_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_screen.dart';

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put(ApiProvider());
    Get.put(BomStockCustomerCodeController());
  });
  tearDown(Get.reset);

  testWidgets('shows the empty-state prompt before any run', (tester) async {
    await tester.pumpWidget(const GetMaterialApp(home: BomStockCustomerCodeScreen()));
    await tester.pump();
    expect(find.textContaining('Run Report'), findsWidgets);
  });

  testWidgets('renders a tile for each result row', (tester) async {
    final c = Get.find<BomStockCustomerCodeController>();
    c.reportRows.assignAll([
      {'item_name': 'BELTS PU HQ', 'item_code': '2002843', 'in_stock_qty': 396, 'running_total': 396},
    ]);
    await tester.pumpWidget(const GetMaterialApp(home: BomStockCustomerCodeScreen()));
    await tester.pump();
    expect(find.text('BELTS PU HQ'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/bom_stock_screen_test.dart`
Expected: FAIL — screen is still the placeholder (no empty-state text / no tile).

- [ ] **Step 3: Replace the screen**

Replace the contents of `bom_stock_customer_code_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/app/modules/global_widgets/doc_card_skeleton.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_filter_sheet.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_tile.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_totals_footer.dart';

class BomStockCustomerCodeScreen
    extends GetView<BomStockCustomerCodeController> {
  const BomStockCustomerCodeScreen({super.key});

  List<Widget> _buildFilterChips(BuildContext context) {
    final chips = <Widget>[];
    controller.activeFilters.forEach((key, label) {
      chips.add(FilterChipWidget(
        icon: Icons.filter_alt_outlined,
        label: label,
        onDeleted: () => controller.clearFilter(key),
      ));
    });
    return chips;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AppShellScaffold(
      backgroundColor: cs.surfaceContainerLow,
      body: Obx(() {
        return Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: controller.runReport,
                color: cs.primary,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    DocTypeListHeader(
                      title: 'BOM Stock with Customer Code',
                      automaticallyImplyLeading: false,
                      activeFilters: controller.activeFilters
                          .map((k, v) => MapEntry(k, v as dynamic))
                          .obs,
                      onFilterTap: () =>
                          showBomStockFilterSheet(context, controller),
                      filterChipsBuilder: _buildFilterChips,
                      onClearAllFilters: controller.clearFilters,
                      extraActionsKey: controller.isRunning.value,
                      extraActions: [
                        AsyncIconButton(
                          busy: controller.isRunning,
                          onPressed: controller.runReport,
                          icon: const Icon(Icons.refresh),
                          tooltip: 'Run report',
                        ),
                      ],
                    ),

                    // ── POS missing-codes banner ──────────────────────────
                    if (controller.posMissingCodes.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${controller.posMissingCodes.length} Customer '
                            'Code(s) from the selected POS Upload were not '
                            'found: ${controller.posMissingCodes.join(', ')}',
                            style: TextStyle(color: cs.onErrorContainer, fontSize: 12),
                          ),
                        ),
                      ),

                    // ── Body ──────────────────────────────────────────────
                    if (controller.isRunning.value)
                      const SliverToBoxAdapter(child: DocCardSkeletonList())
                    else if (controller.reportRows.isEmpty)
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
                                  onPressed: () => showBomStockFilterSheet(
                                      context, controller),
                                  icon: const Icon(Icons.filter_alt_outlined),
                                  label: const Text('Run Report'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child:
                                  BomStockTile(row: controller.reportRows[index]),
                            ),
                            childCount: controller.reportRows.length,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            BomStockTotalsFooter(total: controller.totalRow.value),
          ],
        );
      }),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/bom_stock_screen_test.dart`
Expected: PASS. If `GetMaterialApp` + `AppShellScaffold` pulls unregistered services in test, wrap the registrations in `setUp` accordingly (the screen only reads `controller`; no service beyond `ApiProvider` is touched until a button is tapped).

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_screen.dart test/widget/bom_stock_screen_test.dart
git commit -m "feat(manufacturing): assemble BOM Stock report screen"
```

---

## Task 10: Drawer entry

**Files:**
- Modify: `lib/app/modules/global_widgets/app_nav_drawer.dart`

**Interfaces:**
- Consumes: `AppRoutes.BOM_STOCK_CUSTOMER_CODE`; existing `_DrawerItem`, `DocTypeGuard`, `_GuardedSection`.

- [ ] **Step 1: Add the drawer item**

In `lib/app/modules/global_widgets/app_nav_drawer.dart`, inside the Manufacturing `_GuardedSection` Reports block, add a third `DocTypeGuard` immediately after the Job Card Summary entry (after line 393, before the closing `],` of the `children` list):

```dart
                          DocTypeGuard(
                            doctype: 'BOM',
                            permType: 'report',
                            loading: skeleton,
                            child: _DrawerItem(
                              title: 'BOM Stock with Customer Code',
                              icon: Icons.inventory_2_outlined,
                              route: AppRoutes.BOM_STOCK_CUSTOMER_CODE,
                              currentRoute: currentRoute,
                            ),
                          ),
```

(The section's `doctypes: ['BOM', 'Job Card']` already includes `'BOM'`, so leave it unchanged.)

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/app/modules/global_widgets/app_nav_drawer.dart`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add lib/app/modules/global_widgets/app_nav_drawer.dart
git commit -m "feat(manufacturing): add BOM Stock w/ Customer Code to nav drawer"
```

---

## Task 11: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Analyze the whole project**

Run: `flutter analyze`
Expected: no new errors/warnings from the added files. Fix any that appear (e.g. swap `withValues` → `withOpacity` if the SDK predates `withValues`).

- [ ] **Step 2: Run the full test suite**

Run: `flutter test`
Expected: all tests pass, including the four new files:
- `test/unit/bom_stock_customer_code_api_test.dart`
- `test/unit/bom_stock_customer_code_controller_test.dart`
- `test/widget/bom_stock_tile_test.dart`
- `test/widget/bom_stock_totals_footer_test.dart`
- `test/widget/bom_stock_screen_test.dart`

- [ ] **Step 3: On-device smoke (manual)**

On a device with a user holding the `Manufacturing User`/`Manager` or `Sales User` role:
1. Open the drawer → Manufacturing → confirm **BOM Stock with Customer Code** appears under Reports (and is hidden for a user without BOM report permission).
2. Tap it → screen opens → tap the refresh/filter, run with no filters → rows render as cards + totals footer shows.
3. Set a Customer, add a Customer Code chip, add a Warehouse → run → results narrow; chips show in the header chip row.
4. Pick a POS Upload → codes auto-fill, report runs, and the red **missing-codes banner** lists any codes not found.
5. Confirm a shortfall row (required > running) shows the red accent + red figures.
6. Tap the refresh icon → confirm it shows a visible spinner while loading (Async-feedback).

- [ ] **Step 4: Final commit (if any analyze fixes were made)**

```bash
git add -A
git commit -m "chore(manufacturing): finalize BOM Stock w/ Customer Code report"
```

---

## Self-Review

**Spec coverage:**
- Report run via `query_report.run` with exact name → Task 1. ✓
- Card-tile UI → Task 6; totals footer → Task 7. ✓
- All six filters → Task 8 (customer, codes-as-chips, warehouses, POS Upload, two switches). ✓
- get_list sourcing, no whitelisted dependency → Tasks 1–2 (`searchLinkOptions`, `getPosUploadRefCodes`). ✓
- Customer Codes = chips + discover-from-results + POS auto-fill → Task 4 (`discoveredCodes`, `onPosUploadSelected`) + Task 8 UI. ✓
- POS missing-codes banner → Task 4 (`splitPosCodes`/`posMissingCodes`) + Task 9 banner. ✓
- Shortfall red accent → Task 3 (`isShortfall`) + Task 6. ✓
- Total row from server (`add_total_row`) → Task 3 (`extractTotalRow`) + Task 7. ✓
- Drawer under Manufacturing → Reports, gated BOM report → Task 10. ✓
- Async feedback (AsyncIconButton + re-entrancy + finally) → Task 4 + Task 9. ✓
- Tests (parsers, shortfall, POS split, tile, footer) → Tasks 1–7, 9. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code. The Task-5 placeholder screen is explicitly replaced in Task 9.

**Type consistency:** `isRunning`, `reportRows`, `totalRow`, `posMissingCodes`, `discoveredCodes`, `customerCodes`, `warehouses`, `activeFilters`, `clearFilter`, `runReport`, `onPosUploadSelected`, `buildBomStockFilters`, `runBomStockWithCustomerCode`, `parsePosUploadRefCodes`, `getPosUploadRefCodes`, `searchLinkOptions`, `getWarehouseNames`, `parseDataRows`, `extractTotalRow`, `isShortfall`, `distinctCustomerCodes`, `splitPosCodes`, `BomStockTile`, `BomStockTotalsFooter`, `showBomStockFilterSheet`, `BomStockCustomerCodeScreen`, `BomStockCustomerCodeBinding`, `AppRoutes.BOM_STOCK_CUSTOMER_CODE` — names are consistent across producing and consuming tasks.
