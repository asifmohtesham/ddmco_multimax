# POS & DN Item Rate — Flutter Report Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A mobile report screen that runs the live Desk Script Report "POS and Delivery Note Item Rate" and renders its rows as status-classified cards with server filters, client quick-filters, and summary counts.

**Architecture:** GetX module under `lib/app/modules/selling/reports/pos_dn_item_rate/` modeled on the existing `bom_stock_customer_code` module. One new `ApiProvider` method calls `frappe.desk.query_report.run`; the controller keeps parsing as pure statics; the screen is a `CustomScrollView` of bespoke tiles behind `DocTypeGuard(permType: 'report')`.

**Tech Stack:** Flutter, GetX, Dio (via existing `ApiProvider`), `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-07-03-pos-dn-item-rate-flutter-design.md`

## Global Constraints

- Report name string, exact: `POS and Delivery Note Item Rate`
- Server filter keys, exact: `pos_upload`, `from_date`, `to_date`, `customer`, `customer_group`, `item_group`, `show_mapped`, `only_coded`
- Status strings from the server, exact: `New`, `Already mapped`, `No delivery line`, `No code` — the app NEVER re-derives status
- Row fieldnames from the server: `status`, `ref_code`, `item_code`, `item_group`, `dn_item`, `upload_item`, `customer`, `customer_group`, `upload_qty`, `upload_rate`, `dn_qty`, `dn_name`, `pos_upload`, `idx`
- Contrast rules (CLAUDE.md): status text colours use the AppColors ramp — x700 light / x300 dark; tint fills `accent.withValues(alpha: 0.14)`; never `Colors.grey`/hardcoded white
- Async feedback (CLAUDE.md): busy `RxBool` cleared in `finally`, re-entrancy guard, `AsyncIconButton` for the header refresh
- From Date defaults to 30 days ago (report is ~29k rows unfiltered); first run is user-triggered like every other report screen
- All commands run from repo root `C:\Users\asifm\StudioProjects\ddmco_multimax`; test with `flutter test <path>`, lint with `flutter analyze`
- Deviation from spec (discovered during planning): the shared `ReportFilterSheet` is single-select only, so the filter sheet is bespoke (multi-select chips + link picker), copying the proven `bom_stock_filter_sheet` pattern. Task 7 records this in the spec.

---

### Task 1: ApiProvider — filter builder + report runner

**Files:**
- Modify: `lib/app/data/providers/api_provider.dart` (append after the BOM STOCK section, near line 1490)
- Test: `test/unit/pos_dn_item_rate_api_test.dart` (create)

**Interfaces:**
- Consumes: existing private `_dio`, `_dioInitialised`, `_initDio()` in `ApiProvider`.
- Produces:
  - `static Map<String, dynamic> ApiProvider.buildPosDnItemRateFilters({List<String> posUploads, String? fromDate, String? toDate, List<String> customers, List<String> customerGroups, List<String> itemGroups, bool showMapped, bool onlyCoded})`
  - `Future<Response> ApiProvider.runPosDnItemRateReport({...same params...})`

- [ ] **Step 1: Write the failing test**

Create `test/unit/pos_dn_item_rate_api_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

void main() {
  group('buildPosDnItemRateFilters', () {
    test('empty inputs produce an empty map (report defaults apply)', () {
      expect(ApiProvider.buildPosDnItemRateFilters(), isEmpty);
    });

    test('multi-select filters pass through as lists', () {
      final f = ApiProvider.buildPosDnItemRateFilters(
        posUploads: ['KA-2025-61960', 'KA-2025-61961'],
        customers: ['MULTI BRAND TRADING'],
        customerGroups: ['Commercial'],
        itemGroups: ['Straps'],
      );
      expect(f['pos_upload'], ['KA-2025-61960', 'KA-2025-61961']);
      expect(f['customer'], ['MULTI BRAND TRADING']);
      expect(f['customer_group'], ['Commercial']);
      expect(f['item_group'], ['Straps']);
    });

    test('dates pass through trimmed; blank dates are omitted', () {
      final f = ApiProvider.buildPosDnItemRateFilters(
        fromDate: '2026-06-03',
        toDate: '  ',
      );
      expect(f['from_date'], '2026-06-03');
      expect(f.containsKey('to_date'), isFalse);
    });

    test('checkboxes encode as 1 only when on', () {
      expect(ApiProvider.buildPosDnItemRateFilters()['show_mapped'], isNull);
      final f = ApiProvider.buildPosDnItemRateFilters(
          showMapped: true, onlyCoded: true);
      expect(f['show_mapped'], 1);
      expect(f['only_coded'], 1);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/pos_dn_item_rate_api_test.dart`
Expected: FAIL — `The method 'buildPosDnItemRateFilters' isn't defined`.

- [ ] **Step 3: Write the implementation**

In `lib/app/data/providers/api_provider.dart`, after `getPosUploadRefCodes` (before the `searchLinkOptions` section), add:

```dart
  // ---------------------------------------------------------------------------
  // POS AND DELIVERY NOTE ITEM RATE
  // ---------------------------------------------------------------------------

  /// Builds the `frappe.desk.query_report.run` filter map for the
  /// "POS and Delivery Note Item Rate" report. Empty filters are omitted so
  /// the report applies its own defaults. Checkboxes are encoded as `1` when on.
  static Map<String, dynamic> buildPosDnItemRateFilters({
    List<String> posUploads = const [],
    String? fromDate,
    String? toDate,
    List<String> customers = const [],
    List<String> customerGroups = const [],
    List<String> itemGroups = const [],
    bool showMapped = false,
    bool onlyCoded = false,
  }) {
    final f = <String, dynamic>{};
    if (posUploads.isNotEmpty) f['pos_upload'] = posUploads;
    if (fromDate != null && fromDate.trim().isNotEmpty) {
      f['from_date'] = fromDate.trim();
    }
    if (toDate != null && toDate.trim().isNotEmpty) {
      f['to_date'] = toDate.trim();
    }
    if (customers.isNotEmpty) f['customer'] = customers;
    if (customerGroups.isNotEmpty) f['customer_group'] = customerGroups;
    if (itemGroups.isNotEmpty) f['item_group'] = itemGroups;
    if (showMapped) f['show_mapped'] = 1;
    if (onlyCoded) f['only_coded'] = 1;
    return f;
  }

  /// Runs the "POS and Delivery Note Item Rate" scripted report.
  ///
  /// Returns the raw [Response] so the controller can parse `message.result`
  /// (one row per upload line × mapped item, each carrying a server-computed
  /// `status`). Read-only; the report never writes.
  Future<Response> runPosDnItemRateReport({
    List<String> posUploads = const [],
    String? fromDate,
    String? toDate,
    List<String> customers = const [],
    List<String> customerGroups = const [],
    List<String> itemGroups = const [],
    bool showMapped = false,
    bool onlyCoded = false,
  }) async {
    if (!_dioInitialised) await _initDio();

    final filters = buildPosDnItemRateFilters(
      posUploads: posUploads,
      fromDate: fromDate,
      toDate: toDate,
      customers: customers,
      customerGroups: customerGroups,
      itemGroups: itemGroups,
      showMapped: showMapped,
      onlyCoded: onlyCoded,
    );

    return await _dio.get(
      '/api/method/frappe.desk.query_report.run',
      queryParameters: {
        'report_name'           : 'POS and Delivery Note Item Rate',
        'filters'               : json.encode(filters),
        'ignore_prepared_report': 'true',
        'are_default_filters'   : 'false',
        '_'                     : DateTime.now().millisecondsSinceEpoch,
      },
    );
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/pos_dn_item_rate_api_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/app/data/providers/api_provider.dart test/unit/pos_dn_item_rate_api_test.dart
git commit -m "feat(api): add POS and Delivery Note Item Rate report runner"
```

