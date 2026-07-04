# Default Warehouse + Dashboard-search Stock Balance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional Default Warehouse to Session Defaults and, after the Dashboard global-search document results, show a Stock Balance section for the query-matched items in that warehouse.

**Architecture:** `StorageService` persists the warehouse device-local (unset is a real state). `SessionDefaultsController`/screen gain a picker reusing `WarehousePickerSheet`. A pure `GlobalSearchService.stockBalanceForQuery` resolves matching item codes via the existing Item search, then queries the Stock Balance report; `GlobalDocumentSearchDelegate` renders the result as a footer section under the document groups, filled by its own `FutureBuilder` (so it appears after the results, with loading feedback).

**Tech Stack:** Flutter, GetX, Dio (via `ApiProvider`), `get_storage`, `flutter_test`.

## Global Constraints

- Never hardcode surface/ink colours — use `context.scheme.*` (light+dark safe). Loading indicators must be visible on their surface.
- Any control firing async work shows immediate, painted, visible loading feedback (async-feedback convention).
- The Default Warehouse is **optional**; Company stays required (`persist()` returns false without a company).
- Stock Balance section is **silently hidden** on fetch error — document search must never break.
- `getStockBalanceReport` already handles the single-vs-multi item-code filter across ERPNext versions; callers narrow rows client-side by item code.
- Warehouse list = all non-group, non-disabled warehouses (`WarehouseProvider.getWarehouses()`); not company-filtered (out of scope).
- Follow existing file/test patterns. `StorageService.withStorage(_FakeBox())` for storage unit tests; `buildAppTheme(AppScheme.light, Brightness.light)` + `GetMaterialApp` for widget tests needing `context.scheme`.

---

### Task 1: StorageService — Default Warehouse persistence

**Files:**
- Modify: `lib/app/data/services/storage_service.dart`
- Test: `test/unit/storage_default_warehouse_test.dart` (create)

**Interfaces:**
- Produces: `Future<void> StorageService.saveDefaultWarehouse(String? warehouse)` (null/blank removes the key); `String? StorageService.getDefaultWarehouse()` (null when unset).

- [ ] **Step 1: Write the failing test**

Create `test/unit/storage_default_warehouse_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/storage_service.dart';

/// In-memory stand-in for the GetStorage box used by StorageService.
class _FakeBox {
  final Map<String, dynamic> _m = {};
  T? read<T>(String key) => _m[key] as T?;
  Future<void> write(String key, dynamic value) async => _m[key] = value;
  bool hasData(String key) => _m.containsKey(key);
  Future<void> remove(String key) async => _m.remove(key);
}

void main() {
  test('default warehouse round-trips and clears', () async {
    final s = StorageService.withStorage(_FakeBox());
    expect(s.getDefaultWarehouse(), isNull);

    await s.saveDefaultWarehouse('Stores - M');
    expect(s.getDefaultWarehouse(), 'Stores - M');

    // null clears the key back to unset
    await s.saveDefaultWarehouse(null);
    expect(s.getDefaultWarehouse(), isNull);

    // whitespace-only also clears
    await s.saveDefaultWarehouse('Stores - M');
    await s.saveDefaultWarehouse('   ');
    expect(s.getDefaultWarehouse(), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/storage_default_warehouse_test.dart`
Expected: FAIL — `getDefaultWarehouse`/`saveDefaultWarehouse` not defined.

- [ ] **Step 3: Add the key and methods**

In `lib/app/data/services/storage_service.dart`, add the key after the `_autoSaveDelayKey` declaration (currently line 26):

```dart
  // Default Warehouse (optional; unset = no Stock Balance search shortcut)
  static const String _defaultWarehouseKey = 'session_default_warehouse';
```

Add the methods after the Session Defaults block (after `hasSessionDefaults()`, currently ends line 80):

