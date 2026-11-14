# Packing Slip — Multi-Serial Picker in Item Sheet — Design

**Date:** 2026-06-12
**Status:** Approved
**Builds on:** the scan auto-advance fix (`dn_scan_item_matcher.dart`, same date) and the
Allow Full Serial Toggle infrastructure (`SerialDropdownItem.isFull`,
`SharedInvoiceSerialNumberField` dimming/disabling, 2026-05-23).

## Problem

When the same item code appears on multiple Delivery Note rows (one per invoice
serial), the Packing Slip item sheet shows only a single read-only serial — the
one the scan or tap resolved to. The user cannot see sibling serials' status or
choose to pack against a different serial. The scan auto-advance fix picks the
next unfilled row automatically, but the sheet still hides the alternatives.

## Decision summary (user-confirmed)

1. **Serial scope:** the dropdown lists only serials whose DN rows match the
   scanned item code (and the scanned batch, when a batch was scanned).
2. **Entry points:** both the scan-opened sheet and the tap-to-add sheet get the
   dropdown, pre-selected to the auto-resolved / tapped row. Edit mode stays
   locked to its serial (single-element list, as today).
3. **Allow Full:** suppressed in Packing Slip. Full serials are dimmed with
   "— Full" and hard-disabled. Rationale: PS qty validation treats a 0 cap as
   "uncapped", so allowing a Full serial could permit over-packing the DN row.

## Architecture

Approach: child-driven re-targeting. The PS sheet child controller exposes all
matching serials through the existing `SerialFieldMixin` hooks; a worker on
`selectedSerial` asks the parent to re-target the sheet session when the user
picks a different serial. `SharedInvoiceSerialNumberField` is reused unchanged
apart from a toggle-suppression gate.

### 1. Pure option builder — `lib/app/modules/packing_slip/form/ps_serial_options.dart` (new)

```dart
class PsSerialOption {
  final String serial;
  final DeliveryNoteItem dnRow;  // representative row for this serial
  final double qty;              // DN row qty
  final double remaining;        // qty − packed (current + related slips)
}

List<PsSerialOption> buildPsSerialOptions({
  required List<DeliveryNoteItem> items,
  required String code,
  required String? batch,                              // scanned batch or null
  required double Function(DeliveryNoteItem) remainingQty,
})
```

Rules:
- Filter: `itemCode == code`; when `batch != null`, `batchNo == batch`;
  serial is non-null, non-empty, and not the `'0'` sentinel.
- Deduplicate by serial (dropdown values must be unique): prefer the first row
  with `remainingQty > 0`, else the first row — mirrors `findScannedDnItem`.
- Sort ascending by numeric serial (`int.tryParse(s) ?? 9999`, matching
  `_allDnSerials`).

### 2. `SerialFieldMixin` — `supportsAllowFullToggle`

New overridable getter, default `true` (DN/SE unchanged). When `false`,
`SharedInvoiceSerialNumberField` hides the Allow Full toggle and keeps Full
rows disabled regardless of `allowFullSerials`.

### 3. Parent — `PackingSlipFormController`

- New session field `String? currentScannedBatch` — the batch from the scan
  result, `null` for tap-to-add. `prepareSheetForAdd` gains an optional
  `scannedBatch` parameter; `_handleScanResult` passes `result.batchNo`.
- `bsBatchNo = RxnString()` — reactive batch for the sheet's batch tile,
  seeded in `_populateItemDetails`. The `BatchDisplayTile` custom field is
  wrapped in `Obx` so it updates (or hides) when re-targeting changes the row.
- The serial badge's `posItemQtyOverride` reads the child's live
  `selectedSerial` instead of capturing the open-time serial.
- `serialOptionsForSheet()` → `buildPsSerialOptions` with `currentItemCode`,
  `currentScannedBatch`, and `_calcRemainingQtyForDnItem`.
- `retargetSheetToSerial(String serial)`: resolves the option, then
  `_populateItemDetails(option.dnRow)` and `bsMaxQty.value = option.remaining`.

### 4. Child — `PackingSlipItemFormController`

- `supportsAllowFullToggle => false`.
- `availableSerialNos`: `[]` when no POS Upload (unchanged gate); pinned
  single-element list in edit mode (unchanged); otherwise the serials from
  `parent.serialOptionsForSheet()`.
- `posDropdownItemFor(serial)`: option lookup + `parent.getPosItemName(serial)`;
  `qty` = DN row qty, `remaining` = DN-row remaining, `used = qty − remaining`.
  `isFull` therefore reflects the DN row being fully packed across the current
  and related slips.
- Stored `Worker` on `selectedSerial` (created in `initialise` after the seed,
  cancelled in `onClose` before `super.onClose()`): on change in add mode,
  calls `parent.retargetSheetToSerial`, re-prefills qty from the new
  `bsMaxQty`, and revalidates.

## Safety notes

- Auto-submit fires on `saveButtonState == success` (explicit save), not on
  validity; programmatic qty writes reset state to idle via
  `_resetSaveStateOnEdit`. Serial switching therefore cannot auto-pack.
- `ever` workers fire only on changes after creation; the initial serial seed
  happens before worker creation, so no spurious retarget on sheet open.
- `_mergeItemQty` / `_addItemToList` read the session context
  (`currentItemDnDetail`, `currentSerial`, `currentBatchNo`) which
  `retargetSheetToSerial` re-seeds, so the packed row lands on the chosen
  serial's DN row.

## Testing

TDD throughout:
- Unit tests for `buildPsSerialOptions` (code/batch filtering, `'0'` exclusion,
  numeric sort, per-serial dedupe preference, qty/remaining values).
- Widget test for `SharedInvoiceSerialNumberField`: Allow Full toggle hidden
  when `supportsAllowFullToggle == false` and a Full row exists; still shown
  for default adopters.
- Existing `findScannedDnItem` and `refreshDnDetails` tests must stay green.

## Out of scope

- Showing the dropdown when no POS Upload is loaded.
- Changing a packed item's serial in edit mode.
- Any over-pack allowance (Allow Full) for Packing Slip.
