# DocType Header Redesign — Design Spec

**Date:** 2026-05-23  
**Branch:** `release/play-store-beta-1-build-5`  
**Approach:** C — standalone `DocTypeFormHeader` sliver; `DocTypeListHeader` untouched

---

## 1. Problem

The current `DocTypeFormHeader` is a thin wrapper over `DocTypeListHeader`. As form-screen requirements diverge (two-line collapsed toolbar, status pill, doc-type label, unsaved-changes indicator), sharing a delegate creates growing complexity and regression risk in the list header. The existing `StatusPill` widget also has incorrect and incomplete colour mappings that do not match ERPNext v16.

---

## 2. Goals

1. Form headers show the document name, doc-type label, workflow status pill, and unsaved-changes indicator at all scroll positions.
2. Excellent colour contrast; status pill colours match ERPNext v16 verbatim.
3. `DocTypeListHeader` is not modified — zero risk of regressions on list screens.
4. Commit `48e1596b` fix must not regress: `SaveIconButton` must not receive `color: cs.onPrimary`; `extraActionsKey` in `DocTypeListHeader` may remain but is no longer relied upon by form screens.

---

## 3. Out of Scope

- `DocTypeListHeader` changes of any kind.
- Dark-mode support (app is light-only today).
- Lint rule for `automaticallyImplyLeading` (noted in `docs/app_bar_conventions.md §4.1` — separate task).

---

## 4. Visual Design

### 4.1 Expanded state (user at top of screen)

```
┌──────────────────────────────────────────────────┐
│  ← [title faded]                  ↻  💾  ↗      │  ← 56dp toolbar row
├──────────────────────────────────────────────────┤
│  WORK ORDER                                      │  ← 11sp maroon (#870E18) label
│  WO-2024-00123                                   │  ← 24sp bold doc name
│  [Draft]  ● Unsaved changes                      │  ← status pill + amber indicator
└──────────────────────────────────────────────────┘
```

- Doc-type label: 11sp, weight 700, letter-spacing 0.07em, uppercase, `#870E18`
- Doc name: 24sp, weight 800, `#171717`
- Status pill: Frappe UI subtle badge (see §6)
- Unsaved indicator: `● Unsaved changes`, 11sp, weight 600, amber `#DB7706` — visible only when `canSave && docStatus == 0`
- Large title fades as `shrinkOffset` increases (same `Opacity(expandProgress)` pattern as `DocTypeListHeader`)

### 4.2 Collapsed state (scrolled)

```
┌──────────────────────────────────────────────────┐
│  ← WORK ORDER  [Draft]             ↻  💾  ↗     │  ← line 1: 10sp maroon cap + pill
│    WO-2024-00123                                  │  ← line 2: 15sp bold navy name
└──────────────────────────────────────────────────┘
   64dp total toolbar height
```

- Caption line: 10sp, weight 700, letter-spacing 0.07em, uppercase, `#870E18` + inline status pill (14dp height, 9sp)
- Doc name: 15sp, weight 700, `#25286F`, `AutoSizeText` with same min-font / max-lines as list header

### 4.3 Save button states

| State | Visual |
|---|---|
| `isDirty && docStatus == 0` | `IconButton.filled` with `#25286F` background, white icon — requires `showFilledWhenDirty: true` on `SaveIconButton` |
| `isSaving` | `CircularProgressIndicator` (existing `SaveIconButton` behaviour) |
| `saveResult == success` | Green check for 1.5 s (existing `SaveIconButton` behaviour) |
| `saveResult == error` | Red error icon for 1.5 s (existing `SaveIconButton` behaviour) |
| clean / submitted / cancelled | Icon at reduced opacity (default disabled behaviour — no explicit `color:`) |

**Regression guard:** The new `showFilledWhenDirty` param uses `IconButton.filled` (which picks its own foreground colour automatically). The plain/disabled state must still carry no explicit `color:` argument — the fix from commit `48e1596b` that removed `color: cs.onPrimary` must not be re-introduced in any state branch.

---

## 5. Architecture

### 5.1 Files changed

| File | Change |
|---|---|
| `global_widgets/doctype_form_header.dart` | Full rewrite — standalone `SliverPersistentHeader` |
| `global_widgets/status_pill.dart` | Full rewrite — correct ERPNext v16 colour map |
| `global_widgets/save_icon_button.dart` | Add `showFilledWhenDirty` param (backward-compat, default `false`) |
| `global_widgets/doctype_list_header.dart` | **Untouched** |
| `modules/*/form/*_form_screen.dart` | Add `docType` + `statusLabel` params (6 screens) |

