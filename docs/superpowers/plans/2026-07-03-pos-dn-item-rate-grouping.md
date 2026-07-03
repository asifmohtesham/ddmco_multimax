# POS & DN Item Rate — Group-by Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add client-side two-level nested grouping (primary + optional secondary field) to the POS & DN Item Rate report, with collapsible headers showing value + row count + summed POS/DN qty.

**Architecture:** All grouping logic lives in a new pure module `pos_dn_grouping.dart` (no GetX, no network) — an enum of groupable fields, a `groupRows` tree builder, and a `flattenForDisplay` that turns the tree + a collapsed-key set into a flat list a single `SliverList` renders. The controller holds only Rx state and delegates to those pure helpers. Two small stateless widgets (`PosDnGroupHeader`, `PosDnGroupByBar`) take plain params/callbacks so they test without Get.

**Tech Stack:** Flutter, GetX (state/DI), existing report widgets (`PosDnItemRateTile`, `AnimatedExpandIcon`), `bom_stock_format.dart` helpers (`toNum`, `formatQty`).

## Global Constraints

- Grouping is **client-side & presentational only** — no API/provider/backend changes; server `status` stays authoritative and is never re-derived.
- Grouping runs over `controller.filteredRows` (after status chip + text search), **not** raw `reportRows`.
- Qty totals **sum quantity columns only, never rate** (report convention).
- Preserve existing conventions unchanged: `Scrollbar` (shared `ScrollController`), bottom safe-area via `MediaQuery.of(context).padding.bottom`, end-of-list totals footer, `ResultCountPill`, `RefreshIndicator`, tile taps.
- **Theme-aware colours only** — use `Theme.of(context).colorScheme` / `AppColors` ramp (x700 light / x300 dark). Never hardcode `Colors.white`, `grey.shadeX`, or status x500 bases as text/surfaces.
- Blank/missing group value renders as `—` and sorts **last**.
- Base branch: `feature/pos-dn-item-rate-grouping` (worktree off `release/play-store`). Full suite baseline: **722 passing**.

---

### Task 1: Grouping core — fields, tree, sanitize

**Files:**
- Create: `lib/app/modules/selling/reports/pos_dn_item_rate/pos_dn_grouping.dart`
- Test: `test/unit/pos_dn_grouping_test.dart`

**Interfaces:**
- Consumes: `toNum`, `formatQty` from `manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_format.dart`.
- Produces:
  - `enum PosDnGroupField { itemGroup, customer, customerGroup, posItemName, rate }` with `String get key`, `String get label`, `bool get numeric`, `String valueOf(Map<String,dynamic> row)`, and `static const String blank = '—'`.
  - `class GroupNode { final String key; final List<Map<String,dynamic>> rows; final List<GroupNode> children; int count; num posQty; num dnQty; GroupNode(this.key); }`
  - `List<GroupNode> groupRows(List<Map<String,dynamic>> rows, PosDnGroupField primary, {PosDnGroupField? secondary})`
  - `PosDnGroupField? sanitizeSecondary(PosDnGroupField? primary, PosDnGroupField? secondary)` — returns null when secondary equals primary, else secondary.

- [ ] **Step 1: Write the failing test**

```dart
// test/unit/pos_dn_grouping_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_grouping.dart';

const _rows = <Map<String, dynamic>>[
  {'item_group': 'Straps', 'customer': 'MBT', 'upload_item': 'STRAP TX',
   'upload_rate': 10, 'upload_qty': 5, 'dn_qty': 4},
  {'item_group': 'Straps', 'customer': 'ACE', 'upload_item': 'STRAP TX',
   'upload_rate': 100, 'upload_qty': 2, 'dn_qty': 2},
  {'item_group': 'Buckles', 'customer': 'MBT', 'upload_item': 'BUCKLE',
   'upload_rate': 2, 'upload_qty': 3, 'dn_qty': 0},
  {'item_group': '', 'customer': null, 'upload_item': 'X',
   'upload_rate': null, 'upload_qty': 1, 'dn_qty': 1},
];

void main() {
  group('PosDnGroupField.valueOf', () {
    test('text fields; blank/missing -> dash', () {
      expect(PosDnGroupField.itemGroup.valueOf(_rows[0]), 'Straps');
      expect(PosDnGroupField.itemGroup.valueOf(_rows[3]), '—');
      expect(PosDnGroupField.customer.valueOf(_rows[3]), '—');
    });
    test('rate formats numerically; missing -> dash', () {
      expect(PosDnGroupField.rate.valueOf(_rows[0]), '10');
      expect(PosDnGroupField.rate.valueOf(_rows[3]), '—');
      expect(PosDnGroupField.rate.numeric, isTrue);
    });
  });

  group('groupRows single level', () {
    test('buckets, counts, qty totals; blanks last', () {
      final g = groupRows(_rows, PosDnGroupField.itemGroup);
      expect(g.map((n) => n.key), ['Buckles', 'Straps', '—']);
      final straps = g.firstWhere((n) => n.key == 'Straps');
      expect(straps.count, 2);
      expect(straps.posQty, 7);
      expect(straps.dnQty, 6);
      expect(straps.children, isEmpty);
      expect(straps.rows.length, 2);
    });

    test('rate groups sort numerically not lexically', () {
      final g = groupRows(_rows, PosDnGroupField.rate);
      expect(g.map((n) => n.key), ['2', '10', '100', '—']);
    });
  });

  group('groupRows two levels', () {
    test('nests, aggregates parent recursively', () {
      final g = groupRows(_rows, PosDnGroupField.itemGroup,
          secondary: PosDnGroupField.customer);
      final straps = g.firstWhere((n) => n.key == 'Straps');
      expect(straps.rows, isEmpty);
      expect(straps.children.map((c) => c.key), ['ACE', 'MBT']);
      expect(straps.count, 2);           // sum of children counts
      expect(straps.posQty, 7);          // 2 + 5
      final mbt = straps.children.firstWhere((c) => c.key == 'MBT');
      expect(mbt.count, 1);
      expect(mbt.posQty, 5);
    });
  });

  group('sanitizeSecondary', () {
    test('drops secondary when equal to primary', () {
      expect(sanitizeSecondary(PosDnGroupField.customer, PosDnGroupField.customer),
          isNull);
      expect(sanitizeSecondary(PosDnGroupField.customer, PosDnGroupField.rate),
          PosDnGroupField.rate);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/pos_dn_grouping_test.dart`