---

### Task 2: Controller — pure parsers + reactive state

**Files:**
- Create: `lib/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_controller.dart`
- Test: `test/unit/pos_dn_item_rate_controller_test.dart` (create)

**Interfaces:**
- Consumes: `ApiProvider.runPosDnItemRateReport` (Task 1), `GlobalSnackbar.error` (existing, `lib/app/modules/global_widgets/global_snackbar.dart`).
- Produces (used by Tasks 3–5):
  - `class PosDnItemRateController extends GetxController`
  - statics: `parseRows(dynamic message) -> List<Map<String, dynamic>>`, `statusCounts(List<Map<String, dynamic>>) -> Map<String, int>`, `applyFilters(List<Map<String, dynamic>> rows, String status, String query) -> List<Map<String, dynamic>>`, `defaultFromDate(DateTime now) -> String`
  - status constants: `statusNew = 'New'`, `statusMapped = 'Already mapped'`, `statusNoDelivery = 'No delivery line'`, `statusNoCode = 'No code'`
  - observables: `posUploads`, `customers`, `customerGroups`, `itemGroups` (`RxList<String>`), `fromDate`, `toDate` (`RxnString`), `showMapped`, `onlyCoded` (`RxBool`), `statusFilter` (`RxString`, `'ALL'` default), `searchQuery` (`RxString`), `reportRows` (`RxList<Map<String, dynamic>>`), `isRunning`, `hasRun` (`RxBool`), `errorMessage` (`RxnString`), `activeFilters` (`RxMap<String, String>`)
  - getters: `filteredRows`, `counts`
  - methods: `runReport()`, `setStatusFilter(String)`, `setSearchQuery(String)`, `addTo(RxList<String>, String)`, `removeFrom(RxList<String>, String)`, `clearFilters()`, `clearFilter(String key)`

- [ ] **Step 1: Write the failing tests**

Create `test/unit/pos_dn_item_rate_controller_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_controller.dart';

void main() {
  // Canned query_report.run message with all four statuses (keyed rows).
  const message = {
    'columns': [
      {'fieldname': 'status', 'label': 'Status'},
      {'fieldname': 'ref_code', 'label': 'Customer Code'},
      {'fieldname': 'item_code', 'label': 'Item Code'},
    ],
    'result': [
      {'status': 'New', 'ref_code': '5067101', 'item_code': '2001272',
       'dn_item': 'STRAPS T/X', 'upload_item': 'STRAP TX', 'customer': 'MBT'},
      {'status': 'Already mapped', 'ref_code': '5067102', 'item_code': '2001273',
       'dn_item': 'BELTS PU', 'upload_item': 'BELT PU', 'customer': 'MBT'},
      {'status': 'No delivery line', 'ref_code': '5067103', 'item_code': null,
       'dn_item': null, 'upload_item': 'WALLETS COW', 'customer': null},
      {'status': 'No code', 'ref_code': null, 'item_code': null,
       'dn_item': null, 'upload_item': 'CARD CASE', 'customer': null},
    ],
  };

  group('parseRows', () {
    test('returns empty for null / wrong-shape message', () {
      expect(PosDnItemRateController.parseRows(null), isEmpty);
      expect(PosDnItemRateController.parseRows({'result': 'x'}), isEmpty);
    });

    test('parses keyed (list-of-maps) rows', () {
      final rows = PosDnItemRateController.parseRows(message);
      expect(rows.length, 4);
      expect(rows.first['ref_code'], '5067101');
    });

    test('parses positional (list-of-lists) rows by zipping column fieldnames',
        () {
      final rows = PosDnItemRateController.parseRows(const {
        'columns': [
          {'fieldname': 'status'},
          {'fieldname': 'ref_code'},
          {'fieldname': 'item_code'},
        ],
        'result': [
          ['New', '5067101', '2001272'],
        ],
      });
      expect(rows.single['status'], 'New');
      expect(rows.single['item_code'], '2001272');
    });
  });

  group('statusCounts', () {
    test('counts each status', () {
      final rows = PosDnItemRateController.parseRows(message);
      final c = PosDnItemRateController.statusCounts(rows);
      expect(c[PosDnItemRateController.statusNew], 1);
      expect(c[PosDnItemRateController.statusMapped], 1);
      expect(c[PosDnItemRateController.statusNoDelivery], 1);
      expect(c[PosDnItemRateController.statusNoCode], 1);
    });
  });

  group('applyFilters', () {
    final rows = PosDnItemRateController.parseRows(message);

    test('ALL + empty query returns everything', () {
      expect(PosDnItemRateController.applyFilters(rows, 'ALL', ''), rows);
    });

    test('status filter matches exactly', () {
      final out =
          PosDnItemRateController.applyFilters(rows, 'No delivery line', '');
      expect(out.single['ref_code'], '5067103');
    });

    test('text query is case-insensitive across code/item/customer fields', () {
      expect(
          PosDnItemRateController.applyFilters(rows, 'ALL', 'straps').length, 1);
      expect(PosDnItemRateController.applyFilters(rows, 'ALL', '5067102')
          .single['status'], 'Already mapped');
      expect(PosDnItemRateController.applyFilters(rows, 'ALL', 'mbt').length, 2);
    });

    test('status filter and query compose', () {
      expect(
        PosDnItemRateController.applyFilters(rows, 'New', 'wallets'),
        isEmpty,
      );
    });
  });

  group('defaultFromDate', () {
    test('is 30 days before now, yyyy-MM-dd zero-padded', () {
      expect(PosDnItemRateController.defaultFromDate(DateTime(2026, 7, 3)),
          '2026-06-03');
      expect(PosDnItemRateController.defaultFromDate(DateTime(2026, 1, 5)),
          '2025-12-06');
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/unit/pos_dn_item_rate_controller_test.dart`
Expected: FAIL — controller file does not exist.

