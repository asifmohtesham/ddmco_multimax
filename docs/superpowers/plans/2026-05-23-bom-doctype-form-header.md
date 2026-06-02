# BOM DocTypeFormHeader Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire `docType` and `statusLabel` into the BOM form's `DocTypeFormHeader`, and remove the now-redundant `StatusPill` from `_BomHeaderCard`.

**Architecture:** Single-file edit in `bom_form_screen.dart` — two surgical changes. No controller, model, or routing changes. The `bom.status` derived getter already returns the correct label string; this plan only connects it to the existing widget API.

**Tech Stack:** Flutter, GetX, `DocTypeFormHeader` (global_widgets)

---

### Task 1: Wire docType + statusLabel and remove duplicate StatusPill

**Files:**
- Modify: `lib/app/modules/bom/form/bom_form_screen.dart`

#### Edit A — `DocTypeFormHeader` call (around line 38)

- [ ] **Step 1: Open the file and locate the `DocTypeFormHeader` call**

In `bom_form_screen.dart`, the `headerSliverBuilder` block starts around line 37. The current call looks like:

```dart
DocTypeFormHeader(
  title:      bom?.name ?? controller.bomName,
  canSave:    isDirty,
  docStatus:  bom?.docstatus ?? 0,
  isSaving:   isSaving,
  saveResult: saveResult,
  onSave:     isDirty ? controller.save : null,
  extraActions: [...],
  bottom: const TabBar(...),
),
```

- [ ] **Step 2: Add `docType` and `statusLabel` params**

Insert the two new named params immediately after `title:`:

```dart
DocTypeFormHeader(
  title:       bom?.name ?? controller.bomName,
  docType:     'Bill of Materials',
  statusLabel: bom?.status,
  canSave:     isDirty,
  docStatus:   bom?.docstatus ?? 0,
  isSaving:    isSaving,
  saveResult:  saveResult,
  onSave:      isDirty ? controller.save : null,
  extraActions: [
    if (bom != null)
      IconButton(
        icon: const Icon(Icons.precision_manufacturing_outlined),
        tooltip: 'Create Work Order',
        onPressed: controller.createWorkOrder,
      ),
  ],
  bottom: const TabBar(
    tabs: [
      Tab(text: 'Items'),
      Tab(text: 'Exploded Items'),
      Tab(text: 'Costing'),
    ],
  ),
),
```

#### Edit B — `_BomHeaderCard` item row (around line 110)

- [ ] **Step 3: Remove `StatusPill` from the item/name row**

The current Row in `_BomHeaderCard.build` looks like:

```dart
Row(
  children: [
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            bom.item,
            style: text.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if ((bom.itemName ?? '').isNotEmpty)
            Text(
              bom.itemName!,
              style: text.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    ),
    StatusPill(status: bom.status),   // ← remove this line
  ],
),
```

Remove the `StatusPill(status: bom.status),` line. The `Row` with its single `Expanded` child is valid and requires no further changes.

After the edit the row reads:

```dart
Row(
  children: [
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            bom.item,
            style: text.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if ((bom.itemName ?? '').isNotEmpty)
            Text(
              bom.itemName!,
              style: text.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    ),
  ],
),
```

#### Verify & commit

- [ ] **Step 4: Run the analyzer**

```bash
flutter analyze lib/app/modules/bom/form/bom_form_screen.dart
```

Expected output: `No issues found!` (or only pre-existing warnings unrelated to this file).

- [ ] **Step 5: Smoke-test on device**

Navigate to any BOM form. Verify:
- Expanded header shows `BILL OF MATERIALS` label (maroon, uppercase) and the status pill (e.g. `Active`, `Draft`)
- Collapsed (scrolled) header shows the maroon label + compact pill in the top line
- `_BomHeaderCard` no longer shows a `StatusPill` in the item row
- "Unsaved changes" amber indicator still appears after toggling Active/Default

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/bom/form/bom_form_screen.dart
git commit -m "feat(bom): wire docType, statusLabel into DocTypeFormHeader; remove duplicate StatusPill from card"
```
