# BOM DocTypeFormHeader Parity Design

**Date:** 2026-05-23
**Status:** Approved

## Problem

`BomFormScreen` uses `DocTypeFormHeader` but passes neither `docType` nor `statusLabel`, so the header renders without the maroon doctype label or status pill. Every other form screen in the app (Delivery Note, Work Order, Packing Slip, Material Request, Purchase Order, Purchase Receipt, Stock Entry) already passes both fields.

Additionally, `_BomHeaderCard` renders a `StatusPill` inline in the item/name row — a duplicate once the header carries the pill.

## Design

### Single file changed: `lib/app/modules/bom/form/bom_form_screen.dart`

**1. `DocTypeFormHeader` call — add two params**

```dart
DocTypeFormHeader(
  title:       bom?.name ?? controller.bomName,
  docType:     'Bill of Materials',   // ← add
  statusLabel: bom?.status,           // ← add
  canSave:     isDirty,
  ...
)
```

`bom?.status` is a derived getter on `BOM` returning `'Draft'` (docstatus 0), `'Active'` / `'Inactive'` (docstatus 1), or `'Cancelled'` (docstatus 2). No model or controller changes needed.

**2. `_BomHeaderCard` item row — remove duplicate StatusPill**

```dart
Row(
  children: [
    Expanded(child: Column(...)),   // item code + name — unchanged
    // StatusPill(status: bom.status) ← remove
  ],
),
```

The header is now the single source of truth for document status.

## Out of Scope

- `onReload` support (not requested; BomFormController exposes no public reload method)
- Any other card/tab layout changes
