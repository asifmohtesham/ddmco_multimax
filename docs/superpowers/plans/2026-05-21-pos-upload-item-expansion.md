# POS Upload Item Tile Expansion & Packing Progress Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add expandable PS item rows and a packing progress bar to each item tile in the POS Upload Items tab.

**Architecture:** Two new observable maps (`resolvedDnQty`, `resolvedPsItems`) are pre-computed in the controller during existing fetch phases. A static `matchPsItems` method handles the pure matching logic (testable in isolation). `_ItemCard` is converted from `StatelessWidget` to `StatefulWidget` with local `_expanded` state; progress bar and expandable panel are added to its build method.

**Tech Stack:** Flutter, GetX (observables), `AnimatedSize` / `AnimatedRotation` for expansion animation, `LinearProgressIndicator` for progress.

**Spec:** `docs/superpowers/specs/2026-05-21-pos-upload-item-expansion-design.md`

---

## File Map

| File | Role |
|---|---|
| `lib/app/modules/pos_upload/form/pos_upload_form_controller.dart` | Add `PsItemEntry`, `matchPsItems`, `resolvedDnQty`, `resolvedPsItems`, `_buildDnQtyMap`; wire into fetchers |
| `lib/app/modules/pos_upload/form/pos_upload_form_screen.dart` | Convert `_ItemCard` to `StatefulWidget`; add progress bar; add expandable PS items panel |
| `test/unit/pos_upload_ps_matching_test.dart` | Unit tests for `matchPsItems` static method |

---

## Task 1: PsItemEntry class + matchPsItems static method + unit tests

**Files:**
- Modify: `lib/app/modules/pos_upload/form/pos_upload_form_controller.dart`
- Create: `test/unit/pos_upload_ps_matching_test.dart`

### Background

`PsItemEntry` is a plain data class that represents one Packing Slip item that has been matched to a POS Upload item. `matchPsItems` is a static method on the controller — extracting it as static makes it unit-testable without any GetX or network setup.

The matching condition (from the spec):
- `ps.customPoNo == posUploadName` — this PS was created for this POS Upload
- `psItem.customInvoiceSerialNumber == itemIdx.toString()` — this PS line references this POS Upload item

---

- [ ] **Step 1: Add `PsItemEntry` to `pos_upload_form_controller.dart`**

In `pos_upload_form_controller.dart`, after the closing `}` of the `CaseOption` class (currently around line 53), insert:

```dart
class PsItemEntry {
  final String psName;
  final int? fromCaseNo;
  final int? toCaseNo;
  final PackingSlipItem item;
  const PsItemEntry({
    required this.psName,
    this.fromCaseNo,
    this.toCaseNo,
    required this.item,
  });
}
```

- [ ] **Step 2: Add `matchPsItems` static method to `PosUploadFormController`**

Inside the `PosUploadFormController` class body, add this static method alongside `fmtAmount` and `fmtQty` (around line 98):

```dart
static List<PsItemEntry> matchPsItems({
  required List<PackingSlip> slips,
  required String posUploadName,
  required int itemIdx,
}) {
  final entries = <PsItemEntry>[];
  for (final ps in slips) {
    if (ps.customPoNo != posUploadName) continue;
    for (final psItem in ps.items) {
      if (psItem.customInvoiceSerialNumber == itemIdx.toString()) {
        entries.add(PsItemEntry(
          psName: ps.name,
          fromCaseNo: ps.fromCaseNo,
          toCaseNo: ps.toCaseNo,
          item: psItem,
        ));
      }
    }
  }
  return entries;
}
```

- [ ] **Step 3: Write the unit tests**

