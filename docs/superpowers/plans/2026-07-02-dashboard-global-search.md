# Dashboard Global Document Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Dashboard header Refresh button with a unified search that finds any document across all routed doctypes and opens its form on tap.

**Architecture:** A `const` registry (`kGlobalSearchTargets`) is the single source of truth for which doctypes are searchable and how each result navigates. A new `GlobalSearchService.searchAll` fans the existing per-doctype `search` out over every permitted target concurrently and returns results grouped by doctype. A focused `GlobalDocumentSearchDelegate` renders those groups and navigates on tap. Drag-to-refresh already exists and is left untouched.

**Tech Stack:** Flutter, GetX (DI + navigation), Dio (via `ApiProvider`), `SearchDelegate`.

## Global Constraints

- **No hardcoded surface/ink colours in new UI.** Use `context.scheme` (`.text`, `.textMuted`, `.textSubtle`, `.fg`, `.subtle`, `.border`) / `colorScheme`. Decorative doctype icon tints may use Material colours at low alpha (matches existing Quick-Create tiles). (CLAUDE.md contrast rules.)
- **GetX patterns:** services extend `GetxService`; resolve deps with `Get.find<T>()`.
- **Doctype queried for POS Upload is `'POS Upload'`** (the list screen's `searchDoctype: 'POS Invoice'` is unrelated; do not copy it).
- **Tests favour pure/static functions** tested directly (see `test/unit/bom_stock_customer_code_controller_test.dart`) — avoid network/Get mocking where a pure helper will do.
- Run `flutter analyze` (clean) and `flutter test` (green) before each commit.

---

## File Structure

**New**
- `lib/app/data/constants/global_search_targets.dart` — `GlobalSearchTarget` model + `kGlobalSearchTargets` registry.
- `lib/app/modules/global_widgets/global_document_search_delegate.dart` — the `SearchDelegate`.
- `test/unit/global_search_targets_test.dart`
- `test/unit/global_search_all_test.dart`
- `test/widget/global_document_search_delegate_test.dart`

**Modified**
- `lib/app/data/services/global_search_service.dart` — add `GlobalSearchGroup`, pure helpers (`filterPermittedTargets`, `buildGroups`, `runSearchAll`) and instance `searchAll`.
- `lib/app/modules/home/home_screen.dart` — Refresh `IconButton` → Search `IconButton`.

---

## Task 1: Search-target registry

**Files:**
- Create: `lib/app/data/constants/global_search_targets.dart`
- Test: `test/unit/global_search_targets_test.dart`

**Interfaces:**
- Consumes: `AppRoutes` (`lib/app/data/routes/app_routes.dart`).
- Produces:
  - `class GlobalSearchTarget { final String doctype; final String label; final IconData icon; final Color color; final String route; final Map<String, dynamic> Function(String id) argsFor; const GlobalSearchTarget({...}); }`
  - `const List<GlobalSearchTarget> kGlobalSearchTargets`

- [ ] **Step 1: Write the failing test**

Create `test/unit/global_search_targets_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/global_search_targets.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

GlobalSearchTarget _byDoctype(String d) =>
    kGlobalSearchTargets.firstWhere((t) => t.doctype == d);

void main() {
  group('kGlobalSearchTargets', () {
    test('has no duplicate doctypes', () {
      final seen = kGlobalSearchTargets.map((t) => t.doctype).toSet();
      expect(seen.length, kGlobalSearchTargets.length);
    });

    test('every target has a non-empty route and label', () {
      for (final t in kGlobalSearchTargets) {
        expect(t.route, isNotEmpty, reason: '${t.doctype} route');
        expect(t.label, isNotEmpty, reason: '${t.doctype} label');
      }
    });

    test('Item argsFor uses itemCode key', () {
      expect(_byDoctype('Item').argsFor('FG-1'), {'itemCode': 'FG-1'});
      expect(_byDoctype('Item').route, AppRoutes.ITEM_FORM);
    });

    test('view-mode doctypes pass name + mode:view', () {
      for (final d in const [
        'Delivery Note', 'Purchase Receipt', 'Stock Entry', 'Purchase Order',
        'Packing Slip', 'Material Request', 'POS Upload', 'ToDo', 'Work Order',
      ]) {
        expect(_byDoctype(d).argsFor('X'), {'name': 'X', 'mode': 'view'},
            reason: d);
      }
    });

    test('Batch opens in edit mode', () {
      expect(_byDoctype('Batch').argsFor('B-1'), {'name': 'B-1', 'mode': 'edit'});
      expect(_byDoctype('Batch').route, AppRoutes.BATCH_FORM);
    });

    test('Job Card and BOM pass name only', () {
      expect(_byDoctype('Job Card').argsFor('JC-1'), {'name': 'JC-1'});
      expect(_byDoctype('BOM').argsFor('BOM-1'), {'name': 'BOM-1'});
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/global_search_targets_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'multimax' ... global_search_targets.dart` (file does not exist).

- [ ] **Step 3: Write the registry**

Create `lib/app/data/constants/global_search_targets.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:multimax/app/data/routes/app_routes.dart';

/// One searchable doctype for the Dashboard global search.
///
/// [argsFor] returns the exact navigation arguments the target form expects —
/// traced per-doctype from each form controller / list-row tap. This is the
/// canonical "open this document" contract for the doctype.
class GlobalSearchTarget {
  /// Frappe DocType queried, e.g. 'Delivery Note'.
  final String doctype;

  /// Section header shown in the grouped results, e.g. 'Delivery Notes'.
  final String label;

  /// Decorative leading icon (reuses the Quick-Create tile visuals).
  final IconData icon;

  /// Decorative tint for [icon] (rendered at low alpha over the surface).
  final Color color;

  /// Form route to navigate to on tap.
  final String route;

  /// Builds the navigation arguments for document [id].
  final Map<String, dynamic> Function(String id) argsFor;

  const GlobalSearchTarget({
    required this.doctype,
    required this.label,
    required this.icon,
    required this.color,
    required this.route,
    required this.argsFor,
  });
}

Map<String, dynamic> _nameView(String id) => {'name': id, 'mode': 'view'};

/// Every routed doctype the Dashboard search can reach, in display order.
const List<GlobalSearchTarget> kGlobalSearchTargets = [
  GlobalSearchTarget(
    doctype: 'Item',
    label: 'Items',
    icon: Icons.inventory_2_outlined,
    color: Colors.blueGrey,
    route: AppRoutes.ITEM_FORM,
    argsFor: _itemArgs,
  ),
  GlobalSearchTarget(
    doctype: 'Delivery Note',
    label: 'Delivery Notes',
    icon: Icons.local_shipping_outlined,
    color: Colors.blue,
    route: AppRoutes.DELIVERY_NOTE_FORM,
    argsFor: _nameView,
  ),
  GlobalSearchTarget(
    doctype: 'Purchase Receipt',
    label: 'Purchase Receipts',
    icon: Icons.receipt_long_outlined,
    color: Colors.green,
    route: AppRoutes.PURCHASE_RECEIPT_FORM,
    argsFor: _nameView,
  ),
  GlobalSearchTarget(
    doctype: 'Stock Entry',
    label: 'Stock Entries',
    icon: Icons.compare_arrows_outlined,
    color: Colors.orange,
    route: AppRoutes.STOCK_ENTRY_FORM,
    argsFor: _nameView,
  ),
  GlobalSearchTarget(
    doctype: 'Packing Slip',
    label: 'Packing Slips',
    icon: Icons.assignment_return_outlined,
    color: Colors.purple,
    route: AppRoutes.PACKING_SLIP_FORM,
    argsFor: _nameView,
  ),
  GlobalSearchTarget(
    doctype: 'POS Upload',
    label: 'POS Uploads',
    icon: Icons.shopping_bag_outlined,
    color: Colors.deepPurple,
    route: AppRoutes.POS_UPLOAD_FORM,
    argsFor: _nameView,
  ),
  GlobalSearchTarget(
    doctype: 'Purchase Order',
    label: 'Purchase Orders',
    icon: Icons.shopping_cart_outlined,
    color: Colors.brown,
    route: AppRoutes.PURCHASE_ORDER_FORM,
    argsFor: _nameView,
  ),
  GlobalSearchTarget(
    doctype: 'Material Request',
    label: 'Material Requests',
    icon: Icons.request_page_outlined,
    color: Colors.pink,
    route: AppRoutes.MATERIAL_REQUEST_FORM,
    argsFor: _nameView,
  ),
  GlobalSearchTarget(
    doctype: 'Work Order',
    label: 'Work Orders',
    icon: Icons.precision_manufacturing_outlined,
    color: Colors.indigo,
    route: AppRoutes.WORK_ORDER_FORM,
    argsFor: _nameView,
  ),
  GlobalSearchTarget(
    doctype: 'Job Card',
    label: 'Job Cards',
    icon: Icons.assignment_ind_outlined,
    color: Colors.deepOrange,
    route: AppRoutes.JOB_CARD_FORM,
    argsFor: _nameOnly,
  ),
  GlobalSearchTarget(
    doctype: 'BOM',
    label: 'BOMs',
    icon: Icons.account_tree_outlined,
    color: Colors.teal,
    route: AppRoutes.BOM_FORM,
    argsFor: _nameOnly,
  ),
  GlobalSearchTarget(
    doctype: 'Batch',
    label: 'Batches',
    icon: Icons.layers_outlined,
    color: Colors.amber,
    route: AppRoutes.BATCH_FORM,
    argsFor: _batchArgs,
  ),
  GlobalSearchTarget(
    doctype: 'ToDo',
    label: 'To-Dos',
    icon: Icons.check_circle_outline,
    color: Colors.cyan,
    route: AppRoutes.TODO_FORM,
    argsFor: _nameView,
  ),
];

// Top-level functions (const list requires const-tear-off-able references).
Map<String, dynamic> _itemArgs(String id) => {'itemCode': id};
Map<String, dynamic> _nameOnly(String id) => {'name': id};
Map<String, dynamic> _batchArgs(String id) => {'name': id, 'mode': 'edit'};
```

Note: `_nameView` is referenced by multiple entries; `const` list entries may
reference top-level functions (static tear-offs are const). If the analyzer
rejects a top-level tear-off in a `const` context, change `kGlobalSearchTargets`
from `const` to `final` — the registry is still immutable in practice.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/global_search_targets_test.dart`
Expected: PASS (all 6 tests).

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/app/data/constants/global_search_targets.dart`
Expected: No issues. (If a `const`-tear-off error appears, switch the list to `final` as noted, re-run.)

- [ ] **Step 6: Commit**

```bash
git add lib/app/data/constants/global_search_targets.dart test/unit/global_search_targets_test.dart
git commit -m "feat(search): add global search target registry"
```

---

## Task 2: `searchAll` fan-out on GlobalSearchService

**Files:**
- Modify: `lib/app/data/services/global_search_service.dart`
- Test: `test/unit/global_search_all_test.dart`

**Interfaces:**
- Consumes: `GlobalSearchTarget`, `kGlobalSearchTargets` (Task 1); existing `GlobalSearchService.search(String, String)`; existing `GlobalSearchItem`; `PermissionService.hasAccess` (`lib/app/data/services/permission_service.dart`).
- Produces:
  - `class GlobalSearchGroup { final GlobalSearchTarget target; final List<GlobalSearchItem> items; const GlobalSearchGroup({required this.target, required this.items}); }`
  - `static List<GlobalSearchTarget> GlobalSearchService.filterPermittedTargets(List<GlobalSearchTarget> targets, bool? Function(String doctype) canRead)`
  - `static List<GlobalSearchGroup> GlobalSearchService.buildGroups(List<MapEntry<GlobalSearchTarget, List<GlobalSearchItem>>> entries)`
  - `static Future<List<GlobalSearchGroup>> GlobalSearchService.runSearchAll({required List<GlobalSearchTarget> targets, required bool? Function(String) canRead, required Future<List<GlobalSearchItem>> Function(String doctype) searcher, int cap})`
  - `Future<List<GlobalSearchGroup>> GlobalSearchService.searchAll(String query)`

- [ ] **Step 1: Write the failing test**

Create `test/unit/global_search_all_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/global_search_targets.dart';
import 'package:multimax/app/data/models/global_search_item.dart';
import 'package:multimax/app/data/services/global_search_service.dart';

GlobalSearchTarget _t(String d) => GlobalSearchTarget(
      doctype: d,
      label: d,
      icon: Icons.circle,
      color: Colors.grey,
      route: '/x',
      argsFor: (id) => {'name': id},
    );

GlobalSearchItem _item(String id) =>
    GlobalSearchItem(id: id, title: id, rawData: const {});

void main() {
  final targets = [_t('Item'), _t('Batch'), _t('BOM')];

  group('filterPermittedTargets', () {
    test('drops targets the user cannot read (false)', () {
      final out = GlobalSearchService.filterPermittedTargets(
        targets,
        (d) => d == 'Batch' ? false : true,
      );
      expect(out.map((t) => t.doctype), ['Item', 'BOM']);
    });

    test('keeps targets whose permission is unknown (null)', () {
      final out = GlobalSearchService.filterPermittedTargets(
        targets,
        (d) => d == 'BOM' ? null : true,
      );
      expect(out.map((t) => t.doctype), ['Item', 'Batch', 'BOM']);
    });
  });

  group('buildGroups', () {
    test('preserves order and drops empty groups', () {
      final groups = GlobalSearchService.buildGroups([
        MapEntry(_t('Item'), [_item('A')]),
        MapEntry(_t('Batch'), <GlobalSearchItem>[]),
        MapEntry(_t('BOM'), [_item('B'), _item('C')]),
      ]);
      expect(groups.map((g) => g.target.doctype), ['Item', 'BOM']);
      expect(groups.first.items.single.id, 'A');
      expect(groups.last.items.length, 2);
    });
  });

  group('runSearchAll', () {
    test('fans out only over permitted targets, caps, groups in order',
        () async {
      final calls = <String>[];
      final groups = await GlobalSearchService.runSearchAll(
        targets: targets,
        canRead: (d) => d != 'Batch',
        cap: 2,
        searcher: (doctype) async {
          calls.add(doctype);
          if (doctype == 'Item') {
            return [_item('I1'), _item('I2'), _item('I3')]; // > cap
          }
          if (doctype == 'BOM') return [_item('B1')];
          return [];
        },
      );

      expect(calls.toSet(), {'Item', 'BOM'}); // Batch never searched
      expect(groups.map((g) => g.target.doctype), ['Item', 'BOM']);
      expect(groups.first.items.length, 2); // capped
      expect(groups.last.items.single.id, 'B1');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/global_search_all_test.dart`
Expected: FAIL — `The method 'filterPermittedTargets' isn't defined for the type 'GlobalSearchService'` (and `GlobalSearchGroup` undefined).

- [ ] **Step 3: Add the model, helpers, and `searchAll`**

In `lib/app/data/services/global_search_service.dart`:

Add imports at the top (after the existing imports):

```dart
import 'package:multimax/app/data/constants/global_search_targets.dart';
import 'package:multimax/app/data/services/permission_service.dart';
```

Add this class **above** `class GlobalSearchService`:

```dart
/// A doctype's search hits, for the grouped Dashboard results.
class GlobalSearchGroup {
  final GlobalSearchTarget target;
  final List<GlobalSearchItem> items;
  const GlobalSearchGroup({required this.target, required this.items});
}
```

Add these members **inside** `class GlobalSearchService` (e.g. after the
existing `search` method):

```dart
  /// Max hits shown per doctype group.
  static const int kGroupCap = 8;

  /// Targets the user is allowed to read. A target is kept unless permission
  /// is explicitly `false`; `null` (cache not yet warm) degrades permissive.
  static List<GlobalSearchTarget> filterPermittedTargets(
    List<GlobalSearchTarget> targets,
    bool? Function(String doctype) canRead,
  ) =>
      targets.where((t) => canRead(t.doctype) != false).toList();

  /// Builds groups in [entries] order, dropping any with no items.
  static List<GlobalSearchGroup> buildGroups(
    List<MapEntry<GlobalSearchTarget, List<GlobalSearchItem>>> entries,
  ) =>
      [
        for (final e in entries)
          if (e.value.isNotEmpty)
            GlobalSearchGroup(target: e.key, items: e.value),
      ];

  /// Pure fan-out: searches every permitted target via [searcher] concurrently,
  /// caps each group at [cap], and groups the results. Injectable for testing.
  static Future<List<GlobalSearchGroup>> runSearchAll({
    required List<GlobalSearchTarget> targets,
    required bool? Function(String doctype) canRead,
    required Future<List<GlobalSearchItem>> Function(String doctype) searcher,
    int cap = kGroupCap,
  }) async {
    final permitted = filterPermittedTargets(targets, canRead);
    final entries = await Future.wait(
      permitted.map((t) async =>
          MapEntry(t, (await searcher(t.doctype)).take(cap).toList())),
    );
    return buildGroups(entries);
  }

  /// Searches [query] across every permitted [kGlobalSearchTargets] doctype and
  /// returns the hits grouped by doctype (registry order, empty groups dropped).
  Future<List<GlobalSearchGroup>> searchAll(String query) {
    final permission = Get.find<PermissionService>();
    return runSearchAll(
      targets: kGlobalSearchTargets,
      canRead: (doctype) => permission.hasAccess(doctype),
      searcher: (doctype) => search(doctype, query),
    );
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/global_search_all_test.dart`
Expected: PASS (all 4 tests).

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/app/data/services/global_search_service.dart`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add lib/app/data/services/global_search_service.dart test/unit/global_search_all_test.dart
git commit -m "feat(search): add searchAll fan-out to GlobalSearchService"
```

---

## Task 3: GlobalDocumentSearchDelegate

**Files:**
- Create: `lib/app/modules/global_widgets/global_document_search_delegate.dart`
- Test: `test/widget/global_document_search_delegate_test.dart`

**Interfaces:**
- Consumes: `GlobalSearchGroup`, `GlobalSearchService` (Task 2); `GlobalSearchTarget` (Task 1); `GlobalSearchItem`; `context.scheme` (`lib/app/data/constants/app_theme.dart`).
- Produces:
  - `class GlobalDocumentSearchDelegate extends SearchDelegate<void>` with constructor `GlobalDocumentSearchDelegate({GlobalSearchService? service})`.
  - `@visibleForTesting Widget buildResultsList(BuildContext context, List<GlobalSearchGroup> groups, void Function(GlobalSearchTarget, GlobalSearchItem) onTap)`.

- [ ] **Step 1: Write the failing test**

Create `test/widget/global_document_search_delegate_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/global_search_targets.dart';
import 'package:multimax/app/data/models/global_search_item.dart';
import 'package:multimax/app/data/services/global_search_service.dart';
import 'package:multimax/app/modules/global_widgets/global_document_search_delegate.dart';

GlobalSearchTarget _target(String d) => GlobalSearchTarget(
      doctype: d,
      label: '$d s',
      icon: Icons.circle,
      color: Colors.blue,
      route: '/x',
      argsFor: (id) => {'name': id},
    );

void main() {
  testWidgets('renders group headers, rows, and fires onTap', (tester) async {
    final delegate = GlobalDocumentSearchDelegate();
    final groups = [
      GlobalSearchGroup(target: _target('Item'), items: [
        GlobalSearchItem(id: 'FG-1', title: 'Blue Strap', rawData: const {}),
      ]),
      GlobalSearchGroup(target: _target('Delivery Note'), items: [
        GlobalSearchItem(id: 'KA-DN-1', title: 'Acme', rawData: const {}),
      ]),
    ];

    GlobalSearchTarget? tappedTarget;
    GlobalSearchItem? tappedItem;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => delegate.buildResultsList(
            context,
            groups,
            (t, i) {
              tappedTarget = t;
              tappedItem = i;
            },
          ),
        ),
      ),
    ));

    // Section headers
    expect(find.text('Item s'), findsOneWidget);
    expect(find.text('Delivery Note s'), findsOneWidget);
    // Rows
    expect(find.text('Blue Strap'), findsOneWidget);
    expect(find.text('Acme'), findsOneWidget);

    await tester.tap(find.text('Blue Strap'));
    expect(tappedTarget?.doctype, 'Item');
    expect(tappedItem?.id, 'FG-1');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/global_document_search_delegate_test.dart`
Expected: FAIL — couldn't resolve `global_document_search_delegate.dart` (file does not exist).

- [ ] **Step 3: Write the delegate**

Create `lib/app/modules/global_widgets/global_document_search_delegate.dart`:

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/constants/global_search_targets.dart';
import 'package:multimax/app/data/models/global_search_item.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/global_search_service.dart';

/// Dashboard-wide search across every routed doctype.
///
/// Fans [GlobalSearchService.searchAll] out over the permitted targets and
/// renders the hits grouped by doctype. Tapping a hit opens that document's
/// form with the arguments the form expects ([GlobalSearchTarget.argsFor]).
///
/// Deliberately separate from [DocTypeSearchDelegate] (which 11 list screens
/// depend on) so this stays single-purpose and that one stays stable.
class GlobalDocumentSearchDelegate extends SearchDelegate<void> {
  GlobalDocumentSearchDelegate({GlobalSearchService? service})
      : _service = service ?? Get.put(GlobalSearchService());

  final GlobalSearchService _service;
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  static const int _kMinChars = 3;

  // ── Debounced search (delegate instance persists across keystrokes) ──────
  Timer? _debounce;
  String? _pendingQuery;
  Future<List<GlobalSearchGroup>>? _pendingFuture;

  Future<List<GlobalSearchGroup>> _search(String q) {
    if (q == _pendingQuery && _pendingFuture != null) return _pendingFuture!;
    _pendingQuery = q;
    _debounce?.cancel();
    final completer = Completer<List<GlobalSearchGroup>>();
    _pendingFuture = completer.future;
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        completer.complete(await _service.searchAll(q));
      } catch (e) {
        if (!completer.isCompleted) completer.completeError(e);
      }
    });
    return completer.future;
  }

  @override
  String? get searchFieldLabel => 'Search any document…';

  @override
  List<Widget>? buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            tooltip: 'Clear search',
            onPressed: () {
              query = '';
              showSuggestions(context);
            },
          ),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _buildBody(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildBody(context);

  Widget _buildBody(BuildContext context) {
    if (query.trim().length < _kMinChars) {
      return _messageState(
        context,
        icon: Icons.search,
        message: 'Type at least $_kMinChars characters',
      );
    }
    return FutureBuilder<List<GlobalSearchGroup>>(
      future: _search(query.trim()),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator();
        }
        if (snapshot.hasError) {
          return _messageState(
            context,
            icon: Icons.error_outline,
            message: 'Search failed. Please try again.',
            isError: true,
          );
        }
        final groups = snapshot.data ?? const [];
        if (groups.isEmpty) {
          return _messageState(
            context,
            icon: Icons.search_off,
            message: 'No documents found matching "$query"',
          );
        }
        return buildResultsList(
          context,
          groups,
          (target, item) {
            close(context, null);
            Get.toNamed(target.route, arguments: target.argsFor(item.id));
          },
        );
      },
    );
  }

  /// Flat scroll list: a header row per group, then its result rows.
  @visibleForTesting
  Widget buildResultsList(
    BuildContext context,
    List<GlobalSearchGroup> groups,
    void Function(GlobalSearchTarget target, GlobalSearchItem item) onTap,
  ) {
    final scheme = context.scheme;
    final children = <Widget>[];
    for (final group in groups) {
      children.add(_sectionHeader(context, group.target));
      for (final item in group.items) {
        children.add(_resultTile(context, group.target, item, onTap));
      }
    }
    return Container(
      color: scheme.bg,
      child: ListView(children: children),
    );
  }

  Widget _sectionHeader(BuildContext context, GlobalSearchTarget target) {
    final scheme = context.scheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Row(
        children: [
          Icon(target.icon, size: 15, color: target.color),
          const SizedBox(width: 8),
          Text(
            target.label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: scheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultTile(
    BuildContext context,
    GlobalSearchTarget target,
    GlobalSearchItem item,
    void Function(GlobalSearchTarget, GlobalSearchItem) onTap,
  ) {
    final scheme = context.scheme;
    return ListTile(
      leading: _leadingIcon(target, item.imageUrl),
      title: Text(
        item.title,
        style: TextStyle(fontWeight: FontWeight.w600, color: scheme.text),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: item.subtitle != null
          ? Text(
              item.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.textMuted),
            )
          : null,
      trailing: Icon(Icons.chevron_right, color: scheme.textSubtle),
      onTap: () => onTap(target, item),
    );
  }

  Widget _leadingIcon(GlobalSearchTarget target, String? imageUrl) {
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final fullUrl = imageUrl.startsWith('http')
          ? imageUrl
          : '${_apiProvider.baseUrl}$imageUrl';
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          fullUrl,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _iconAvatar(target),
        ),
      );
    }
    return _iconAvatar(target);
  }

  Widget _iconAvatar(GlobalSearchTarget target) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: target.color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(target.icon, color: target.color, size: 20),
      );

  Widget _messageState(
    BuildContext context, {
    required IconData icon,
    required String message,
    bool isError = false,
  }) {
    final scheme = context.scheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: isError ? colorScheme.error : scheme.textSubtle,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isError ? colorScheme.error : scheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/global_document_search_delegate_test.dart`
Expected: PASS. (The test only exercises `buildResultsList`, so no service/network is touched.)

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/app/modules/global_widgets/global_document_search_delegate.dart`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/global_widgets/global_document_search_delegate.dart test/widget/global_document_search_delegate_test.dart
git commit -m "feat(search): add GlobalDocumentSearchDelegate"
```

---

## Task 4: Wire the Dashboard header Search button

**Files:**
- Modify: `lib/app/modules/home/home_screen.dart:51-60` (the Refresh `IconButton` in `extraActions`)

**Interfaces:**
- Consumes: `GlobalDocumentSearchDelegate` (Task 3); Flutter `showSearch`.
- Produces: nothing (leaf wiring).

- [ ] **Step 1: Add the import**

In `lib/app/modules/home/home_screen.dart`, add with the other
`global_widgets` imports (near line 5-8):

```dart
import 'package:multimax/app/modules/global_widgets/global_document_search_delegate.dart';
```

- [ ] **Step 2: Replace the Refresh button with a Search button**

Find (`home_screen.dart` ~line 51-60):

```dart
              extraActions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh Data',
                  onPressed: () {
                    controller.fetchDashboardData();
                    controller.fetchPerformanceData();
                  },
                ),
              ],