Expected: FAIL — target of URI doesn't exist / `PosDnGroupField` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/app/modules/selling/reports/pos_dn_item_rate/pos_dn_grouping.dart
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_format.dart';

/// A field the POS & DN Item Rate report can be grouped by. Pure — no GetX.
enum PosDnGroupField {
  itemGroup('item_group', 'Item Group', false),
  customer('customer', 'Customer', false),
  customerGroup('customer_group', 'Customer Group', false),
  posItemName('upload_item', 'POS Item Name', false),
  rate('upload_rate', 'Rate', true);

  const PosDnGroupField(this.key, this.label, this.numeric);

  final String key;
  final String label;

  /// Rate is a numeric key — sorted by value, not lexically.
  final bool numeric;

  /// Placeholder for blank/missing group values; always sorts last.
  static const String blank = '—';

  /// The group key for [row] under this field (formatted, never empty).
  String valueOf(Map<String, dynamic> row) {
    if (numeric) {
      final n = toNum(row[key]);
      return n == null ? blank : formatQty(n);
    }
    final s = (row[key] ?? '').toString().trim();
    return s.isEmpty ? blank : s;
  }
}

/// One node in the group tree. Leaf nodes carry [rows] and empty [children];
/// parent nodes carry [children] and empty [rows]. [count]/[posQty]/[dnQty]
/// aggregate recursively.
class GroupNode {
  GroupNode(this.key);
  final String key;
  final List<Map<String, dynamic>> rows = [];
  final List<GroupNode> children = [];
  int count = 0;
  num posQty = 0;
  num dnQty = 0;
}

/// Groups [rows] by [primary], optionally sub-grouping by [secondary].
/// Sorted ascending by key (numeric for rate); [PosDnGroupField.blank] last.
List<GroupNode> groupRows(
  List<Map<String, dynamic>> rows,
  PosDnGroupField primary, {
  PosDnGroupField? secondary,
}) {
  final buckets = <String, List<Map<String, dynamic>>>{};
  for (final r in rows) {
    (buckets[primary.valueOf(r)] ??= []).add(r);
  }

  final nodes = <GroupNode>[];
  buckets.forEach((pk, pRows) {
    final node = GroupNode(pk);
    if (secondary == null) {
      node.rows.addAll(pRows);
      _fillLeafTotals(node);
    } else {
      final sub = <String, List<Map<String, dynamic>>>{};
      for (final r in pRows) {
        (sub[secondary.valueOf(r)] ??= []).add(r);
      }
      final children = <GroupNode>[];
      sub.forEach((sk, sRows) {
        final c = GroupNode(sk)..rows.addAll(sRows);
        _fillLeafTotals(c);
        children.add(c);
      });
      _sortNodes(children, secondary);
      node.children.addAll(children);
      _fillParentTotals(node);
    }
    nodes.add(node);
  });

  _sortNodes(nodes, primary);
  return nodes;
}

void _fillLeafTotals(GroupNode n) {
  n.count = n.rows.length;
  for (final r in n.rows) {
    n.posQty += toNum(r['upload_qty']) ?? 0;
    n.dnQty += toNum(r['dn_qty']) ?? 0;
  }
}

