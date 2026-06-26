# POS Upload — Unified Export Sheet (Delivery Note / Packing Slip)

**Date:** 2026-06-11
**Status:** Approved
**Module:** `lib/app/modules/pos_upload/form/`

## Problem

The POS Upload form's share action exports only the Packing Slip:

> Dashboard → Menu → POS Upload → Share → "Export Packing Slip" sheet → Share as Excel

Operators also need an Excel export of the linked **Delivery Note**. The DN
resolves earlier in the document lifecycle than packing slips (packing may not
have started), so the share action should not be gated on packing slips alone.

## Decision

Replace the single-purpose sheet with **one unified bottom sheet** containing a
`SegmentedButton` that picks the document type (Delivery Note / Packing Slip),
with the export options below adapting to the selection. Chosen over a
two-step picker→config flow (extra tap + sheet transition per export) and an
anchored popup menu (small top-right targets, poor for one-handed warehouse
devices).

The DN export **mirrors the Packing Slip Excel style** (same column set minus
Case #, same Compact toggle, same sort behaviour) so the team reads one
consistent output format.

## UI Specification

### Entry point (share icon, `DocTypeFormHeader.onShare`)

Enabled when either export is possible:

```dart
final canShare = controller.deliveryNote.value != null ||
    controller.packingSlips.isNotEmpty;
```

Gating on the retained `deliveryNote` object (rather than
`linkedDocType`/`linkedDocName`) is deliberately stricter: if the DN list
resolves but the detail fetch fails, the export stays disabled instead of
opening a sheet that would throw.

- ML/KA uploads: icon enables as soon as the DN resolves (earlier than today).
- MX/KX (Stock Entry-linked) uploads: icon stays disabled (unchanged).

### Bottom sheet — "Export as Excel"

```
┌──────────────────────────────────┐
│  Export as Excel                 │
│ ┌───────────────┬──────────────┐ │
│ │ ● Delivery    │ ○ Packing    │ │
│ │   Note        │   Slip       │ │
│ └───────────────┴──────────────┘ │
│  (helper line when a segment     │
│   is disabled)                   │
│  Compact              [ ON ● ]   │
│  Sort by   [ None (natural) ▾ ]  │
│  [ 📊  Share as Excel        ]   │
└──────────────────────────────────┘
```

- **Selector:** `SegmentedButton<ExportDocType>` (new
  `enum ExportDocType { deliveryNote, packingSlip }`). Icons match the
  linked-doc banners: `local_shipping_outlined` (DN),
  `inventory_outlined` (PS).
- **Default selection:** Packing Slip when `packingSlips.isNotEmpty`
  (current, most-used export), otherwise Delivery Note. Happy path stays
  2 taps: Share → Share as Excel.
- **Disabled segments:** PS segment disabled when no packing slips, with a
  one-line helper below the selector: "No packing slips yet". DN segment
  disabled when no DN resolved (rare — icon gating prevents it).
- **Options (shared by both doc types):**
  - *Compact* switch — identical semantics for both exports. Subtitle lists
    the active column set.
  - *Sort by* dropdown — items come from the selected doc type's column
    list. On segment switch, `sortByColumn` resets to `null` **only if** the
    selected column does not exist for the new doc type (in the mirrored
    column sets the only such column is **Case #**, PS-only).
- **Primary button:** existing `FilledButton.icon` pattern with in-button
  spinner and disabled controls while exporting (unchanged from current
  sheet).
- **Share payload:** filename
  `POS Upload - <safeName> - <Delivery Note|Packing Slip> - <timestamp>.xlsx`;
  share subject `"<POS Upload name> – <Delivery Note|Packing Slip>"`.

## Data & Controller Changes (`PosUploadFormController`)

1. **Retain the DN:** add `final deliveryNote = Rxn<DeliveryNote>();` and set
   it inside `_fetchDeliveryNote` where the `DeliveryNote` is already parsed
   (no new API call). Clear it when the linked doc resolves to none.
2. **New builder:** `Future<String> buildDeliveryNoteExcel({required bool
   compact, String? sortByColumn})`, parallel to `buildPackingSlipExcel`:
   - Runs row building + encoding in a `compute()` isolate.
   - Throws `Exception('No delivery note data available')` if
     `deliveryNote.value == null`.
3. **DN columns:**
   - Compact: `Invoice Serial #, Item Name, Qty, Country of Origin`
   - Full: `Invoice Serial #, Variant Of, Item Code, Item Name, Qty,
     Country of Origin`
   - No Case # column — cases are Packing Slip-level data.
4. **Row semantics (mirrors PS builder):**
   - Item name resolves from POS Upload items via
     `itemNameByIdx[customInvoiceSerialNumber]`, falling back to the DN
     item's own `itemName`.
   - Rows with identical key (all displayed text columns) aggregate `qty`.
   - Sorting reuses the existing comparator logic; sorted column moves to
     the first position, as in the PS export.
5. **Sheet header rows:** "Delivery Note", DN name, and the export date
   (`DateTime.now()`, format `dd MMM yyyy`) — same layout as the PS
   export's header block, which also uses the export date.
   *(Post-smoke-test change: originally the document's posting date.)*
6. **Totals row:** both exports declare a table totals row
   (`totalsRowCount="1"`) with a "Total" label in the first column and a
   filter-aware `SUBTOTAL(109, …)` sum over the Qty column. Skipped when
   there are no data rows. *(Post-smoke-test addition.)*
7. **Excel Table injection:** `_injectExcelTable` reused; the hardcoded
   `PackingSlipTable` name becomes a parameter
   (`DeliveryNoteTable` / `PackingSlipTable`).
7. **Implementation note:** the `_PSRow`/`_PSCol` record machinery is shared;
   case fields are simply unused for DN rows. Either a second top-level
   isolate function or one shared function taking a column list — planner's
   choice, no structural refactor required.

## Error Handling

Unchanged pattern from the current sheet: build/share failures keep the sheet
open, re-enable the button (`isExporting = false`), and surface
`GlobalSnackbar.error('Export failed: …')`.

## Testing

- Unit tests for `buildDeliveryNoteExcel` (or its isolate function): row
  aggregation by key, qty summation, sort + column reorder, compact vs full
  column sets, item-name fallback when serial not found in POS items.
- Existing PS export tests must keep passing (table-name parameterisation is
  the only touchpoint).
- Widget behaviours (segment disable states, default selection rule, Case #
  sort reset on segment switch) verified by device smoke test, consistent
  with prior POS Upload features.

## Out of Scope

- Any export for Stock Entry-linked (MX/KX) uploads.
- Changes to the Packing Slip export's columns or row logic.
- Navigation from the linked-doc banner (existing TODO, untouched).
