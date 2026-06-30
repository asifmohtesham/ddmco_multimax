# BOM Stock — Customer-Code Grouped POS View — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]` checkboxes.

**Goal:** When a POS Upload is active, render the BOM Stock results as collapsible **Customer Code** groups (mirroring the POS Upload item card), each line showing In Stock / Avail (`running_total`) / Need / Short with apparent green/red coding; fix the clipped filter-sheet Run Report button.

**Architecture:** Delta to the shipped redesign. Controller gains a pure `groupByCustomerCode` + `groupedRows` getter + expand/collapse state. Shared `StatCell`/`StatusPill`/`coverageAccent` are extracted into `widgets/bom_stock_bits.dart` and reused by the tile, a new `BomStockLineRow`, and a new `BomStockGroupCard` (mirrors `ItemGroupCard`). The screen branches grouped-vs-flat on `posUpload`. Server `running_total`/`shortage_qty` are used as-is (no server/API change).

**Tech Stack:** Flutter, GetX, flutter_test. References: `lib/app/shared/pos_upload/item_group_card.dart` (group card structure), `lib/app/modules/global_widgets/animated_expand_icon.dart` (`AnimatedExpandIcon(isExpanded:)`), `lib/app/data/constants/app_theme.dart` (`AppColors.green500`/`green300`/`red500`).

## Global Constraints

- Shortfall = `BomStockCustomerCodeController.isShortfall(row)` (`shortage_qty > 0`). Numerics via `toNum`, never `as num?`.
- **Green = covered**, **red = short**. Green = `Theme.of(context).brightness == Brightness.dark ? AppColors.green300 : AppColors.green500`; red = `colorScheme.error`. No other hardcoded colors; `withValues(alpha:)` not `withOpacity`.
- Grouped view ONLY when `controller.posUpload.value != null`; flat `BomStockTile` list otherwise.
- Groups collapsed by default (empty `expandedCodes` set).
- Grouping order = first-seen `customer_code` order over `filteredRows`; rows within a group keep server order.
- Commit after each task; `flutter analyze` clean on touched files before each commit.

---

## Task G1: Controller — customer-code grouping + expand state

**Files:**
- Modify: `lib/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart`
- Test: `test/unit/bom_stock_customer_code_controller_test.dart`

**Interfaces produced:**
- `class BomStockGroup { final String code; final List<Map<String,dynamic>> rows; int get itemCount; num get totalShortage; bool get anyShort; }`
- `static List<BomStockGroup> groupByCustomerCode(List<Map<String,dynamic>> rows)`
- `List<BomStockGroup> get groupedRows`
- `RxSet<String> expandedCodes`; `void toggleGroup(String code)`; `bool isGroupExpanded(String code)`

- [ ] **Step 1: Tests (TDD).** Append to `test/unit/bom_stock_customer_code_controller_test.dart` (inside `main`):

```dart
  group('groupByCustomerCode', () {
    final rows = <Map<String, dynamic>>[
      {'customer_code': 'A', 'item_code': 'I1', 'shortage_qty': 0},
      {'customer_code': 'B', 'item_code': 'I2', 'shortage_qty': 5},
      {'customer_code': 'A', 'item_code': 'I3', 'shortage_qty': 0},
      {'customer_code': '',  'item_code': 'I4', 'shortage_qty': 0},
    ];
    test('buckets by customer_code in first-seen order', () {
      final g = BomStockCustomerCodeController.groupByCustomerCode(rows);
      expect(g.map((e) => e.code), ['A', 'B', '']);
      expect(g.first.itemCount, 2);
      expect(g.first.rows.map((r) => r['item_code']), ['I1', 'I3']);
    });
    test('totalShortage sums the group; anyShort flags it', () {
      final g = BomStockCustomerCodeController.groupByCustomerCode(rows);
      expect(g[0].anyShort, isFalse);
      expect(g[0].totalShortage, 0);
      expect(g[1].anyShort, isTrue);
      expect(g[1].totalShortage, 5);
    });
  });

  group('group expand state', () {
    setUp(() {
      Get.testMode = true;
      if (!Get.isRegistered<ApiProvider>()) Get.put(ApiProvider());
    });
    tearDown(Get.reset);
    test('collapsed by default; toggleGroup flips; clearFilters resets', () {
      final c = BomStockCustomerCodeController();
      expect(c.isGroupExpanded('A'), isFalse);
      c.toggleGroup('A');
      expect(c.isGroupExpanded('A'), isTrue);
      c.toggleGroup('A');
      expect(c.isGroupExpanded('A'), isFalse);
      c.toggleGroup('B');
      c.clearFilters();
      expect(c.isGroupExpanded('B'), isFalse);
    });
  });
```
(The `group expand state` group needs `import 'package:get/get.dart';` and `import 'package:multimax/app/data/providers/api_provider.dart';` — already present in this test file from earlier tasks. The path_provider stub from earlier `setUpAll` also already exists at the top of the file; constructing `ApiProvider` is covered.)