```dart
  // --- Default Warehouse (optional) ---
  Future<void> saveDefaultWarehouse(String? warehouse) async {
    final w = warehouse?.trim() ?? '';
    if (w.isEmpty) {
      await _box.remove(_defaultWarehouseKey);
    } else {
      await _box.write(_defaultWarehouseKey, w);
    }
  }

  String? getDefaultWarehouse() {
    final w = _box.read<String>(_defaultWarehouseKey);
    return (w == null || w.isEmpty) ? null : w;
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/storage_default_warehouse_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/app/data/services/storage_service.dart test/unit/storage_default_warehouse_test.dart
git commit -m "feat(session-defaults): persist optional Default Warehouse in StorageService

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: SessionDefaultsController — warehouse state, load, persist, clear

**Files:**
- Modify: `lib/app/modules/session_defaults/session_defaults_controller.dart`
- Test: `test/unit/session_defaults_controller_test.dart` (extend)

**Interfaces:**
- Consumes: `StorageService.saveDefaultWarehouse` / `getDefaultWarehouse` (Task 1); `WarehouseProvider.getWarehouses()` → `Future<Response>` with `data['data']` a list of `{name, warehouse_name, ...}`.
- Produces: `RxnString selectedWarehouse`; `RxList<String> warehouses`; `RxBool isLoadingWarehouses`; `void clearWarehouse()`. `persist()` also writes the warehouse. Constructor gains optional `WarehouseProvider? warehouseProvider`.

- [ ] **Step 1: Write the failing test**

Append to `test/unit/session_defaults_controller_test.dart` (inside `main()`, after the existing test):

```dart
  test('persist saves and clears the default warehouse', () async {
    final storage = StorageService.withStorage(_FakeBox());
    final c = SessionDefaultsController(storage: storage);
    c.selectedCompany.value = 'Multimax';

    c.selectedWarehouse.value = 'Stores - M';
    expect(await c.persist(), isTrue);
    expect(storage.getDefaultWarehouse(), 'Stores - M');

    c.clearWarehouse();
    expect(c.selectedWarehouse.value, isNull);
    expect(await c.persist(), isTrue);
    expect(storage.getDefaultWarehouse(), isNull);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/session_defaults_controller_test.dart`
Expected: FAIL — `selectedWarehouse` / `clearWarehouse` not defined.

- [ ] **Step 3: Implement the controller changes**

In `lib/app/modules/session_defaults/session_defaults_controller.dart`:

Add the import (after the `permission_service` import):

```dart
import 'package:multimax/app/data/providers/warehouse_provider.dart';
```

Change the field declarations + constructor (currently lines 11–17) to:

```dart
  final StorageService _storage;
  ApiProvider? _api;
  WarehouseProvider? _wh;

  SessionDefaultsController({
    StorageService? storage,
    WarehouseProvider? warehouseProvider,
  })  : _storage = storage ?? Get.find<StorageService>(),
        _wh = warehouseProvider;

  ApiProvider get _apiProvider => _api ??= Get.find<ApiProvider>();
  WarehouseProvider get _warehouseProvider => _wh ??= WarehouseProvider();
```

Add these observables after `autoSaveDelay` (currently line 25):

```dart
  final warehouses = <String>[].obs;
  final selectedWarehouse = RxnString();
  final isLoadingWarehouses = false.obs;
```

In `load()`, restore the warehouse right after the `selectedCompany` line, and fetch the list at the end of the method. Replace the current `load()` body's tail so it reads:

```dart
    selectedCompany.value =
        _storage.hasSessionDefaults() ? _storage.getCompany() : null;
    selectedWarehouse.value = _storage.getDefaultWarehouse();
    try {
      final list = await _apiProvider.getList('Company');
      companies.assignAll(list.map((c) => c['name'] as String));
      if (companies.length == 1 && selectedCompany.value == null) {
        selectedCompany.value = companies.first;
      }
    } catch (_) {
      AppNotification.error('Failed to load companies');
    } finally {
      isLoading.value = false;
    }
    await _loadWarehouses();
  }

  Future<void> _loadWarehouses() async {
    isLoadingWarehouses.value = true;
    try {
      final res = await _warehouseProvider.getWarehouses();
      final data = res.data['data'] as List? ?? const [];
      warehouses.assignAll(
        data
            .map((w) => (w['name'] ?? '').toString())
            .where((s) => s.isNotEmpty),
      );
    } catch (_) {
      AppNotification.error('Failed to load warehouses');
    } finally {
      isLoadingWarehouses.value = false;
    }
  }
```

In `persist()`, add the warehouse save after `saveAutoSaveDelay` and before `return true;`:

```dart
    await _storage.saveDefaultWarehouse(selectedWarehouse.value);
    return true;
  }