Create `test/unit/pos_upload_ps_matching_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/modules/pos_upload/form/pos_upload_form_controller.dart';

PackingSlipItem _item(String serial, double qty) => PackingSlipItem(
  name: 'row-$serial',
  dnDetail: '',
  itemCode: 'ITEM-001',
  itemName: 'Test Item',
  qty: qty,
  uom: 'Nos',
  batchNo: '',
  netWeight: 0,
  weightUom: 0,
  customInvoiceSerialNumber: serial,
);

PackingSlip _ps(String name, String? poNo, int? from, int? to,
    List<PackingSlipItem> items) =>
    PackingSlip(
      name: name,
      deliveryNote: 'DN-001',
      modified: '',
      creation: '',
      docstatus: 1,
      status: 'Submitted',
      customPoNo: poNo,
      fromCaseNo: from,
      toCaseNo: to,
      items: items,
    );

void main() {
  group('PosUploadFormController.matchPsItems', () {
    test('returns matching entry when PS po_no and serial match', () {
      final slips = [_ps('PS-001', 'ML-001', 1, 3, [_item('3', 10)])];
      final result = PosUploadFormController.matchPsItems(
        slips: slips,
        posUploadName: 'ML-001',
        itemIdx: 3,
      );
      expect(result, hasLength(1));
      expect(result.first.psName, 'PS-001');
      expect(result.first.item.qty, 10);
      expect(result.first.fromCaseNo, 1);
      expect(result.first.toCaseNo, 3);
    });

    test('returns multiple entries when serial appears across different PSes', () {
      final slips = [
        _ps('PS-001', 'ML-001', 1, 3, [_item('3', 10)]),
        _ps('PS-002', 'ML-001', 4, 6, [_item('3', 5)]),
      ];
      final result = PosUploadFormController.matchPsItems(
        slips: slips,
        posUploadName: 'ML-001',
        itemIdx: 3,
      );
      expect(result, hasLength(2));
      expect(result.map((e) => e.psName), containsAll(['PS-001', 'PS-002']));
    });

    test('excludes PSes with different po_no', () {
      final slips = [
        _ps('PS-001', 'ML-002', 1, 3, [_item('3', 10)]),
        _ps('PS-002', 'ML-001', 1, 3, [_item('3', 7)]),
      ];
      final result = PosUploadFormController.matchPsItems(
        slips: slips,
        posUploadName: 'ML-001',
        itemIdx: 3,
      );
      expect(result, hasLength(1));
      expect(result.first.psName, 'PS-002');
    });

    test('excludes PSes with null po_no', () {
      final slips = [_ps('PS-001', null, 1, 3, [_item('3', 10)])];
      final result = PosUploadFormController.matchPsItems(
        slips: slips,
        posUploadName: 'ML-001',
        itemIdx: 3,
      );
      expect(result, isEmpty);
    });

    test('excludes items whose serial does not match itemIdx', () {
      final slips = [
        _ps('PS-001', 'ML-001', 1, 3, [_item('5', 10), _item('3', 8)]),
      ];
      final result = PosUploadFormController.matchPsItems(
        slips: slips,
        posUploadName: 'ML-001',
        itemIdx: 3,
      );
      expect(result, hasLength(1));
      expect(result.first.item.qty, 8);
    });

    test('returns empty list when no slips match', () {
      final slips = [_ps('PS-001', 'ML-002', 1, 3, [_item('3', 10)])];
      final result = PosUploadFormController.matchPsItems(
        slips: slips,
        posUploadName: 'ML-001',
        itemIdx: 3,
      );
      expect(result, isEmpty);
    });

    test('returns empty list for empty slips input', () {
      final result = PosUploadFormController.matchPsItems(
        slips: [],
        posUploadName: 'ML-001',
        itemIdx: 1,
      );
      expect(result, isEmpty);
    });
  });
}
```

- [ ] **Step 4: Run the tests — expect FAIL (matchPsItems not yet on controller)**

```
flutter test test/unit/pos_upload_ps_matching_test.dart
```

Expected: compile error or test failure — `matchPsItems` is not yet defined on the controller.

- [ ] **Step 5: Run the tests again — expect PASS**

After adding the code from Steps 1–2:

```
flutter test test/unit/pos_upload_ps_matching_test.dart
```

Expected: 7 tests, all PASS.

- [ ] **Step 6: Run analyze**

```
flutter analyze lib/app/modules/pos_upload/form/pos_upload_form_controller.dart
```

Expected: No new issues.

- [ ] **Step 7: Commit**

```
git add lib/app/modules/pos_upload/form/pos_upload_form_controller.dart test/unit/pos_upload_ps_matching_test.dart
git commit -m "feat: add PsItemEntry and matchPsItems for PS item resolution"
```

---

