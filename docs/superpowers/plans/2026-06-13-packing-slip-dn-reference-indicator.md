# Packing Slip DN-Reference Validity Indicator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface, on the Packing Slip Items tab, whether every slip row resolves to a valid linked Delivery Note Item, with a one-tap Resolve action that re-matches orphaned `dn_detail` references so the slip submits cleanly in ERPNext.

**Architecture:** A single pure resolver (`resolveDnReferences`) and a pure status function (`computeDnRefStatus`) hold all the logic and are fully unit-tested. The existing on-load auto-repair (`_refreshDnDetails`) is refactored to delegate to the resolver (DRY). Thin controller getters expose validity state; a stateless `Obx` banner renders the indicator and wires Resolve/Remove to existing controller methods (`saveDocument`, `deleteItem`).

**Tech Stack:** Flutter, GetX (`.obs` observables, `Get.find`), `package:collection` (`firstWhereOrNull`), `flutter_test`.

---

## Background (verified facts)

- ERPNext `version-15` `validate_items` throws "missing a valid Delivery Note Item reference" when `frappe.db.get_value("Delivery Note Item", {"name": dn_detail, "docstatus": 0}, "sum(qty-packed_qty)")` returns `None`.
- Scope: DNs are always **Draft**, backend is **stock v15** → only the unresolved/stale `dn_detail` case applies.
- The Items tab (`_buildChecklistRow`) is **DN-anchored**: it iterates DN items and finds the slip row via `getCurrentSlipItem(dnItem.name)`. A slip row with empty/stale `dn_detail` renders nowhere — it is an invisible orphan.
- `PackingSlipItemCard` is **unused** (only self-referenced) — do not touch it.
- Frappe runs `validate()` on every save, so a successful app save proves reference-validity for submit.

## File Structure

**New**
- `lib/app/modules/packing_slip/form/ps_dn_reference_resolver.dart` — `DnRefStatus` enum, `validDnItemNames`, `isSlipItemLinked`, `computeDnRefStatus`, `resolveDnReferences`. Pure; no GetX/Flutter imports beyond models + `package:collection`.
- `lib/app/modules/packing_slip/form/widgets/packing_slip_dn_link_banner.dart` — stateless `Obx` banner.
- `test/unit/packing_slip_dn_reference_resolver_test.dart` — unit tests for the resolver + status function.

**Modified**
- `lib/app/modules/packing_slip/form/packing_slip_form_controller.dart` — validity getters, `resolveDnReferencesAndSave`, refactor `_refreshDnDetails`.
- `lib/app/modules/packing_slip/form/packing_slip_form_screen.dart` — mount banner in `_buildItemsView`.

**Removed**
- `test/unit/packing_slip_refresh_dn_details_test.dart` — its local `refreshDnDetails` helper duplicates the new resolver; scenarios are subsumed by the new test file.

---

## Task 1: Pure resolver + status function

