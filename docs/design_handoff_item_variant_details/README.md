# Handoff: Item Variant Details — card redesign + Cards/Compact toggle

## Overview
Redesign of the **Item Variant Details** report in the Multimax Flutter app. Each
variant leads with its **photo**, shows **Balance Qty + UOM** as a colour-coded
headline, lists attributes in a clear hierarchy, and can be browsed as rich
**Cards** or a dense **Compact** list. The variant **image gallery** — central to
this report — is **revamped** with filmstrip navigation and a rich caption.

## About the Design Files
The files in this bundle are **design references created in HTML** — a prototype
showing intended look and behaviour, **not production code to copy**. The task is
to **recreate the design in the existing Flutter + GetX + Material 3 codebase**
using its established patterns (`Theme.colorScheme`, the report-screen archetype,
the existing `_ImageBanner` / `_StockSection` widgets), not to port HTML/CSS.

Open `Item Variant Details — Redesign.html` in a browser:
- **Left phone** — recreation of the screen as it ships today (the "before").
- **Middle phone** — the redesign. Tap **Cards / Compact** in the view-bar to
  switch layouts; tap any variant **photo** to open the gallery.
- **Right phone** — the **revamped image gallery** (standalone).

## Fidelity
**High-fidelity.** Colours, type scale, spacing and the two layouts are final
intent. Recreate pixel-faithfully using the codebase's theme tokens — but note
the HTML is drawn in the Multimax **blue** design language; the live app theme
(and any pink seen in screenshots) is an app-level override. Use
`Theme.of(context).colorScheme` + the status palette below; **do not re-theme**.

## Screens / Views

### Item Variant Details — result list (report archetype)
**Purpose:** After running the report for an Item (e.g. `895C`), the user browses
its variants, sees on-hand stock per variant, and drills into per-rack stock.

**Layout:** `AppShellScaffold` → `CustomScrollView` with `DocTypeListHeader`
(title "Item Variant Details", filter chip e.g. `Item: 895C`), then a new thin
**view-bar**, then the result list. Empty state = "Enter an Item and tap Run
Report" (unchanged — report archetype, see `docs/doctype_list_view_conventions.md`
§6).

**View-bar (new):** left = quiet summary `N variants · K out`; right = a
segmented **Cards / Compact** toggle (pill, 26px segments, selected = surface +
primary fg + xs shadow).

#### Components — Cards layout (option A)
- **Card:** Material card, radius 16, elevation 1, `clipBehavior: antiAlias`.
- **Image banner (optional):** full-width 200px when the variant has an image —
  **reuse the existing `_ImageBanner` + gallery viewer unchanged**.
- **Header (tap → Item form):** leading **54px image thumbnail** (the variant
  photo; a "no photo" placeholder if absent — **never code initials**) with a
  corner expand glyph; tapping it opens the gallery at this variant. Then
  `item_name` (titleSmall w600, 1-line ellipsis) over `item_code · item_group`
  (bodySmall, onSurfaceVariant, monospace code).
- **Balance-Qty pill (top-right, the hero):** rounded box (radius 8, tint bg +
  accent@26% border): `current_stock` (23px, w700, state fg, tabular) + its
  `stock_uom` (11px, w700) on a baseline row — e.g. **"24 PCS"** — over a state
  caption (8.5px, UPPERCASE: In stock / Low stock / Out of stock).
- **Attribute grid:** 2-column grid in a quiet inset (surfaceVariant bg, 1px
  border, radius 8, 11×12 padding, 8×14 gaps). Each cell: micro-label (9.5px,
  w700, UPPERCASE, subtle) over value (13px, w600, onSurface, ellipsis). One cell
  per non-empty attribute column. **Replaces the `label: value` pills.**
- **Footer:** quiet "Check stock" secondary button (primary fg, primary@9% fill,
  32px) → `fetchStockBalance(itemCode)` (toggles "Hide stock"); muted "View ›".
- **Expanded stock:** the existing `_StockSection` per-rack rows, unchanged.