- [ ] **Step 3: Write the controller**

Create `lib/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_controller.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

/// Controller for the "POS and Delivery Note Item Rate" report.
///
/// Status is computed SERVER-SIDE by the script report (including the
/// Item Customer Detail triple check, which 403s for non-System-Manager
/// users when read directly) — the app never re-derives it. Parsing lives
/// in pure static helpers so it can be unit-tested without GetX or the
/// network.
class PosDnItemRateController extends GetxController {
  final ApiProvider _api = Get.find<ApiProvider>();

  // Server-computed status strings (exact).
  static const statusNew        = 'New';
  static const statusMapped     = 'Already mapped';
  static const statusNoDelivery = 'No delivery line';
  static const statusNoCode     = 'No code';

  // ── Server-side filter state ────────────────────────────────────────────
  final posUploads     = <String>[].obs;
  final customers      = <String>[].obs;
  final customerGroups = <String>[].obs;
  final itemGroups     = <String>[].obs;
  final fromDate       = RxnString();
  final toDate         = RxnString();
  final showMapped     = false.obs;
  final onlyCoded      = false.obs;

  // ── Client-side quick filters ───────────────────────────────────────────
  final statusFilter = 'ALL'.obs;
  final searchQuery  = ''.obs;
  void setStatusFilter(String v) => statusFilter.value = v;
  void setSearchQuery(String v)  => searchQuery.value = v;

  // ── Result state ────────────────────────────────────────────────────────
  final reportRows   = <Map<String, dynamic>>[].obs;
  final isRunning    = false.obs;
  final hasRun       = false.obs;
  final errorMessage = RxnString();

  // ── Active-filter chips ─────────────────────────────────────────────────
  final activeFilters = <String, String>{}.obs;

  /// Result rows after the status chip + text search are applied.
  List<Map<String, dynamic>> get filteredRows =>
      applyFilters(reportRows, statusFilter.value, searchQuery.value);

  /// Per-status row counts over the full (unfiltered) result set.
  Map<String, int> get counts => statusCounts(reportRows);

  @override
  void onInit() {
    super.onInit();
    // Default window: the report is ~29k rows unfiltered (MAX_JOIN_SIZE
    // caveat) — never invite a full scan.
    fromDate.value = defaultFromDate(DateTime.now());
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  Future<void> runReport() async {
    if (isRunning.value) return;
    isRunning.value = true;
    _rebuildActiveFilters();
    try {
      final resp = await _api.runPosDnItemRateReport(
        posUploads:     posUploads.toList(),
        fromDate:       fromDate.value,
        toDate:         toDate.value,
        customers:      customers.toList(),
        customerGroups: customerGroups.toList(),
        itemGroups:     itemGroups.toList(),
        showMapped:     showMapped.value,
        onlyCoded:      onlyCoded.value,
      );
      if (resp.statusCode == 200) {
        reportRows.assignAll(parseRows(resp.data['message']));
        hasRun.value = true;
        errorMessage.value = null;
      }
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final body = e.response?.data?.toString() ?? '';
      errorMessage.value = code == 403
          ? 'You do not have access to this report.'
          : (code == 404 || body.contains('DoesNotExistError'))
              ? 'Report not deployed on this instance.'
              : 'Failed to run report.';
      GlobalSnackbar.error(
          title: 'Report Error', message: errorMessage.value!);
    } catch (e) {
      errorMessage.value = 'Failed to run report.';
      GlobalSnackbar.error(
          title: 'Report Error', message: 'POS & DN Item Rate: $e');
    } finally {
      isRunning.value = false;
    }
  }

  void addTo(RxList<String> list, String value) {
    final v = value.trim();
    if (v.isEmpty || list.contains(v)) return;
    list.add(v);
  }

  void removeFrom(RxList<String> list, String value) => list.remove(value);

  void clearFilters() {
    posUploads.clear();
    customers.clear();
    customerGroups.clear();
    itemGroups.clear();
    fromDate.value = defaultFromDate(DateTime.now());
    toDate.value = null;
    showMapped.value = false;
    onlyCoded.value = false;
    statusFilter.value = 'ALL';
    searchQuery.value = '';
    activeFilters.clear();
  }

  void clearFilter(String key) {
    switch (key) {
      case 'pos_upload':     posUploads.clear();
      case 'from_date':      fromDate.value = null;
      case 'to_date':        toDate.value = null;
      case 'customer':       customers.clear();
      case 'customer_group': customerGroups.clear();
      case 'item_group':     itemGroups.clear();
      case 'show_mapped':    showMapped.value = false;
      case 'only_coded':     onlyCoded.value = false;
    }
    activeFilters.remove(key);
  }

  void _rebuildActiveFilters() {
    final m = <String, String>{};
    if (posUploads.isNotEmpty) m['pos_upload'] = 'POS: ${posUploads.length}';
    if ((fromDate.value ?? '').isNotEmpty) m['from_date'] = 'From ${fromDate.value}';
    if ((toDate.value ?? '').isNotEmpty) m['to_date'] = 'To ${toDate.value}';
    if (customers.isNotEmpty) m['customer'] = 'Customers: ${customers.length}';
    if (customerGroups.isNotEmpty) {
      m['customer_group'] = 'Groups: ${customerGroups.length}';
    }
    if (itemGroups.isNotEmpty) m['item_group'] = 'Item Groups: ${itemGroups.length}';
    if (showMapped.value) m['show_mapped'] = 'Incl. mapped';
    if (onlyCoded.value) m['only_coded'] = 'Only coded';
    activeFilters.assignAll(m);
  }

  // ── Static parsers (pure) ───────────────────────────────────────────────

  /// Rows from a `query_report.run` `message`. Tolerates both row shapes:
  /// keyed maps (this report's normal output) and positional lists (zipped
  /// against `columns[].fieldname`).
  static List<Map<String, dynamic>> parseRows(dynamic message) {
    if (message is! Map) return [];
    final result = message['result'];
    if (result is! List) return [];
    final columns = message['columns'];
    final fieldnames = <String>[
      if (columns is List)
        for (final c in columns.whereType<Map>())
          (c['fieldname'] ?? '').toString(),
    ];
    final rows = <Map<String, dynamic>>[];
    for (final e in result) {
      if (e is Map) {
        rows.add(Map<String, dynamic>.from(e));
      } else if (e is List && fieldnames.isNotEmpty) {
        rows.add({
          for (var i = 0; i < e.length && i < fieldnames.length; i++)
            if (fieldnames[i].isNotEmpty) fieldnames[i]: e[i],
        });
      }
    }
    return rows;
  }

  /// Row count per server `status` value.
  static Map<String, int> statusCounts(List<Map<String, dynamic>> rows) {
    final counts = <String, int>{};
    for (final r in rows) {
      final s = (r['status'] ?? '').toString();
      if (s.isEmpty) continue;
      counts[s] = (counts[s] ?? 0) + 1;
    }
    return counts;
  }

  /// Applies the status chip ('ALL' = no-op) and a case-insensitive text
  /// query over the code / item / customer / voucher fields.
  static List<Map<String, dynamic>> applyFilters(
      List<Map<String, dynamic>> rows, String status, String query) {
    Iterable<Map<String, dynamic>> out = rows;
    if (status != 'ALL') {
      out = out.where((r) => (r['status'] ?? '').toString() == status);
    }
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      const searched = [
        'ref_code', 'item_code', 'dn_item', 'upload_item',
        'customer', 'dn_name', 'pos_upload',
      ];
      out = out.where((r) => searched.any(
          (f) => (r[f] ?? '').toString().toLowerCase().contains(q)));
    }
    return out.toList();
  }

  /// 30 days before [now], formatted yyyy-MM-dd.
  static String defaultFromDate(DateTime now) {
    final d = now.subtract(const Duration(days: 30));
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/unit/pos_dn_item_rate_controller_test.dart`
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_controller.dart test/unit/pos_dn_item_rate_controller_test.dart
git commit -m "feat(pos-dn-rate): controller with pure report parsers and filter state"
```

---

### Task 3: Binding + row tile widget

**Files:**
- Create: `lib/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_binding.dart`
- Create: `lib/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_item_rate_tile.dart`
- Test: `test/widget/pos_dn_item_rate_tile_test.dart` (create)

**Interfaces:**
- Consumes: `PosDnItemRateController` status constants (Task 2), `toNum`/`formatQty` from `lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_format.dart` (existing pure helpers), `AppColors` from `lib/app/data/constants/app_theme.dart`, `AppRoutes.DELIVERY_NOTE_FORM` / `AppRoutes.POS_UPLOAD_FORM`.
- Produces:
  - `class PosDnItemRateBinding extends Bindings`
  - `class PosDnItemRateTile extends StatelessWidget` — `PosDnItemRateTile({required Map<String, dynamic> row})`
  - `Color posDnStatusAccent(BuildContext context, String status)` (public for tests)
  - `class PosDnStatusPill extends StatelessWidget` — `PosDnStatusPill({required String status})`

- [ ] **Step 1: Write the failing widget tests**

Create `test/widget/pos_dn_item_rate_tile_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_item_rate_tile.dart';