## Task 2: Controller state — resolvedDnQty + resolvedPsItems + wire into fetchers

**Files:**
- Modify: `lib/app/modules/pos_upload/form/pos_upload_form_controller.dart`

### Background

Two new observable maps are added to the controller. `resolvedDnQty` is populated in `_fetchDeliveryNote` (which already fetches DN item data). `resolvedPsItems` is populated in `_fetchPackingSlips` using the `matchPsItems` static method added in Task 1. Neither map requires a new network call.

---

- [ ] **Step 1: Add the two new observable maps**

In `pos_upload_form_controller.dart`, in the `// ── Packing Slip layer` section (after the `packingSlips` declaration, around line 93), add:

```dart
/// idx → DN item qty (null = item not found in DN)
final resolvedDnQty = <int, double?>{}.obs;

/// idx → PS items matching this POS Upload item (empty list = none matched)
final resolvedPsItems = <int, List<PsItemEntry>>{}.obs;
```

- [ ] **Step 2: Add `_buildDnQtyMap` private method**

After the `_buildSerialMap` method (currently ending around line 307), add:

```dart
void _buildDnQtyMap({
  required List<PosUploadItem> posItems,
  required double? Function(int idx) matchQty,
}) {
  final map = <int, double?>{};
  for (final item in posItems) {
    map[item.idx] = matchQty(item.idx);
  }
  resolvedDnQty.value = map;
}
```

- [ ] **Step 3: Populate `resolvedDnQty` in `_fetchDeliveryNote`**

In `_fetchDeliveryNote`, after the existing `_buildSerialMap(...)` call (currently around lines 164–169), add a call to `_buildDnQtyMap`:

The existing block looks like:
```dart
_buildSerialMap(
  posItems: upload.items,
  matchSerial: (idx) => dn.items
      .firstWhereOrNull((i) => i.idx == idx)
      ?.customInvoiceSerialNumber,
);
```

Add immediately after it:
```dart
_buildDnQtyMap(
  posItems: upload.items,
  matchQty: (idx) =>
      dn.items.firstWhereOrNull((i) => i.idx == idx)?.qty,
);
```

- [ ] **Step 4: Populate `resolvedPsItems` in `_fetchPackingSlips`**

In `_fetchPackingSlips`, after the line `resolvedPackingSlips.value = psMap;` (currently around line 268), add:

```dart
// Build idx → list-of-matching-PS-items using the static matching method.
final psItemsMap = <int, List<PsItemEntry>>{};
for (final item in upload.items) {
  psItemsMap[item.idx] = matchPsItems(
    slips: slips,
    posUploadName: upload.name,
    itemIdx: item.idx,
  );
}
resolvedPsItems.value = psItemsMap;
```

- [ ] **Step 5: Run all unit tests**

```
flutter test
```

Expected: all existing tests pass; the 7 new tests from Task 1 still pass.

- [ ] **Step 6: Run analyze**

```
flutter analyze lib/app/modules/pos_upload/form/pos_upload_form_controller.dart
```

Expected: No issues.

- [ ] **Step 7: Commit**

```
git add lib/app/modules/pos_upload/form/pos_upload_form_controller.dart
git commit -m "feat: add resolvedDnQty and resolvedPsItems observable maps to controller"
```

---

## Task 3: Convert _ItemCard to StatefulWidget + add new params + pass from itemBuilder

**Files:**
- Modify: `lib/app/modules/pos_upload/form/pos_upload_form_screen.dart`

### Background

`_ItemCard` is currently a `StatelessWidget`. Converting it to a `StatefulWidget` lets it hold a local `_expanded` bool for the expand/collapse behaviour added in Task 5. This task only does the conversion — the UI should look identical to before. Two new constructor params (`dnQty`, `psItems`) are added but not used in the build method yet; the `_ItemsTabState` itemBuilder is updated to pass them.

The `_resolveMatchStatus()` method moves from the widget class to the state class.

---

- [ ] **Step 1: Replace `_ItemCard` with the StatefulWidget version**

In `pos_upload_form_screen.dart`, replace the entire `_ItemCard` class (lines 543–736, starting with `class _ItemCard extends StatelessWidget` through the closing `}` of `_MatchStatus`) with the following. Note: `_MatchStatus` stays as a separate class at the bottom — only `_ItemCard` and its build method change.