```

Add `clearWarehouse()` after `persist()`:

```dart
  void clearWarehouse() => selectedWarehouse.value = null;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/session_defaults_controller_test.dart`
Expected: PASS (both tests). The persist test does not call `load()`, so `_warehouseProvider` is never constructed — no DI needed.

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/session_defaults/session_defaults_controller.dart test/unit/session_defaults_controller_test.dart
git commit -m "feat(session-defaults): controller warehouse state, load, persist, clear

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: SessionDefaultsScreen — Default Warehouse field

**Files:**
- Modify: `lib/app/modules/session_defaults/session_defaults_screen.dart`
- Test: `test/widget/session_defaults_warehouse_field_test.dart` (create)

**Interfaces:**
- Consumes: `controller.selectedWarehouse`, `controller.warehouses`, `controller.isLoadingWarehouses`, `controller.clearWarehouse()` (Task 2); `WarehousePickerSheet` (`warehouses`, `isLoading`, `onSelected`).

- [ ] **Step 1: Write the failing test**

Create `test/widget/session_defaults_warehouse_field_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/main.dart' show buildAppTheme;
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/warehouse_picker_sheet.dart';
import 'package:multimax/app/modules/session_defaults/session_defaults_controller.dart';
import 'package:multimax/app/modules/session_defaults/session_defaults_screen.dart';

class _FakeBox {
  final Map<String, dynamic> _m = {};
  T? read<T>(String key) => _m[key] as T?;
  Future<void> write(String key, dynamic value) async => _m[key] = value;
  bool hasData(String key) => _m.containsKey(key);
  Future<void> remove(String key) async => _m.remove(key);
}

/// Skips the network `load()` so the screen renders from injected state.
class _TestController extends SessionDefaultsController {
  _TestController(StorageService s) : super(storage: s);
  @override
  void onInit() {}
}