**Files:**
- Create: `lib/app/modules/packing_slip/form/ps_dn_reference_resolver.dart`
- Create: `test/unit/packing_slip_dn_reference_resolver_test.dart`
- Remove: `test/unit/packing_slip_refresh_dn_details_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/unit/packing_slip_dn_reference_resolver_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/modules/packing_slip/form/ps_dn_reference_resolver.dart';

PackingSlipItem _slip({
  required String dnDetail,
  required String itemCode,
  String serial = '1',
  String batchNo = '',
  double qty = 1.0,
  String name = 'PS-ROW-1',
}) =>
    PackingSlipItem(
      name: name,
      dnDetail: dnDetail,
      itemCode: itemCode,
      itemName: 'Test Item',
      qty: qty,
      uom: 'Nos',
      batchNo: batchNo,
      netWeight: 0.0,
      weightUom: 0.0,
      customInvoiceSerialNumber: serial,
    );

DeliveryNoteItem _dn({
  required String name,
  required String itemCode,
  String serial = '1',
  String? batchNo,
  double qty = 5.0,
}) =>
    DeliveryNoteItem(
      name: name,
      itemCode: itemCode,
      qty: qty,
      rate: 10.0,
      customInvoiceSerialNumber: serial,
      docstatus: 0,
      batchNo: batchNo,
    );

void main() {
  group('resolveDnReferences', () {
    test('all already valid -> no change, fixed=0, unresolved=0', () {
      final r = resolveDnReferences(
        slipItems: [_slip(dnDetail: 'row-A', itemCode: 'ITEM-A')],
        dnItems: [_dn(name: 'row-A', itemCode: 'ITEM-A')],
      );
      expect(r.fixed, 0);
      expect(r.unresolved, 0);
      expect(r.items.first.dnDetail, 'row-A');
    });

    test('empty dn_detail matched by itemCode + serial -> fixed=1', () {
      final r = resolveDnReferences(
        slipItems: [_slip(dnDetail: '', itemCode: 'ITEM-A')],
        dnItems: [_dn(name: 'new-row', itemCode: 'ITEM-A')],
      );
      expect(r.fixed, 1);
      expect(r.unresolved, 0);
      expect(r.items.first.dnDetail, 'new-row');
    });

    test('stale dn_detail re-matched -> fixed=1', () {
      final r = resolveDnReferences(
        slipItems: [_slip(dnDetail: 'old-row', itemCode: 'ITEM-A')],
        dnItems: [_dn(name: 'new-row', itemCode: 'ITEM-A')],
      );
      expect(r.fixed, 1);
      expect(r.items.first.dnDetail, 'new-row');
    });

    test('no candidate -> unresolved=1, row untouched', () {
      final r = resolveDnReferences(
        slipItems: [_slip(dnDetail: '', itemCode: 'ITEM-A')],
        dnItems: [_dn(name: 'row-B', itemCode: 'ITEM-B')],
      );
      expect(r.fixed, 0);
      expect(r.unresolved, 1);
      expect(r.items.first.dnDetail, '');
    });

    test('batch must match when slip row carries a batch', () {
      final r = resolveDnReferences(
        slipItems: [_slip(dnDetail: '', itemCode: 'ITEM-A', batchNo: 'BX')],
        dnItems: [_dn(name: 'row-by', itemCode: 'ITEM-A', batchNo: 'BY')],
      );
      expect(r.unresolved, 1);
      expect(r.items.first.dnDetail, '');
    });

    test('prefers candidate with remaining qty > 0 when several match', () {
      final r = resolveDnReferences(
        slipItems: [_slip(dnDetail: '', itemCode: 'ITEM-A')],
        dnItems: [
          _dn(name: 'full-row', itemCode: 'ITEM-A'),
          _dn(name: 'open-row', itemCode: 'ITEM-A'),
        ],
        remainingQty: (d) => d.name == 'open-row' ? 3.0 : 0.0,
      );
      expect(r.fixed, 1);
      expect(r.items.first.dnDetail, 'open-row');
    });

    test('falls back to first candidate when none has remaining qty', () {
      final r = resolveDnReferences(
        slipItems: [_slip(dnDetail: '', itemCode: 'ITEM-A')],
        dnItems: [
          _dn(name: 'first-row', itemCode: 'ITEM-A'),
          _dn(name: 'second-row', itemCode: 'ITEM-A'),
        ],
        remainingQty: (_) => 0.0,
      );
      expect(r.fixed, 1);
      expect(r.items.first.dnDetail, 'first-row');
    });
  });

  group('computeDnRefStatus', () {
    final validNames = {'row-A'};

    test('DN not loaded -> checking', () {
      expect(
        computeDnRefStatus(
          items: [_slip(dnDetail: '', itemCode: 'ITEM-A')],
          validNames: const {},
          dnLoaded: false,
        ),
        DnRefStatus.checking,
      );
    });

    test('all linked -> allLinked', () {
      expect(
        computeDnRefStatus(
          items: [_slip(dnDetail: 'row-A', itemCode: 'ITEM-A')],
          validNames: validNames,
          dnLoaded: true,
        ),
        DnRefStatus.allLinked,
      );
    });

    test('an orphan present -> hasUnlinked', () {
      expect(
        computeDnRefStatus(
          items: [
            _slip(dnDetail: 'row-A', itemCode: 'ITEM-A'),
            _slip(dnDetail: '', itemCode: 'ITEM-B', name: 'PS-ROW-2'),
          ],
          validNames: validNames,
          dnLoaded: true,
        ),
        DnRefStatus.hasUnlinked,
      );
    });

    test('empty slip with DN loaded -> allLinked', () {
      expect(
        computeDnRefStatus(items: const [], validNames: validNames, dnLoaded: true),
        DnRefStatus.allLinked,
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/unit/packing_slip_dn_reference_resolver_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../ps_dn_reference_resolver.dart'` / undefined `resolveDnReferences`, `computeDnRefStatus`, `DnRefStatus`.

