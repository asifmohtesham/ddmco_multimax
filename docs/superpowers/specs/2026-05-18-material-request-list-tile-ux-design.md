# Material Request List Tile — UI/UX Improvement

**Date:** 2026-05-18  
**Scope:** `material_request_screen.dart`, `material_request_provider.dart`, `material_request_model.dart`

---

## Goal

Improve both the collapsed and expanded states of the Material Request list tile:
- **Collapsed:** surface owner, last-modified, and total quantity without requiring expansion
- **Expanded:** better visual hierarchy through three distinct content zones and a merged footer

---

## Section 1 — API / Data Layer

**File:** `lib/app/data/providers/material_request_provider.dart`

Add three fields to the `getMaterialRequests()` list fetch:

```dart
fields: [
  'name', 'transaction_date', 'schedule_date', 'status', 'docstatus',
  'material_request_type', 'owner', 'modified', 'total_qty'
]
```

`owner`, `modified`, and `total_qty` are standard Frappe fields — no backend changes required.

**File:** `lib/app/data/models/material_request_model.dart`

Add `totalQty` field (double) to `MaterialRequest`:

```dart
final double totalQty;
```

Parse from JSON:
```dart
totalQty: double.tryParse(json['total_qty']?.toString() ?? '0') ?? 0.0,
```

---

## Section 2 — Collapsed Tile

**File:** `lib/app/modules/material_request/material_request_screen.dart`

### Changes to the `GenericDocumentCard` call

**Remove** the redundant type stat:
```dart
// DELETE this:
GenericDocumentCard.buildIconStat(context, Icons.assignment_outlined, req.materialRequestType),
```

**Replace** with total qty stat:
```dart
GenericDocumentCard.buildIconStat(
  context,
  Icons.inventory_2_outlined,
  '${req.totalQty.toStringAsFixed(0)} qty',
),
```

**Add** `auditStats` parameter with owner and modified:
```dart
auditStats: [
  GenericDocumentCard.buildIconStat(
    context,
    Icons.person_outline,
    _abbreviateOwner(req.owner ?? '—'),
  ),
  GenericDocumentCard.buildIconStat(
    context,
    Icons.edit_outlined,
    FormattingHelper.getRelativeTime(req.modified),
  ),
],
```

**Helper** (add as a private method on `_MaterialRequestScreenState`):
```dart
String _abbreviateOwner(String email) {
  if (email == '—') return '—';
  return email.split('@').first;
}
```

### Resulting collapsed tile layout

```
[Material Issue]              [Draft]
MAT-MR-2025-00002
[📦 120 qty] [🕐 4mo ago] [📅 Due 4mo ago]   ⌄
[👤 asif] [✏️ 4mo ago]
```

---

## Section 3 — Expanded Section Polish

**File:** `lib/app/modules/material_request/material_request_screen.dart`

Restructure `_buildExpandedContent` into three visual zones plus a merged footer.

### Zone 1 — Warehouse
No structural change. Keep existing `InfoBlock` for `setWarehouse`.

### Zone 2 — Dates
Wrap the existing two-column date row in a tinted rounded container:

```dart
Container(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  decoration: BoxDecoration(
    color: colorScheme.surfaceContainerHighest,
    borderRadius: BorderRadius.circular(8),
  ),
  child: Row(/* existing _infoCell widgets */),
)
```

### Zone 3 — Items
Keep the existing `InfoBlock` + `_miniStat` row. Below the mini-stats row, add a fulfillment progress bar:

```dart
// After the existing _miniStat Row:
const SizedBox(height: 8),
ClipRRect(
  borderRadius: BorderRadius.circular(4),
  child: LinearProgressIndicator(
    value: totalQty > 0 ? (orderedQty / totalQty).clamp(0.0, 1.0) : 0.0,
    minHeight: 4,
    backgroundColor: colorScheme.surfaceContainerHighest,
    valueColor: AlwaysStoppedAnimation<Color>(
      orderedQty >= totalQty ? Colors.green : colorScheme.primary,
    ),
  ),
),
```

Where `orderedQty` = `detailed.items.fold(0.0, (sum, i) => sum + i.orderedQty)` and `totalQty` = `detailed.items.fold(0.0, (sum, i) => sum + i.qty)`.

### Footer — Merged Row
Replace the current two-row footer (owner+modified row + action buttons row) with a single row:

```dart
Row(
  children: [
    Icon(Icons.person_outline, size: 14, color: colorScheme.onSurfaceVariant),
    const SizedBox(width: 6),
    Expanded(
      child: Text(
        _abbreviateOwner(detailed.owner ?? '—'),
        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        overflow: TextOverflow.ellipsis,
      ),
    ),
    // Action buttons (delete + edit/view) — unchanged logic
    if (detailed.docstatus == 0) ...[
      RoleGuard(...delete button...),
      const SizedBox(width: 8),
      RoleGuard(...edit button...),
    ] else ...[
      ...view button...
    ],
  ],
)
```

The standalone `modified` time is removed from the footer — it is now visible in the collapsed tile's audit stats row.

---

## Files to Modify

| File | Change |
|------|--------|
| `lib/app/data/providers/material_request_provider.dart` | Add `owner`, `modified`, `total_qty` to list fields |
| `lib/app/data/models/material_request_model.dart` | Add `totalQty` field, parse from JSON |
| `lib/app/modules/material_request/material_request_screen.dart` | Collapsed tile stats, expanded zones, merged footer |

No changes to `GenericDocumentCard` — it already supports `auditStats`.

---

## Non-Goals

- No changes to the filter sheet, form screen, or any other module
- No new API endpoints or backend changes
- No changes to `GenericDocumentCard`