void main() {
  final theme = buildAppTheme(AppScheme.light, Brightness.light);
  tearDown(Get.reset);

  testWidgets('shows Default Warehouse field and opens the picker',
      (tester) async {
    final c = _TestController(StorageService.withStorage(_FakeBox()))
      ..isLoading.value = false
      ..isLoadingWarehouses.value = false
      ..warehouses.assignAll(['Stores - M', 'Finished Goods - M']);
    Get.put<SessionDefaultsController>(c);

    await tester.pumpWidget(GetMaterialApp(
      theme: theme,
      home: const SessionDefaultsScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Default Warehouse'), findsOneWidget);
    expect(find.text('Select warehouse (optional)'), findsOneWidget);

    // Tapping the field opens the searchable picker sheet.
    await tester.tap(find.text('Select warehouse (optional)'));
    await tester.pumpAndSettle();
    expect(find.byType(WarehousePickerSheet), findsOneWidget);

    // Selecting a warehouse reflects back into the field.
    await tester.tap(find.text('Stores - M').last);
    await tester.pumpAndSettle();
    expect(c.selectedWarehouse.value, 'Stores - M');
    expect(find.text('Stores - M'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/session_defaults_warehouse_field_test.dart`
Expected: FAIL — no `Default Warehouse` field rendered.

- [ ] **Step 3: Implement the field**

In `lib/app/modules/session_defaults/session_defaults_screen.dart`:

Add the import (after the `session_defaults_controller` import):

```dart
import 'package:multimax/app/modules/global_widgets/warehouse_picker_sheet.dart';
```

Change the SESSION `SettingsGroup` (currently lines 27–30) to include the warehouse field:

```dart
              SettingsGroup(
                label: 'Session',
                children: [
                  _companyField(context),
                  _warehouseField(context),
                ],
              ),
```

Add `_warehouseField` and `_pickWarehouse` after the existing `_pickCompany` method (end of class):

```dart
  Widget _warehouseField(BuildContext context) {
    final s = context.scheme;
    final selected = controller.selectedWarehouse.value;
    return Padding(
      padding: const EdgeInsets.all(AppSpace.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Default Warehouse',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: s.textMuted)),
          const SizedBox(height: 7),
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () => _pickWarehouse(context),
            child: Container(
              constraints: const BoxConstraints(minHeight: 46),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: s.subtle,
                border: Border.all(color: s.borderStrong),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  Icon(Icons.warehouse_outlined, size: 18, color: s.textSubtle),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      selected ?? 'Select warehouse (optional)',
                      style: TextStyle(
                          fontSize: 15,
                          color: selected == null ? s.textSubtle : s.text),
                    ),
                  ),
                  if (selected != null)
                    InkWell(
                      onTap: controller.clearWarehouse,
                      borderRadius: BorderRadius.circular(20),
                      child: Icon(Icons.close, size: 18, color: s.textSubtle),
                    )
                  else
                    Icon(Icons.expand_more, size: 18, color: s.textSubtle),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text('Used for the Dashboard search Stock Balance shortcut.',
              style: TextStyle(fontSize: 11.5, color: s.textMuted)),
        ],
      ),
    );
  }

  void _pickWarehouse(BuildContext context) {
    Get.bottomSheet(
      Obx(() => WarehousePickerSheet(
            warehouses: controller.warehouses.toList(),
            isLoading: controller.isLoadingWarehouses.value,
            onSelected: (wh) => controller.selectedWarehouse.value = wh,
          )),
      isScrollControlled: true,
    );
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/session_defaults_warehouse_field_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/session_defaults/session_defaults_screen.dart test/widget/session_defaults_warehouse_field_test.dart
git commit -m "feat(session-defaults): Default Warehouse picker field on the screen

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: GlobalSearchService — WarehouseStockLine + stockBalanceForQuery

**Files:**
- Create: `lib/app/data/models/warehouse_stock_line.dart`
- Modify: `lib/app/data/services/global_search_service.dart`
- Test: `test/unit/global_search_stock_balance_test.dart` (create)

**Interfaces:**
- Consumes: `GlobalSearchService.search('Item', query)` → `List<GlobalSearchItem>`; `ApiProvider.getStockBalanceReport(fromDate, toDate, itemCodes, warehouse)` → `({columns, rows})`.
- Produces: `class WarehouseStockLine { String itemCode; String itemName; double balanceQty; String uom; }` (const ctor, all required); `Future<List<WarehouseStockLine>> GlobalSearchService.stockBalanceForQuery(String query, String warehouse)`; `static List<WarehouseStockLine> GlobalSearchService.mapStockLines(List<Map<String,dynamic>> rows)`; `static List<String> GlobalSearchService.itemCodesFrom(List<GlobalSearchItem> items)`.

- [ ] **Step 1: Write the failing test**

Create `test/unit/global_search_stock_balance_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/global_search_item.dart';
import 'package:multimax/app/data/services/global_search_service.dart';

void main() {
  group('mapStockLines', () {
    test('maps bal_qty, name, uom; parses legacy/string; skips blank codes', () {
      final rows = <Map<String, dynamic>>[
        {'item_code': 'FG-1', 'item_name': 'Blue Strap', 'bal_qty': 12, 'stock_uom': 'Nos'},
        {'item_code': '', 'item_name': 'ghost', 'bal_qty': 5},
        {'item_code': 'FG-2', 'balance_qty': '3.5', 'stock_uom': 'Mtr'},
      ];
      final lines = GlobalSearchService.mapStockLines(rows);
      expect(lines.length, 2);
      expect(lines[0].itemCode, 'FG-1');
      expect(lines[0].itemName, 'Blue Strap');
      expect(lines[0].balanceQty, 12);
      expect(lines[0].uom, 'Nos');
      expect(lines[1].itemCode, 'FG-2');
      expect(lines[1].balanceQty, 3.5); // legacy balance_qty, string-parsed
      expect(lines[1].itemName, '');
    });

    test('empty rows -> empty lines', () {
      expect(GlobalSearchService.mapStockLines(const []), isEmpty);
    });
  });

  group('itemCodesFrom', () {
    test('drops blanks and caps at kGroupCap', () {
      final items = <GlobalSearchItem>[
        for (var i = 0; i < 12; i++)
          GlobalSearchItem(id: 'C$i', title: 'C$i', rawData: const {}),
        GlobalSearchItem(id: '', title: 'blank', rawData: const {}),
      ];
      final codes = GlobalSearchService.itemCodesFrom(items);
      expect(codes.length, GlobalSearchService.kGroupCap);
      expect(codes.contains(''), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/global_search_stock_balance_test.dart`
Expected: FAIL — `WarehouseStockLine` / `mapStockLines` / `itemCodesFrom` not defined.

- [ ] **Step 3: Create the model**

Create `lib/app/data/models/warehouse_stock_line.dart`:

```dart
/// One Stock Balance line for the Dashboard-search warehouse section:
/// an item's balance quantity in the default warehouse.
class WarehouseStockLine {
  final String itemCode;
  final String itemName;
  final double balanceQty;
  final String uom;

  const WarehouseStockLine({
    required this.itemCode,
    required this.itemName,
    required this.balanceQty,
    required this.uom,
  });
}
```

- [ ] **Step 4: Add the service methods**

In `lib/app/data/services/global_search_service.dart`, add the import (after the `global_search_item` import):

```dart
import 'package:multimax/app/data/models/warehouse_stock_line.dart';
```

Add these methods inside the `GlobalSearchService` class (e.g. after `searchAll`):

```dart
  /// Stock Balance lines for the items matching [query], scoped to [warehouse].
  /// Resolves matching item codes via the existing Item search, then queries
  /// the Stock Balance report for those items in [warehouse] for today. Returns
  /// an empty list when nothing matches. Errors propagate to the caller (the
  /// delegate hides the section on error).
  Future<List<WarehouseStockLine>> stockBalanceForQuery(
    String query,
    String warehouse,
  ) async {
    final codes = itemCodesFrom(await search('Item', query));
    if (codes.isEmpty) return const [];
    final today = _today();
    final result = await _apiProvider.getStockBalanceReport(
      fromDate: today,
      toDate: today,
      itemCodes: codes,
      warehouse: warehouse,
    );
    final allowed = codes.toSet();
    final rows = result.rows
        .where((r) => allowed.contains((r['item_code'] ?? '').toString()))
        .toList();
    return mapStockLines(rows);
  }

  /// Non-blank item codes from [items], capped at [kGroupCap]. Pure.
  static List<String> itemCodesFrom(List<GlobalSearchItem> items) => items
      .map((i) => i.id)
      .where((c) => c.isNotEmpty)
      .take(kGroupCap)
      .toList();

  /// Maps Stock Balance report rows to [WarehouseStockLine]s, reading the
  /// balance from `bal_qty` (falling back to legacy `balance_qty`). Rows with a
  /// blank item code are skipped. Pure.
  static List<WarehouseStockLine> mapStockLines(
    List<Map<String, dynamic>> rows,
  ) {
    final out = <WarehouseStockLine>[];
    for (final r in rows) {
      final code = (r['item_code'] ?? '').toString();
      if (code.isEmpty) continue;
      out.add(WarehouseStockLine(
        itemCode: code,
        itemName: (r['item_name'] ?? '').toString(),
        balanceQty: _num(r, const ['bal_qty', 'balance_qty']),
        uom: (r['stock_uom'] ?? '').toString(),
      ));
    }
    return out;
  }

  static double _num(Map<String, dynamic> row, List<String> keys) {
    for (final k in keys) {
      final v = row[k];
      if (v == null) continue;
      if (v is num) return v.toDouble();
      final p = double.tryParse(v.toString().trim());
      if (p != null) return p;
    }
    return 0.0;
  }

  static String _today() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/unit/global_search_stock_balance_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/app/data/models/warehouse_stock_line.dart lib/app/data/services/global_search_service.dart test/unit/global_search_stock_balance_test.dart
git commit -m "feat(search): stockBalanceForQuery + WarehouseStockLine mapping

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: GlobalDocumentSearchDelegate — render the Stock Balance section

**Files:**
- Modify: `lib/app/modules/global_widgets/global_document_search_delegate.dart`
- Test: `test/widget/stock_balance_search_section_test.dart` (create)

**Interfaces:**
- Consumes: `WarehouseStockLine` (Task 4); `GlobalSearchService.stockBalanceForQuery` (Task 4); `StorageService.getDefaultWarehouse()` (Task 1); `kGlobalSearchTargets` Item entry.
- Produces: top-level `@visibleForTesting Widget buildStockBalanceSection(BuildContext context, String warehouse, List<WarehouseStockLine>? lines, {void Function(WarehouseStockLine)? onTap})` — `lines == null` = loading (progress indicator), empty = message, non-empty = rows. `buildResultsList` gains an optional `{Widget? footer}` param appended as the last list child.

- [ ] **Step 1: Write the failing test**

Create `test/widget/stock_balance_search_section_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/main.dart' show buildAppTheme;
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/warehouse_stock_line.dart';
import 'package:multimax/app/modules/global_widgets/global_document_search_delegate.dart';

void main() {
  final theme = buildAppTheme(AppScheme.light, Brightness.light);
  Widget app(Widget child) =>
      GetMaterialApp(theme: theme, home: Scaffold(body: child));

  testWidgets('renders header + rows and fires onTap', (tester) async {
    WarehouseStockLine? tapped;
    await tester.pumpWidget(app(Builder(
      builder: (context) => buildStockBalanceSection(
        context,
        'Stores - M',
        const [
          WarehouseStockLine(
              itemCode: 'FG-1', itemName: 'Blue Strap', balanceQty: 12, uom: 'Nos'),
        ],
        onTap: (l) => tapped = l,
      ),
    )));

    expect(find.text('STOCK BALANCE · STORES - M'), findsOneWidget);
    expect(find.text('Blue Strap'), findsOneWidget);
    expect(find.text('12 Nos'), findsOneWidget);

    await tester.tap(find.text('Blue Strap'));
    expect(tapped?.itemCode, 'FG-1');
  });

  testWidgets('loading state shows a visible progress indicator',
      (tester) async {
    await tester.pumpWidget(app(Builder(
      builder: (context) =>
          buildStockBalanceSection(context, 'Stores - M', null),
    )));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('empty state shows a message', (tester) async {
    await tester.pumpWidget(app(Builder(
      builder: (context) =>
          buildStockBalanceSection(context, 'Stores - M', const []),
    )));
    expect(find.textContaining('No stock for matching items'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/stock_balance_search_section_test.dart`
Expected: FAIL — `buildStockBalanceSection` not defined.

- [ ] **Step 3: Add imports + the footer param + the section renderer + wiring**

In `lib/app/modules/global_widgets/global_document_search_delegate.dart`:

Add imports (after the existing `global_search_service` import):

```dart
import 'package:multimax/app/data/models/warehouse_stock_line.dart';
import 'package:multimax/app/data/services/storage_service.dart';
```

Add the default-warehouse getter and scope guard inside the class (e.g. after the `_apiProvider` getter, ~line 49):

```dart
  /// The saved Default Warehouse, or null when unset / DI not warm (tests).
  String? get _defaultWarehouse => Get.isRegistered<StorageService>()
      ? Get.find<StorageService>().getDefaultWarehouse()
      : null;

  /// The Stock Balance section only shows under the All or Item scopes.
  static bool _sbScopeAllowed(GlobalSearchTarget? scope) =>
      scope == null || scope.doctype == 'Item';

  static final GlobalSearchTarget _itemTarget =
      kGlobalSearchTargets.firstWhere((t) => t.doctype == 'Item');
```

Replace the results success branch in `_buildResultsArea` (currently the `return buildResultsList(context, groups, (target, item) {...});` block, ~lines 198–205) with:

```dart
        final wh = _defaultWarehouse;
        final footer = (wh != null && _sbScopeAllowed(scope))
            ? _StockBalanceSection(
                query: query.trim(),
                warehouse: wh,
                service: _service,
                onTapItem: (line) {
                  close(context, null);
                  Get.toNamed(
                    _itemTarget.route,
                    arguments: _itemTarget.argsFor(line.itemCode),
                  );
                },
              )
            : null;
        return buildResultsList(
          context,
          groups,
          (target, item) {
            close(context, null);
            Get.toNamed(target.route, arguments: target.argsFor(item.id));
          },
          footer: footer,
        );
```

Add the `footer` param to `buildResultsList` (currently ~lines 264–281). Change its signature and append the footer:

```dart
  @visibleForTesting
  Widget buildResultsList(
    BuildContext context,
    List<GlobalSearchGroup> groups,
    void Function(GlobalSearchTarget target, GlobalSearchItem item) onTap, {
    Widget? footer,
  }) {
    final scheme = context.scheme;
    final children = <Widget>[];
    for (final group in groups) {
      children.add(_sectionHeader(context, group.target));
      for (final item in group.items) {
        children.add(_resultTile(context, group.target, item, onTap));
      }
    }
    if (footer != null) children.add(footer);
    return Container(
      color: scheme.bg,
      child: ListView(children: children),
    );
  }
```

Add the section StatefulWidget and the top-level renderer at the end of the file (after the `GlobalDocumentSearchDelegate` class closes):

```dart
/// Async wrapper: fetches Stock Balance for [query] in [warehouse] and renders
/// it via [buildStockBalanceSection]. Its own future so it fills in AFTER the
/// document results (loading feedback), and re-fires when query/warehouse change.
class _StockBalanceSection extends StatefulWidget {
  const _StockBalanceSection({
    required this.query,
    required this.warehouse,
    required this.service,
    required this.onTapItem,
  });

  final String query;
  final String warehouse;
  final GlobalSearchService service;
  final void Function(WarehouseStockLine) onTapItem;

  @override
  State<_StockBalanceSection> createState() => _StockBalanceSectionState();
}

class _StockBalanceSectionState extends State<_StockBalanceSection> {
  late Future<List<WarehouseStockLine>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.service.stockBalanceForQuery(widget.query, widget.warehouse);
  }

  @override
  void didUpdateWidget(_StockBalanceSection old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query || old.warehouse != widget.warehouse) {
      _future =
          widget.service.stockBalanceForQuery(widget.query, widget.warehouse);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<WarehouseStockLine>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return buildStockBalanceSection(context, widget.warehouse, null);
        }
        // Hide the section entirely on error — never break document search.
        if (snap.hasError) return const SizedBox.shrink();
        return buildStockBalanceSection(
          context,
          widget.warehouse,
          snap.data ?? const [],
          onTap: widget.onTapItem,
        );
      },
    );
  }
}

String _qtyLabel(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

/// Pure renderer for the search Stock Balance section. [lines] == null renders
/// the loading state; empty renders a message; non-empty renders tappable rows.
@visibleForTesting
Widget buildStockBalanceSection(
  BuildContext context,
  String warehouse,
  List<WarehouseStockLine>? lines, {
  void Function(WarehouseStockLine)? onTap,
}) {
  final scheme = context.scheme;
  final header = Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
    child: Row(
      children: [
        const Icon(Icons.warehouse_outlined, size: 15, color: Colors.teal),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'STOCK BALANCE · $warehouse'.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: scheme.textMuted,
            ),
          ),
        ),
      ],
    ),
  );

  if (lines == null) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: LinearProgressIndicator(),
        ),
      ],
    );
  }

  if (lines.isEmpty) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            'No stock for matching items in $warehouse',
            style: TextStyle(color: scheme.textMuted),
          ),
        ),
      ],
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      header,
      for (final line in lines)
        ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.inventory_2_outlined,
                color: Colors.teal, size: 20),
          ),
          title: Text(
            line.itemName.isEmpty ? line.itemCode : line.itemName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w600, color: scheme.text),
          ),
          subtitle: Text(
            line.itemCode,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.textMuted),
          ),
          trailing: Text(
            '${_qtyLabel(line.balanceQty)} ${line.uom}'.trim(),
            style: TextStyle(fontWeight: FontWeight.w700, color: scheme.text),
          ),
          onTap: onTap == null ? null : () => onTap(line),
        ),
    ],
  );
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/widget/stock_balance_search_section_test.dart`
Expected: PASS (all three states).

- [ ] **Step 5: Run the existing delegate tests to confirm no regression**

Run: `flutter test test/widget/global_document_search_delegate_test.dart`
Expected: PASS — the `footer` param defaults to null, so the direct `buildResultsList` calls are unaffected.

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/global_widgets/global_document_search_delegate.dart test/widget/stock_balance_search_section_test.dart
git commit -m "feat(search): show Stock Balance for Default Warehouse under results

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Analyze**

Run: `flutter analyze`
Expected: no new errors/warnings from the touched files.

- [ ] **Step 2: Run the full suite**

Run: `flutter test`
Expected: all tests pass (existing + the four new/extended files). If a pre-existing unrelated failure appears, confirm it also fails on a clean checkout before treating it as a regression (see the pub-cache-corruption note in project memory).

- [ ] **Step 3: On-device smoke (manual)**

Verify on device:
- Session Defaults → Default Warehouse picker lists warehouses, is searchable, selects, clears (×), and survives save + reopen.
- Dashboard search icon → type ≥3 chars matching an item → after the document results, a "STOCK BALANCE · <warehouse>" section appears with a brief loading indicator, then the matching items' balances; tapping a row opens the Item form.
- With no Default Warehouse set → no Stock Balance section appears.

---

## Notes / deviations from the spec

- `WarehouseStockLine` omits `imageUrl`: the raw Stock Balance report rows don't carry `item_image` (image enrichment lives in `StockBalanceController`, not the provider). The section uses an icon avatar; adding thumbnails would need an extra image fetch — deliberately skipped (YAGNI).
- Unit coverage for the query→codes and rows→lines seams is via the pure `itemCodesFrom` and `mapStockLines` statics (DI-free). `stockBalanceForQuery`'s network orchestration is verified in the on-device smoke, matching the existing suite's DI-free convention.

## Versioning

New setting + new search capability → **MINOR** bump at release time per `docs/versioning_conventions.md`. Not part of this plan.
