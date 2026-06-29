# BOM Stock Card Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]` checkboxes.

**Goal:** Rebuild the BOM Stock report's result card to mirror the POS Upload item tile, add an `All | In Stock | Shortage` segmented filter, surface the server's new `shortage_qty` as the demand signal, and compute the totals footer over the filtered rows.

**Architecture:** Delta to the shipped feature. Controller gains a segmented-filter state + pure filter/sum statics + a redefined `isShortfall` (now `shortage_qty > 0`). `BomStockTile` and `BomStockTotalsFooter` are rebuilt; the screen wires the segmented filter and filtered rows/totals. API, filters, routing, drawer untouched.

**Tech Stack:** Flutter, GetX, flutter_test. Reference patterns: `pos_upload_form_screen.dart` item `Card` + `_Stat`; `stock_balance_screen.dart` `_SegmentedStateFilter`.

## Global Constraints

- Shortfall = `toNum(row['shortage_qty']) != null && > 0` (server-authoritative). Never re-derive from running/required.
- No hardcoded colors — theme `ColorScheme` tokens only; `withValues(alpha:)` not `withOpacity`.
- Numeric reads go through the existing `toNum(dynamic)` (in `widgets/bom_stock_format.dart`) — never `as num?`.
- Card visual contract = POS item tile: `Card(elevation 0, radius 12, BorderSide(outlineVariant), surfaceContainerLowest)` → header(index badge + name + status) → `Divider` → stat row → chips `Wrap`.
- Segmented filter values: `'ALL' | 'instock' | 'shortage'`.
- Commit after each task; `flutter analyze` clean on touched files before every commit.

---

## Task R1: Controller — segmented filter, sums, shortfall redefinition

**Files:**
- Modify: `lib/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart`
- Test: `test/unit/bom_stock_customer_code_controller_test.dart`

**Interfaces produced:**
- `static bool isShortfall(Map<String,dynamic>)` — redefined on `shortage_qty`.
- `RxString rowFilter` (default `'ALL'`); `void setRowFilter(String)`.
- `static List<Map<String,dynamic>> applyRowFilter(List<Map<String,dynamic>> rows, String filter)`.
- `List<Map<String,dynamic>> get filteredRows`.
- `static Map<String,num> sumTotals(List<Map<String,dynamic>> rows)`.
- `Map<String,num> get filteredTotals`.

- [ ] **Step 1: Update the tests (TDD)** — in `test/unit/bom_stock_customer_code_controller_test.dart`, REPLACE the existing `group('isShortfall', ...)` and `group('isShortfall string-coercion hardening', ...)` blocks with the single group below, and ADD the two new groups. Leave `parseDataRows`, `extractTotalRow`, `distinctCustomerCodes`, `splitPosCodes`, and `controller mutations (no network)` untouched.