Replace `class _ItemCard extends StatelessWidget { ... }` (the widget class and its `build` method, up to but NOT including `class _MatchStatus`) with:

```dart
class _ItemCard extends StatefulWidget {
  final PosUploadItem item;
  final int displayIndex;
  final bool isLoadingLinked;
  final bool isLoadingPS;
  final LinkedDocType linkedDocType;
  final String? resolvedSerial;
  final PackingSlipInfo? packingSlipInfo;
  final bool hasLinkedDoc;
  final double? dnQty;
  final List<PsItemEntry> psItems;

  const _ItemCard({
    required this.item,
    required this.displayIndex,
    required this.isLoadingLinked,
    required this.isLoadingPS,
    required this.linkedDocType,
    required this.resolvedSerial,
    required this.packingSlipInfo,
    required this.hasLinkedDoc,
    required this.dnQty,
    required this.psItems,
  });

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final matchStatus = _resolveMatchStatus();

    final chips = <Widget>[];

    if (widget.resolvedSerial != null && widget.resolvedSerial!.isNotEmpty) {
      chips.add(_InfoChip(
        icon: Icons.tag,
        label: '#${widget.resolvedSerial!}',
        backgroundColor: cs.secondaryContainer,
        foregroundColor: cs.onSecondaryContainer,
        tooltip: 'Invoice serial: ${widget.resolvedSerial!}',
      ));
    }

    if (widget.isLoadingPS && widget.linkedDocType == LinkedDocType.deliveryNote) {
      chips.add(_InfoChip(
        icon: Icons.hourglass_top_rounded,
        label: 'PS…',
        backgroundColor: Colors.blue.withValues(alpha: 0.12),
        foregroundColor: Colors.blue.shade700,
        isSpinner: true,
      ));
    } else if (widget.packingSlipInfo != null) {
      final from = widget.packingSlipInfo!.fromCaseNo;
      final to = widget.packingSlipInfo!.toCaseNo;
      final caseLabel = (from != null && to != null)
          ? 'Cases $from – $to'
          : (from != null ? 'Case $from' : widget.packingSlipInfo!.psName);
      chips.add(_InfoChip(
        icon: Icons.inventory_outlined,
        label: caseLabel,
        backgroundColor: cs.secondaryContainer,
        foregroundColor: cs.onSecondaryContainer,
        tooltip: 'Packing Slip: ${widget.packingSlipInfo!.psName}',
      ));
    } else if (!widget.isLoadingPS &&
        widget.linkedDocType == LinkedDocType.deliveryNote &&
        widget.resolvedSerial != null &&
        widget.resolvedSerial!.isNotEmpty) {
      chips.add(_InfoChip(
        icon: Icons.inventory_outlined,
        label: 'No PS',
        backgroundColor: cs.errorContainer,
        foregroundColor: cs.onErrorContainer,
        tooltip: 'No matching Packing Slip found',
      ));
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      color: cs.surfaceContainerLowest,
      child: InkWell(
        onTap: null, // wired in Task 5
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: cs.primaryContainer,
                    child: Text(
                      '${widget.displayIndex}',
                      style: TextStyle(
                        fontSize: 9,
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.item.itemName,
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (matchStatus != null) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(matchStatus.icon,
                                  size: 12, color: matchStatus.color),
                              const SizedBox(width: 3),
                              Text(
                                matchStatus.label,
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: matchStatus.color),
                              ),
                            ],
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
                  _Stat(
                    label: 'Qty',
                    value: PosUploadFormController.fmtQty(widget.item.quantity),
                  ),
                  _Stat(
                    label: 'Rate',
                    value: PosUploadFormController.fmtAmount(widget.item.rate),
                  ),
                  _Stat(
                    label: 'Amount',
                    value: PosUploadFormController.fmtAmount(widget.item.amount),
                    highlight: true,
                    colorScheme: cs,
                  ),
                ],
              ),

              // ── Chips ────────────────────────────────────────────────────
              if (chips.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: chips),
              ],
            ],
          ),
        ),
      ),
    );
  }

  _MatchStatus? _resolveMatchStatus() {
    if (!widget.hasLinkedDoc) return null;
    if (widget.isLoadingLinked) {
      return _MatchStatus(
          icon: Icons.hourglass_top,
          label: 'Checking…',
          color: Colors.orange);
    }
    if (widget.resolvedSerial != null && widget.resolvedSerial!.isNotEmpty) {
      return _MatchStatus(
          icon: Icons.check_circle,
          label: 'Matched',
          color: Colors.green.shade700);
    }
    if (widget.resolvedSerial != null) {
      return _MatchStatus(
          icon: Icons.check_circle_outline,
          label: 'Matched – no serial',
          color: Colors.teal.shade600);
    }
    return _MatchStatus(
        icon: Icons.cancel_outlined,
        label: 'Not found',
        color: Colors.red.shade600);
  }
}
```