- [ ] **Step 3: Implement the resolver**

Create `lib/app/modules/packing_slip/form/ps_dn_reference_resolver.dart`:

```dart
import 'package:collection/collection.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';

/// Validity of a Packing Slip's Delivery Note Item references, as it relates
/// to ERPNext's `validate_items` submit gate.
///
/// * [checking]   – the linked Delivery Note is not loaded yet; do not assert.
/// * [allLinked]  – every slip row resolves to a valid DN Item row name.
/// * [hasUnlinked]– at least one slip row's `dn_detail` is empty or stale and
///                  would trigger "missing a valid Delivery Note Item reference".
enum DnRefStatus { checking, allLinked, hasUnlinked }

/// Names of DN items that are valid link targets (non-empty `name`).
Set<String> validDnItemNames(List<DeliveryNoteItem> dnItems) => {
      for (final d in dnItems)
        if (d.name != null && d.name!.isNotEmpty) d.name!,
    };

/// True when [item]'s `dn_detail` points at a current DN Item row.
bool isSlipItemLinked(PackingSlipItem item, Set<String> validNames) =>
    item.dnDetail.isNotEmpty && validNames.contains(item.dnDetail);

/// Pure status decision used by the Items-tab banner.
DnRefStatus computeDnRefStatus({
  required List<PackingSlipItem> items,
  required Set<String> validNames,
  required bool dnLoaded,
}) {
  if (!dnLoaded) return DnRefStatus.checking;
  final hasOrphan = items.any((i) => !isSlipItemLinked(i, validNames));
  return hasOrphan ? DnRefStatus.hasUnlinked : DnRefStatus.allLinked;
}

/// Re-matches orphaned slip rows to current DN Item rows.
///
/// A row is an orphan when its `dn_detail` is empty or absent from the current
/// DN. For each orphan, candidate DN rows must share `itemCode`, the invoice
/// serial (`customInvoiceSerialNumber ?? '0'` on both sides), and — when the
/// slip row carries a non-empty batch — `batchNo`.
///
/// Among candidates, one with [remainingQty] > 0 is preferred (so packed qty is
/// attributed to a DN line that still has capacity, mirroring `findScannedDnItem`);
/// otherwise the first candidate is used. When [remainingQty] is null the first
/// candidate is always used.
///
/// Returns the patched item list plus counts: [fixed] rows were re-linked,
/// [unresolved] rows had no candidate and were left untouched.
({List<PackingSlipItem> items, int fixed, int unresolved}) resolveDnReferences({
  required List<PackingSlipItem> slipItems,
  required List<DeliveryNoteItem> dnItems,
  double Function(DeliveryNoteItem)? remainingQty,
}) {
  final validNames = validDnItemNames(dnItems);
  var fixed = 0;
  var unresolved = 0;

  final patched = slipItems.map((item) {
    if (isSlipItemLinked(item, validNames)) return item;

    final itemSerial = item.customInvoiceSerialNumber ?? '0';
    final candidates = dnItems.where((d) {
      if (d.name == null || d.name!.isEmpty) return false;
      if (d.itemCode != item.itemCode) return false;
      if ((d.customInvoiceSerialNumber ?? '0') != itemSerial) return false;
      if (item.batchNo.isNotEmpty && d.batchNo != item.batchNo) return false;
      return true;
    }).toList();

    if (candidates.isEmpty) {
      unresolved++;
      return item;
    }

    final chosen = remainingQty == null
        ? candidates.first
        : (candidates.firstWhereOrNull((d) => remainingQty(d) > 0) ??
            candidates.first);

    fixed++;
    return item.copyWith(dnDetail: chosen.name!);
  }).toList();

  return (items: patched, fixed: fixed, unresolved: unresolved);
}
```