- [ ] **Step 2: Run — expect RED.** `flutter test test/unit/bom_stock_customer_code_controller_test.dart`

- [ ] **Step 3: Implement.** In the controller:

(a) After the `// ── Segmented row filter` block, add expand state:
```dart
  // ── Customer-code group expand state (collapsed by default) ─────────────
  final expandedCodes = <String>{}.obs;
  void toggleGroup(String code) {
    if (expandedCodes.contains(code)) {
      expandedCodes.remove(code);
    } else {
      expandedCodes.add(code);
    }
  }
  bool isGroupExpanded(String code) => expandedCodes.contains(code);
```

(b) After the `filteredTotals` getter, add:
```dart
  /// Filtered rows grouped by customer code (first-seen order).
  List<BomStockGroup> get groupedRows => groupByCustomerCode(filteredRows);
```

(c) In `clearFilters()`, add `expandedCodes.clear();`.

(d) In the static section, add:
```dart
  /// Buckets [rows] by `customer_code` in first-seen order.
  static List<BomStockGroup> groupByCustomerCode(
      List<Map<String, dynamic>> rows) {
    final order = <String>[];
    final byCode = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final code = (r['customer_code'] ?? '').toString();
      if (!byCode.containsKey(code)) {
        byCode[code] = [];
        order.add(code);
      }
      byCode[code]!.add(r);
    }
    return [for (final code in order) BomStockGroup(code, byCode[code]!)];
  }
```

(e) At the BOTTOM of the file (after the controller class closes), add:
```dart
/// A customer-code bucket of result rows.
class BomStockGroup {
  final String code;
  final List<Map<String, dynamic>> rows;
  const BomStockGroup(this.code, this.rows);

  int get itemCount => rows.length;
  num get totalShortage =>
      rows.fold<num>(0, (a, r) => a + (toNum(r['shortage_qty']) ?? 0));
  bool get anyShort => rows.any(BomStockCustomerCodeController.isShortfall);
}
```
(`toNum` is already imported at the top of the controller file.)

- [ ] **Step 4: Run — GREEN**, then analyze + full suite. `flutter test test/unit/bom_stock_customer_code_controller_test.dart`; `flutter analyze lib/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart`; `flutter test`.

- [ ] **Step 5: Commit**
```bash
git add lib/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart test/unit/bom_stock_customer_code_controller_test.dart
git commit -m "feat(manufacturing): BOM Stock customer-code grouping + expand state"
```

---

## Task G2: Extract shared `StatCell` / `StatusPill` / `coverageAccent`

**Files:**
- Create: `lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_bits.dart`
- Modify: `lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_tile.dart`

**Interfaces produced:** top-level `Color coverageAccent(BuildContext, bool short)`; `class StatusPill extends StatelessWidget` (`{required num shortage}`); `class StatCell extends StatelessWidget` (`{required String label, required String value, bool alert}`).

This is a refactor: the tile keeps identical rendered output (its widget tests are the regression guard), so no new test is added here — run the existing tile test.

- [ ] **Step 1: Create `bom_stock_bits.dart`:**
```dart
import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_format.dart';

/// Green (covered) / red (short) accent. Green is the design-system success
/// token, theme-aware; red is the scheme error color.
Color coverageAccent(BuildContext context, bool short) {
  if (short) return Theme.of(context).colorScheme.error;
  return Theme.of(context).brightness == Brightness.dark
      ? AppColors.green300
      : AppColors.green500;
}

/// Demand status pill: green "Covered" or red "Short N".
class StatusPill extends StatelessWidget {
  final num shortage;
  const StatusPill({super.key, required this.shortage});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final short = shortage > 0;
    final accent = coverageAccent(context, short);
    final bg = short ? cs.errorContainer : accent.withValues(alpha: 0.14);
    final fg = short ? cs.onErrorContainer : accent;
    final icon = short ? Icons.warning_amber_rounded : Icons.check_circle_outline;
    final label = short ? 'Short ${formatQty(shortage)}' : 'Covered';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}

/// Label-over-value stat cell. `alert` paints the value in the error color.
class StatCell extends StatelessWidget {
  final String label;
  final String value;
  final bool alert;
  const StatCell({super.key, required this.label, required this.value, this.alert = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        Text(value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: alert ? cs.error : null,
            )),
      ],
    );
  }
}
```