- [ ] **Step 2: Update `_ItemsTabState` itemBuilder to pass new params**

In `_ItemsTabState.build`, find the `itemBuilder` lambda (around line 514–530). Update it to pass `dnQty` and `psItems`:

```dart
itemBuilder: (context, index) {
  final item = items[index];
  return Obx(() => _ItemCard(
        item: item,
        displayIndex: item.idx,
        isLoadingLinked: ctrl.isLoadingLinked.value,
        isLoadingPS: ctrl.isLoadingPackingSlips.value,
        linkedDocType: ctrl.linkedDocType.value,
        resolvedSerial: ctrl.resolvedSerials[item.idx],
        packingSlipInfo: ctrl.resolvedPackingSlips[item.idx],
        hasLinkedDoc: ctrl.resolvedSerials.isNotEmpty,
        dnQty: ctrl.resolvedDnQty[item.idx],
        psItems: ctrl.resolvedPsItems[item.idx] ?? [],
      ));
},
```

- [ ] **Step 3: Run analyze**

```
flutter analyze lib/app/modules/pos_upload/form/pos_upload_form_screen.dart
```

Expected: No issues.

- [ ] **Step 4: Run all tests**

```
flutter test
```

Expected: all tests pass.

- [ ] **Step 5: Build and verify visually**

Run the app on a connected device and navigate to a POS Upload form → Items tab. The Items tab should look exactly as it did before this task. No visual change yet.

- [ ] **Step 6: Commit**

```
git add lib/app/modules/pos_upload/form/pos_upload_form_screen.dart
git commit -m "refactor: convert _ItemCard to StatefulWidget, add dnQty/psItems params"
```

---

## Task 4: Add packing progress bar to _ItemCard

**Files:**
- Modify: `lib/app/modules/pos_upload/form/pos_upload_form_screen.dart`

### Background

For items that are matched in a Delivery Note AND have PS items loaded, the "Matched" status row is replaced by a `LinearProgressIndicator` showing packed qty vs DN qty. The logic lives entirely in `_ItemCardState` as getters and a new header layout.

State machine (determines what appears in the status slot below the item name):
- `isLoadingLinked` → "Checking…" (unchanged)
- Matched + `isLoadingPS` → "Matched" text (PS not yet loaded)
- Matched + PS loaded + `psItems.isNotEmpty` → progress bar + label
- Matched + PS loaded + `psItems.isEmpty` → "Matched" text (no PS data for this item)
- Not matched → "Not found" (unchanged)

---

- [ ] **Step 1: Add the progress bar getters to `_ItemCardState`**

Inside `_ItemCardState`, after the `_expanded` declaration and before `build()`, add:

```dart
bool get _showProgressBar =>
    widget.resolvedSerial != null &&
    widget.resolvedSerial!.isNotEmpty &&
    !widget.isLoadingPS &&
    widget.psItems.isNotEmpty;

double get _packedQty =>
    widget.psItems.fold(0.0, (s, e) => s + e.item.qty);

double? get _progressRatio {
  final dq = widget.dnQty;
  if (dq == null || dq == 0) return null;
  return (_packedQty / dq).clamp(0.0, 1.0);
}

String get _progressLabel {
  final packed = PosUploadFormController.fmtQty(_packedQty);
  final dq = widget.dnQty;
  final total = (dq != null && dq > 0)
      ? PosUploadFormController.fmtQty(dq)
      : '–';
  return '$packed Packed / $total DN Qty';
}
```

