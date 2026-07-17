# Item Auto re-order — Design

**Date:** 2026-07-17
**Status:** Awaiting review
**Branch:** `claude/item-auto-reorder-c8aadc`

## Goal

Bring ERPNext's **Auto re-order** section (`Item.reorder_levels`) into the Multimax
Item form as a **viewable and editable** surface, mirroring the default behaviour of
`frappe/erpnext` branch `version-15`.

Today the app has zero reorder support — no reference to `Item Reorder`,
`reorder_levels`, or any reorder field exists in `lib/` or `test/`.

## Background: what version-15 actually does

Verified against `raw.githubusercontent.com/frappe/erpnext/version-15` on 2026-07-17.
These facts drive every decision below.

### `Item Reorder` child DocType

`erpnext/stock/doctype/item_reorder/item_reorder.json` — controller is an empty
`class ItemReorder(Document): pass`. **No server-side defaults, no hooks.**

| fieldname | fieldtype | label (Desk) | options | reqd |
|---|---|---|---|---|
| `warehouse_group` | Link | **Check in (group)** | `Warehouse` | 0 |
| `warehouse` | Link | **Request for** | `Warehouse` | **1** |
| `warehouse_reorder_level` | Float | **Re-order Level** | — | 0 |
| `warehouse_reorder_qty` | Float | **Re-order Qty** | — | 0 |
| `material_request_type` | Select | **Material Request Type** | `Purchase`/`Transfer`/`Material Issue`/`Manufacture` | **1** |

Only `warehouse` and `material_request_type` are mandatory. No field carries a
`default` in the JSON.

Note the option is **`Transfer`**, not `Material Transfer` — it is remapped at MR
creation (`"Material Transfer" if request_type == "Transfer" else request_type`).

### Section on Item

`erpnext/stock/doctype/item/item.json`:

- `reorder_section` — label **"Auto re-order"**, `collapsible: 1`,
  `depends_on: "is_stock_item"` (bare fieldname, not `eval:`).