```dart
  group('isShortfall (shortage_qty)', () {
    test('true when shortage_qty > 0', () {
      expect(BomStockCustomerCodeController.isShortfall({'shortage_qty': 2004}), isTrue);
    });
    test('false when shortage_qty is 0', () {
      expect(BomStockCustomerCodeController.isShortfall({'shortage_qty': 0}), isFalse);
    });
    test('false when shortage_qty absent (no POS)', () {
      expect(BomStockCustomerCodeController.isShortfall({'in_stock_qty': 10}), isFalse);
    });
    test('coerces stringified shortage and never throws', () {
      expect(BomStockCustomerCodeController.isShortfall({'shortage_qty': '5'}), isTrue);
      expect(BomStockCustomerCodeController.isShortfall({'shortage_qty': 'n/a'}), isFalse);
    });
  });

  group('applyRowFilter', () {
    final rows = <Map<String, dynamic>>[
      {'item_code': 'A', 'in_stock_qty': 10, 'shortage_qty': 0},
      {'item_code': 'B', 'in_stock_qty': 0,  'shortage_qty': 5},
      {'item_code': 'C', 'in_stock_qty': 3,  'shortage_qty': 2},
    ];
    test('ALL returns every row', () {
      expect(BomStockCustomerCodeController.applyRowFilter(rows, 'ALL').length, 3);
    });
    test('instock keeps positive stock only', () {
      final r = BomStockCustomerCodeController.applyRowFilter(rows, 'instock');
      expect(r.map((e) => e['item_code']), ['A', 'C']);
    });
    test('shortage keeps short rows only', () {
      final r = BomStockCustomerCodeController.applyRowFilter(rows, 'shortage');
      expect(r.map((e) => e['item_code']), ['B', 'C']);
    });
  });

  group('sumTotals', () {
    test('sums in_stock / required / shortage across rows', () {
      final rows = <Map<String, dynamic>>[
        {'in_stock_qty': 10, 'required_qty': 4, 'shortage_qty': 0},
        {'in_stock_qty': 3,  'required_qty': 8, 'shortage_qty': 5},
      ];
      final t = BomStockCustomerCodeController.sumTotals(rows);
      expect(t['in_stock'], 13);
      expect(t['required'], 12);
      expect(t['shortage'], 5);
    });
    test('empty rows give zeros', () {
      final t = BomStockCustomerCodeController.sumTotals(const []);
      expect(t, {'in_stock': 0, 'required': 0, 'shortage': 0});
    });
  });
```

Also append one assertion to the existing `controller mutations (no network)` `clearFilters` test, before its closing `});`:
```dart
      c.setRowFilter('shortage');
      c.clearFilters();
      expect(c.rowFilter.value, 'ALL');
```

- [ ] **Step 2: Run the tests — expect RED** (`applyRowFilter`/`sumTotals`/`setRowFilter` undefined; new isShortfall semantics fail against old body).

Run: `flutter test test/unit/bom_stock_customer_code_controller_test.dart`

- [ ] **Step 3: Implement.** In `bom_stock_customer_code_controller.dart`:

(a) Replace the body of `isShortfall`:
```dart
  /// True when the row is short of its POS demand (server-computed shortage).
  static bool isShortfall(Map<String, dynamic> row) {
    final s = toNum(row['shortage_qty']);
    return s != null && s > 0;
  }
```

(b) After the `// ── Filter state` block (after `hideOutOfStock`), add:
```dart
  // ── Segmented row filter (All | In Stock | Shortage) ────────────────────
  final rowFilter = 'ALL'.obs;
  void setRowFilter(String v) => rowFilter.value = v;
```

(c) After the `// ── Result state` block, add the two getters:
```dart
  /// Result rows after the segmented filter is applied.
  List<Map<String, dynamic>> get filteredRows =>
      applyRowFilter(reportRows, rowFilter.value);

  /// In-stock / required / shortage sums over the currently-filtered rows.
  Map<String, num> get filteredTotals => sumTotals(filteredRows);
```

(d) In `clearFilters()`, add `rowFilter.value = 'ALL';` (anywhere in the body).

(e) In the static section (next to the other statics), add:
```dart
  /// Applies the segmented filter. 'instock' → positive stock; 'shortage' →
  /// short rows; anything else → all rows.
  static List<Map<String, dynamic>> applyRowFilter(
      List<Map<String, dynamic>> rows, String filter) {
    switch (filter) {
      case 'instock':
        return rows.where((r) => (toNum(r['in_stock_qty']) ?? 0) > 0).toList();
      case 'shortage':
        return rows.where(isShortfall).toList();
      default:
        return List<Map<String, dynamic>>.from(rows);
    }
  }

  /// Sums in_stock_qty / required_qty / shortage_qty across [rows].
  static Map<String, num> sumTotals(List<Map<String, dynamic>> rows) {
    num inStock = 0, required = 0, shortage = 0;
    for (final r in rows) {
      inStock += toNum(r['in_stock_qty']) ?? 0;
      required += toNum(r['required_qty']) ?? 0;
      shortage += toNum(r['shortage_qty']) ?? 0;
    }
    return {'in_stock': inStock, 'required': required, 'shortage': shortage};
  }
```

