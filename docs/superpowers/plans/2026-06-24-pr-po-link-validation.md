# Purchase Receipt PO-Link Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the 417 "Invalid reference Purchase Order Item" save failure by validating each Purchase Receipt item's `purchase_order_item` against live PO data — auto-linking when unambiguous, prompting a picker when not, and blocking (with an Allow Over-Receipt escape) when no open PO line exists.

**Architecture:** A pure resolver (`resolvePoLinkFor`) holds all linking rules and returns auto-link / picker / block. The PR form controller wraps it over its cached PO rows; the item-form controller calls it at submit time (proactive) and carries an `allowOverReceipt` toggle mirroring the Delivery Note "Allow Full" pattern. `saveDocument` gains a one-shot reactive safety net that detects the 417, re-fetches the PO fresh, re-links the offending items, and re-saves once. A new bottom sheet renders the picker.

**Tech Stack:** Flutter, GetX, Dio, ERPNext/Frappe REST. Tests via `flutter_test`.

## Global Constraints

- Maroon design system (`#870E18`) — use `Theme.of(context).colorScheme`, never hardcode brand colors.
- GetX patterns: observables `.obs`, controllers extend existing bases, no new permanent services.
- Notifications: `AppNotification.*` in the form controller; `GlobalSnackbar.*` in the item controller (match each file's existing convention).
- The reactive re-save runs **at most once** per save attempt (loop guard).
- Drop the current silent fallback that links to ANY PO row including fully-received ones.
- No server-side ERPNext changes. The app only guarantees a *valid* reference; ERPNext still enforces its own over-receipt tolerance on submit.

---

### Task 1: Pure resolver, qty ceiling, and 417 parser

**Files:**
- Create: `lib/app/modules/purchase_receipt/form/po_link_resolver.dart`
- Test: `test/unit/po_link_resolver_test.dart`

**Interfaces:**
- Consumes: `PurchaseOrderItem` from `lib/app/data/models/purchase_order_model.dart` (`name`, `itemCode`, `itemName`, `qty`, `receivedQty`, `rate`, `amount`).
- Produces:
  - `class PoLinkCandidate { String poName; PurchaseOrderItem item; bool get isOpen; }`
  - `enum PoLinkOutcome { autoLinked, needsPicker, blocked }`
  - `class PoLinkResult` with `outcome`, `linked`, `candidates`, `allForItem`, `reason` and factories `autoLinked/needsPicker/blocked`.
  - `PoLinkResult resolvePoLinkFor(List<PoLinkCandidate> cached, String itemCode, {required bool allowOverReceipt})`
  - `double poQtyCeiling(double? poQty, {required bool allowOverReceipt})`
  - `Set<String> parseInvalidPoItemRefs(String message)`
  - `class PoLinkAbortedException implements Exception`

- [ ] **Step 1: Write the failing test**

Create `test/unit/po_link_resolver_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/modules/purchase_receipt/form/po_link_resolver.dart';

PoLinkCandidate _cand(
  String po,
  String code, {
  double qty = 10,
  double received = 0,
  String name = 'row',
}) =>
    PoLinkCandidate(
      po,
      PurchaseOrderItem(
        name: name,
        itemCode: code,
        itemName: code,
        qty: qty,
        receivedQty: received,
        rate: 1,
        amount: qty,
      ),
    );

void main() {
  group('resolvePoLinkFor', () {
    test('single open candidate auto-links', () {
      final r = resolvePoLinkFor(
          [_cand('PO1', 'A', name: 'r1')], 'A', allowOverReceipt: false);
      expect(r.outcome, PoLinkOutcome.autoLinked);
      expect(r.linked!.item.name, 'r1');
    });

    test('multiple open candidates need picker', () {
      final r = resolvePoLinkFor([
        _cand('PO1', 'A', name: 'r1'),
        _cand('PO2', 'A', name: 'r2'),
      ], 'A', allowOverReceipt: false);
      expect(r.outcome, PoLinkOutcome.needsPicker);
      expect(r.candidates.length, 2);
    });

    test('zero open candidates blocked when toggle off', () {
      final r = resolvePoLinkFor([
        _cand('PO1', 'A', qty: 10, received: 10, name: 'r1'),
      ], 'A', allowOverReceipt: false);
      expect(r.outcome, PoLinkOutcome.blocked);
      expect(r.reason, contains('Allow Over-Receipt'));
    });

    test('fully-received candidate eligible when toggle on', () {
      final r = resolvePoLinkFor([
        _cand('PO1', 'A', qty: 10, received: 10, name: 'r1'),
      ], 'A', allowOverReceipt: true);
      expect(r.outcome, PoLinkOutcome.autoLinked);
      expect(r.linked!.item.name, 'r1');
    });

    test('item absent from all POs is blocked regardless of toggle', () {
      final r = resolvePoLinkFor(
          [_cand('PO1', 'B', name: 'r1')], 'A', allowOverReceipt: true);
      expect(r.outcome, PoLinkOutcome.blocked);
      expect(r.reason, contains('any linked Purchase Order'));
    });

    test('allForItem carries every row for the item_code', () {
      final r = resolvePoLinkFor([
        _cand('PO1', 'A', qty: 10, received: 10, name: 'r1'),
        _cand('PO1', 'A', name: 'r2'),
        _cand('PO1', 'B', name: 'r3'),
      ], 'A', allowOverReceipt: false);
      expect(r.allForItem.map((c) => c.item.name), ['r1', 'r2']);
    });
  });

  group('poQtyCeiling', () {
    test('caps at PO qty when toggle off', () {
      expect(poQtyCeiling(5, allowOverReceipt: false), 5);
    });
    test('infinite when toggle on', () {
      expect(poQtyCeiling(5, allowOverReceipt: true), double.infinity);
    });
    test('infinite when no PO qty', () {
      expect(poQtyCeiling(null, allowOverReceipt: false), double.infinity);
    });
  });

  group('parseInvalidPoItemRefs', () {
    test('extracts a single row name', () {
      final s = parseInvalidPoItemRefs(
          'frappe.exceptions.ValidationError: Invalid reference '
          'Purchase Order Item h03g3r24ji');
      expect(s, {'h03g3r24ji'});
    });
    test('extracts multiple distinct names', () {
      final s = parseInvalidPoItemRefs(
          'Invalid reference Purchase Order Item aaa111 ... '
          'Invalid reference Purchase Order Item bbb222');
      expect(s, {'aaa111', 'bbb222'});
    });
    test('returns empty when no match', () {
      expect(parseInvalidPoItemRefs('some other error'), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/po_link_resolver_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'po_link_resolver.dart'` / undefined names.

- [ ] **Step 3: Write the implementation**

Create `lib/app/modules/purchase_receipt/form/po_link_resolver.dart`:

```dart
import 'package:multimax/app/data/models/purchase_order_model.dart';

/// One cached Purchase Order row paired with its source PO name.
class PoLinkCandidate {
  final String poName;
  final PurchaseOrderItem item;
  const PoLinkCandidate(this.poName, this.item);

  /// A row still has open quantity to receive against.
  bool get isOpen => item.receivedQty < item.qty;
}

enum PoLinkOutcome { autoLinked, needsPicker, blocked }

/// Result of resolving a Purchase Order Item reference for a scanned item.
class PoLinkResult {
  final PoLinkOutcome outcome;

  /// Set for [PoLinkOutcome.autoLinked].
  final PoLinkCandidate? linked;

  /// Eligible rows for [PoLinkOutcome.needsPicker].
  final List<PoLinkCandidate> candidates;

  /// Every cached row for the item_code (open + closed) — what the picker shows.
  final List<PoLinkCandidate> allForItem;

  /// Human-readable reason for [PoLinkOutcome.blocked].
  final String? reason;

  const PoLinkResult._({
    required this.outcome,
    this.linked,
    this.candidates = const [],
    this.allForItem = const [],
    this.reason,
  });

  factory PoLinkResult.autoLinked(
          PoLinkCandidate row, List<PoLinkCandidate> all) =>
      PoLinkResult._(
          outcome: PoLinkOutcome.autoLinked, linked: row, allForItem: all);

  factory PoLinkResult.needsPicker(
          List<PoLinkCandidate> eligible, List<PoLinkCandidate> all) =>
      PoLinkResult._(
          outcome: PoLinkOutcome.needsPicker,
          candidates: eligible,
          allForItem: all);

  factory PoLinkResult.blocked(String reason, List<PoLinkCandidate> all) =>
      PoLinkResult._(
          outcome: PoLinkOutcome.blocked, reason: reason, allForItem: all);
}

/// Resolves which cached Purchase Order row an item should link to.
///
/// Rules (design 2026-06-24, Section 1):
///   - Candidates = cached rows with matching item_code.
///   - Open candidates have received_qty < qty.
///   - Closed rows (received_qty >= qty) are eligible only when
///     [allowOverReceipt] is true.
///   - 1 eligible -> autoLinked; >=2 -> needsPicker; 0 -> blocked.
PoLinkResult resolvePoLinkFor(
  List<PoLinkCandidate> cached,
  String itemCode, {
  required bool allowOverReceipt,
}) {
  final all = cached.where((c) => c.item.itemCode == itemCode).toList();
  if (all.isEmpty) {
    return PoLinkResult.blocked(
      'No Purchase Order line for $itemCode on any linked Purchase Order.',
      all,
    );
  }

  final open = all.where((c) => c.isOpen).toList();
  final eligible = allowOverReceipt ? all : open;

  if (eligible.isEmpty) {
    return PoLinkResult.blocked(
      'No open Purchase Order line for $itemCode on ${all.first.poName} — '
      'enable Allow Over-Receipt to receive against a closed line.',
      all,
    );
  }
  if (eligible.length == 1) {
    return PoLinkResult.autoLinked(eligible.first, all);
  }
  return PoLinkResult.needsPicker(eligible, all);
}

/// Qty ceiling for the qty field. Over-receipt lifts the PO cap entirely.
double poQtyCeiling(double? poQty, {required bool allowOverReceipt}) {
  if (allowOverReceipt) return double.infinity;
  if (poQty != null && poQty > 0) return poQty;
  return double.infinity;
}

/// Extracts offending PO Item row names from an ERPNext 417 exception string.
/// Matches `Invalid reference Purchase Order Item <name>` (name is a Frappe
/// hash: word chars and dashes), stopping cleanly before the closing JSON `"`.
Set<String> parseInvalidPoItemRefs(String message) {
  final re = RegExp(r'Invalid reference Purchase Order Item ([\w-]+)');
  return re.allMatches(message).map((m) => m.group(1)!).toSet();
}

/// Thrown from item-sheet submit when the user cancels the link picker or the
/// item is blocked — keeps the sheet open (submitWithFeedback returns false).
class PoLinkAbortedException implements Exception {
  const PoLinkAbortedException();
  @override
  String toString() => 'PoLinkAbortedException';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/po_link_resolver_test.dart`
Expected: PASS (all groups green).

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/purchase_receipt/form/po_link_resolver.dart test/unit/po_link_resolver_test.dart
git commit -m "feat(pr): pure PO-link resolver, qty ceiling, and 417 parser"
```

---

### Task 2: Allow Over-Receipt toggle + qty-cap guard on the item controller

**Files:**
- Modify: `lib/app/modules/purchase_receipt/form/purchase_receipt_item_form_controller.dart`

**Interfaces:**
- Consumes: `poQtyCeiling` from Task 1.
- Produces: `RxBool allowOverReceipt` on `PurchaseReceiptItemFormController`; `effectiveMaxQty` now honors it.

- [ ] **Step 1: Add the resolver import**

At the top of `purchase_receipt_item_form_controller.dart`, with the other `package:multimax/...` imports:

```dart
import 'package:multimax/app/modules/purchase_receipt/form/po_link_resolver.dart';
```

- [ ] **Step 2: Add the `allowOverReceipt` field**

Immediately after the PO link metadata block (after `final RxnDouble poRate = RxnDouble();`, ~line 157):

```dart
  /// When true, the qty cap is lifted and fully-received PO rows become
  /// linkable. Mirrors Delivery Note's `allowFullSerials`. Reset on each
  /// sheet open.
  final RxBool allowOverReceipt = false.obs;
```

- [ ] **Step 3: Route `effectiveMaxQty` through `poQtyCeiling`**

Replace the existing getter (~lines 136-141):

```dart
  @override
  double get effectiveMaxQty {
    final po = poQty.value;
    if (po != null && po > 0) return po;
    return double.infinity;
  }
```

with:

```dart
  @override
  double get effectiveMaxQty =>
      poQtyCeiling(poQty.value, allowOverReceipt: allowOverReceipt.value);
```

- [ ] **Step 4: Reset the toggle on every sheet open**

In `initForCreate`, in the PO reset block (after `poRate.value = null;`, ~line 302) add:

```dart
    allowOverReceipt.value = false;
```

In `initForEdit`, immediately after `poRate.value = ...;` (~line 336) add:

```dart
    allowOverReceipt.value = false;
```

- [ ] **Step 5: Verify it compiles**

Run: `flutter analyze lib/app/modules/purchase_receipt/form/purchase_receipt_item_form_controller.dart`
Expected: No new errors (pre-existing infos/warnings unchanged). The qty-cap logic itself is covered by the `poQtyCeiling` tests from Task 1.

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/purchase_receipt/form/purchase_receipt_item_form_controller.dart
git commit -m "feat(pr-item): Allow Over-Receipt toggle lifts PO qty cap"
```

---

### Task 3: Link-picker bottom sheet + `showPoLinkPicker`

**Files:**
- Create: `lib/app/modules/purchase_receipt/form/widgets/purchase_receipt_po_link_sheet.dart`
- Modify: `lib/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart`
- Test: `test/widget/purchase_receipt_po_link_sheet_test.dart`

**Interfaces:**
- Consumes: `PoLinkCandidate` (Task 1).
- Produces:
  - Widget `PurchaseReceiptPoLinkSheet({required String itemCode, required List<PoLinkCandidate> candidates, required bool initialAllowOverReceipt})` — pops a `PoLinkCandidate?` via `Navigator.pop`.
  - `Future<PoLinkCandidate?> showPoLinkPicker({required String itemCode, required List<PoLinkCandidate> candidates, required bool initialAllowOverReceipt})` on `PurchaseReceiptFormController`.

- [ ] **Step 1: Write the failing widget test**

Create `test/widget/purchase_receipt_po_link_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/modules/purchase_receipt/form/po_link_resolver.dart';
import 'package:multimax/app/modules/purchase_receipt/form/widgets/purchase_receipt_po_link_sheet.dart';

PoLinkCandidate _cand(String name,
        {double qty = 10, double received = 0}) =>
    PoLinkCandidate(
      'PO1',
      PurchaseOrderItem(
        name: name,
        itemCode: 'A',
        itemName: 'Item A',
        qty: qty,
        receivedQty: received,
        rate: 1,
        amount: qty,
      ),
    );

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('open rows are tappable; closed rows hidden until toggle on',
      (tester) async {
    await tester.pumpWidget(_host(
      PurchaseReceiptPoLinkSheet(
        itemCode: 'A',
        candidates: [
          _cand('open1'),
          _cand('closed1', qty: 10, received: 10),
        ],
        initialAllowOverReceipt: false,
      ),
    ));
    await tester.pumpAndSettle();

    // Open row visible.
    expect(find.textContaining('open1'), findsOneWidget);
    // Closed row hidden while toggle off.
    expect(find.textContaining('closed1'), findsNothing);

    // Toggle on -> closed row appears.
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.textContaining('closed1'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/purchase_receipt_po_link_sheet_test.dart`
Expected: FAIL — `PurchaseReceiptPoLinkSheet` undefined.

- [ ] **Step 3: Create the picker widget**

Create `lib/app/modules/purchase_receipt/form/widgets/purchase_receipt_po_link_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:multimax/app/modules/purchase_receipt/form/po_link_resolver.dart';

/// Bottom sheet that lets the operator link a Purchase Receipt item to a valid
/// Purchase Order Item row. Open rows are always selectable; fully-received
/// rows are revealed only when the Allow Over-Receipt switch is on.
///
/// Pops the chosen [PoLinkCandidate] (or null when dismissed).
class PurchaseReceiptPoLinkSheet extends StatefulWidget {
  final String itemCode;
  final List<PoLinkCandidate> candidates;
  final bool initialAllowOverReceipt;

  const PurchaseReceiptPoLinkSheet({
    super.key,
    required this.itemCode,
    required this.candidates,
    required this.initialAllowOverReceipt,
  });

  @override
  State<PurchaseReceiptPoLinkSheet> createState() =>
      _PurchaseReceiptPoLinkSheetState();
}

class _PurchaseReceiptPoLinkSheetState
    extends State<PurchaseReceiptPoLinkSheet> {
  late bool _allowOverReceipt = widget.initialAllowOverReceipt;

  String _fmt(double v) =>
      v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final hasClosed = widget.candidates.any((c) => !c.isOpen);
    final shown = _allowOverReceipt
        ? widget.candidates
        : widget.candidates.where((c) => c.isOpen).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28.0)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                alignment: Alignment.center,
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Link ${widget.itemCode} to a PO line',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(
                        backgroundColor: cs.surfaceContainerHigh,
                        foregroundColor: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasClosed)
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20),
                  dense: true,
                  title: const Text('Allow Over-Receipt'),
                  subtitle:
                      const Text('Show fully-received PO lines'),
                  value: _allowOverReceipt,
                  onChanged: (v) =>
                      setState(() => _allowOverReceipt = v),
                ),
              Divider(height: 1, color: cs.outlineVariant),
              Expanded(
                child: shown.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.link_off,
                                  size: 56, color: cs.outlineVariant),
                              const SizedBox(height: 16),
                              Text(
                                'No open Purchase Order line',
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (hasClosed) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Enable Allow Over-Receipt to receive '
                                  'against a closed line.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(
                                          color: cs.onSurfaceVariant),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: EdgeInsets.only(
                          bottom:
                              MediaQuery.of(context).padding.bottom + 16,
                        ),
                        itemCount: shown.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          indent: 20,
                          endIndent: 16,
                          color: cs.outlineVariant.withValues(alpha: 0.5),
                        ),
                        itemBuilder: (context, index) {
                          final c = shown[index];
                          final remaining =
                              (c.item.qty - c.item.receivedQty)
                                  .clamp(0, double.infinity)
                                  .toDouble();
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 4),
                            leading: CircleAvatar(
                              backgroundColor: c.isOpen
                                  ? cs.primaryContainer
                                  : cs.surfaceContainerHighest,
                              foregroundColor: c.isOpen
                                  ? cs.onPrimaryContainer
                                  : cs.onSurfaceVariant,
                              child: Icon(
                                c.isOpen
                                    ? Icons.inventory_2_outlined
                                    : Icons.check_circle_outline,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              '${c.poName} • ${c.item.name}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                                color: cs.onSurface,
                              ),
                            ),
                            subtitle: Text(
                              'Ordered ${_fmt(c.item.qty)} • '
                              'Received ${_fmt(c.item.receivedQty)} • '
                              'Remaining ${_fmt(remaining)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            trailing: Icon(Icons.chevron_right,
                                color: cs.onSurfaceVariant),
                            onTap: () => Navigator.of(context).pop(c),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/purchase_receipt_po_link_sheet_test.dart`
Expected: PASS.

- [ ] **Step 5: Add `showPoLinkPicker` to the form controller**

In `purchase_receipt_form_controller.dart`, add the import near the other module imports:

```dart
import 'package:multimax/app/modules/purchase_receipt/form/po_link_resolver.dart';
import 'package:multimax/app/modules/purchase_receipt/form/widgets/purchase_receipt_po_link_sheet.dart';
```

Add this method in the "PO linking" section (after `linkToPurchaseOrder`, ~line 328):

```dart
  /// Opens the link picker and returns the chosen PO row (null if dismissed).
  Future<PoLinkCandidate?> showPoLinkPicker({
    required String itemCode,
    required List<PoLinkCandidate> candidates,
    required bool initialAllowOverReceipt,
  }) {
    return Get.bottomSheet<PoLinkCandidate>(
      PurchaseReceiptPoLinkSheet(
        itemCode: itemCode,
        candidates: candidates,
        initialAllowOverReceipt: initialAllowOverReceipt,
      ),
      isScrollControlled: true,
    );
  }
```

- [ ] **Step 6: Verify compile + commit**

Run: `flutter analyze lib/app/modules/purchase_receipt/form/`
Expected: no new errors.

```bash
git add lib/app/modules/purchase_receipt/form/widgets/purchase_receipt_po_link_sheet.dart lib/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart test/widget/purchase_receipt_po_link_sheet_test.dart
git commit -m "feat(pr): PO-link picker sheet + showPoLinkPicker"
```

---

### Task 4: Resolver-backed linking in the form controller

**Files:**
- Modify: `lib/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart`

**Interfaces:**
- Consumes: `resolvePoLinkFor`, `PoLinkCandidate`, `PoLinkResult`, `PoLinkOutcome` (Task 1); `PurchaseReceiptItemFormController.allowOverReceipt` (Task 2).
- Produces:
  - `PoLinkResult resolvePoLink(String itemCode, {required bool allowOverReceipt})`
  - `void applyPoLink(PurchaseReceiptItemFormController child, PoLinkCandidate c)`
  - `linkToPurchaseOrder` reimplemented over the resolver (same signature, same call sites).

- [ ] **Step 1: Add `resolvePoLink` + `applyPoLink`**

In the "PO linking" section of `purchase_receipt_form_controller.dart`, add:

```dart
  /// Resolves a valid PO Item row for [itemCode] against the cached PO rows.
  PoLinkResult resolvePoLink(String itemCode,
      {required bool allowOverReceipt}) {
    final cands = _cachedPoItems
        .map((d) =>
            PoLinkCandidate(d['poName'] as String, d['item'] as PurchaseOrderItem))
        .toList();
    return resolvePoLinkFor(cands, itemCode,
        allowOverReceipt: allowOverReceipt);
  }

  /// Writes a resolved PO row onto the item-sheet controller.
  void applyPoLink(
      PurchaseReceiptItemFormController child, PoLinkCandidate c) {
    child.poItemId.value = c.item.name ?? '';
    child.poDocName.value = c.poName;
    child.poQty.value = c.item.qty;
    child.poRate.value = c.item.rate;
  }
```

> Note: `PurchaseReceiptItemFormController` is already imported at the top of this file (line 16). `PurchaseOrderItem` is imported via `purchase_order_model.dart` (line 10).

- [ ] **Step 2: Reimplement `linkToPurchaseOrder` over the resolver**

Replace the whole existing method (~lines 310-328):

```dart
  void linkToPurchaseOrder(
      String itemCode, PurchaseReceiptItemFormController child) {
    var match = _cachedPoItems.firstWhereOrNull((d) {
      final PurchaseOrderItem item = d['item'];
      return item.itemCode == itemCode && item.receivedQty < item.qty;
    });
    match ??= _cachedPoItems.firstWhereOrNull((d) {
      final PurchaseOrderItem item = d['item'];
      return item.itemCode == itemCode;
    });

    if (match != null) {
      final PurchaseOrderItem item = match['item'];
      child.poItemId.value  = item.name  ?? '';
      child.poDocName.value = match['poName'];
      child.poQty.value     = item.qty;
      child.poRate.value    = item.rate;
    }
  }
```

with:

```dart
  /// Best-effort PO link used when the sheet opens, so the PO Qty chip and
  /// progress bar populate. Final authority is the submit-time resolve in
  /// PurchaseReceiptItemFormController.submit(). Never links a closed row
  /// here (toggle defaults off); blocked items are simply left unlinked.
  void linkToPurchaseOrder(
      String itemCode, PurchaseReceiptItemFormController child) {
    final result =
        resolvePoLink(itemCode, allowOverReceipt: child.allowOverReceipt.value);
    switch (result.outcome) {
      case PoLinkOutcome.autoLinked:
        applyPoLink(child, result.linked!);
      case PoLinkOutcome.needsPicker:
        applyPoLink(child, result.candidates.first);
      case PoLinkOutcome.blocked:
        break;
    }
  }
```

- [ ] **Step 3: Verify compile**

Run: `flutter analyze lib/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart`
Expected: no new errors. (`firstWhereOrNull` may now be unused — if analyze flags the `package:get` import or a lint, leave the import; it is used elsewhere in the file.)

- [ ] **Step 4: Commit**

```bash
git add lib/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart
git commit -m "refactor(pr): route linkToPurchaseOrder through the resolver"
```

---

### Task 5: Proactive resolve at submit + in-sheet Allow Over-Receipt switch

**Files:**
- Modify: `lib/app/modules/purchase_receipt/form/purchase_receipt_item_form_controller.dart`
- Modify: `lib/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart`

**Interfaces:**
- Consumes: `resolvePoLink`, `applyPoLink`, `showPoLinkPicker` (Tasks 3-4); `PoLinkAbortedException`, `PoLinkOutcome` (Task 1).

- [ ] **Step 1: Resolve before adding in `submit()`**

In `purchase_receipt_item_form_controller.dart`, replace the entire `submit()` method (~lines 255-277):

```dart
  @override
  Future<void> submit() async {
    final qty       = double.tryParse(qtyController.text) ?? 0.0;
    final batch     = batchController.text.trim();
    final rack      = rackController.text.trim();
    final warehouse = resolvedWarehouse ?? '';

    if (editingItemName.value != null) {
      parent.updateItem(
        editingItemName.value!, qty, batch, rack, warehouse,
      );
    } else {
      parent.addItem(
        itemCode.value, itemName.value, qty, batch, rack, warehouse,
        uom:       itemUom.value,
        poItemId:  poItemId.value,
        poDocName: poDocName.value,
        poQty:     poQty.value  ?? 0.0,
        poRate:    poRate.value ?? 0.0,
      );
    }
    await parent.saveDocument();
  }
```

with:

```dart
  @override
  Future<void> submit() async {
    final qty       = double.tryParse(qtyController.text) ?? 0.0;
    final batch     = batchController.text.trim();
    final rack      = rackController.text.trim();
    final warehouse = resolvedWarehouse ?? '';

    if (editingItemName.value != null) {
      parent.updateItem(editingItemName.value!, qty, batch, rack, warehouse);
      await parent.saveDocument();
      return;
    }

    // Resolve a VALID Purchase Order Item before adding (design Section 3).
    final result = parent.resolvePoLink(itemCode.value,
        allowOverReceipt: allowOverReceipt.value);
    switch (result.outcome) {
      case PoLinkOutcome.autoLinked:
        parent.applyPoLink(this, result.linked!);
      case PoLinkOutcome.needsPicker:
        final chosen = await parent.showPoLinkPicker(
          itemCode: itemCode.value,
          candidates: result.allForItem,
          initialAllowOverReceipt: allowOverReceipt.value,
        );
        if (chosen == null) throw const PoLinkAbortedException();
        parent.applyPoLink(this, chosen);
      case PoLinkOutcome.blocked:
        GlobalSnackbar.error(message: result.reason!);
        throw const PoLinkAbortedException();
    }

    parent.addItem(
      itemCode.value, itemName.value, qty, batch, rack, warehouse,
      uom:       itemUom.value,
      poItemId:  poItemId.value,
      poDocName: poDocName.value,
      poQty:     poQty.value  ?? 0.0,
      poRate:    poRate.value ?? 0.0,
    );
    await parent.saveDocument();
  }
```

> `GlobalSnackbar` is already imported (line 8). `PoLinkAbortedException`/`PoLinkOutcome` come from the resolver import added in Task 2 Step 1.

- [ ] **Step 2: Add the in-sheet Allow Over-Receipt switch**

In `purchase_receipt_form_controller.dart`, in `_openItemSheet`, append a third entry to the `customFields:` list (after the `SharedRackField`, ~line 519). The list currently ends:

```dart
            SharedRackField(
              c:           child,
              accentColor: Colors.green,
              label:       'Target Rack',
              hint:        'Rack',
              editMode:    true,
              balanceOverride: () => null,
            ),
          ],