- `reorder_levels` — Table of `Item Reorder`, label
  **"Reorder level based on Warehouse"**, description
  **"Will also apply for variants unless overrridden"**
  (*sic* — three r's in the source; match exactly if string-comparing).
- `reorder_levels` itself has no `depends_on`/`hidden`/`reqd`; it inherits
  visibility from the section.

### Server validation — `item.py:497-534` `validate_warehouse_for_reorder()`

1. **Blank group defaults to the warehouse** (`item.py:508-509`):
   ```python
   for d in self.get("reorder_levels"):
       if not d.warehouse_group:
           d.warehouse_group = d.warehouse
   ```
   This is the single most important default in the feature. A saved row always
   has `warehouse_group` set.
2. **Duplicate check** keys on the tuple `(warehouse, material_request_type)`,
   raising `DuplicateReorderRows`:
   `"Row #{0}: A reorder entry already exists for warehouse {1} with reorder type {2}."`
   Two rows for the same warehouse with *different* types are legal.
3. **Conditional mandatory** (`item.py:520-521`): level-without-qty throws
   `"Row #{0}: Please set reorder quantity"`. Qty-without-level is allowed.
4. **Descendant check** (`item.py:523-534`): `warehouse` must be in
   `get_child_warehouses(warehouse_group)`. That helper appends self
   (`return [*children, warehouse]`), which is *why* the blank-group default in (1)
   passes trivially. The server does **not** validate `warehouse_group.is_group == 1`
   — that exists only as a client-side link filter. The check is also skipped on edit
   when the row's warehouse is unchanged.
5. **`validate_auto_reorder_enabled_in_stock_settings()`** (`item.py:1154-1161`) —
   `msgprint`, **not** `throw`. Rows save fine with `auto_indent` off; they are inert.

### Client JS — `item.js`

- **Row-add default** (`item.js:292-298`) — the only place the type gets a default:
  ```js
  row.material_request_type = type == "Material Transfer" ? "Transfer" : type;
  ```
  from `Item.default_material_request_type` (itself defaulting to `"Purchase"`).
  API inserts get no default and fail `reqd`.
- **Link filters** (`item.js:449-473`): `warehouse_group` → `is_group: 1`;
  `warehouse` → `is_group: 0`.

### The engine — `reorder_item.py`

- Scheduler hook is **`daily_maintenance`**, not `daily`.
- **`Stock Settings.auto_indent` defaults to `0` — auto re-order is OFF out of the box.**
  `reorder_item()` returns early unless it is ticked.
- `get_items_for_reorder()` **inner-joins** `Item Reorder`, so **an item with no
  reorder rows never enters consideration**. There is no item-defaults or
  safety-stock fallback in v15; `Item.safety_stock` is never read by the engine.
- Trigger: `projected_qty(warehouse_group) <= reorder_level` **and** at least one of
  level/qty non-zero. Order qty = `max(reorder_qty, level - projected)`.
- **`warehouse_group` is where stock is *measured*; `warehouse` is where the MR is
  *raised*.** That is the entire point of the group/leaf pair.
- MRs are created **already submitted** (`docstatus=1`), one per (type, company).

## Design

### Placement

A **5th tab, "Re-order"**, on the Item form:

```
[Overview] [Stock Levels] [Attributes] [Attachments] [Re-order]
```

The TabBar is already `isScrollable: true`, so a 5th tab is cheap. Cost is a
one-line change to the hardcoded `TabController(length: 4, …)`
(`item_tab_controller.dart:26`).

**Rejected:** a section in the Overview tab (higher Desk fidelity, but Overview is
pure read-only display and one editable card in it is inconsistent); inside Stock
Levels (already dense with chart + batch history + ledger).

### Data flow

`getDocument('Item', code)` already hits `GET /api/resource/Item/<code>`, which
returns child tables — **`reorder_levels` is already in the response and currently
discarded** by `Item.fromJson`. Display therefore needs **no new fetch**.

New fetches required:
- Warehouse lists for the two pickers (`WarehouseProvider`).
- `Stock Settings.auto_indent` for the banner (below).

### Screen anatomy

```
Re-order tab
├─ [warning banner]            ← only when auto_indent == false
├─ DocSectionCard "Auto re-order"
│   ├─ "Reorder level based on Warehouse"       (section description)
│   ├─ "Will also apply for variants unless overrridden"
│   ├─ rule card ×N   → tap opens editor sheet
│   └─ [+ Add rule]                              ← gated on Item:write
└─ footer AsyncFilledButton [Save]               ← gated on Item:write, enabled when dirty
```

Each rule card shows: `warehouse_group → warehouse`, `Re-order at <level> · Order
<qty>`, and the type. Overflow menu per row offers Edit / Delete.

### The auto_indent banner

On first open of the Re-order tab, read `Stock Settings.auto_indent`. When `0`, show
a persistent warning banner above the rules:

> ⚠ Auto re-order is disabled in Stock Settings. These rules will not raise Material
> Requests.

This is deliberately **stronger than Desk**, which only `msgprint`s on save. Since
`auto_indent` defaults off, a rules editor without this banner silently saves rules
that do nothing.

**Permission caveat:** reading the `Stock Settings` Single requires permission on
that doctype, and the resource API 403s for non-System-Manager users (per the
MR/PS permission-gate precedent). The check therefore **fails open** — on any error
or 403, no banner is shown. It will resolve for SM accounts and stay silent for
operators. This is accepted: a false-negative banner is better than a false alarm,
and operators cannot change the setting anyway.

Status colours follow the CLAUDE.md ramp: `isDark ? AppColors.orange300 :
AppColors.orange700` for ink, `orange500.withValues(alpha: 0.13)` fill, `0.35`
border.

### Row editor (bottom sheet)

Tapping a rule card — or **+ Add rule** — opens a bottom sheet with five fields,
built from `DocPickerField`:

| Field | Widget | Behaviour |
|---|---|---|
| Check in (group) | `DocPickerField` → warehouse picker | filter `is_group: 1`; optional |
| Request for | `DocPickerField` → warehouse picker | filter `is_group: 0`; **required** |
| Re-order Level | numeric `TextFormField` | Float |
| Re-order Qty | numeric `TextFormField` | Float |
| Material Request Type | `DocPickerField` → 4-option picker | **required**; defaults on add |

Sheet surface uses `context.scheme.fg` / `colorScheme.surface` — never
`Colors.white` (dark-mode contrast rule).

**Rejected:** inline expanding card (cramped; pickers need sheets anyway);
full-screen route (heaviest navigation for a 5-field form).

### Validation

Mirrored **client-side** for immediate feedback:

- `warehouse` required; `material_request_type` required.
- Blank `warehouse_group` → set to `warehouse` **on save**, mirroring
  `item.py:508-509`. Applied to the payload, and the UI reflects the resulting value
  after a successful save.
- Duplicate `(warehouse, material_request_type)` across rows → block save, message
  mirroring `DuplicateReorderRows` with the offending row index.
- Level set with blank/zero qty → block save with
  `"Row #N: Please set reorder quantity"`. Qty without level is allowed.

**Deferred to the server** (surface its throw verbatim via `GlobalSnackbar.error`):

- The **descendant check** (`warehouse ∈ get_child_warehouses(warehouse_group)`).
  Evaluating it client-side needs the warehouse tree (`lft`/`rgt` or a
  `parent_warehouse` walk); the server is the authority and its message is already
  specific (`"Row #{0}: The warehouse {1} is not a child warehouse of a group
  warehouse {2}"`). Not worth a tree fetch on every sheet open.

### Type default on add

Mirrors `item.js:292-298`: default from `Item.default_material_request_type`, with
`Material Transfer` → `Transfer`.

**One deliberate deviation from v15.** `Item.default_material_request_type` has
option `Customer Provided`, which is **not** a valid `Item Reorder.material_request_type`
option. Desk copies it verbatim, producing a row with an invalid Select value. This
app instead **leaves the type blank** when the remapped value is not one of the four
valid options, forcing an explicit choice. Rationale: writing a knowingly invalid
value to satisfy bug-compatibility serves nobody.

### Link filters

Match v15 exactly: group picker `is_group: 1`, request-for picker `is_group: 0`.

**No narrowing of "Request for" to descendants of the chosen group.** v15 *intends*
to narrow (`item.js:449-473`) but the branch is dead — `Item Reorder` has no
`parent_warehouse` field, so the guard never fires, and `filters.extend({...})` is
Python idiom that would `TypeError` in JS if it did. Desk therefore lists every leaf
warehouse company-wide. Since the brief is "default as per version-15", this app
does the same, and lets the server's descendant throw catch a mismatched pair.

*Noted for a future decision:* narrowing would be a real UX improvement and would
prevent that round-trip. Deliberately out of scope here.

### Variant inheritance

Display **stored rows only** — what is actually in this item's `reorder_levels`.
When an item has a `variant_of` and no rows of its own, show a hint mirroring the
Desk description:

> No rules of its own. The template's rules apply unless you add rules here.

The app does **not** fetch and render the template's rows as if they were the
variant's. Inheritance in v15 is computed in memory at each scheduler run
(`get_reorder_levels_for_variants`) and never persisted, so showing them as rows on
the variant would misrepresent stored state and make "delete this row" meaningless.

> **⚠ Unverified upstream defect — flagged, not acted on.**
> `get_reorder_levels_for_variants()` `.extend()`s the **template's row objects by
> reference**; those rows carry the template's `has_variants = 1`. `_reorder_item()`
> then does `for d in reorder_levels: if d.has_variants: continue`. So a variant
> relying on inheritance appears to have its rows skipped and **never generates a
> Material Request**. Variant *overrides* work (own rows carry `has_variants = 0`);
> *inheritance* looks inert. The guard reads `has_variants` off the row's originating
> item rather than the item being processed.
> This is a **code-reading conclusion only** — no Frappe instance was executed, and
> no matching upstream issue was found. `develop`/v16 carries the same code unchanged.
> **Verify empirically before relying on template inheritance.** It does not affect
> this build.

### Non-stock items

Desk hides the section via `depends_on: "is_stock_item"`. This app keeps the tab
count **static at 5** and shows a `FormEmptyState` on the Re-order tab when
`is_stock_item == 0`:

> Auto re-order applies to stock items only.

**Rationale:** dynamically resizing a `TabController` built on
`GetSingleTickerProviderStateMixin` is fragile, and `item_tab_controller.dart:5-17`
already documents a ticker-disposal hazard in this exact controller. A static tab
count with a gated body preserves the intent of `depends_on` without the churn.

### Save

Whole-document `PUT /api/resource/Item/<code>` via
`ApiProvider.updateDocument` (`api_provider.dart:315`), sending the full
`reorder_levels` array plus the optimistic-lock `modified` token — mirroring
`todo_form_controller.dart:383`.

Existing rows keep their `name` so Frappe updates rather than recreates them; new
rows omit it. Omitted rows are deleted by Frappe's child-table replace semantics.

Per CLAUDE.md, the REST call lives in `ItemProvider`, not the controller.

Follows the async-feedback convention: `isSavingReorder` `RxBool`, re-entrancy guard
`if (isSavingReorder.value) return;`, cleared in a `finally`, driving an
`AsyncFilledButton`.

**Save is a footer button in the tab, not `DocTypeFormHeader.onSave`.** This departs
from `docs/doctype_form_view_conventions.md:16-26`, which puts `onSave` in the
header. Two reasons:

1. **Scope honesty.** That convention describes forms that are editable *throughout*.
   Here four of five tabs are read-only, so a header Save would imply the whole Item
   doc is editable when only one tab is.
2. **It sidesteps a documented trap.** `DocTypeFormHeader` is a
   `SliverPersistentHeader`; making a header action appear only on the Re-order tab
   means a reactive header, and CLAUDE.md:79 plus the existing regression test
   `test/widget/doctype_form_header_extra_action_reactive_test.dart` both record that
   its `shouldRebuild` keys on action *count* and will not repaint an icon→spinner
   swap.

The header is left exactly as it is today.

### Dirty tracking

Snapshot-diff (**not** a one-way latch), mirroring `todo_form_controller.dart:163`:
snapshot `reorder_levels` after fetch, compare on every mutation. `PopScope(canPop:
!isDirty)` with a confirm-discard dialog wraps the Item form — introduced here for
the first time, since the form was previously read-only and had nothing to lose.

**Known edge case — sheet dismissal.** `ItemFormScreen` serves both a route and a
bottom sheet; the sheet is opened from the dashboard scan flow with
`enableDrag: true` (`home_controller.dart:607-626`). `PopScope` guards the back
button but does **not** intercept drag-to-dismiss, which calls `Navigator.pop`
directly, so a user could drag away unsaved rules.

**Resolved during planning:** `Get.bottomSheet`'s `enableDrag` is fixed at open time
and cannot track dirty state, so the item sheet is opened with
`enableDrag: false` and the existing Close button
(`item_form_screen.dart:37-45`) is routed through the same confirm-discard as
`PopScope`. The trade-off — no swipe-to-dismiss on the item sheet — is accepted in
exchange for a deterministic guard; the Close button already exists and is
unchanged in position.

### Permissions

Gate on **`Item:write`** — exactly what the server enforces for
`PUT /api/resource/Item/<code>`.

- Add `(doctype: 'Item', permType: 'write')` to `kStockPermissions`
  (`permission_entries.dart:10-30`) so it resolves at login with no on-screen delay.
  Item already has `read`/`report` there; `write` triggers one `getdoctype` fetch
  that caches `create` for free.
- Wrap **+ Add rule**, the row overflow menu, and **Save** in
  `DocTypeGuard(doctype: 'Item', permType: 'write', …)`.
- Without write permission the section stays **readable** — rules render, edit
  affordances are absent. Fail-closed via `PermissionService`.

## Files

### New

| File | Purpose |
|---|---|
| `lib/app/modules/item/form/reorder_rules.dart` | Pure v15 validation + type-default logic (no GetX, no network) |
| `lib/app/modules/item/form/widgets/reorder_rule_sheet.dart` | Bottom-sheet row editor |
| `lib/app/modules/item/form/widgets/reorder_rule_card.dart` | One rule as a card |
| `test/unit/item_reorder_model_test.dart` | `fromJson`/`toJson` round-trip |
| `test/unit/reorder_rules_test.dart` | Pure validation rules |
| `test/unit/item_form_reorder_controller_test.dart` | Controller state + save path |
| `test/widget/reorder_rule_card_test.dart` | Card rendering + dark-mode/contrast |
| `test/widget/reorder_rule_sheet_test.dart` | Sheet fields + dark-mode surface |
| `test/widget/reorder_tab_test.dart` | Save-bar spinner repaint |

> No `auto_indent_banner.dart`: the existing `InlineBanner`
> (`lib/app/modules/global_widgets/inline_banner.dart`) already implements this
> spec's status-tint convention exactly — `BannerType.warning` renders an
> `orange500` α0.13 fill with `orange700`/`orange300` ink — and is already
> covered by `test/widget/status_ink_contrast_test.dart`. Reuse it.
>
> Likewise no bespoke warehouse picker: `WarehousePickerSheet`
> (`lib/app/modules/global_widgets/warehouse_picker_sheet.dart`) already offers
> search, a themed surface, and a `groupNames` set for tagging group warehouses.

### Modified

| File | Change |
|---|---|
| `lib/app/data/models/item_model.dart` | `ItemReorder` class (first `toJson`); `Item` gains `reorderLevels`, `isStockItem`, `defaultMaterialRequestType`, `modified` |
| `lib/app/data/providers/item_provider.dart` | `updateReorderLevels()`, `getStockSettings()` — first write in this provider |
| `lib/app/data/providers/warehouse_provider.dart` | `getWarehouses()` gains an `isGroup` filter (currently hardcodes `is_group: 0` unless `includeGroups`) |
| `lib/app/modules/item/form/item_form_controller.dart` | First write path: `reorderRows`, dirty snapshot, `isSavingReorder`, `saveReorderLevels()`; gains `OptimisticLockingMixin` |
| `lib/app/modules/item/form/item_tab_controller.dart` | `length: 4` → `5` |
| `lib/app/modules/item/form/item_form_screen.dart` | 5th tab + body; `PopScope`; guarded Close |
| `lib/app/modules/item/form/item_form_binding.dart` | Register `WarehouseProvider` |
| `lib/app/modules/home/home_controller.dart` | `enableDrag: false` on the item sheet; register `WarehouseProvider` |
| `lib/app/data/constants/permission_entries.dart` | `(doctype: 'Item', permType: 'write')` |
| `pubspec.yaml` | `2.11.0+50` → `2.12.0+51` |

## Testing

Follows the house pattern: **hand-rolled fakes subclassing the real provider,
injected via `Get.put`**. No mockito/mocktail in this repo. Reference:
`test/unit/todo_form_controller_test.dart`.

Every controller test **must** stub `path_provider` — `ApiProvider`'s constructor
fires `_initDio()` for the cookie jar:

```dart
TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
    .setMockMethodCallHandler(
  const MethodChannel('plugins.flutter.io/path_provider'),
  (MethodCall call) async => '/tmp/test_cookies',
);
```
plus `tearDown(() => Get.deleteAll(force: true))`.

Coverage:

- `ItemReorder.fromJson`/`toJson` round-trip; `reorder_levels` parsed off a real
  Item payload; absent key → empty list.
- Blank `warehouse_group` → payload carries `warehouse`.
- Duplicate `(warehouse, type)` blocks save; same warehouse + *different* type saves.
- Level-without-qty blocks; qty-without-level saves.
- `Customer Provided` default → type left blank, not written.
- Save sends the `modified` optimistic-lock token.
- Re-entrancy: `isSavingReorder = true` → provider never called.
- `DioException` 417 → error surfaced, `isSavingReorder` cleared.
- Dirty is a **diff**, not a latch: mutate then revert → not dirty.
- `auto_indent` false → banner shown; 403 → **no** banner (fail open).
- `is_stock_item == 0` → empty state, no editor.
- Widget: sheet surfaces in dark mode; `AsyncFilledButton` actually repaints
  icon→spinner (per CLAUDE.md, "a clean `flutter analyze` proves nothing here").

## Versioning

`feat:` — a new module surface and flow → **MINOR**. Per CLAUDE.md, do not default
to PATCH.

Current `2.11.0+50` → **`2.12.0+51`**.

Not MAJOR: this requires no backend change, no custom field, and no server script.
It reads and writes stock `Item.reorder_levels` on a stock v15 instance.

## Out of scope

- Enabling `Stock Settings.auto_indent` — the app **reports** it, never changes it.
  That is a Desk setting change and the user's call.
- Narrowing "Request for" to descendants of the chosen group (see Link filters).
- Rendering inherited template rows on a variant (see Variant inheritance).
- Viewing or managing the Material Requests the engine generates.
- Item-level `safety_stock` — never read by the v15 reorder engine.
- Making any other Item field editable. The Re-order tab is the only editable
  surface; Overview, Stock Levels, Attributes and Attachments stay read-only.

## Open questions

**Design-level: none.** The three forks (mobile-vs-server scope, placement,
auto_indent handling) were resolved with the user on 2026-07-17. The seven remaining
calls were made by Claude with rationale recorded inline above; each is reversible.

**Resolved during planning:**

- Modal dismissal while dirty → `enableDrag: false` on the item sheet plus a
  confirm-guarded Close button. See *Dirty tracking*.

**Flagged for empirical verification, does not block this build:**

- Whether variant template-inheritance generates Material Requests at all in v15.
  See the defect note under *Variant inheritance*.