### 5.2 New `DocTypeFormHeader` public API

```dart
class DocTypeFormHeader extends StatelessWidget {
  final String title;          // doc ID — e.g. "WO-2024-00123"
  final String? docType;       // e.g. "Work Order" — shown as maroon label
  final String? statusLabel;   // e.g. "Draft" — drives StatusPill; nullable = no pill

  final VoidCallback? onReload;
  final VoidCallback? onSave;
  final VoidCallback? onShare;

  final bool canSave;          // default false
  final int  docStatus;        // 0 draft · 1 submitted · 2 cancelled; default 0
  final bool isSaving;         // default false
  final SaveResult saveResult; // default SaveResult.idle

  final PreferredSizeWidget? bottom;
  final List<Widget>? extraActions;
}
```

`docType` and `statusLabel` are nullable so existing call sites that don't yet pass them compile and render without label or pill (no breaking change).

### 5.3 `_DocTypeFormHeaderDelegate` extents

```
minExtent = statusBarHeight + 64dp + bottomHeight
maxExtent = statusBarHeight + 56dp + 96dp + bottomHeight
          = statusBarHeight + 152dp + bottomHeight
```

The 64dp collapsed toolbar (vs 56dp in `DocTypeListHeader`) is needed to fit the two-line caption + doc name.

### 5.4 `shouldRebuild` fields compared

```dart
return title          != old.title          ||
       docType        != old.docType        ||
       statusLabel    != old.statusLabel    ||
       canSave        != old.canSave        ||
       isSaving       != old.isSaving       ||
       saveResult     != old.saveResult     ||
       docStatus      != old.docStatus      ||
       statusBarHeight!= old.statusBarHeight||
       (extraActions?.length ?? 0) != (old.extraActions?.length ?? 0);
```

No `Obx` wrapper is needed — the parent screen already wraps its `build` in `Obx`, so `DocTypeFormHeader` is rebuilt whenever any reactive state changes. `shouldRebuild` is the sliver-level guard against redundant delegate swaps.

### 5.5 No `extraActionsKey` dependency

`DocTypeFormHeader` no longer delegates to `DocTypeListHeader`, so it does not need to pass `extraActionsKey`. The `extraActionsKey` param remains in `DocTypeListHeader` for future use but is not called by any form screen after this change.

---

## 6. StatusPill — Complete ERPNext v16 Colour Map

All hex values sourced from Frappe UI `tailwind/colors.json` semantic tokens.

| Frappe indicator | bg token | bg hex | text token | text hex |
|---|---|---|---|---|
| `red` | `surface-red-2` | `#FFE7E7` | `ink-red-4` | `#CC2929` |
| `orange` | `surface-amber-1` | `#FDFAED` | `ink-amber-3` | `#DB7706` |
| `yellow` | `yellow/100` | `#FFF7D3` | `yellow/700` | `#AB6E05` |
| `green` | `surface-green-2` | `#E4FAEB` | `ink-green-3` | `#278F5E` |
| `blue` | `surface-blue-2` | `#E6F4FF` | `ink-blue-2` | `#0289F7` |
| `gray` | `surface-gray-2` | `#F3F3F3` | `ink-gray-6` | `#525252` |

### Status-to-colour mapping (verbatim from ERPNext v16 listview JS + indicator.js + guess_style)

**Red** (`#FFE7E7` / `#CC2929`):  
`Draft`, `Cancelled`, `Open`, `Not Started`, `Stopped`, `Rejected`, `Expired`, `Overdue`
- Source: `indicator.js` docstatus 0/2; `work_order_list.js`; `material_request_list.js`; `utils.js guess_style`

**Blue** (`#E6F4FF` / `#0289F7`):  
`Submitted`, `Stock Reserved`
- Source: `indicator.js` docstatus 1; `work_order_list.js`

**Orange** (`#FDFAED` / `#DB7706`):  
`To Bill`, `On Hold`, `Hold`, `In Process`, `Pending`, `Not Saved`,  
`To Receive and Bill`, `To Receive`, `Stock Partially Reserved`, `Material Returned from WIP`
- Source: `delivery_note_list.js`; `purchase_order_list.js`; `purchase_receipt_list.js`; `work_order_list.js`; `material_request_list.js`; `stock_entry_list.js`; `indicator.js` (`__unsaved`)