- [ ] **Step 2: Replace the item name + status-row section in `build()`**

In `_ItemCardState.build()`, inside the `Column` that contains the item name and status row (the inner `Column` inside the `Expanded` in the header `Row`), replace:

```dart
Text(
  widget.item.itemName,
  style: theme.textTheme.bodyLarge
      ?.copyWith(fontWeight: FontWeight.w600),
),
if (matchStatus != null) ...[
  const SizedBox(height: 2),
  Row(
    children: [
      Icon(matchStatus.icon,
          size: 12, color: matchStatus.color),
      const SizedBox(width: 3),
      Text(
        matchStatus.label,
        style: theme.textTheme.labelSmall
            ?.copyWith(color: matchStatus.color),
      ),
    ],
  ),
],
```

with:

```dart
Text(
  widget.item.itemName,
  style: theme.textTheme.bodyLarge
      ?.copyWith(fontWeight: FontWeight.w600),
),
if (_showProgressBar) ...[
  const SizedBox(height: 4),
  LinearProgressIndicator(
    value: _progressRatio,
    borderRadius: BorderRadius.circular(2),
  ),
  const SizedBox(height: 2),
  Text(
    _progressLabel,
    style: theme.textTheme.labelSmall
        ?.copyWith(color: cs.onSurfaceVariant),
  ),
] else if (matchStatus != null) ...[
  const SizedBox(height: 2),
  Row(
    children: [
      Icon(matchStatus.icon, size: 12, color: matchStatus.color),
      const SizedBox(width: 3),
      Text(
        matchStatus.label,
        style: theme.textTheme.labelSmall
            ?.copyWith(color: matchStatus.color),
      ),
    ],
  ),
],
```

- [ ] **Step 3: Run analyze**

```
flutter analyze lib/app/modules/pos_upload/form/pos_upload_form_screen.dart
```

Expected: No issues.

- [ ] **Step 4: Verify visually**

Navigate to a POS Upload form → Items tab. For items that are matched to a DN AND have packing slip items, the "Matched" label should be replaced by a `LinearProgressIndicator` with a label such as `"10 Packed / 20 DN Qty"`. For items with no PS data, the label still shows "Matched". For unmatched items, "Not found" is unchanged.

- [ ] **Step 5: Commit**

```
git add lib/app/modules/pos_upload/form/pos_upload_form_screen.dart
git commit -m "feat: add packing progress bar to matched item tiles"
```

---

## Task 5: Add expandable PS items panel to _ItemCard

**Files:**
- Modify: `lib/app/modules/pos_upload/form/pos_upload_form_screen.dart`

### Background

Tapping a card (when it has PS items) toggles `_expanded`. An `AnimatedRotation` chevron in the header signals whether the card can be expanded. An `AnimatedSize` block at the bottom of the card's `Column` reveals the PS items panel when expanded.

Each PS item row shows:
- A case-range chip (`Cases 1–3` / `Case 1` / PS name fallback), in `secondaryContainer`
- Item name (bold) + qty (tertiary) on one line
- Item code · variant · country on a second line

---

- [ ] **Step 1: Wire up `onTap` and add the chevron to the header**

In `_ItemCardState.build()`:

**1a.** Change `InkWell(onTap: null, ...)` to:

```dart
InkWell(
  onTap: widget.psItems.isNotEmpty
      ? () => setState(() => _expanded = !_expanded)
      : null,
  borderRadius: BorderRadius.circular(12),
  child: Padding( ... ),
)
```

**1b.** Inside the header `Row`, replace the item-name `Text` with a `Row` that includes the chevron on the trailing side. Change:

```dart
Expanded(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        widget.item.itemName,
        style: theme.textTheme.bodyLarge
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
      // ... status row ...
    ],
  ),
),
```

with:

```dart
Expanded(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              widget.item.itemName,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (widget.psItems.isNotEmpty) ...[
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: _expanded ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.expand_more,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      if (_showProgressBar) ...[
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: _progressRatio,
          borderRadius: BorderRadius.circular(2),
        ),
        const SizedBox(height: 2),
        Text(
          _progressLabel,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
      ] else if (matchStatus != null) ...[
        const SizedBox(height: 2),
        Row(
          children: [
            Icon(matchStatus.icon, size: 12, color: matchStatus.color),
            const SizedBox(width: 3),
            Text(
              matchStatus.label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: matchStatus.color),
            ),
          ],
        ),
      ],
    ],
  ),
),
```

