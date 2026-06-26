# To-Do — Item Variant Details: image-first card, prominent Balance Qty, revamped gallery, Cards/Compact toggle

**DocType:** ToDo
**Priority:** Medium
**Reference Type:** Report
**Reference Name:** Item Variant Details
**Assigned module:** `lib/app/modules/stock/reports/item_variant_details/`

---

## Description

Rework the Item Variant Details report so each variant leads with its **photo**,
shows **Balance Qty with its UOM** as the headline figure, presents attributes in
a clear hierarchy, and can be browsed as rich **Cards** or a dense **Compact**
list. The variant **image gallery** is central to this report and is **revamped**
(filmstrip navigation + a rich caption), not just reused.

This is a **presentation + light-state** change: `_VariantTile` and helpers in
`item_variant_details_screen.dart`, the `_ImageGallery` viewer in the same file,
plus a small persisted `viewMode` flag on the controller. No API/networking
changes — the data is already loaded by `runReport()` / `_fetchDetails()`.

## Why

- **The leading slot is meant to be the variant photo.** Today, when a variant
  has no image, `_ItemThumb` falls back to `itemCode.substring(0, 2)` — so the
  hero element shows "10" for every variant sharing a code prefix
  (1002092 / 1001951 / 1000927 → all "10"): a meaningless, colliding placeholder.
  Images are a primary signal in this report and deserve a proper image slot +
  a real "no photo" placeholder, plus an easy path into the gallery.
- **Balance Qty is buried.** `current_stock` (the on-hand qty) is in
  `_VariantTile._skipFields` and never shown — the user must tap "Check Stock".
  It should be the headline, paired with the **stock UOM** (`stock_uom`, e.g.
  "24 PCS"), colour-coded by state.
- **Attributes are a flat pill dump.** Four identical `label: value`
  `_AttrChip`s with no hierarchy.
- **No density control** for long variant lists.

## Acceptance criteria

- [ ] Each variant **leads with its image** (variant `image`); missing images get
      a proper "no photo" placeholder — **never** code initials. `_ItemThumb` is
      removed/replaced.
- [ ] **Balance Qty = hero:** `current_stock` shown large with its `stock_uom`
      ("24 PCS"), colour-coded — in-stock (green) / low <10 (orange) / out =0
      (gray) — with a small state caption. Removed from the attribute area.
- [ ] **Image gallery revamped** (`_ImageGallery`): adds a **thumbnail filmstrip**
      to jump across variants, prev/next controls, and a **rich caption** showing
      the variant code, name, its **attributes**, and **Balance Qty + UOM** with
      the state colour. Tapping a card/row photo opens the gallery at that variant.
- [ ] **Cards (A):** image thumbnail (tap → gallery) + name-led header
      (item_name primary, item_code · group secondary) + Balance-Qty pill; a
      compact 2-column **key/value grid** for attributes (replaces the pills);
      a quiet "Check stock" secondary action (existing inline `fetchStockBalance`
      retained).
- [ ] **Compact (B):** one ~64px row — small photo thumbnail, name + code, a
      single dotted attribute line, Balance Qty + UOM colour-coded, chevron.
      ~6 rows visible per screen.
- [ ] A persisted **Cards / Compact** toggle switches layouts without re-running
      the report.
- [ ] Inline per-rack **Check Stock** (`_StockSection`) still works in both modes.
- [ ] All colours from `Theme.colorScheme` + the status palette; light + dark
      both pass; no row overflow. **Do not** re-theme the app to the pink seen in
      the live screenshot (that is an app theme override, not this design).

## Design reference

`Item Variant Details — Redesign.html` in this bundle (open in a browser):
left = current screen; middle = redesign (tap **Cards / Compact**; tap a photo to
open the gallery); right = the revamped **Image gallery** standalone. See
`README.md` for the full spec and `CLAUDE_CODE_PROMPT.md` for the prompt.