#### Components — Compact layout (option B)
- A one-line column header: `VARIANT` / `ON HAND` (10px, w700, UPPERCASE,
  subtle, bottom divider).
- **Row (~64px), 1px dividers:** 3px left accent bar (state colour); a 40px image
  thumbnail (tap → gallery); main column line 1 = `item_name` (14.5 w600
  ellipsis) + `item_code` (11.5 subtle mono); line 2 = attributes joined by
  ` · ` (12px, onSurfaceVariant, 1-line ellipsis); right = `current_stock` (19px,
  w700, state fg, tabular) over `stock_uom` (8.5px, muted-state); trailing
  chevron.
- Tap → Item form (recommended); long-press → `fetchStockBalance` (mirrors list
  screens). Document whichever you choose.

## Interactions & Behavior
- **Image gallery (revamped, central):** tapping a card/row photo opens a
  full-screen viewer — swipeable `PageView` across all variant photos, pinch
  zoom, prev/next controls, a **thumbnail filmstrip** to jump between variants,
  and a **rich caption** (variant code + name, its attribute chips, and
  **Balance Qty + UOM** in the state colour) with an "Open item ›" button.
- **View toggle:** tap Cards / Compact → `controller.setViewMode(...)`; list body
  in `Obx(viewMode)`; **does not** re-run the report. Choice **persists** (reuse
  the app's existing view-pref storage — see how Item's grid/list is stored).
- **Check Stock:** `fetchStockBalance(itemCode)` is a toggle — first call loads +
  expands `_StockSection`, second collapses. `loadingStock[itemCode]` drives the
  spinner. Unchanged from today.
- **Header / row tap:** `Get.toNamed(AppRoutes.ITEM_FORM, {itemCode})`.
- **Image tap:** opens the existing full-screen gallery (`_ImageGallery`).

## State Management
- Add `viewMode` (`'cards' | 'compact'`, `RxString`, persisted) +
  `setViewMode()` to `ItemVariantDetailsController`. Everything else
  (`reportData`, `reportColumns`, `itemDetails`, `stockBalances`,
  `loadingStock`) already exists — no other controller change.
- Derive each row's stock **state** from `current_stock`: `<=0` out (gray),
  `<10` low (orange), else in-stock (green).

## Design Tokens
HTML reference values → map to `Theme.colorScheme` in app.
- **Primary:** `#2490ef` → `colorScheme.primary`
- **In-stock (ok):** `#38a160` / text `#1f5e34` → `green.shade600/700`
- **Low:** `#f0851b` / text `#9e5409` → `orange.shade600/800`
- **Out:** `#bcc4cb` / text `#74808b` → `outline` / `onSurfaceVariant`
- **Surfaces:** card `#ffffff` → surface; inset `#f9fafa` → surfaceVariant;
  border `#ebeef0` → outlineVariant
- **Radius:** card 16, inset/pill 8. **Type:** Inter (app uses its own).
- **Status tint bg:** `accent.withValues(alpha: 0.12)` composited over surface.

## Assets
None new. Variant images come from `itemDetails[code]['image']` (already wired).
Icons are Material (`inventory_2_outlined`, `chevron_right`, `view_agenda_outlined`,
`view_list_outlined`).

## Files
- `Item Variant Details — Redesign.html` — the prototype (self-contained; open in
  a browser). Left = current, right = redesign with the Cards/Compact toggle.
- `variant-phones.jsx`, `design-canvas.jsx` — source of the prototype (reference
  only).
- `ds.css` — the Multimax design-system tokens used to render the HTML.
- `TASK.md` — the To-Do (ERPNext ToDo format).
- `CLAUDE_CODE_PROMPT.md` — paste-ready implementation prompt for Claude Code.

Target source files in the app:
- `lib/app/modules/stock/reports/item_variant_details/item_variant_details_screen.dart`
- `lib/app/modules/stock/reports/item_variant_details/item_variant_details_controller.dart`