- [ ] **Step 4: Remove the superseded test file**

Run: `git rm test/unit/packing_slip_refresh_dn_details_test.dart`

- [ ] **Step 5: Run the new tests to verify they pass**

Run: `flutter test test/unit/packing_slip_dn_reference_resolver_test.dart`
Expected: PASS (all 11 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/packing_slip/form/ps_dn_reference_resolver.dart \
        test/unit/packing_slip_dn_reference_resolver_test.dart \
        test/unit/packing_slip_refresh_dn_details_test.dart
git commit -m "feat(packing-slip): pure DN-reference resolver + status function

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Wire the controller (validity getters, Resolve action, refactor auto-repair)

**Files:**
- Modify: `lib/app/modules/packing_slip/form/packing_slip_form_controller.dart`

- [ ] **Step 1: Add the resolver import**

At the import block (near the other `packing_slip/form` imports, e.g. after the `ps_serial_options.dart` import at line 26), add:

```dart
import 'package:multimax/app/modules/packing_slip/form/ps_dn_reference_resolver.dart';
```

- [ ] **Step 2: Refactor `_refreshDnDetails` to delegate to the resolver**

Replace the entire body of `_refreshDnDetails` (currently lines ~362-404) with:

```dart
  void _refreshDnDetails(DeliveryNote dn) {
    final slip = packingSlip.value;
    if (slip == null) return;

    final result = resolveDnReferences(
      slipItems:    slip.items,
      dnItems:      dn.items,
      remainingQty: _calcRemainingQtyForDnItem,
    );

    if (result.fixed > 0) {
      packingSlip.value = slip.copyWith(items: result.items);
      _checkForChanges();
    }
  }
```

(Keep the existing doc-comment block above the method; only the implementation changes. `_calcRemainingQtyForDnItem` has an optional named param and is assignable to `double Function(DeliveryNoteItem)`.)

- [ ] **Step 3: Add validity getters**

Add these getters immediately after `_refreshDnDetails` (before the "Fetch error handler" section comment, around line 405):

```dart
  // ── DN-reference validity (Items-tab indicator) ────────────────────────────

  /// Names of the linked DN's item rows that are valid link targets.
  Set<String> get _validDnNames =>
      validDnItemNames(linkedDeliveryNote.value?.items ?? const []);

  /// Slip rows whose `dn_detail` is empty or stale (would block ERPNext submit).
  /// Empty while the linked DN is not loaded — validity is unknown then.
  List<PackingSlipItem> get unlinkedItems {
    if (linkedDeliveryNote.value == null) return const [];
    final names = _validDnNames;
    return packingSlip.value?.items
            .where((i) => !isSlipItemLinked(i, names))
            .toList() ??
        const [];
  }

  /// Reactive validity status consumed by [PackingSlipDnLinkBanner].
  DnRefStatus get dnRefStatus => computeDnRefStatus(
        items:      packingSlip.value?.items ?? const [],
        validNames: _validDnNames,
        dnLoaded:   linkedDeliveryNote.value != null,
      );
```

- [ ] **Step 4: Add the Resolve action**

Add these methods immediately after the getters from Step 3:

```dart
  // ── User-triggered reference resolution ────────────────────────────────────

  /// Re-matches orphaned `dn_detail` references and persists the slip so it
  /// becomes immediately submittable in ERPNext. Guarded to draft documents
  /// with a loaded Delivery Note.
  Future<void> resolveDnReferencesAndSave() async {
    final dn   = linkedDeliveryNote.value;
    final slip = packingSlip.value;
    if (dn == null || slip == null) {
      GlobalSnackbar.error(message: 'Delivery Note not loaded yet.');
      return;
    }
    if (slip.docstatus != 0) return;

    final result = resolveDnReferences(
      slipItems:    slip.items,
      dnItems:      dn.items,
      remainingQty: _calcRemainingQtyForDnItem,
    );

    if (result.fixed > 0) {
      packingSlip.value = slip.copyWith(items: result.items);
      _checkForChanges();
      if (isDirty.value) await saveDocument();
    }

    _announceResolveResult(result.fixed, result.unresolved);
  }

  /// Surfaces the outcome of [resolveDnReferencesAndSave] as a snackbar.
  void _announceResolveResult(int fixed, int unresolved) {
    if (fixed == 0 && unresolved == 0) {
      GlobalSnackbar.info(
          message: 'All items already linked to the Delivery Note.');
      return;
    }
    final parts = <String>[];
    if (fixed > 0) parts.add('Linked $fixed item(s) to the Delivery Note');
    if (unresolved > 0) {
      parts.add('$unresolved could not be matched — remove them to proceed');
    }
    final msg = parts.join('. ');
    if (unresolved > 0) {
      GlobalSnackbar.warning(message: msg);
    } else {
      GlobalSnackbar.success(message: msg);
    }
  }
```

- [ ] **Step 5: Verify analysis passes and resolver tests still pass**

Run: `flutter analyze lib/app/modules/packing_slip/form/packing_slip_form_controller.dart`
Expected: No errors (info/warnings consistent with the rest of the file are acceptable).

Run: `flutter test test/unit/packing_slip_dn_reference_resolver_test.dart`
Expected: PASS — the refactor of `_refreshDnDetails` keeps the same logic the resolver tests already cover.

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/packing_slip/form/packing_slip_form_controller.dart
git commit -m "feat(packing-slip): DN-reference validity getters + Resolve action

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Items-tab banner widget

**Files:**
- Create: `lib/app/modules/packing_slip/form/widgets/packing_slip_dn_link_banner.dart`
- Modify: `lib/app/modules/packing_slip/form/packing_slip_form_screen.dart`

- [ ] **Step 1: Create the banner widget**

Create `lib/app/modules/packing_slip/form/widgets/packing_slip_dn_link_banner.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/modules/packing_slip/form/ps_dn_reference_resolver.dart';
import 'package:multimax/app/modules/packing_slip/form/packing_slip_form_controller.dart';

/// Items-tab indicator of Delivery Note reference validity.
///
/// * [DnRefStatus.checking]    → nothing (DN still loading).
/// * [DnRefStatus.allLinked]   → slim green confirmation chip.
/// * [DnRefStatus.hasUnlinked] → amber banner listing orphan rows with a
///   Resolve action (re-match + save) and per-row Remove.
class PackingSlipDnLinkBanner extends StatelessWidget {
  const PackingSlipDnLinkBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<PackingSlipFormController>();
    return Obx(() {
      switch (controller.dnRefStatus) {
        case DnRefStatus.checking:
          return const SizedBox.shrink();
        case DnRefStatus.allLinked:
          return _allLinkedChip();
        case DnRefStatus.hasUnlinked:
          return _unlinkedBanner(controller);
      }
    });
  }

  Widget _allLinkedChip() => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
            const SizedBox(width: 8),
            Text(
              'All items linked to Delivery Note',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.green.shade900),
            ),
          ],
        ),
      );

  Widget _unlinkedBanner(PackingSlipFormController controller) {
    final orphans = controller.unlinkedItems;
    final canEdit = controller.packingSlip.value?.docstatus == 0;
    final isSaving = controller.isSaving.value;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 18, color: Colors.amber.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${orphans.length} packed item(s) aren\'t linked to the '
                  'Delivery Note — they will block submission in ERPNext.',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.amber.shade900),
                ),
              ),
            ],
          ),
          if (canEdit) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed:
                    isSaving ? null : controller.resolveDnReferencesAndSave,
                icon: isSaving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_fix_high, size: 16),
                label: const Text('Resolve'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade700,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
            const Divider(height: 16),
            ...orphans.map((o) => _orphanTile(controller, o, canEdit)),
          ],
        ],
      ),
    );
  }

  Widget _orphanTile(
    PackingSlipFormController controller,
    PackingSlipItem item,
    bool canEdit,
  ) {
    final serial = item.customInvoiceSerialNumber;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${item.itemCode}  ·  ${item.qty} ${item.uom}'
              '${serial != null && serial != '0' ? '  ·  #$serial' : ''}',
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (canEdit)
            IconButton(
              icon: Icon(Icons.delete_outline,
                  size: 18, color: Colors.red.shade400),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(4),
              tooltip: 'Remove',
              onPressed: () => controller.deleteItem(item),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Mount the banner in the Items tab**

In `lib/app/modules/packing_slip/form/packing_slip_form_screen.dart`, add the import near the other form imports (after the `barcode_input_widget.dart` import at line 12):

```dart
import 'package:multimax/app/modules/packing_slip/form/widgets/packing_slip_dn_link_banner.dart';
```

Then in `_buildItemsView`, insert the banner between the filter-chip `Divider` and the `Expanded` list. Locate (around lines 230-231):

```dart
        const Divider(height: 1),
        Expanded(
```

Change to:

```dart
        const Divider(height: 1),
        const PackingSlipDnLinkBanner(),
        Expanded(
```

- [ ] **Step 3: Verify analysis passes**

Run: `flutter analyze lib/app/modules/packing_slip/form/widgets/packing_slip_dn_link_banner.dart lib/app/modules/packing_slip/form/packing_slip_form_screen.dart`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add lib/app/modules/packing_slip/form/widgets/packing_slip_dn_link_banner.dart \
        lib/app/modules/packing_slip/form/packing_slip_form_screen.dart
git commit -m "feat(packing-slip): Items-tab DN-link banner with Resolve action

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Analyze the whole module**

Run: `flutter analyze lib/app/modules/packing_slip`
Expected: No new errors introduced by this work.

- [ ] **Step 2: Run the full unit-test suite**

Run: `flutter test`
Expected: The new `packing_slip_dn_reference_resolver_test.dart` passes. Pre-existing failures noted on `release/play-store` (`status_pill`, `doctype_form_header` widget tests) may remain — confirm no *new* failures are introduced relative to that baseline.

- [ ] **Step 3: Manual smoke (device/emulator)**

1. Open a Packing Slip whose linked DN is Draft and fully linked → green "All items linked to Delivery Note" chip on the Items tab.
2. Construct/observe an orphan (e.g. a slip saved before its DN was amended) → amber banner shows the orphan count + the orphan row(s); tap **Resolve** → snackbar reports linked count, banner flips to green once all resolve and the slip saves.
3. For an orphan with no DN candidate → it remains listed; tap **Remove** → confirmation dialog → row deleted and saved.

---

## Self-Review Notes

- **Spec coverage:** validity model (Task 2 getters + Task 1 `computeDnRefStatus`); resolve mechanism with remaining-qty preference (Task 1 `resolveDnReferences`, Task 2 `resolveDnReferencesAndSave`); `_refreshDnDetails` delegation (Task 2 Step 2); banner with three states + Resolve + Remove (Task 3); error handling via `saveDocument`/`_handleSaveError` and the not-loaded guard (Task 2 Step 4); tests (Task 1). All spec sections map to a task.
- **Minor deviation from spec wording:** the orphan list is rendered inline within the amber banner rather than inside an `ExpansionTile`; this satisfies the "list of orphan rows each with Remove" requirement with less widget complexity and easier reasoning. Counts are typically small.
- **Type consistency:** `resolveDnReferences`, `computeDnRefStatus`, `DnRefStatus`, `validDnItemNames`, `isSlipItemLinked`, `unlinkedItems`, `dnRefStatus`, `resolveDnReferencesAndSave` used identically across Tasks 1-3.
- **No qty/already-packed validation** folded in (out of scope per spec).