- [ ] **Step 4: Run tests — expect GREEN**, then full suite.

Run: `flutter test test/unit/bom_stock_customer_code_controller_test.dart` then `flutter analyze lib/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart` then `flutter test`.

- [ ] **Step 5: Commit**
```bash
git add lib/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart test/unit/bom_stock_customer_code_controller_test.dart
git commit -m "feat(manufacturing): BOM Stock segmented filter + shortage-based shortfall"
```

---

## Task R2: Rebuild `BomStockTile` (mirror POS item tile)

**Files:**
- Rewrite: `lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_tile.dart`
- Rewrite test: `test/widget/bom_stock_tile_test.dart`

**Interfaces consumed:** `BomStockCustomerCodeController.isShortfall`, `toNum`, `formatQty`.

- [ ] **Step 1: Rewrite the test (TDD).** Replace the entire contents of `test/widget/bom_stock_tile_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_tile.dart';

Widget _wrap(Map<String, dynamic> row) => MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 380, child: BomStockTile(row: row))),
      ),
    );

void main() {
  testWidgets('renders item name, code/group subline, customer-code chip, In Stock',
      (tester) async {
    await tester.pumpWidget(_wrap(const {
      'sl_no': '1',
      'item_name': 'STRAPS T/X PRINT 40mm',
      'item_code': '2001272',
      'item_group': 'Straps',
      'customer_code': '5052483',
      'in_stock_qty': 816,
    }));
    expect(find.text('STRAPS T/X PRINT 40mm'), findsOneWidget);
    expect(find.textContaining('2001272'), findsWidgets);
    expect(find.text('5052483'), findsOneWidget);
    expect(find.text('In Stock'), findsOneWidget);
    expect(find.text('816'), findsOneWidget);
  });

  testWidgets('no POS: hides Need/Short and the status pill', (tester) async {
    await tester.pumpWidget(_wrap(const {
      'sl_no': '1', 'item_name': 'X', 'item_code': 'X1', 'in_stock_qty': 10,
    }));
    expect(find.text('Need'), findsNothing);
    expect(find.text('Short'), findsNothing);
    expect(find.text('Covered'), findsNothing);
  });

  testWidgets('POS covered row: shows Need/Short stats + green Covered pill',
      (tester) async {
    await tester.pumpWidget(_wrap(const {
      'sl_no': '2', 'item_name': 'STRAPS', 'item_code': '2001272',
      'in_stock_qty': 816, 'required_qty': 36, 'shortage_qty': 0,
    }));
    expect(find.text('Need'), findsOneWidget);
    expect(find.text('Short'), findsOneWidget);
    expect(find.text('Covered'), findsOneWidget);
  });

  testWidgets('POS shortfall row: shows red Short pill with the deficit',
      (tester) async {
    await tester.pumpWidget(_wrap(const {
      'sl_no': '3', 'item_name': 'BELTS PU HQ', 'item_code': '2002843',
      'in_stock_qty': 396, 'required_qty': 2400, 'shortage_qty': 2004,
    }));
    expect(find.text('Short 2004'), findsOneWidget);
    expect(find.text('Covered'), findsNothing);
  });

  testWidgets('shows Build only when enough_parts_to_build present', (tester) async {
    await tester.pumpWidget(_wrap(const {
      'sl_no': '4', 'item_name': 'SUB', 'item_code': 'S1',
      'in_stock_qty': 5, 'enough_parts_to_build': 12, 'bom': 'BOM-S1-001',
    }));
    expect(find.text('Build'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('long BOM name does not overflow', (tester) async {
    await tester.pumpWidget(_wrap(const {
      'sl_no': '5', 'item_name': 'SUB ASSEMBLY ITEM', 'item_code': 'S2',
      'in_stock_qty': 1, 'bom': 'BOM-VERY-LONG-NAME-2001272-REV-003-EXTENDED',
    }));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run — expect RED** (`find.text('Covered')`/`'Need'`/`'Build'` etc. fail against the old tile). Run: `flutter test test/widget/bom_stock_tile_test.dart`

- [ ] **Step 3: Implement.** Replace the entire contents of `bom_stock_tile.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_format.dart';