```

becomes:

```dart
            SharedRackField(
              c:           child,
              accentColor: Colors.green,
              label:       'Target Rack',
              hint:        'Rack',
              editMode:    true,
              balanceOverride: () => null,
            ),
            Obx(() => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Allow Over-Receipt'),
                  subtitle: const Text(
                      'Receive above ordered qty / against closed PO lines'),
                  value: child.allowOverReceipt.value,
                  onChanged: (v) {
                    child.allowOverReceipt.value = v;
                    child.validateSheet();
                  },
                )),
          ],
```

- [ ] **Step 3: Verify compile**

Run: `flutter analyze lib/app/modules/purchase_receipt/form/`
Expected: no new errors.

- [ ] **Step 4: Commit**

```bash
git add lib/app/modules/purchase_receipt/form/purchase_receipt_item_form_controller.dart lib/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart
git commit -m "feat(pr): proactive PO-link resolve at Add Item + in-sheet over-receipt switch"
```

---

### Task 6: Reactive 417 safety net in `saveDocument`

**Files:**
- Modify: `lib/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart`

**Interfaces:**
- Consumes: `parseInvalidPoItemRefs`, `resolvePoLink`, `showPoLinkPicker`, `PoLinkOutcome` (Tasks 1, 3, 4).

- [ ] **Step 1: Add the recovery guard field**

Near the other form-controller fields (e.g. just below `final List<Map<String, dynamic>> _cachedPoItems = [];`, ~line 81), add:

```dart
  /// Re-entrancy guard so the 417 PO-link recovery re-save runs at most once.
  bool _poLinkRecoveryAttempted = false;