Widget _wrap(Map<String, dynamic> row, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: Center(
            child: SizedBox(width: 380, child: PosDnItemRateTile(row: row))),
      ),
    );

const _newRow = {
  'status': 'New',
  'ref_code': '5067101',
  'item_code': '2001272',
  'item_group': 'Straps',
  'dn_item': 'STRAPS T/X PRINT 40mm',
  'upload_item': 'STRAP TX 40',
  'customer': 'MULTI BRAND TRADING',
  'customer_group': 'Commercial',
  'upload_qty': 108,
  'upload_rate': 120.0,
  'dn_qty': 108,
  'dn_name': 'MAT-DN-2025-01234',
  'pos_upload': 'KA-2025-61960',
  'idx': 7,
};

void main() {
  testWidgets('New row: shows pill, hero code+item, both item names, numbers',
      (tester) async {
    await tester.pumpWidget(_wrap(_newRow));
    expect(find.text('New'), findsOneWidget);
    expect(find.text('5067101'), findsOneWidget);
    expect(find.text('2001272'), findsOneWidget);
    expect(find.text('STRAPS T/X PRINT 40mm'), findsOneWidget);
    expect(find.text('STRAP TX 40'), findsOneWidget);
    expect(find.text('MULTI BRAND TRADING'), findsOneWidget);
    expect(find.text('MAT-DN-2025-01234'), findsOneWidget);
    expect(find.textContaining('KA-2025-61960'), findsOneWidget);
  });

  testWidgets('No delivery line row: renders without item_code or DN link',
      (tester) async {
    await tester.pumpWidget(_wrap(const {
      'status': 'No delivery line',
      'ref_code': '5067103',
      'upload_item': 'WALLETS COW',
      'upload_qty': 72,
      'pos_upload': 'KA-2025-61961',
      'idx': 3,
    }));
    expect(find.text('No delivery line'), findsOneWidget);
    expect(find.text('WALLETS COW'), findsOneWidget);
  });

  testWidgets('No code row: renders em-dash for the missing ref_code',
      (tester) async {
    await tester.pumpWidget(_wrap(const {
      'status': 'No code',
      'upload_item': 'CARD CASE FANCY',
      'upload_qty': 108,
      'pos_upload': 'KA-2025-61960',
      'idx': 1,
    }));
    expect(find.text('No code'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('Already mapped row renders its pill', (tester) async {
    await tester.pumpWidget(_wrap(const {
      'status': 'Already mapped',
      'ref_code': '5067102',
      'item_code': '2001273',
      'upload_item': 'BELT PU',
      'pos_upload': 'KA-2025-61960',
      'idx': 2,
    }));
    expect(find.text('Already mapped'), findsOneWidget);
  });

  group('posDnStatusAccent uses the theme-aware ramp', () {
    testWidgets('light: New=green700, No delivery line=orange700',
        (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        home: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ));
      expect(posDnStatusAccent(ctx, 'New'), AppColors.green700);
      expect(posDnStatusAccent(ctx, 'No delivery line'), AppColors.orange700);
    });

    testWidgets('dark: New=green300, No delivery line=orange300',
        (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ));
      expect(posDnStatusAccent(ctx, 'New'), AppColors.green300);
      expect(posDnStatusAccent(ctx, 'No delivery line'), AppColors.orange300);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widget/pos_dn_item_rate_tile_test.dart`
Expected: FAIL — tile file does not exist.

- [ ] **Step 3: Write binding + tile**

Create `lib/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_binding.dart`:

```dart
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_controller.dart';

class PosDnItemRateBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ApiProvider>(() => ApiProvider());
    Get.lazyPut<PosDnItemRateController>(() => PosDnItemRateController());
  }
}
```

Create `lib/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_item_rate_tile.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/routes/app_pages.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_bits.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_format.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_controller.dart';

/// Theme-aware accent for a server status. Doubles as pill TEXT, so it uses
/// the x700 (light) / x300 (dark) ramp — never the x500 bases.
Color posDnStatusAccent(BuildContext context, String status) {
  final cs = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  switch (status) {
    case PosDnItemRateController.statusNew:
      return dark ? AppColors.green300 : AppColors.green700;
    case PosDnItemRateController.statusNoDelivery:
      return dark ? AppColors.orange300 : AppColors.orange700;
    case PosDnItemRateController.statusMapped:
      return cs.outline;
    default: // 'No code' and anything unexpected
      return cs.onSurfaceVariant;
  }
}

/// Status pill: server status text over a 14%-alpha tint of its accent.
class PosDnStatusPill extends StatelessWidget {
  final String status;
  const PosDnStatusPill({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final accent = posDnStatusAccent(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: accent),
      ),
    );
  }
}

/// One report row: (upload line, mapped item_code) with its server status.
class PosDnItemRateTile extends StatelessWidget {
  final Map<String, dynamic> row;
  const PosDnItemRateTile({super.key, required this.row});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final status     = (row['status'] ?? '').toString();
    final refCode    = (row['ref_code'] ?? '').toString();
    final itemCode   = (row['item_code'] ?? '').toString();
    final itemGroup  = (row['item_group'] ?? '').toString();
    final dnItem     = (row['dn_item'] ?? '').toString();
    final uploadItem = (row['upload_item'] ?? '').toString();
    final customer   = (row['customer'] ?? '').toString();
    final custGroup  = (row['customer_group'] ?? '').toString();
    final dnName     = (row['dn_name'] ?? '').toString();
    final posUpload  = (row['pos_upload'] ?? '').toString();
    final idx        = (row['idx'] ?? '').toString();

    final customerLine =
        [customer, custGroup].where((s) => s.isNotEmpty).join(' · ');

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      color: cs.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero: customer code + item code + status ───────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    refCode.isEmpty ? '—' : refCode,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFamily: 'ShureTechMono',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PosDnStatusPill(status: status),
              ],
            ),
            if (itemCode.isNotEmpty || itemGroup.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                [itemCode, itemGroup].where((s) => s.isNotEmpty).join(' · '),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // ── Item names: the naming gap is the point — show both ────────
            if (dnItem.isNotEmpty) _NameRow(label: 'DN', value: dnItem),
            if (uploadItem.isNotEmpty) _NameRow(label: 'POS', value: uploadItem),
            if (customerLine.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(customerLine,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
            ],
            const SizedBox(height: 8),

            // ── Numbers ────────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                StatCell(label: 'POS Qty', value: formatQty(toNum(row['upload_qty']))),
                StatCell(label: 'POS Rate', value: formatQty(toNum(row['upload_rate']))),
                StatCell(label: 'DN Qty', value: formatQty(toNum(row['dn_qty']))),
              ],
            ),

            // ── Voucher links ──────────────────────────────────────────────
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (dnName.isNotEmpty)
                  _VoucherChip(
                    icon: Icons.local_shipping_outlined,
                    label: dnName,
                    onTap: () => Get.toNamed(AppRoutes.DELIVERY_NOTE_FORM,
                        arguments: {'name': dnName, 'mode': 'edit'}),
                  ),
                if (posUpload.isNotEmpty)
                  _VoucherChip(
                    icon: Icons.cloud_upload_outlined,
                    label: idx.isEmpty ? posUpload : '$posUpload · #$idx',
                    onTap: () => Get.toNamed(AppRoutes.POS_UPLOAD_FORM,
                        arguments: {'name': posUpload, 'mode': 'edit'}),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NameRow extends StatelessWidget {
  final String label;
  final String value;
  const _NameRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Text(label,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _VoucherChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _VoucherChip(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: cs.primary),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: cs.primary)),
          ],
        ),
      ),
    );
  }
}
```

Note: `StatCell` is imported from `bom_stock_bits.dart` (existing shared-enough widget). If `flutter analyze` flags the cross-module import as undesirable, copy `StatCell` into the tile file instead — do NOT modify the BOM module.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widget/pos_dn_item_rate_tile_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/selling/reports/pos_dn_item_rate/ test/widget/pos_dn_item_rate_tile_test.dart
git commit -m "feat(pos-dn-rate): binding, status pill, and row tile"
```