- [ ] **Step 2: Refactor `bom_stock_tile.dart`:**
- Add import: `import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_bits.dart';`
- DELETE the private `class _StatusPill` and `class _StatCell` from the bottom of the file.
- Replace `_StatusPill(shortage: shortage)` → `StatusPill(shortage: shortage)`.
- Replace each `_StatCell(...)` → `StatCell(...)`.
- Leave `_chip` and everything else unchanged.

- [ ] **Step 3: Verify (no behavior change).** `flutter analyze lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_tile.dart lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_bits.dart` (0 issues); `flutter test test/widget/bom_stock_tile_test.dart` (existing tests still GREEN — the tile renders the same text; only the "Covered" pill's color changed from secondaryContainer to the success green, which the tests don't assert); then full `flutter test`.

- [ ] **Step 4: Commit**
```bash
git add lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_bits.dart lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_tile.dart
git commit -m "refactor(manufacturing): extract shared StatCell/StatusPill + green coverage accent"
```

---

## Task G3: `BomStockLineRow` widget

**Files:**
- Create: `lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_line_row.dart`
- Test: `test/widget/bom_stock_line_row_test.dart`

**Interface produced:** `const BomStockLineRow({required Map<String,dynamic> row})`.

- [ ] **Step 1: Test (TDD).** Create `test/widget/bom_stock_line_row_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_line_row.dart';

Widget _wrap(Map<String, dynamic> row) =>
    MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 380, child: BomStockLineRow(row: row)))));

void main() {
  testWidgets('shows item name + In Stock/Avail/Need/Short figures', (tester) async {
    await tester.pumpWidget(_wrap(const {
      'item_name': 'STRAPS IT 35mm', 'item_code': '2001999', 'item_group': 'Straps',
      'in_stock_qty': 84, 'running_total': 84, 'required_qty': 108, 'shortage_qty': 24,
    }));
    expect(find.text('STRAPS IT 35mm'), findsOneWidget);
    expect(find.text('In Stock'), findsOneWidget);
    expect(find.text('Avail'), findsOneWidget);
    expect(find.text('Need'), findsOneWidget);
    expect(find.text('Short'), findsOneWidget);
    expect(find.text('108'), findsOneWidget);
    expect(find.text('24'), findsOneWidget);
  });

  testWidgets('covered row shows Short 0', (tester) async {
    await tester.pumpWidget(_wrap(const {
      'item_name': 'X', 'item_code': 'X1', 'in_stock_qty': 816,
      'running_total': 816, 'required_qty': 36, 'shortage_qty': 0,
    }));
    expect(find.text('0'), findsOneWidget); // Short 0
  });
}
```

- [ ] **Step 2: Run — RED.** `flutter test test/widget/bom_stock_line_row_test.dart`

- [ ] **Step 3: Implement.** Create `bom_stock_line_row.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_bits.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_format.dart';

/// A condensed item line inside a Customer Code group.
class BomStockLineRow extends StatelessWidget {
  final Map<String, dynamic> row;
  const BomStockLineRow({super.key, required this.row});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final short = BomStockCustomerCodeController.isShortfall(row);
    final accent = coverageAccent(context, short);

    final itemName = (row['item_name'] ?? '').toString();
    final itemCode = (row['item_code'] ?? '').toString();
    final itemGroup = (row['item_group'] ?? '').toString();
    final inStock = toNum(row['in_stock_qty']);
    final avail = toNum(row['running_total']);
    final need = toNum(row['required_qty']);
    final shortage = toNum(row['shortage_qty']) ?? 0;
    final subline = [itemCode, itemGroup].where((s) => s.isNotEmpty).join(' · ');

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(itemName.isEmpty ? itemCode : itemName,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          if (subline.isNotEmpty)
            Text(subline,
                style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              StatCell(label: 'In Stock', value: formatQty(inStock)),
              StatCell(label: 'Avail', value: formatQty(avail), alert: short),
              StatCell(label: 'Need', value: formatQty(need)),
              StatCell(label: 'Short', value: formatQty(shortage), alert: shortage > 0),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run — GREEN**, then analyze + full suite.

- [ ] **Step 5: Commit**
```bash
git add lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_line_row.dart test/widget/bom_stock_line_row_test.dart
git commit -m "feat(manufacturing): add BomStockLineRow (In Stock/Avail/Need/Short)"
```

---

## Task G4: `BomStockGroupCard` widget

**Files:**
- Create: `lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_group_card.dart`
- Test: `test/widget/bom_stock_group_card_test.dart`

**Interface produced:** `const BomStockGroupCard({required BomStockGroup group, required bool expanded, required VoidCallback onToggle})`.

- [ ] **Step 1: Test (TDD).** Create `test/widget/bom_stock_group_card_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_group_card.dart';

