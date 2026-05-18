# App Bar Conventions

This document defines the standard app bar layout for every screen in the app.
All screens use `DocTypeListHeader` (a `SliverAppBar.large` wrapper) as the
unified header. The two screen archetypes — **List View** and **Form View** —
have distinct leading-button and action-bar rules.

---

## 1. List View Screens

### Rule

| Slot | Widget | Why |
|------|--------|-----|
| Leading (left) | ☰ Drawer / Menu `IconButton` | List screens are **top-level destinations** opened from the nav drawer. There is no meaningful parent route to go back to. |
| Actions (right) | Filter icon · Search icon · any extras | Filter and search are the only list-level actions. |

### How to implement

Pass `automaticallyImplyLeading: false` to `DocTypeListHeader`. Flutter then
lets the parent `Scaffold` render the drawer hamburger icon automatically when
a `Scaffold.drawer` is present.

```dart
DocTypeListHeader(
  title: 'Work Orders',
  automaticallyImplyLeading: false,   // ← required for every list screen
  activeFilters: controller.activeFilters
      .map((k, v) => MapEntry(k, v as dynamic))
      .obs,
  onFilterTap: controller.openFilterSheet,
  filterChipsBuilder: _buildFilterChips,
  onClearAllFilters: controller.clearFilters,
),
```

### Screens that must follow this rule

| Screen | File |
|--------|------|
| BOM Search | `manufacturing/reports/bom_search/bom_search_screen.dart` ✅ |
| Work Order List | `work_order/work_order_screen.dart` |
| Material Request List | `material_request/material_request_screen.dart` |
| Purchase Order List | `purchase_order/purchase_order_screen.dart` |
| Purchase Receipt List | `purchase_receipt/purchase_receipt_screen.dart` |
| Delivery Note List | `delivery_note/delivery_note_screen.dart` |
| Stock Entry List | `stock_entry/stock_entry_screen.dart` |
| POS Upload | `pos_upload/pos_upload_screen.dart` |

> **Action item:** audit every screen in the table above and add
> `automaticallyImplyLeading: false` to its `DocTypeListHeader` call if not
> already present.

---

## 2. Form View Screens

### Rule

| Slot | Widget | Why |
|------|--------|-----|
| Leading (left) | ← Back `IconButton` | Form screens are **pushed on top** of a list. The user always has a parent list to return to. |
| Actions (right) | Reload · Save · Share | The three universal document actions, in that order. |

### How to implement

Form screens should **not** set `automaticallyImplyLeading: false` — Flutter's
default (`true`) auto-inserts the back arrow when a predecessor route exists on
the stack. Use `extraActions` to supply the three action icons.

```dart
DocTypeListHeader(
  title: workOrder.name,
  // automaticallyImplyLeading omitted → defaults to true → back arrow shown
  extraActions: [
    IconButton(
      icon: const Icon(Icons.refresh),
      tooltip: 'Reload',
      onPressed: controller.reload,
    ),
    IconButton(
      icon: const Icon(Icons.save_outlined),
      tooltip: 'Save',
      onPressed: controller.save,
    ),
    IconButton(
      icon: const Icon(Icons.share_outlined),
      tooltip: 'Share',
      onPressed: controller.share,
    ),
  ],
),
```

### Screens that must follow this rule

| Screen | File |
|--------|------|
| Work Order Form | `work_order/form/work_order_form_screen.dart` |
| Stock Entry Form | `stock_entry/form/stock_entry_form_screen.dart` |
| Material Request Form | `material_request/form/material_request_form_screen.dart` |
| Purchase Order Form | `purchase_order/form/purchase_order_form_screen.dart` |
| Purchase Receipt Form | `purchase_receipt/form/purchase_receipt_form_screen.dart` |
| Delivery Note Form | `delivery_note/form/delivery_note_form_screen.dart` |

---

## 3. Quick-Reference Cheat Sheet

```
List screen
┌────────────────────────────────────────────────┐
│ ☰  BOM Search                  🔽  🔍         │  ← collapsed
│                                                │
│ BOM Search                                     │  ← expanded
│                                                │
│ [Item Code 1: 2001423 ✕]                       │  ← filter chips
└────────────────────────────────────────────────┘
  automaticallyImplyLeading: false
  extraActions: [ filter, search ]

Form screen
┌────────────────────────────────────────────────┐
│ ←  BOM-3000015-001          🔄  💾  ↗         │  ← collapsed
│                                                │
│ BOM-3000015-001                                │  ← expanded
└────────────────────────────────────────────────┘
  automaticallyImplyLeading: true (default)
  extraActions: [ reload, save, share ]
```

---

## 4. Suggestions for Future Improvement

### 4.1 — Lint rule: enforce `automaticallyImplyLeading: false` on list screens

Consider a custom `dart analyze` lint (via `custom_lint` package) that warns
whenever `DocTypeListHeader` is used inside a file whose name ends with
`_screen.dart` (but not `_form_screen.dart`) without
`automaticallyImplyLeading: false`. This catches omissions at CI time rather
than during manual review.

### 4.2 — Introduce a `DocTypeFormHeader` widget

The form action pattern (reload · save · share) is repeated across every form
screen. Extract it into a dedicated `DocTypeFormHeader` widget that accepts
`onReload`, `onSave`, `onShare` callbacks and always renders with
`automaticallyImplyLeading: true`. This eliminates copy-paste drift between
form screens and makes the three-action contract explicit at the type level.

```dart
// Proposed API
DocTypeFormHeader(
  title: workOrder.name,
  docStatus: controller.docStatus,   // drives Save button enabled/disabled
  onReload: controller.reload,
  onSave: controller.save,
  onShare: controller.share,
)
```

### 4.3 — Encode the convention in `DocTypeListHeader`'s doc comment

Add a `/// List screens: pass automaticallyImplyLeading: false.` line directly
above the `automaticallyImplyLeading` parameter declaration so every developer
sees the rule in their IDE without having to consult this document.

### 4.4 — Centralise the `Scaffold.drawer` so all list screens share it

If each list screen constructs its own `Scaffold`, duplicate drawer definitions
are a risk. Consider a shared `AppShell` widget (a single `Scaffold` with the
drawer) and use `Navigator` or `GetX`'s nested navigation for the body. This
guarantees the hamburger icon always appears for `automaticallyImplyLeading: false`
screens — it only works if the `Scaffold` that owns the route also has a
`drawer` set.