---

### Task 4: Filter sheet (bespoke multi-select)

**Files:**
- Create: `lib/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_item_rate_filter_sheet.dart`
- Test: `test/widget/pos_dn_item_rate_filter_sheet_test.dart` (create)

**Interfaces:**
- Consumes: `PosDnItemRateController` filter observables + `addTo`/`removeFrom`/`clearFilters`/`runReport` (Task 2), `ApiProvider.searchLinkOptions(doctype, {query})` (existing).
- Produces: `void showPosDnItemRateFilterSheet(BuildContext context, PosDnItemRateController c)`

- [ ] **Step 1: Write the failing widget test**

Create `test/widget/pos_dn_item_rate_filter_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_controller.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_item_rate_filter_sheet.dart';

void main() {
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => r'C:\temp\test_cookies',
    );
  });

  setUp(() {
    Get.testMode = true;
    Get.put(ApiProvider());
    Get.put(PosDnItemRateController());
  });
  tearDown(Get.reset);

  testWidgets('sheet shows all filter sections, defaults, and Run button',
      (tester) async {
    final c = Get.find<PosDnItemRateController>();
    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => FilledButton(
            onPressed: () => showPosDnItemRateFilterSheet(ctx, c),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('POS Uploads'), findsOneWidget);
    expect(find.text('Customers'), findsOneWidget);
    expect(find.text('Customer Groups'), findsOneWidget);
    expect(find.text('Item Groups'), findsOneWidget);
    expect(find.text('From Date'), findsOneWidget);
    expect(find.text('To Date'), findsOneWidget);
    expect(find.text('Show already-mapped'), findsOneWidget);
    expect(find.text('Only lines with a customer code'), findsOneWidget);
    expect(find.text('Run Report'), findsOneWidget);
    // From Date is pre-filled with the 30-day default from onInit.
    expect(c.fromDate.value, isNotNull);
    expect(find.text(c.fromDate.value!), findsOneWidget);
  });

  testWidgets('selected values render as removable chips', (tester) async {
    final c = Get.find<PosDnItemRateController>();
    c.posUploads.add('KA-2025-61960');
    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => FilledButton(
            onPressed: () => showPosDnItemRateFilterSheet(ctx, c),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('KA-2025-61960'), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.widgetWithText(InputChip, 'KA-2025-61960'),
        matching: find.byIcon(Icons.cancel)));
    await tester.pumpAndSettle();
    expect(c.posUploads, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/pos_dn_item_rate_filter_sheet_test.dart`
Expected: FAIL — sheet file does not exist.

- [ ] **Step 3: Write the filter sheet**

Create `lib/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_item_rate_filter_sheet.dart`:

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_controller.dart';

/// Opens the POS & DN Item Rate filter editor as a scrollable bottom sheet.
/// Reads/writes the controller's reactive filter state; multi-select link
/// filters render as removable chips fed by a searchable picker.
void showPosDnItemRateFilterSheet(
    BuildContext context, PosDnItemRateController c) {
  Get.bottomSheet(
    _PosDnFilterSheet(c: c),
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
  );
}

class _PosDnFilterSheet extends StatefulWidget {
  final PosDnItemRateController c;
  const _PosDnFilterSheet({required this.c});