void _fillParentTotals(GroupNode n) {
  for (final c in n.children) {
    n.count += c.count;
    n.posQty += c.posQty;
    n.dnQty += c.dnQty;
  }
}

void _sortNodes(List<GroupNode> nodes, PosDnGroupField field) {
  nodes.sort((a, b) {
    final aBlank = a.key == PosDnGroupField.blank;
    final bBlank = b.key == PosDnGroupField.blank;
    if (aBlank != bBlank) return aBlank ? 1 : -1;
    if (aBlank && bBlank) return 0;
    if (field.numeric) {
      return (toNum(a.key) ?? 0).compareTo(toNum(b.key) ?? 0);
    }
    return a.key.toLowerCase().compareTo(b.key.toLowerCase());
  });
}

/// Returns null when [secondary] would duplicate [primary]; else [secondary].
PosDnGroupField? sanitizeSecondary(
    PosDnGroupField? primary, PosDnGroupField? secondary) {
  if (secondary == null) return null;
  return secondary == primary ? null : secondary;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/pos_dn_grouping_test.dart`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/selling/reports/pos_dn_item_rate/pos_dn_grouping.dart test/unit/pos_dn_grouping_test.dart
git commit -m "feat(pos-dn-rate): grouping core (fields, tree, sanitize)"
```

---

### Task 2: Flatten tree for display

**Files:**
- Modify: `lib/app/modules/selling/reports/pos_dn_item_rate/pos_dn_grouping.dart`
- Test: `test/unit/pos_dn_grouping_test.dart` (add a group)

**Interfaces:**
- Consumes: `GroupNode`, `groupRows` (Task 1).
- Produces:
  - `String primaryCollapseKey(String primaryKey)` → `"P␟<primaryKey>"`
  - `String secondaryCollapseKey(String primaryKey, String secondaryKey)` → `"S␟<primaryKey>␟<secondaryKey>"`
  - `enum DisplayKind { primaryHeader, secondaryHeader, row }`
  - `class DisplayItem { final DisplayKind kind; final GroupNode? node; final Map<String,dynamic>? row; final String? collapseKey; }` with factories `DisplayItem.primaryHeader(GroupNode)`, `DisplayItem.secondaryHeader(GroupNode parent, GroupNode child)`, `DisplayItem.row(Map<String,dynamic>)`.
  - `List<DisplayItem> flattenForDisplay(List<GroupNode> nodes, Set<String> collapsed)`
  - `Set<String> collapseKeysFor(List<GroupNode> nodes)` — every header key in the tree (for collapse-all).

- [ ] **Step 1: Write the failing test** (append to `test/unit/pos_dn_grouping_test.dart`, inside `main()`)

```dart
  group('flattenForDisplay', () {
    test('single level: header then its rows; collapse hides rows', () {
      final tree = groupRows(_rows, PosDnGroupField.itemGroup);
      final open = flattenForDisplay(tree, <String>{});
      // Buckles(header,1 row), Straps(header,2 rows), —(header,1 row)
      expect(open.where((d) => d.kind == DisplayKind.primaryHeader).length, 3);
      expect(open.where((d) => d.kind == DisplayKind.row).length, 4);

      final collapsed = flattenForDisplay(
          tree, {primaryCollapseKey('Straps')});
      expect(collapsed.where((d) => d.kind == DisplayKind.row).length, 2);
    });

    test('two levels: primary header, secondary headers, rows; nesting order',
        () {
      final tree = groupRows(_rows, PosDnGroupField.itemGroup,
          secondary: PosDnGroupField.customer);
      final items = flattenForDisplay(tree, <String>{});
      final straps = items.indexWhere((d) =>
          d.kind == DisplayKind.primaryHeader && d.node!.key == 'Straps');
      expect(items[straps + 1].kind, DisplayKind.secondaryHeader); // ACE
      expect(items[straps + 2].kind, DisplayKind.row);

      // Collapsing the Straps primary hides its secondary headers too.
      final c = flattenForDisplay(tree, {primaryCollapseKey('Straps')});
      expect(
        c.any((d) =>
            d.kind == DisplayKind.secondaryHeader && d.node!.key == 'ACE'),
        isFalse,
      );
    });

    test('collapseKeysFor returns all header keys', () {
      final tree = groupRows(_rows, PosDnGroupField.itemGroup,
          secondary: PosDnGroupField.customer);
      final keys = collapseKeysFor(tree);
      expect(keys.contains(primaryCollapseKey('Straps')), isTrue);
      expect(keys.contains(secondaryCollapseKey('Straps', 'ACE')), isTrue);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/pos_dn_grouping_test.dart`
Expected: FAIL — `flattenForDisplay` / `DisplayItem` undefined.

- [ ] **Step 3: Write minimal implementation** (append to `pos_dn_grouping.dart`)

```dart
// ── Flattening for a single SliverList ──────────────────────────────────────

const String _sep = '␟'; // Unit Separator glyph — never in real values.

String primaryCollapseKey(String primaryKey) => 'P$_sep$primaryKey';
String secondaryCollapseKey(String primaryKey, String secondaryKey) =>
    'S$_sep$primaryKey$_sep$secondaryKey';

enum DisplayKind { primaryHeader, secondaryHeader, row }

/// A flattened render item: a primary/secondary header (carrying its
/// [GroupNode] and its [collapseKey]) or a leaf [row].
class DisplayItem {
  const DisplayItem._(this.kind, {this.node, this.row, this.collapseKey});

  final DisplayKind kind;
  final GroupNode? node;
  final Map<String, dynamic>? row;
  final String? collapseKey;

  factory DisplayItem.primaryHeader(GroupNode n) => DisplayItem._(
        DisplayKind.primaryHeader,
        node: n,
        collapseKey: primaryCollapseKey(n.key),
      );

  factory DisplayItem.secondaryHeader(GroupNode parent, GroupNode child) =>
      DisplayItem._(
        DisplayKind.secondaryHeader,
        node: child,
        collapseKey: secondaryCollapseKey(parent.key, child.key),
      );

  factory DisplayItem.row(Map<String, dynamic> r) =>
      DisplayItem._(DisplayKind.row, row: r);
}

/// Flattens [nodes] into render order, skipping the children of any header
/// whose collapse key is in [collapsed].
List<DisplayItem> flattenForDisplay(
    List<GroupNode> nodes, Set<String> collapsed) {
  final out = <DisplayItem>[];
  for (final p in nodes) {
    out.add(DisplayItem.primaryHeader(p));
    if (collapsed.contains(primaryCollapseKey(p.key))) continue;
    if (p.children.isEmpty) {
      for (final r in p.rows) {
        out.add(DisplayItem.row(r));
      }
    } else {
      for (final c in p.children) {
        out.add(DisplayItem.secondaryHeader(p, c));
        if (collapsed.contains(secondaryCollapseKey(p.key, c.key))) continue;
        for (final r in c.rows) {
          out.add(DisplayItem.row(r));
        }
      }
    }
  }
  return out;
}

/// Every header collapse key in [nodes] (both levels) — for collapse-all.
Set<String> collapseKeysFor(List<GroupNode> nodes) {
  final keys = <String>{};
  for (final p in nodes) {
    keys.add(primaryCollapseKey(p.key));
    for (final c in p.children) {
      keys.add(secondaryCollapseKey(p.key, c.key));
    }
  }
  return keys;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/pos_dn_grouping_test.dart`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/selling/reports/pos_dn_item_rate/pos_dn_grouping.dart test/unit/pos_dn_grouping_test.dart
git commit -m "feat(pos-dn-rate): flatten group tree for display"
```

---

### Task 3: Controller wiring

**Files:**
- Modify: `lib/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_controller.dart`
- Test: `test/unit/pos_dn_item_rate_group_controller_test.dart` (create)

**Interfaces:**
- Consumes: `groupRows`, `flattenForDisplay`, `collapseKeysFor`, `sanitizeSecondary`, `primaryCollapseKey`, `PosDnGroupField`, `DisplayItem` (Tasks 1–2); existing `filteredRows`.
- Produces (on `PosDnItemRateController`):
  - `final Rxn<PosDnGroupField> primaryGroup`, `final Rxn<PosDnGroupField> secondaryGroup`, `final RxSet<String> collapsedGroups`
  - `bool get isGrouped`
  - `List<DisplayItem> get displayItems`
  - `void setPrimaryGroup(PosDnGroupField?)`, `void setSecondaryGroup(PosDnGroupField?)`
  - `void toggleGroupCollapsed(String key)`, `void expandAllGroups()`, `void collapseAllGroups()`
  - `clearFilters()` also resets grouping.

- [ ] **Step 1: Write the failing test**

```dart
// test/unit/pos_dn_item_rate_group_controller_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_grouping.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_controller.dart';

void main() {
  late PosDnItemRateController c;

  setUp(() {
    Get.reset();
    Get.put(ApiProvider());
    c = PosDnItemRateController();
    c.reportRows.assignAll(const [
      {'status': 'New', 'item_group': 'Straps', 'customer': 'MBT',
       'upload_qty': 5, 'dn_qty': 4},
      {'status': 'New', 'item_group': 'Straps', 'customer': 'ACE',
       'upload_qty': 2, 'dn_qty': 2},
      {'status': 'New', 'item_group': 'Buckles', 'customer': 'MBT',
       'upload_qty': 3, 'dn_qty': 0},
    ]);
  });

  tearDown(Get.reset);

  test('not grouped by default -> empty displayItems', () {
    expect(c.isGrouped, isFalse);
    expect(c.displayItems, isEmpty);
  });

  test('setPrimaryGroup builds display items over filteredRows', () {
    c.setPrimaryGroup(PosDnGroupField.itemGroup);
    expect(c.isGrouped, isTrue);
    expect(c.displayItems.where((d) => d.kind == DisplayKind.primaryHeader)
        .length, 2); // Straps, Buckles
    expect(c.displayItems.where((d) => d.kind == DisplayKind.row).length, 3);
  });

  test('secondary equal to primary is dropped', () {
    c.setPrimaryGroup(PosDnGroupField.customer);
    c.setSecondaryGroup(PosDnGroupField.customer);
    expect(c.secondaryGroup.value, isNull);
  });

  test('changing primary clears collapsed set', () {
    c.setPrimaryGroup(PosDnGroupField.itemGroup);
    c.toggleGroupCollapsed(primaryCollapseKey('Straps'));
    expect(c.collapsedGroups, isNotEmpty);
    c.setPrimaryGroup(PosDnGroupField.customer);
    expect(c.collapsedGroups, isEmpty);
  });

  test('collapseAll then expandAll', () {
    c.setPrimaryGroup(PosDnGroupField.itemGroup);
    c.collapseAllGroups();
    expect(c.displayItems.where((d) => d.kind == DisplayKind.row), isEmpty);
    c.expandAllGroups();
    expect(c.displayItems.where((d) => d.kind == DisplayKind.row).length, 3);
  });

  test('clearFilters resets grouping', () {
    c.setPrimaryGroup(PosDnGroupField.itemGroup);
    c.clearFilters();
    expect(c.primaryGroup.value, isNull);
    expect(c.isGrouped, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/pos_dn_item_rate_group_controller_test.dart`
Expected: FAIL — `primaryGroup` / `setPrimaryGroup` undefined on controller.

- [ ] **Step 3: Write minimal implementation**

Add the import near the top of `pos_dn_item_rate_controller.dart` (after the existing imports):

```dart
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_grouping.dart';
```

Add the group state fields in the "Client-side quick filters" section (after `searchQuery`):

```dart
  // ── Grouping (two-level, client-side) ───────────────────────────────────
  final primaryGroup   = Rxn<PosDnGroupField>();
  final secondaryGroup = Rxn<PosDnGroupField>();
  final collapsedGroups = <String>{}.obs;

  bool get isGrouped => primaryGroup.value != null;

  /// Ordered render items for the current grouping; empty when not grouped.
  List<DisplayItem> get displayItems {
    if (!isGrouped) return const [];
    final tree = groupRows(filteredRows, primaryGroup.value!,
        secondary: secondaryGroup.value);
    return flattenForDisplay(tree, collapsedGroups);
  }

  void setPrimaryGroup(PosDnGroupField? f) {
    primaryGroup.value = f;
    secondaryGroup.value = sanitizeSecondary(f, secondaryGroup.value);
    collapsedGroups.clear();
  }

  void setSecondaryGroup(PosDnGroupField? f) {
    secondaryGroup.value = sanitizeSecondary(primaryGroup.value, f);
    collapsedGroups.clear();
  }

  void toggleGroupCollapsed(String key) {
    if (collapsedGroups.contains(key)) {
      collapsedGroups.remove(key);
    } else {
      collapsedGroups.add(key);
    }
  }

  void expandAllGroups() => collapsedGroups.clear();

  void collapseAllGroups() {
    if (!isGrouped) return;
    final tree = groupRows(filteredRows, primaryGroup.value!,
        secondary: secondaryGroup.value);
    collapsedGroups.assignAll(collapseKeysFor(tree));
  }
```

In `clearFilters()`, add these three lines before `activeFilters.clear();`:

```dart
    primaryGroup.value = null;
    secondaryGroup.value = null;
    collapsedGroups.clear();
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/pos_dn_item_rate_group_controller_test.dart`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_controller.dart test/unit/pos_dn_item_rate_group_controller_test.dart
git commit -m "feat(pos-dn-rate): controller group state + display items"
```

---

### Task 4: `PosDnGroupHeader` widget

**Files:**
- Create: `lib/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_group_header.dart`
- Test: `test/widget/pos_dn_group_header_test.dart`

**Interfaces:**
- Consumes: `GroupNode` (Task 1), `AnimatedExpandIcon`, `formatQty`.
- Produces: `class PosDnGroupHeader extends StatelessWidget` with named params `{required GroupNode node, required bool isSecondary, required bool isExpanded, required VoidCallback onToggle}`.

- [ ] **Step 1: Write the failing test**

```dart
// test/widget/pos_dn_group_header_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_grouping.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_group_header.dart';

void main() {
  GroupNode node() => GroupNode('Straps')
    ..count = 3
    ..posQty = 12
    ..dnQty = 10;

  testWidgets('shows value, count and qty totals; tap toggles', (tester) async {
    var toggled = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PosDnGroupHeader(
          node: node(),
          isSecondary: false,
          isExpanded: true,
          onToggle: () => toggled++,
        ),
      ),
    ));

    expect(find.text('Straps'), findsOneWidget);
    expect(find.textContaining('3'), findsWidgets);   // count
    expect(find.textContaining('12'), findsWidgets);  // POS qty
    expect(find.textContaining('10'), findsWidgets);  // DN qty

    await tester.tap(find.byType(PosDnGroupHeader));
    expect(toggled, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/pos_dn_group_header_test.dart`
Expected: FAIL — `pos_dn_group_header.dart` doesn't exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_group_header.dart
import 'package:flutter/material.dart';
import 'package:multimax/app/modules/global_widgets/animated_expand_icon.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_format.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_grouping.dart';

/// Collapsible group header for the report. Primary headers read bold on a
/// tinted surface; secondary headers are indented and lighter. Theme-aware
/// only — no hardcoded surfaces/inks.
class PosDnGroupHeader extends StatelessWidget {
  final GroupNode node;
  final bool isSecondary;
  final bool isExpanded;
  final VoidCallback onToggle;

  const PosDnGroupHeader({
    super.key,
    required this.node,
    required this.isSecondary,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bg =
        isSecondary ? cs.surfaceContainerLow : cs.surfaceContainerHighest;

    return Padding(
      padding: EdgeInsets.only(left: isSecondary ? 16 : 0, bottom: 6, top: 2),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                AnimatedExpandIcon(isExpanded: isExpanded),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    node.key,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight:
                          isSecondary ? FontWeight.w600 : FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                _CountBadge(count: node.count),
                const SizedBox(width: 10),
                _QtyTotals(posQty: node.posQty, dnQty: node.dnQty),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;
  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$count',
        style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary),
      ),
    );
  }
}

class _QtyTotals extends StatelessWidget {
  final num posQty;
  final num dnQty;
  const _QtyTotals({required this.posQty, required this.dnQty});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontSize: 12,
      fontFamily: 'ShureTechMono',
      color: cs.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('POS ${formatQty(posQty)}', style: style),
        Text('DN ${formatQty(dnQty)}', style: style),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/pos_dn_group_header_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_group_header.dart test/widget/pos_dn_group_header_test.dart
git commit -m "feat(pos-dn-rate): collapsible group header widget"
```

---

### Task 5: `PosDnGroupByBar` widget

**Files:**
- Create: `lib/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_group_by_bar.dart`
- Test: `test/widget/pos_dn_group_by_bar_test.dart`

**Interfaces:**
- Consumes: `PosDnGroupField` (Task 1).
- Produces: `class PosDnGroupByBar extends StatelessWidget` with params
  `{required PosDnGroupField? primary, required PosDnGroupField? secondary, required ValueChanged<PosDnGroupField?> onPrimaryChanged, required ValueChanged<PosDnGroupField?> onSecondaryChanged, required VoidCallback onExpandAll, required VoidCallback onCollapseAll}`.
  Selecting a field is done via a bottom-sheet menu of `None + the 5 fields` (secondary menu omits the current primary). Expand/collapse-all buttons show only when `primary != null`.

- [ ] **Step 1: Write the failing test**

```dart
// test/widget/pos_dn_group_by_bar_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_grouping.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_group_by_bar.dart';

void main() {
  testWidgets('picking a primary field fires onPrimaryChanged', (tester) async {
    PosDnGroupField? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PosDnGroupByBar(
          primary: null,
          secondary: null,
          onPrimaryChanged: (f) => picked = f,
          onSecondaryChanged: (_) {},
          onExpandAll: () {},
          onCollapseAll: () {},
        ),
      ),
    ));

    // Open the primary menu (the chip shows the placeholder label).
    await tester.tap(find.text('Group by'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Item Group').last);
    await tester.pumpAndSettle();

    expect(picked, PosDnGroupField.itemGroup);
  });

  testWidgets('secondary controls appear only when primary is set',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PosDnGroupByBar(
          primary: PosDnGroupField.itemGroup,
          secondary: null,
          onPrimaryChanged: (_) {},
          onSecondaryChanged: (_) {},
          onExpandAll: () {},
          onCollapseAll: () {},
        ),
      ),
    ));
    // Expand/collapse-all affordance present when grouped.
    expect(find.byIcon(Icons.unfold_less), findsOneWidget);
    expect(find.byIcon(Icons.unfold_more), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/pos_dn_group_by_bar_test.dart`
Expected: FAIL — `pos_dn_group_by_bar.dart` doesn't exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_group_by_bar.dart
import 'package:flutter/material.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_grouping.dart';

/// "Group by" control row: a primary field chip, an optional secondary field
/// chip (shown once a primary is chosen), and expand/collapse-all buttons.
/// Selection uses a bottom-sheet menu (None + the five groupable fields).
class PosDnGroupByBar extends StatelessWidget {
  final PosDnGroupField? primary;
  final PosDnGroupField? secondary;
  final ValueChanged<PosDnGroupField?> onPrimaryChanged;
  final ValueChanged<PosDnGroupField?> onSecondaryChanged;
  final VoidCallback onExpandAll;
  final VoidCallback onCollapseAll;

  const PosDnGroupByBar({
    super.key,
    required this.primary,
    required this.secondary,
    required this.onPrimaryChanged,
    required this.onSecondaryChanged,
    required this.onExpandAll,
    required this.onCollapseAll,
  });

  Future<void> _pick(
    BuildContext context, {
    required PosDnGroupField? current,
    required PosDnGroupField? exclude,
    required ValueChanged<PosDnGroupField?> onChanged,
  }) async {
    final options = <PosDnGroupField?>[
      null,
      ...PosDnGroupField.values.where((f) => f != exclude),
    ];
    final chosen = await showModalBottomSheet<Object?>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final f in options)
                ListTile(
                  title: Text(f?.label ?? 'None'),
                  trailing: f == current
                      ? Icon(Icons.check, color: cs.primary)
                      : null,
                  // Wrap null in a sentinel so it survives the pop.
                  onTap: () => Navigator.pop(ctx, f ?? _none),
                ),
            ],
          ),
        );
      },
    );
    if (chosen == null) return; // dismissed
    onChanged(identical(chosen, _none) ? null : chosen as PosDnGroupField);
  }

  static const Object _none = Object();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Row(
      children: [
        Text('Group by:',
            style: theme.textTheme.labelMedium
                ?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ActionChip(
                avatar: Icon(Icons.layers_outlined, size: 16, color: cs.primary),
                label: Text(primary?.label ?? 'Group by'),
                onPressed: () => _pick(
                  context,
                  current: primary,
                  exclude: null,
                  onChanged: onPrimaryChanged,
                ),
              ),
              if (primary != null)
                ActionChip(
                  avatar: Icon(Icons.subdirectory_arrow_right,
                      size: 16, color: cs.primary),
                  label: Text(secondary?.label ?? '+ Then by'),
                  onPressed: () => _pick(
                    context,
                    current: secondary,
                    exclude: primary,
                    onChanged: onSecondaryChanged,
                  ),
                ),
            ],
          ),
        ),
        if (primary != null) ...[
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.unfold_more),
            tooltip: 'Expand all',
            onPressed: onExpandAll,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.unfold_less),
            tooltip: 'Collapse all',
            onPressed: onCollapseAll,
          ),
        ],
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/pos_dn_group_by_bar_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_group_by_bar.dart test/widget/pos_dn_group_by_bar_test.dart
git commit -m "feat(pos-dn-rate): group-by selector bar widget"
```

---

### Task 6: Wire the bar + grouped body into the screen

**Files:**
- Modify: `lib/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_screen.dart`

**Interfaces:**
- Consumes: `controller.primaryGroup/secondaryGroup/isGrouped/displayItems`, `controller.setPrimaryGroup/setSecondaryGroup/toggleGroupCollapsed/expandAllGroups/collapseAllGroups`, `controller.collapsedGroups`; `PosDnGroupByBar` (Task 5); `PosDnGroupHeader` (Task 4); `DisplayItem`/`DisplayKind` (Task 2); existing `PosDnItemRateTile`.

- [ ] **Step 1: Add imports**

At the top of `pos_dn_item_rate_screen.dart`, add:

```dart
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_grouping.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_group_by_bar.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_group_header.dart';
```

- [ ] **Step 2: Insert the Group-by bar sliver**

Immediately after the `_StatusChipRow` `SliverToBoxAdapter` block (the one guarded by `if (!controller.isRunning.value && controller.reportRows.isNotEmpty)`, ending near line 109) and before the Result count pill block, add:

```dart
                // ── Group-by bar ─────────────────────────────────────────
                if (!controller.isRunning.value &&
                    controller.reportRows.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
                      child: PosDnGroupByBar(
                        primary: controller.primaryGroup.value,
                        secondary: controller.secondaryGroup.value,
                        onPrimaryChanged: controller.setPrimaryGroup,
                        onSecondaryChanged: controller.setSecondaryGroup,
                        onExpandAll: controller.expandAllGroups,
                        onCollapseAll: controller.collapseAllGroups,
                      ),
                    ),
                  ),
```

- [ ] **Step 3: Branch the body between flat and grouped rendering**

The current final branch is `else ...[ flat list + footer ]` (the flat `SliverList` of tiles plus `_EndOfListFooter`, roughly lines 218–240). Split it into two branches: keep the flat list when `!controller.isGrouped`, and render `controller.displayItems` when grouped. Both branches are sliver spreads (`...[ ... ]`), so every child must be a sliver — do **not** wrap the `SliverList` in a `Builder`/box widget. `controller.displayItems` is read inside the `SliverChildBuilderDelegate` callback, so it stays reactive under the enclosing `Obx`.

Replace that final `else ...[ ... ]` block with exactly:

```dart
                else if (!controller.isGrouped) ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
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
                  SliverToBoxAdapter(
                    child: Padding(
                      padding:
                          EdgeInsets.fromLTRB(12, 4, 12, 16 + bottomInset),
                      child: _EndOfListFooter(
                        totals: PosDnItemRateController.sumTotals(rows),
                      ),
                    ),
                  ),
                ] else ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _buildDisplayItem(
                            context, controller.displayItems[index]),
                        childCount: controller.displayItems.length,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding:
                          EdgeInsets.fromLTRB(12, 4, 12, 16 + bottomInset),
                      child: _EndOfListFooter(
                        totals: PosDnItemRateController.sumTotals(rows),
                      ),
                    ),
                  ),
                ],
```

The end-of-list footer keeps summing `rows` (all `filteredRows`) in both branches, so the totals stay identical whether or not grouping is on.

- [ ] **Step 4: Add the display-item renderer**

Add this method to `_PosDnItemRateScreenState` (e.g. after `_buildFilterChips`):

```dart
  Widget _buildDisplayItem(BuildContext context, DisplayItem item) {
    switch (item.kind) {
      case DisplayKind.primaryHeader:
      case DisplayKind.secondaryHeader:
        final key = item.collapseKey!;
        return PosDnGroupHeader(
          node: item.node!,
          isSecondary: item.kind == DisplayKind.secondaryHeader,
          isExpanded: !controller.collapsedGroups.contains(key),
          onToggle: () => controller.toggleGroupCollapsed(key),
        );
      case DisplayKind.row:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: PosDnItemRateTile(row: item.row!),
        );
    }
  }
```

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/app/modules/selling/reports/pos_dn_item_rate/`
Expected: No errors (warnings pre-existing elsewhere are fine; the touched files must be clean).

- [ ] **Step 6: Run the report's whole test set**

Run: `flutter test test/unit/pos_dn_grouping_test.dart test/unit/pos_dn_item_rate_group_controller_test.dart test/unit/pos_dn_item_rate_controller_test.dart test/widget/pos_dn_group_header_test.dart test/widget/pos_dn_group_by_bar_test.dart test/widget/pos_dn_item_rate_screen_test.dart`
Expected: PASS. If `pos_dn_item_rate_screen_test.dart` fails because the new bar changed the widget tree, update that test's finders to accommodate the bar (do not weaken existing assertions).

- [ ] **Step 7: Commit**

```bash
git add lib/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_screen.dart
git commit -m "feat(pos-dn-rate): render group-by bar and grouped list on screen"
```

---

### Task 7: Full suite + docs

**Files:**
- Modify: `docs/pos_delivery_note_item_rate_report.md` (append a short "Grouping" note) — optional but preferred.

- [ ] **Step 1: Run the full suite**

Run: `flutter test`
Expected: PASS — baseline was 722; expect 722 + new tests, 0 failures.

- [ ] **Step 2: Analyze the whole project**

Run: `flutter analyze`
Expected: No new errors introduced by this change.

- [ ] **Step 3: Append a grouping note to the report doc**

Add to `docs/pos_delivery_note_item_rate_report.md` (end of file):

```markdown
## Mobile: Group-by

The Flutter report screen supports client-side two-level grouping (primary +
optional secondary) over the fetched rows — by Item Group, Customer, Customer
Group, POS Item Name, or Rate. Headers show value + row count + summed POS/DN
qty (qty only, never rate). Logic lives in
`lib/app/modules/selling/reports/pos_dn_item_rate/pos_dn_grouping.dart` (pure,
unit-tested); the server report and status are unchanged.
```

- [ ] **Step 4: Commit**

```bash
git add docs/pos_delivery_note_item_rate_report.md
git commit -m "docs(pos-dn-rate): note mobile group-by feature"
```

---

## Self-Review notes

- **Spec coverage:** two-level model (Tasks 1,3), 5 fields (Task 1), headers value+count+qty (Task 4), on-screen bar (Tasks 5,6), default expanded + collapse-all (Tasks 3,5,6), pure core + flatten (Tasks 1,2), composes with filteredRows (Task 3), preserved conventions (Task 6 keeps footer/scrollbar/safe-area), YAGNI honored (no 3+ levels / persistence).
- **Type consistency:** `PosDnGroupField`, `GroupNode`, `DisplayItem`/`DisplayKind`, `primaryCollapseKey`/`secondaryCollapseKey`, `collapseKeysFor`, `sanitizeSecondary`, and all controller members are named identically across tasks.
- **DRY note:** leaf qty totals are summed inline in `groupRows` (via `toNum` on `upload_qty`/`dn_qty`) rather than importing the controller's `sumTotals`, to keep `pos_dn_grouping.dart` GetX-free; the two sums are trivially small and independently tested.