**Yellow** (`#FFF7D3` / `#AB6E05`):  
`Partially Billed`, `Partly Billed`, `In Transit`, `Partially Ordered`, `Partially Received`
- Source: `delivery_note_list.js`; `purchase_receipt_list.js`; `material_request_list.js`

**Green** (`#E4FAEB` / `#278F5E`):  
`Completed`, `Active`, `Paid`, `Settled`, `Enabled`, `Closed`,  
`Ordered`, `Transferred`, `Issued`, `Received`, `Goods Transferred`
- Source: all list views; `utils.js guess_style`

**Gray** (`#F3F3F3` / `#525252`) — default for unknown statuses:  
`In Progress`, `Disabled`, `Passive`, `Return`, `Return Issued`,  
`Goods In Transit`, `To Pay`
- Source: `utils.js guess_style` (no keyword match); explicit list view returns

### Fixes vs current `status_pill.dart`

| Status | Current (wrong) | Corrected |
|---|---|---|
| `Submitted` | green | **blue** |
| `Open` | blue | **red** |
| `Closed` | gray | **green** |
| `In Progress` | blue | **gray** |

### Additions (not currently handled)

`Not Started`, `Stopped`, `In Process`, `Stock Reserved`, `Stock Partially Reserved`,  
`Partially Billed`, `Partly Billed`, `To Receive and Bill`, `To Receive`,  
`Partially Ordered`, `Partially Received`, `In Transit`,  
`Ordered`, `Transferred`, `Issued`, `Received`, `Goods Transferred`,  
`Return`, `Return Issued`, `Goods In Transit`, `To Pay`, `Material Returned from WIP`

---

## 7. Call-Site Changes (6 form screens)

Each screen adds two params to its existing `DocTypeFormHeader(...)` call:

```dart
// Example — work_order_form_screen.dart
DocTypeFormHeader(
  title:       title,
  docType:     'Work Order',                          // ADD
  statusLabel: wo?.status,                            // ADD — e.g. "Draft", "In Process"
  onSave:      controller.canEdit ? controller.save : null,
  onReload:    controller.mode != 'new' ? controller.reload : null,
  isSaving:    controller.isSaving.value,
  canSave:     controller.isDirty.value,
  docStatus:   wo?.docstatus ?? 0,
)
```

Screens to update:

| Screen | `docType` string | `statusLabel` field |
|---|---|---|
| `work_order_form_screen.dart` | `'Work Order'` | `wo?.status` |
| `stock_entry/form/stock_entry_form_screen.dart` | `'Stock Entry'` | `entry?.status` |
| `delivery_note/form/delivery_note_form_screen.dart` | `'Delivery Note'` | `dn?.status` |
| `purchase_order/form/purchase_order_form_screen.dart` | `'Purchase Order'` | `po?.status` |
| `purchase_receipt/form/purchase_receipt_form_screen.dart` | `'Purchase Receipt'` | `pr?.status` |
| `material_request/form/material_request_form_screen.dart` | `'Material Request'` | `mr?.status` |

---

## 8. Testing

- [ ] All 6 form screens render the doctype label and status pill in both expanded and collapsed states
- [ ] Status pill shows correct colour for: Draft (red), Submitted (blue), In Process (orange), Partially Billed (yellow), Completed (green), Closed (green), Return (gray)
- [ ] Save button is navy-filled when `isDirty == true && docStatus == 0`
- [ ] Save button is disabled-gray when `docStatus == 1` or `docStatus == 2`
- [ ] Spinner shows during save; green check / red error flash post-save (existing `SaveIconButton` behaviour)
- [ ] Unsaved-changes indicator visible when dirty; hidden when clean
- [ ] Scroll collapse animates correctly; status pill visible in both states
- [ ] `DocTypeListHeader` list screens are unaffected (smoke-test Work Order list, Delivery Note list)
- [ ] `SaveIconButton` has no `color:` argument (grep check: `grep -r "color:.*onPrimary" lib/`)

---

## 9. Regression Guards

1. `grep -r "color:.*onPrimary" lib/app/modules/global_widgets/save_icon_button.dart` must return empty.
2. `DocTypeListHeader` file diff must be empty after this work.
3. `save_icon_button.dart` diff must contain only the `showFilledWhenDirty` addition — no other changes, and no `color:` argument in any non-filled code path.