  @override
  State<_PosDnFilterSheet> createState() => _PosDnFilterSheetState();
}

class _PosDnFilterSheetState extends State<_PosDnFilterSheet> {
  PosDnItemRateController get c => widget.c;

  Future<void> _pickLink({
    required String doctype,
    required String title,
    required ValueChanged<String> onSelected,
  }) async {
    await Get.bottomSheet(
      _LinkSearchSheet(
        title: title,
        onSearch: (q) =>
            Get.find<ApiProvider>().searchLinkOptions(doctype, query: q),
        onSelected: onSelected,
      ),
      isScrollControlled: true,
    );
  }

  Future<void> _pickDate(RxnString target) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(target.value ?? '') ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) {
      target.value = '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    }
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
                _MultiLinkSection(
                  label: 'POS Uploads',
                  values: c.posUploads,
                  onAdd: () => _pickLink(
                    doctype: 'POS Upload',
                    title: 'Select POS Upload',
                    onSelected: (v) => c.addTo(c.posUploads, v),
                  ),
                  onRemove: (v) => c.removeFrom(c.posUploads, v),
                ),
                _MultiLinkSection(
                  label: 'Customers',
                  values: c.customers,
                  onAdd: () => _pickLink(
                    doctype: 'Customer',
                    title: 'Select Customer',
                    onSelected: (v) => c.addTo(c.customers, v),
                  ),
                  onRemove: (v) => c.removeFrom(c.customers, v),
                ),
                _MultiLinkSection(
                  label: 'Customer Groups',
                  values: c.customerGroups,
                  onAdd: () => _pickLink(
                    doctype: 'Customer Group',
                    title: 'Select Customer Group',
                    onSelected: (v) => c.addTo(c.customerGroups, v),
                  ),
                  onRemove: (v) => c.removeFrom(c.customerGroups, v),
                ),
                _MultiLinkSection(
                  label: 'Item Groups',
                  values: c.itemGroups,
                  onAdd: () => _pickLink(
                    doctype: 'Item Group',
                    title: 'Select Item Group',
                    onSelected: (v) => c.addTo(c.itemGroups, v),
                  ),
                  onRemove: (v) => c.removeFrom(c.itemGroups, v),
                ),
                const SizedBox(height: 8),

                // ── Dates ───────────────────────────────────────────────
                Obx(() => _DateRow(
                      label: 'From Date',
                      value: c.fromDate.value,
                      onTap: () => _pickDate(c.fromDate),
                      onClear: () => c.fromDate.value = null,
                    )),
                const SizedBox(height: 12),
                Obx(() => _DateRow(
                      label: 'To Date',
                      value: c.toDate.value,
                      onTap: () => _pickDate(c.toDate),
                      onClear: () => c.toDate.value = null,
                    )),
                const SizedBox(height: 8),

                // ── Switches ────────────────────────────────────────────
                Obx(() => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show already-mapped'),
                      value: c.showMapped.value,
                      onChanged: (v) => c.showMapped.value = v,
                    )),
                Obx(() => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Only lines with a customer code'),
                      value: c.onlyCoded.value,
                      onChanged: (v) => c.onlyCoded.value = v,
                    )),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SafeArea(
            top: false,
            child: SizedBox(
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
          ),
        ],
      ),
    );
  }
}

/// Label + removable value chips + an "Add" affordance for one multi-select
/// link filter.
class _MultiLinkSection extends StatelessWidget {
  final String label;
  final RxList<String> values;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;
  const _MultiLinkSection({
    required this.label,
    required this.values,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Obx(() => Wrap(
                spacing: 6,
                runSpacing: 4,
                children: values
                    .map((v) => InputChip(
                          label: Text(v),
                          onDeleted: () => onRemove(v),
                        ))
                    .toList(),
              )),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: Text('Add ${label.toLowerCase()}'),
              onPressed: onAdd,
            ),
          ),
        ],
      ),
    );
  }
}