/// One result card, mirroring the POS Upload form's item tile.
class BomStockTile extends StatelessWidget {
  final Map<String, dynamic> row;
  const BomStockTile({super.key, required this.row});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final shortfall = BomStockCustomerCodeController.isShortfall(row);

    final slNo      = (row['sl_no'] ?? '').toString();
    final itemName  = (row['item_name'] ?? '').toString();
    final itemCode  = (row['item_code'] ?? '').toString();
    final itemGroup = (row['item_group'] ?? '').toString();
    final custCode  = (row['customer_code'] ?? '').toString();
    final bom       = (row['bom'] ?? '').toString();
    final inStock   = toNum(row['in_stock_qty']);
    final reqNum    = toNum(row['required_qty']);
    final hasReq    = reqNum != null;
    final shortage  = toNum(row['shortage_qty']) ?? 0;
    final enough    = row['enough_parts_to_build'];

    final subline = [itemCode, itemGroup].where((s) => s.isNotEmpty).join(' · ');

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: shortfall ? cs.error : cs.outlineVariant),
      ),
      color: cs.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ───────────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: cs.primaryContainer,
                  child: Text(
                    slNo,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              itemName.isEmpty ? itemCode : itemName,
                              style: theme.textTheme.bodyLarge
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (hasReq) ...[
                            const SizedBox(width: 8),
                            _StatusPill(shortage: shortage),
                          ],
                        ],
                      ),
                      if (subline.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subline,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            // ── Stats ────────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatCell(label: 'In Stock', value: formatQty(inStock)),
                if (hasReq) _StatCell(label: 'Need', value: formatQty(reqNum)),
                if (hasReq)
                  _StatCell(label: 'Short', value: formatQty(shortage), alert: shortage > 0),
                if (enough != null)
                  _StatCell(label: 'Build', value: enough.toString()),
              ],
            ),
            // ── Chips ────────────────────────────────────────────────────
            if (custCode.isNotEmpty || bom.isNotEmpty) ...[
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final maxW = constraints.maxWidth;
                  return Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (custCode.isNotEmpty)
                        _chip(cs, Icons.qr_code_2, custCode, maxW),
                      if (bom.isNotEmpty)
                        _chip(cs, Icons.account_tree_outlined, bom, maxW),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(ColorScheme cs, IconData icon, String label, double maxWidth) =>
      ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
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
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      );
}