const _rows = [
  {'item_name': 'STRAPS 40mm', 'item_code': '2001272', 'in_stock_qty': 816,
   'running_total': 816, 'required_qty': 36, 'shortage_qty': 0},
  {'item_name': 'STRAPS 35mm', 'item_code': '2001999', 'in_stock_qty': 84,
   'running_total': 84, 'required_qty': 108, 'shortage_qty': 24},
];

Widget _wrap({required bool expanded}) => MaterialApp(
      home: Scaffold(
        body: BomStockGroupCard(
          group: const BomStockGroup('5052483', _rows),
          expanded: expanded,
          onToggle: () {},
        ),
      ),
    );

void main() {
  testWidgets('collapsed: header (code + count + short pill), no line rows',
      (tester) async {
    await tester.pumpWidget(_wrap(expanded: false));
    expect(find.text('Code 5052483'), findsOneWidget);
    expect(find.text('2 items'), findsOneWidget);
    expect(find.text('Short 24'), findsOneWidget); // group totalShortage = 24 → red
    expect(find.text('STRAPS 40mm'), findsNothing); // collapsed: lines hidden
  });

  testWidgets('expanded: line rows visible', (tester) async {
    await tester.pumpWidget(_wrap(expanded: true));
    await tester.pumpAndSettle();
    expect(find.text('STRAPS 40mm'), findsOneWidget);
    expect(find.text('STRAPS 35mm'), findsOneWidget);
  });

  testWidgets('all-covered group shows Covered pill', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BomStockGroupCard(
          group: const BomStockGroup('A', [
            {'item_name': 'Z', 'item_code': 'Z1', 'in_stock_qty': 10,
             'running_total': 10, 'required_qty': 4, 'shortage_qty': 0},
          ]),
          expanded: false,
          onToggle: () {},
        ),
      ),
    ));
    expect(find.text('Covered'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run — RED.** `flutter test test/widget/bom_stock_group_card_test.dart`

- [ ] **Step 3: Implement.** Create `bom_stock_group_card.dart` (mirrors `ItemGroupCard`'s rail + header + AnimatedSize children):
```dart
import 'package:flutter/material.dart';
import 'package:multimax/app/modules/global_widgets/animated_expand_icon.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_bits.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_line_row.dart';

/// Collapsible Customer Code group, mirroring the POS Upload ItemGroupCard.
class BomStockGroupCard extends StatelessWidget {
  final BomStockGroup group;
  final bool expanded;
  final VoidCallback onToggle;
  const BomStockGroupCard({
    super.key,
    required this.group,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = coverageAccent(context, group.anyShort);
    final title = group.code.isEmpty ? 'No code' : 'Code ${group.code}';
    final count = '${group.itemCount} item${group.itemCount == 1 ? '' : 's'}';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: accent),
            Expanded(
              child: Column(
                children: [
                  InkWell(
                    onTap: onToggle,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title,
                                    style: theme.textTheme.bodyLarge
                                        ?.copyWith(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(count,
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(color: cs.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          StatusPill(shortage: group.totalShortage),
                          const SizedBox(width: 4),
                          AnimatedExpandIcon(isExpanded: expanded),
                        ],
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topCenter,
                    child: !expanded
                        ? const SizedBox.shrink()
                        : Column(
                            children: [
                              Divider(height: 1, color: cs.outlineVariant),
                              const SizedBox(height: 4),
                              ...group.rows.map((r) => BomStockLineRow(row: r)),
                              const SizedBox(height: 4),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```
> Note: confirm `AnimatedExpandIcon`'s constructor is `AnimatedExpandIcon({required bool isExpanded})` (as used in `item_group_card.dart:187`). If its param differs, match its actual signature.

- [ ] **Step 4: Run — GREEN**, then analyze + full suite.

- [ ] **Step 5: Commit**
```bash
git add lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_group_card.dart test/widget/bom_stock_group_card_test.dart
git commit -m "feat(manufacturing): add collapsible BomStockGroupCard (customer-code group)"
```

---

## Task G5: Screen — grouped vs flat branch

**Files:**
- Modify: `lib/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_screen.dart`
- Test: `test/widget/bom_stock_screen_test.dart`

- [ ] **Step 1: Test (TDD).** Add to `test/widget/bom_stock_screen_test.dart` (inside `main`):
```dart
  testWidgets('POS active: renders grouped customer-code cards (not flat tiles)',
      (tester) async {
    final c = Get.find<BomStockCustomerCodeController>();
    c.posUpload.value = 'ML-2026-02011';
    c.reportRows.assignAll([
      {'sl_no': '1', 'item_name': 'STRAPS 40mm', 'item_code': '2001272',
       'customer_code': '5052483', 'in_stock_qty': 816, 'running_total': 816,
       'required_qty': 36, 'shortage_qty': 0},
    ]);
    await tester.pumpWidget(const GetMaterialApp(home: BomStockCustomerCodeScreen()));
    await tester.pump();
    expect(find.text('Code 5052483'), findsOneWidget);   // group header
    expect(find.text('STRAPS 40mm'), findsNothing);       // collapsed by default
  });
```

- [ ] **Step 2: Run — RED.** `flutter test test/widget/bom_stock_screen_test.dart`

- [ ] **Step 3: Implement.** In `bom_stock_customer_code_screen.dart`:
- Add import: `import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_group_card.dart';`
- In the body, INSERT a new branch between the `else if (rows.isEmpty) …` arm and the existing flat `else` arm:
```dart
                    else if (controller.posUpload.value != null)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate(
                            controller.groupedRows
                                .map((g) => BomStockGroupCard(
                                      group: g,
                                      expanded: controller.isGroupExpanded(g.code),
                                      onToggle: () => controller.toggleGroup(g.code),
                                    ))
                                .toList(),
                          ),
                        ),
                      )
```
(The existing final `else` with the flat `BomStockTile` `SliverList` stays as the no-POS path. `SliverChildListDelegate` builds eagerly inside the `Obx`, so `isGroupExpanded` reads are tracked and `toggleGroup` rebuilds.)

- [ ] **Step 4: Run — GREEN**, then analyze (module dir) + full suite.

- [ ] **Step 5: Commit**
```bash
git add lib/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_screen.dart test/widget/bom_stock_screen_test.dart
git commit -m "feat(manufacturing): group BOM Stock results by customer code when POS active"
```

---

## Task G6: Fix clipped Run Report button (filter sheet)

**Files:**
- Modify: `lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_filter_sheet.dart`

No automated test (layout inset); verify via analyze + manual.

- [ ] **Step 1: Implement.** In `bom_stock_filter_sheet.dart`, find the bottom Run Report button — the final child of the sheet's outer `Column`:
```dart
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
```
Wrap it in `SafeArea(top: false, …)` so it always clears the system nav bar:
```dart
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
```

- [ ] **Step 2: Verify.** `flutter analyze lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_filter_sheet.dart` (0 issues); full `flutter test` (no regressions).

- [ ] **Step 3: Commit**
```bash
git add lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_filter_sheet.dart
git commit -m "fix(manufacturing): keep filter-sheet Run Report button clear of the nav bar"
```

---

## Task G7: Verification

- [ ] **Step 1:** `flutter analyze lib/app/modules/manufacturing/reports/bom_stock_customer_code test/unit/bom_stock_customer_code_controller_test.dart test/widget/bom_stock_tile_test.dart test/widget/bom_stock_line_row_test.dart test/widget/bom_stock_group_card_test.dart test/widget/bom_stock_totals_footer_test.dart test/widget/bom_stock_screen_test.dart` — expect **No issues found**.
- [ ] **Step 2:** `flutter test` — all pass.
- [ ] **Step 3 (manual, user):** on-device with a POS Upload — results group into collapsible Customer Code cards (collapsed, green/red headers); expanding shows In Stock/Avail/Need/Short lines with green/red accents; a repeated item's later line reads `Avail 0`; segmented filter + footer move with the filter; the **Run Report** button in the filter sheet is fully visible above the nav bar; no overflow.

## Self-Review

- Spec coverage: grouping by customer code → G1+G5; collapsed-by-default expand → G1; In Stock/Avail/Need/Short line → G3; group card mirror → G4; green/red coding → G2 (coverageAccent/StatusPill) used in G3/G4; depletion via server running_total (Avail) → G3; Run button fix → G6; filter+footer reuse → G5. ✓
- Placeholder scan: none.
- Type consistency: `BomStockGroup`/`groupByCustomerCode`/`groupedRows`/`expandedCodes`/`toggleGroup`/`isGroupExpanded`/`coverageAccent`/`StatCell`/`StatusPill`/`BomStockLineRow`/`BomStockGroupCard` consistent across producing/consuming tasks. ✓