/// Read-only date field: tap to pick, clear icon to unset.
class _DateRow extends StatelessWidget {
  final String label;
  final String? value;
  final VoidCallback onTap;
  final VoidCallback onClear;
  const _DateRow({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: TextEditingController(text: value ?? ''),
      readOnly: true,
      onTap: onTap,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.calendar_today_outlined),
        suffixIcon: (value ?? '').isEmpty
            ? const Icon(Icons.edit_calendar_outlined, size: 18)
            : IconButton(
                icon: const Icon(Icons.clear, size: 18),
                tooltip: 'Clear',
                onPressed: onClear,
              ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
}

/// A searchable, debounced single-select picker backed by an async name
/// search (same pattern as the BOM Stock filter sheet).
class _LinkSearchSheet extends StatefulWidget {
  final String title;
  final Future<List<String>> Function(String query) onSearch;
  final ValueChanged<String> onSelected;
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
      _debounce = Timer(
          const Duration(milliseconds: 300), () => _run(_searchCtrl.text));
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Text(widget.title,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widget/pos_dn_item_rate_filter_sheet_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_item_rate_filter_sheet.dart test/widget/pos_dn_item_rate_filter_sheet_test.dart
git commit -m "feat(pos-dn-rate): multi-select filter sheet"
```

---

### Task 5: Screen — summary strip, status chips, body states

**Files:**
- Create: `lib/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_screen.dart`
- Test: `test/widget/pos_dn_item_rate_screen_test.dart` (create)

**Interfaces:**
- Consumes: `PosDnItemRateController` (Task 2), `PosDnItemRateTile`/`posDnStatusAccent` (Task 3), `showPosDnItemRateFilterSheet` (Task 4), existing `AppShellScaffold`, `DocTypeListHeader` (params: `title`, `automaticallyImplyLeading`, `searchQuery`, `onSearchChanged`, `onSearchClear`, `activeFilters`, `onFilterTap`, `filterChipsBuilder`, `onClearAllFilters`, `extraActionsKey`, `extraActions`), `AsyncIconButton`, `DocCardSkeletonList`, `FilterChipWidget`.
- Produces: `class PosDnItemRateScreen extends GetView<PosDnItemRateController>`

- [ ] **Step 1: Write the failing widget tests**

Create `test/widget/pos_dn_item_rate_screen_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_controller.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_screen.dart';

void main() {
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => r'C:\temp\test_cookies',
    );
  });

  setUp(() {
    Get.testMode = true;
    Get.put(ApiProvider());
    Get.put(PermissionService());
    Get.put(AuthenticationController());
    Get.put(PosDnItemRateController());
  });
  tearDown(Get.reset);

  List<Map<String, dynamic>> fourRows() => [
        {'status': 'New', 'ref_code': '5067101', 'item_code': '2001272',
         'upload_item': 'STRAP TX', 'pos_upload': 'KA-1', 'idx': 1},
        {'status': 'Already mapped', 'ref_code': '5067102',
         'item_code': '2001273', 'upload_item': 'BELT PU',
         'pos_upload': 'KA-1', 'idx': 2},
        {'status': 'No delivery line', 'ref_code': '5067103',
         'upload_item': 'WALLETS COW', 'pos_upload': 'KA-1', 'idx': 3},
        {'status': 'No code', 'upload_item': 'CARD CASE',
         'pos_upload': 'KA-1', 'idx': 4},
      ];

  testWidgets('shows the run prompt before any run', (tester) async {
    await tester.pumpWidget(const GetMaterialApp(home: PosDnItemRateScreen()));
    await tester.pump();
    expect(find.textContaining('Run Report'), findsWidgets);
  });

  testWidgets('renders summary counts and one tile per row', (tester) async {
    final c = Get.find<PosDnItemRateController>();
    c.reportRows.assignAll(fourRows());
    c.hasRun.value = true;
    await tester.pumpWidget(const GetMaterialApp(home: PosDnItemRateScreen()));
    await tester.pump();

    expect(find.text('1 new'), findsOneWidget);
    expect(find.text('1 no delivery'), findsOneWidget);
    expect(find.text('1 no code'), findsOneWidget);
    expect(find.text('STRAP TX'), findsOneWidget);
    expect(find.text('CARD CASE'), findsOneWidget);
  });

  testWidgets('status chip filters the list', (tester) async {
    final c = Get.find<PosDnItemRateController>();
    c.reportRows.assignAll(fourRows());
    c.hasRun.value = true;
    await tester.pumpWidget(const GetMaterialApp(home: PosDnItemRateScreen()));
    await tester.pump();

    // The chip label is 'No delivery line (1)' — textContaining hits the chip
    // (chips row precedes the tile list in the tree, so .first is the chip).
    await tester.tap(find.textContaining('No delivery line').first);
    await tester.pump();
    expect(find.text('WALLETS COW'), findsOneWidget);
    expect(find.text('STRAP TX'), findsNothing);
  });

  testWidgets('Already mapped chip appears only when such rows exist',
      (tester) async {
    final c = Get.find<PosDnItemRateController>();
    c.reportRows.assignAll(
        fourRows().where((r) => r['status'] != 'Already mapped').toList());
    c.hasRun.value = true;
    await tester.pumpWidget(const GetMaterialApp(home: PosDnItemRateScreen()));
    await tester.pump();
    expect(find.text('Already mapped'), findsNothing);
  });

  testWidgets('error state renders when a run failed with no rows',
      (tester) async {
    final c = Get.find<PosDnItemRateController>();
    c.errorMessage.value = 'Report not deployed on this instance.';
    await tester.pumpWidget(const GetMaterialApp(home: PosDnItemRateScreen()));
    await tester.pump();
    expect(find.text('Report not deployed on this instance.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widget/pos_dn_item_rate_screen_test.dart`
Expected: FAIL — screen file does not exist.

- [ ] **Step 3: Write the screen**

Create `lib/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/app/modules/global_widgets/doc_card_skeleton.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_controller.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_item_rate_filter_sheet.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_item_rate_tile.dart';

class PosDnItemRateScreen extends GetView<PosDnItemRateController> {
  const PosDnItemRateScreen({super.key});

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
        final rows = controller.filteredRows;
        final counts = controller.counts;
        return RefreshIndicator(
          onRefresh: controller.runReport,
          color: cs.primary,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              DocTypeListHeader(
                title: 'POS & DN Item Rate',
                automaticallyImplyLeading: false,
                searchQuery: controller.searchQuery,
                onSearchChanged: controller.setSearchQuery,
                onSearchClear: () => controller.setSearchQuery(''),
                activeFilters: controller.activeFilters
                    .map((k, v) => MapEntry(k, v as dynamic))
                    .obs,
                onFilterTap: () =>
                    showPosDnItemRateFilterSheet(context, controller),
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

              // ── Summary strip (mobile stand-in for the Desk banner) ────
              if (controller.reportRows.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: _SummaryStrip(
                      counts: counts,
                      onTapStatus: controller.setStatusFilter,
                    ),
                  ),
                ),

              // ── Status chips ───────────────────────────────────────────
              if (!controller.isRunning.value &&
                  controller.reportRows.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: _StatusChipRow(
                      counts: counts,
                      value: controller.statusFilter.value,
                      onChanged: controller.setStatusFilter,
                    ),
                  ),
                ),

              // ── Body ───────────────────────────────────────────────────
              if (controller.isRunning.value)
                const SliverToBoxAdapter(child: DocCardSkeletonList())
              else if (controller.errorMessage.value != null &&
                  controller.reportRows.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline,
                              size: 64, color: cs.error),
                          const SizedBox(height: 16),
                          Text(
                            controller.errorMessage.value!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.tonalIcon(
                            onPressed: controller.runReport,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (!controller.hasRun.value)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.receipt_long_outlined,
                              size: 64, color: cs.outlineVariant),
                          const SizedBox(height: 16),
                          Text(
                            'Runs over the last 30 days by default.\n'
                            'Adjust filters, then run the report.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.tonalIcon(
                            onPressed: () => showPosDnItemRateFilterSheet(
                                context, controller),
                            icon: const Icon(Icons.filter_alt_outlined),
                            label: const Text('Run Report'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (controller.reportRows.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'No rows for these filters',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ),
                )
              else if (rows.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'No rows match this status / search',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: PosDnItemRateTile(row: rows[index]),
                      ),
                      childCount: rows.length,
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

/// N new | N no delivery | N no code — tap a count to filter to that status.
class _SummaryStrip extends StatelessWidget {
  final Map<String, int> counts;
  final ValueChanged<String> onTapStatus;
  const _SummaryStrip({required this.counts, required this.onTapStatus});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget cell(String status, String label) {
      final n = counts[status] ?? 0;
      final accent = posDnStatusAccent(context, status);
      return Expanded(
        child: InkWell(
          onTap: () => onTapStatus(status),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$n $label',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: accent),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          cell(PosDnItemRateController.statusNew, 'new'),
          const SizedBox(width: 6),
          cell(PosDnItemRateController.statusNoDelivery, 'no delivery'),
          const SizedBox(width: 6),
          cell(PosDnItemRateController.statusNoCode, 'no code'),
        ],
      ),
    );
  }
}

/// All + one chip per status present in the data (with row counts).
class _StatusChipRow extends StatelessWidget {
  final Map<String, int> counts;
  final String value;
  final ValueChanged<String> onChanged;
  const _StatusChipRow({
    required this.counts,
    required this.value,
    required this.onChanged,
  });

  static const _order = [
    PosDnItemRateController.statusNew,
    PosDnItemRateController.statusNoDelivery,
    PosDnItemRateController.statusNoCode,
    PosDnItemRateController.statusMapped,
  ];

  @override
  Widget build(BuildContext context) {
    final present = _order.where((s) => (counts[s] ?? 0) > 0);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        ChoiceChip(
          label: const Text('All'),
          selected: value == 'ALL',
          onSelected: (_) => onChanged('ALL'),
          visualDensity: VisualDensity.compact,
        ),
        for (final s in present)
          ChoiceChip(
            label: Text('$s (${counts[s]})'),
            selected: value == s,
            // Toggle-off back to All when re-tapping the active chip.
            onSelected: (_) => onChanged(value == s ? 'ALL' : s),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widget/pos_dn_item_rate_screen_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_screen.dart test/widget/pos_dn_item_rate_screen_test.dart
git commit -m "feat(pos-dn-rate): report screen with summary strip and status chips"
```

---

### Task 6: Wiring — route, page, drawer entry, permission registry

**Files:**
- Modify: `lib/app/data/routes/app_routes.dart` (add consts after `BOM_STOCK_CUSTOMER_CODE` at lines 40 and 79)
- Modify: `lib/app/data/routes/app_pages.dart` (add `GetPage` after the BOM_STOCK_CUSTOMER_CODE page at line 223; add the two imports)
- Modify: `lib/app/modules/global_widgets/app_nav_drawer.dart` (Selling group, after the POS Upload item at line 427)
- Modify: `lib/app/data/constants/permission_entries.dart` (`kSellingPermissions` at line 45)

**Interfaces:**
- Consumes: `PosDnItemRateScreen` (Task 5), `PosDnItemRateBinding` (Task 3).
- Produces: `AppRoutes.POS_DN_ITEM_RATE = '/selling/reports/pos-dn-item-rate'`; drawer item "POS & DN Item Rate" under Selling → REPORTS; `(doctype: 'POS Upload', permType: 'report')` prefetched at login.

- [ ] **Step 1: Add the route constants**

In `lib/app/data/routes/app_routes.dart`, after the `BOM_STOCK_CUSTOMER_CODE` line in `AppRoutes` (line 40):

```dart
  static const POS_DN_ITEM_RATE       = _Paths.POS_DN_ITEM_RATE;
```

and after the `BOM_STOCK_CUSTOMER_CODE` line in `_Paths` (line 79):

```dart
  static const POS_DN_ITEM_RATE       = '/selling/reports/pos-dn-item-rate';
```

- [ ] **Step 2: Register the page**

In `lib/app/data/routes/app_pages.dart`, add imports (alphabetical with the existing module imports):

```dart
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_binding.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_screen.dart';
```

and after the `BOM_STOCK_CUSTOMER_CODE` `GetPage` (line 223):

```dart
    GetPage(
      name: AppRoutes.POS_DN_ITEM_RATE,
      page: () => const PosDnItemRateScreen(),
      binding: PosDnItemRateBinding(),
      transition: Transition.rightToLeftWithFade,
    ),
```

- [ ] **Step 3: Register the report permission**

In `lib/app/data/constants/permission_entries.dart`, extend `kSellingPermissions`:

```dart
const List<PermEntry> kSellingPermissions = [
  (doctype: 'POS Upload', permType: 'read'),
  (doctype: 'POS Upload', permType: 'report'), // POS & DN Item Rate report
];
```

- [ ] **Step 4: Add the drawer entry**

In `lib/app/modules/global_widgets/app_nav_drawer.dart`, inside the Selling `_ModuleGroup` `children`, after the POS Upload `DocTypeGuard` (after line 427):

```dart
                      // ── Selling > Reports ────────────────────────────────────
                      _GuardedSection(
                        doctypes: ['POS Upload'],
                        permType: 'report',
                        children: [
                          const _NavSubheading('Reports'),
                          DocTypeGuard(
                            doctype: 'POS Upload',
                            permType: 'report',
                            loading: skeleton,
                            child: _DrawerItem(
                              title: 'POS & DN Item Rate',
                              icon: Icons.price_change_outlined,
                              route: AppRoutes.POS_DN_ITEM_RATE,
                              currentRoute: currentRoute,
                            ),
                          ),
                        ],
                      ),
```

- [ ] **Step 5: Verify with analyze + the new module's tests**

Run: `flutter analyze`
Expected: `No issues found!` (or only pre-existing infos — zero NEW warnings/errors).

Run: `flutter test test/unit/pos_dn_item_rate_api_test.dart test/unit/pos_dn_item_rate_controller_test.dart test/widget/pos_dn_item_rate_tile_test.dart test/widget/pos_dn_item_rate_filter_sheet_test.dart test/widget/pos_dn_item_rate_screen_test.dart`
Expected: PASS (all).

- [ ] **Step 6: Commit**

```bash
git add lib/app/data/routes/ lib/app/modules/global_widgets/app_nav_drawer.dart lib/app/data/constants/permission_entries.dart
git commit -m "feat(pos-dn-rate): route, drawer entry, and report permission wiring"
```

---

### Task 7: Full-suite verification + spec correction

**Files:**
- Modify: `docs/superpowers/specs/2026-07-03-pos-dn-item-rate-flutter-design.md` (filter-sheet paragraph)

- [ ] **Step 1: Record the filter-sheet deviation in the spec**

In the spec's "Filter split" section, replace:

```
- **Server-side** (via shared `ReportFilterSheet`; sent as report filters):
```

with:

```
- **Server-side** (via a bespoke multi-select filter sheet — the shared
  `ReportFilterSheet` is single-select only, so this module copies the
  `bom_stock_filter_sheet` chips + link-picker pattern; sent as report filters):
```

and delete the now-wrong line `Multi-selects use `ReportFilterType.doctypeLink`; dates `datePicker`.`

Also in the spec's UI "Body" bullet, replace `ResultCountPill` + `ListEndFooter` with: "row counts are conveyed by the summary strip and status-chip counts; the report is non-paginated, so no end-of-list footer" — matching the established report-screen convention (`bom_stock_customer_code`, Stock Balance), which uses neither.

- [ ] **Step 2: Run the full test suite**

Run: `flutter test`
Expected: ALL tests pass (baseline was 678/678 before this feature; now higher). If any pre-existing test fails, verify it also fails on the base commit before touching it — do not "fix" unrelated tests.

- [ ] **Step 3: Run analyze**

Run: `flutter analyze`
Expected: no new issues.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-07-03-pos-dn-item-rate-flutter-design.md
git commit -m "docs(spec): record bespoke multi-select filter sheet deviation"
```

- [ ] **Step 5: Report status**

Remaining (outside this plan, requires the user): on-device smoke test against the live report on `erp.multimax.cloud` — verify counts match the Desk banner for the same filters, tap-through to DN / POS Upload forms, dark-mode pill contrast, and the non-System-Manager operator sees correct "Already mapped" statuses.