/// Demand status pill: red "Short N" or neutral-positive "Covered".
class _StatusPill extends StatelessWidget {
  final num shortage;
  const _StatusPill({required this.shortage});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final short = shortage > 0;
    final bg = short ? cs.errorContainer : cs.secondaryContainer;
    final fg = short ? cs.onErrorContainer : cs.onSecondaryContainer;
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

/// Label-over-value stat cell (mirrors the POS item tile's `_Stat`).
class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final bool alert;
  const _StatCell({required this.label, required this.value, this.alert = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: alert ? cs.error : null,
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run — expect GREEN**, then analyze + full suite. Run: `flutter test test/widget/bom_stock_tile_test.dart` then `flutter analyze lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_tile.dart` then `flutter test`.

- [ ] **Step 5: Commit**
```bash
git add lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_tile.dart test/widget/bom_stock_tile_test.dart
git commit -m "feat(manufacturing): rebuild BomStockTile to mirror POS item tile + status pill"
```

---

## Task R3: Rebuild `BomStockTotalsFooter` (computed totals)

**Files:**
- Rewrite: `lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_totals_footer.dart`
- Rewrite test: `test/widget/bom_stock_totals_footer_test.dart`

**Interface produced:** `const BomStockTotalsFooter({required Map<String,num>? totals, required bool hasDemand})`.

- [ ] **Step 1: Rewrite the test (TDD).** Replace `test/widget/bom_stock_totals_footer_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_totals_footer.dart';

void main() {
  testWidgets('renders nothing when totals is null', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: BomStockTotalsFooter(totals: null, hasDemand: true)),
    ));
    expect(find.text('Total'), findsNothing);
  });

  testWidgets('no demand: shows Stock only (no Need/Short)', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: BomStockTotalsFooter(
          totals: {'in_stock': 16239, 'required': 0, 'shortage': 0},
          hasDemand: false,
        ),
      ),
    ));
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('Stock'), findsOneWidget);
    expect(find.text('16239'), findsOneWidget);
    expect(find.text('Need'), findsNothing);
    expect(find.text('Short'), findsNothing);
  });

  testWidgets('with demand: shows Stock + Need + Short', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: BomStockTotalsFooter(
          totals: {'in_stock': 16239, 'required': 7644, 'shortage': 2004},
          hasDemand: true,
        ),
      ),
    ));
    expect(find.text('Stock'), findsOneWidget);
    expect(find.text('Need'), findsOneWidget);
    expect(find.text('Short'), findsOneWidget);
    expect(find.text('7644'), findsOneWidget);
    expect(find.text('2004'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run — expect RED** (constructor signature changed). Run: `flutter test test/widget/bom_stock_totals_footer_test.dart`

- [ ] **Step 3: Implement.** Replace `bom_stock_totals_footer.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_format.dart';

/// Sticky footer of in-stock / need / short totals over the filtered rows.
class BomStockTotalsFooter extends StatelessWidget {
  final Map<String, num>? totals;
  final bool hasDemand;
  const BomStockTotalsFooter({
    super.key,
    required this.totals,
    required this.hasDemand,
  });

  @override
  Widget build(BuildContext context) {
    final t = totals;
    if (t == null || t.isEmpty) return const SizedBox.shrink();
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
              _cell(theme, cs, 'Stock', formatQty(t['in_stock'])),
              if (hasDemand) _cell(theme, cs, 'Need', formatQty(t['required'])),
              if (hasDemand) _cell(theme, cs, 'Short', formatQty(t['shortage'])),
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

- [ ] **Step 4: Run — expect GREEN**, then analyze. (The screen still references the old signature — full `flutter test` will fail to compile until Task R4; run the focused footer test + analyze on the footer file only here.) Run: `flutter test test/widget/bom_stock_totals_footer_test.dart` then `flutter analyze lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_totals_footer.dart`.

- [ ] **Step 5: Commit**
```bash
git add lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_totals_footer.dart test/widget/bom_stock_totals_footer_test.dart
git commit -m "feat(manufacturing): BOM Stock footer shows Stock/Need/Short over filtered rows"
```

> Note: between R3 and R4 the screen does not compile (footer signature change). R4 finishes the wiring; do not run the full suite expecting green until R4 Step 4.

---

## Task R4: Segmented filter widget + screen wiring

**Files:**
- Modify: `lib/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_screen.dart`
- Modify test: `test/widget/bom_stock_screen_test.dart`

**Interfaces consumed:** `controller.rowFilter`, `setRowFilter`, `filteredRows`, `filteredTotals`, `posUpload`.

- [ ] **Step 1: Update the screen test (TDD).** In `test/widget/bom_stock_screen_test.dart`, add a third test inside `main` (keep the existing two):
```dart
  testWidgets('shows the All | In Stock | Shortage segmented filter when rows exist',
      (tester) async {
    final c = Get.find<BomStockCustomerCodeController>();
    c.reportRows.assignAll([
      {'sl_no': '1', 'item_name': 'BELTS PU HQ', 'item_code': '2002843', 'in_stock_qty': 396},
    ]);
    await tester.pumpWidget(const GetMaterialApp(home: BomStockCustomerCodeScreen()));
    await tester.pump();
    expect(find.text('All'), findsOneWidget);
    expect(find.text('In Stock'), findsWidgets);
    expect(find.text('Shortage'), findsOneWidget);
  });
```

- [ ] **Step 2: Run — expect RED** (segments not present). Run: `flutter test test/widget/bom_stock_screen_test.dart`

- [ ] **Step 3: Implement.** In `bom_stock_customer_code_screen.dart`:

(a) After the POS missing-codes banner sliver and before the `// ── Body` block, insert the segmented filter sliver:
```dart
                    // ── Segmented row filter ──────────────────────────────
                    if (!controller.isRunning.value &&
                        controller.reportRows.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          child: _SegmentedRowFilter(
                            value: controller.rowFilter.value,
                            onChanged: controller.setRowFilter,
                          ),
                        ),
                      ),
```

(b) In the body, replace the final `else` results branch (the `SliverPadding`/`SliverList` over `controller.reportRows`) with a filtered version that also handles "filter hides everything":
```dart
                    else if (controller.filteredRows.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              'No items match this filter',
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
                              child: BomStockTile(
                                  row: controller.filteredRows[index]),
                            ),
                            childCount: controller.filteredRows.length,
                          ),
                        ),
                      ),
```
(Keep the existing `if (controller.isRunning.value) … else if (controller.reportRows.isEmpty) …` arms ahead of these.)

(c) Replace the footer line:
```dart
            BomStockTotalsFooter(
              totals: controller.filteredTotals,
              hasDemand: controller.posUpload.value != null,
            ),
```

(d) Add the segmented widget at the bottom of the file (after the screen class), mirroring `stock_balance_screen.dart`'s `_SegmentedStateFilter`:
```dart
/// All | In Stock | Shortage — client-side segmented filter over the rows.
class _SegmentedRowFilter extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _SegmentedRowFilter({required this.value, required this.onChanged});

  static const _segments = [
    ('ALL', 'All'),
    ('instock', 'In Stock'),
    ('shortage', 'Shortage'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          for (final (val, label) in _segments)
            Expanded(
              child: InkWell(
                onTap: () => onChanged(val),
                borderRadius: BorderRadius.circular(8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: value == val ? cs.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: value == val ? cs.primary : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run — expect GREEN**, then analyze + FULL suite (compiles again now). Run: `flutter test test/widget/bom_stock_screen_test.dart` then `flutter analyze lib/app/modules/manufacturing/reports/bom_stock_customer_code` then `flutter test`.

- [ ] **Step 5: Commit**
```bash
git add lib/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_screen.dart test/widget/bom_stock_screen_test.dart
git commit -m "feat(manufacturing): wire segmented All/In-Stock/Shortage filter + filtered totals"
```

---

## Task R5: Verification

- [ ] **Step 1:** `flutter analyze lib/app/modules/manufacturing/reports/bom_stock_customer_code test/unit/bom_stock_customer_code_controller_test.dart test/widget/bom_stock_tile_test.dart test/widget/bom_stock_totals_footer_test.dart test/widget/bom_stock_screen_test.dart` — expect **No issues found**.
- [ ] **Step 2:** `flutter test` — expect all pass (no regressions).
- [ ] **Step 3 (manual, user):** on-device — cards mirror the POS item tile; segmented `All | In Stock | Shortage` filters the list; a POS-active row shows `Need`/`Short` + the red "Short N" / green "Covered" pill; footer shows Stock (and Need/Short when a POS Upload is active) over the filtered set; no overflow stripes.

## Self-Review

- Spec coverage: card mirror → R2; segmented filter → R1+R4; shortage-based shortfall → R1; footer over filtered rows → R1(sums)+R3+R4; customer name removed / thumbnail removed → R2; tests → each task. ✓
- Placeholder scan: none. Type consistency: `rowFilter`/`setRowFilter`/`applyRowFilter`/`filteredRows`/`sumTotals`/`filteredTotals`/`isShortfall`/`BomStockTotalsFooter({totals,hasDemand})`/`_SegmentedRowFilter` consistent across producing and consuming tasks. ✓
- Cross-task compile gap (R3→R4) is called out explicitly so a reviewer doesn't flag the intermediate red. ✓