```

- [ ] **Step 2: Branch the DioException handler to recovery**

In `saveDocument`, change the `on DioException catch (e)` block (~lines 658-673). Currently:

```dart
    } on DioException catch (e) {
      if (handleVersionConflict(e)) {
        // handled by OptimisticLockingMixin
      } else {
        _setSaveResult(SaveResult.error);
        String msg = 'Save failed';
        if (e.response?.data is Map) {
          if (e.response!.data['exception'] != null) {
            msg = e.response!.data['exception']
                .toString().split(':').last.trim();
          } else if (e.response!.data['_server_messages'] != null) {
            msg = 'Validation Error: Check form details';
          }
        }
        AppNotification.error(msg);
      }
    } catch (e) {
```

becomes:

```dart
    } on DioException catch (e) {
      if (handleVersionConflict(e)) {
        // handled by OptimisticLockingMixin
      } else if (await _maybeRecoverInvalidPoRef(e)) {
        // 417 invalid PO ref handled: re-linked + re-saved, or surfaced.
      } else {
        _setSaveResult(SaveResult.error);
        String msg = 'Save failed';
        if (e.response?.data is Map) {
          if (e.response!.data['exception'] != null) {
            msg = e.response!.data['exception']
                .toString().split(':').last.trim();
          } else if (e.response!.data['_server_messages'] != null) {
            msg = 'Validation Error: Check form details';
          }
        }
        AppNotification.error(msg);
      }
    } catch (e) {
```

- [ ] **Step 3: Implement `_maybeRecoverInvalidPoRef`**

Add this method immediately after `saveDocument` (after its closing brace, ~line 680):

```dart
  /// Reactive safety net for the 417 "Invalid reference Purchase Order Item"
  /// failure (design Section 4). Re-fetches the linked PO(s) fresh, re-links
  /// the offending items via the resolver, then re-saves ONCE. Returns true
  /// when the failure was a PO-ref problem this method handled (re-saved or
  /// surfaced its own message), false to let the caller show the generic error.
  Future<bool> _maybeRecoverInvalidPoRef(DioException e) async {
    if (_poLinkRecoveryAttempted) return false;
    if (e.response?.statusCode != 417) return false;
    final data = e.response?.data;
    final exc = (data is Map ? data['exception']?.toString() : null) ?? '';
    final badRefs = parseInvalidPoItemRefs(exc);
    if (badRefs.isEmpty) return false;

    _poLinkRecoveryAttempted = true;
    isSaving.value = false; // release the save lock before re-entrant save

    try {
      // Re-fetch linked POs fresh to drop stale child-row names.
      final poNames = purchaseReceipt.value?.items
              .map((i) => i.purchaseOrder)
              .whereType<String>()
              .where((n) => n.isNotEmpty)
              .toSet()
              .toList() ??
          <String>[];
      await _fetchLinkedPurchaseOrders(poNames);

      final items = purchaseReceipt.value?.items.toList() ?? [];
      for (var i = 0; i < items.length; i++) {
        final it = items[i];
        if (it.purchaseOrderItem == null ||
            !badRefs.contains(it.purchaseOrderItem)) {
          continue;
        }
        final result =
            resolvePoLink(it.itemCode, allowOverReceipt: false);
        PoLinkCandidate? chosen;
        switch (result.outcome) {
          case PoLinkOutcome.autoLinked:
            chosen = result.linked;
          case PoLinkOutcome.needsPicker:
          case PoLinkOutcome.blocked:
            chosen = await showPoLinkPicker(
              itemCode: it.itemCode,
              candidates: result.allForItem,
              initialAllowOverReceipt: false,
            );
        }
        if (chosen == null) {
          AppNotification.error(
              'Could not link ${it.itemCode} to a valid Purchase Order Item.');
          return true; // handled (surfaced message); do not re-save
        }
        items[i] = it.copyWith(
          purchaseOrderItem: chosen.item.name,
          purchaseOrder: chosen.poName,
          purchaseOrderQty: chosen.item.qty,
        );
      }
      _rebuildReceipt(items);

      await saveDocument(); // single re-save
      return true;
    } finally {
      _poLinkRecoveryAttempted = false;
    }
  }
```

- [ ] **Step 4: Verify compile**

Run: `flutter analyze lib/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart`
Expected: no new errors. (The 417 parser logic is already covered by Task 1's `parseInvalidPoItemRefs` tests.)

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/purchase_receipt/form/purchase_receipt_form_controller.dart
git commit -m "feat(pr): one-shot 417 recovery — re-fetch PO, re-link, re-save"
```

---

### Task 7: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Analyze the whole module**

Run: `flutter analyze`
Expected: no new errors introduced by this work (compare against the pre-existing baseline; record any pre-existing items).

- [ ] **Step 2: Run the new tests**

Run: `flutter test test/unit/po_link_resolver_test.dart test/widget/purchase_receipt_po_link_sheet_test.dart`
Expected: all PASS.

- [ ] **Step 3: Run the full suite for regressions**

Run: `flutter test`
Expected: no NEW failures. (Per project memory, `status_pill` / `doctype_form_header` failures pre-exist on `release/play-store` — confirm those are the only reds and unrelated to this change.)

- [ ] **Step 4: On-device smoke (manual, by the user)**

Scenario from the bug report: open a Draft Purchase Receipt created from a PO, scan an item, set batch/rack/qty, Add Item, then save. Verify:
1. An item with one open PO line auto-links and saves with no 417.
2. Forcing a stale link (or an amended PO) triggers the recovery picker instead of a hard 417.
3. Toggling Allow Over-Receipt lets qty exceed ordered and links a fully-received line.

---

## Self-Review

**Spec coverage:**
- Section 1 (resolver rules) → Task 1 (`resolvePoLinkFor`).
- Section 2 (over-receipt toggle, qty-cap bypass, reset on open) → Task 2 + Task 5 Step 2 (in-sheet switch).
- Section 3 (proactive Add Item) → Task 5 Step 1.
- Section 4 (reactive 417 net, re-fetch, one-shot re-save) → Task 6.
- Section 5 (picker sheet) → Task 3.
- Section 6 (error-handling matrix) → covered across resolver (Task 1) + submit (Task 5) + recovery (Task 6).
- Testing section → Tasks 1, 3, 7.

**Placeholder scan:** none — every step has concrete code/commands.

**Type consistency:** `PoLinkCandidate`, `PoLinkResult`, `PoLinkOutcome`, `resolvePoLink`/`resolvePoLinkFor`, `applyPoLink`, `showPoLinkPicker`, `poQtyCeiling`, `parseInvalidPoItemRefs`, `PoLinkAbortedException`, `allowOverReceipt` are spelled identically across all tasks. `applyPoLink` writes the same four fields `linkToPurchaseOrder` wrote. `copyWith(purchaseOrderItem/purchaseOrder/purchaseOrderQty)` confirmed present in `purchase_receipt_model.dart`.