```

Replace with:

```dart
              extraActions: [
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'Search documents',
                  onPressed: () => showSearch(
                    context: context,
                    delegate: GlobalDocumentSearchDelegate(),
                  ),
                ),
              ],
```

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/app/modules/home/home_screen.dart`
Expected: No issues (no remaining reference to `Icons.refresh` here; pull-to-refresh `RefreshIndicator` is untouched).

- [ ] **Step 4: Full suite green**

Run: `flutter test`
Expected: PASS — the full suite (existing + the 3 new test files) is green.

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/home/home_screen.dart
git commit -m "feat(dashboard): replace Refresh button with global document search"
```

---

## Task 5: Manual on-device smoke

**Files:** none (verification only).

- [ ] **Step 1: Run on device**

Run: `flutter run -d <device_id>` (see `.vscode/launch.json` for configured devices).

- [ ] **Step 2: Verify search + navigation**

On the Dashboard:
- Confirm the header shows a **Search** icon (magnifier), not Refresh.
- Tap it; the search overlay opens with "Search any document…".
- With < 3 chars: "Type at least 3 characters".
- Type a known **Item** code → Items group appears → tap → the Item form opens.
- Type a known **Delivery Note** name → Delivery Notes group → tap → DN form opens (view mode).
- Type a term that matches a **Work Order** / **BOM** / **Job Card** → correct form opens.
- Pull down on the Dashboard body → the existing refresh still fires (spinner + data reload).

- [ ] **Step 3: Verify permissions (if a limited-role login is available)**

Log in as a user without, e.g., Purchase Order read access → that group never
appears in results (mirrors `DocTypeGuard`).

---

## Self-Review Notes

- **Spec coverage:** registry (Task 1), permission-filtered fan-out grouped in order (Task 2), grouped UI + form navigation (Task 3), header button swap (Task 4), drag-to-refresh left intact (verified, Task 4 Step 3 / Task 5 Step 2), manual smoke (Task 5). All spec sections map to a task.
- **POS Upload** correctly queries `'POS Upload'` (Task 1), not the list screen's `'POS Invoice'`.
- **Type consistency:** `GlobalSearchGroup{target, items}`, `filterPermittedTargets`, `buildGroups`, `runSearchAll`, `searchAll`, `buildResultsList` names/signatures match across Tasks 2–3 and both tests.
- **No hardcoded inks** in the new delegate — all via `context.scheme` / `colorScheme`; only decorative icon tints use Material colours at low alpha (matches Quick-Create tiles).