- [ ] **Step 2: Add the `AnimatedSize` expansion slot after the chips row**

At the bottom of the main `Column` (after `if (chips.isNotEmpty) ...`), add:

```dart
// ── Expanded PS items panel ─────────────────────────────────
AnimatedSize(
  duration: const Duration(milliseconds: 200),
  curve: Curves.easeInOut,
  child: _expanded
      ? _buildPsItemsPanel(context)
      : const SizedBox.shrink(),
),
```

- [ ] **Step 3: Add `_buildPsItemsPanel` to `_ItemCardState`**

Add this method to `_ItemCardState`:

```dart
Widget _buildPsItemsPanel(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: cs.surfaceContainerHighest,
      border: Border.all(color: cs.outlineVariant),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < widget.psItems.length; i++) ...[
          if (i > 0) const Divider(height: 16, thickness: 0.5),
          _buildPsItemRow(context, widget.psItems[i]),
        ],
      ],
    ),
  );
}
```

- [ ] **Step 4: Add `_buildPsItemRow` to `_ItemCardState`**

Add this method to `_ItemCardState`:

```dart
Widget _buildPsItemRow(BuildContext context, PsItemEntry entry) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final psItem = entry.item;

  final String caseLabel;
  if (entry.fromCaseNo != null && entry.toCaseNo != null) {
    caseLabel = 'Cases ${entry.fromCaseNo}–${entry.toCaseNo}';
  } else if (entry.fromCaseNo != null) {
    caseLabel = 'Case ${entry.fromCaseNo}';
  } else {
    caseLabel = entry.psName;
  }

  final subParts = <String>[psItem.itemCode];
  if (psItem.customVariantOf != null && psItem.customVariantOf!.isNotEmpty) {
    subParts.add(psItem.customVariantOf!);
  }
  if (psItem.customCountryOfOrigin != null &&
      psItem.customCountryOfOrigin!.isNotEmpty) {
    subParts.add(psItem.customCountryOfOrigin!);
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Case chip
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: cs.secondaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          caseLabel,
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSecondaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      const SizedBox(height: 4),
      // Item name + qty
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              psItem.itemName,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            PosUploadFormController.fmtQty(psItem.qty),
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: cs.tertiary),
          ),
        ],
      ),
      // Subline: code · variant · country
      Text(
        subParts.join(' · '),
        style: theme.textTheme.labelSmall
            ?.copyWith(color: cs.onSurfaceVariant),
      ),
    ],
  );
}
```

- [ ] **Step 5: Run analyze**

```
flutter analyze lib/app/modules/pos_upload/form/pos_upload_form_screen.dart
```

Expected: No issues.

- [ ] **Step 6: Run all tests**

```
flutter test
```

Expected: all tests pass.

- [ ] **Step 7: Verify visually — expand/collapse**

Navigate to a POS Upload form (ML or KA prefix, must have linked DN and PSes) → Items tab.

- Items with PS data show a chevron (`›`) icon in the top-right of the card.
- Tapping a card with PS data expands it; tapping again collapses it.
- The chevron rotates 180° when expanded.
- The expanded panel shows a `Container` with `surfaceContainerHighest` background, listing one row per matching PS item.
- Each row has a case chip, item name, qty (tertiary colour), and a subline with item code + optional variant + country.
- Items without PS data show no chevron and are not tappable.

- [ ] **Step 8: Verify visually — progress bar coexists with expansion**

For a matched item with PS data:
- The progress bar is visible in the card header.
- Tapping the card expands the PS items panel below the chips.
- The chevron rotates on expand.
- Items tab scrolling still works normally.

- [ ] **Step 9: Commit**

```
git add lib/app/modules/pos_upload/form/pos_upload_form_screen.dart
git commit -m "feat: add expandable PS items panel with AnimatedSize expansion"
```

---

## Done

After Task 5, the feature is complete. Both new observable maps are populated from existing data, the card is expandable, the progress bar shows packing status, and all unit tests pass.
