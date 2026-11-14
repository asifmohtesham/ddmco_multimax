# Handoff: Stock Balance report — refined tile layout

## Overview
Redesign of the **Stock Balance** report result card in the ddmco_multimax
Flutter app. The new layout ranks information by operational value so a warehouse
user reads each row at a glance: on-hand quantity (colour-coded by health),
location + rack, the Opening→In→Out→Balance ledger, free-vs-reserved split, and a
quiet valuation/customer footer.

## About the design files
The files in this bundle are **design references created in HTML** — a prototype
showing the intended look and behaviour, **not** production code to copy. The
task is to **recreate this layout in the existing Flutter codebase** using its
established patterns (GetX controllers, Material 3 `Theme.colorScheme`, the app's
widgets and formatting helpers). Do not port HTML/CSS; do not re-theme the app.

- `Stock Balance Report.html` — the visual reference (open in a browser).
- `ds.css` — the Multimax design-system tokens the reference was styled with
  (for intent only; in-app, map to `Theme.colorScheme`).
- `TASK.md` — the To-Do ticket.
- `CLAUDE_CODE_PROMPT.md` — a ready-to-paste implementation prompt.

## Fidelity
**High-fidelity.** Final hierarchy, spacing, states and copy are settled.
Recreate the structure faithfully, but source colours from the app's existing
theme tokens + the small status palette in the prompt — the reference is shown
in the DS blue language, whereas the live app uses its own Material scheme.

## Screen / view

### Stock Balance — result tile (`_BalanceTile`)
- **Purpose:** scan stock for an item/warehouse and judge health, location,
  movement and commitment without opening a detail view.
- **Layout (single card, 12px radius, elevation 1, 14px padding, 3px left
  accent bar in the state colour), top→bottom:**
  1. **Head** — `Row` spaceBetween: left = item_code (mono 12 w600 muted) over
     item_name (15.5 w600, 1-line ellipsis); right = balance box (radius 8,
     6×11 padding, state-tinted) with number (24 w700, tabular) over uom (10
     w600 uppercase).
  2. **Location line** — pin icon + warehouse (w600) · `Rack NAME`; italic
     "No rack assigned" fallback.
  3. **Ledger strip** — 4-cell inset grid (surfaceVariant, radius 8, hairline
     dividers): Opening / In / Out / Balance. In = green "+", Out = red "−",
     zeros muted; Balance cell faint state tint.
  4. **Commitment** — if balance>0: free(green)/reserved(orange) proportion bar
     + labels; if balance<0: red "Negative stock" note; if balance==0: neutral
     "Out of stock" note.
  5. **Meta footer** — dashed divider, then Rate / Value (muted when 0) and a
     trailing monospace customer-code tag. **Company field dropped.**

## Interactions & behavior
- Tile is display-only (no new tap targets beyond existing list behaviour).
- State is derived per row (see logic in the prompt) — no async work.
- Light/dark: every colour theme-derived; status tints use `withValues(alpha:)`
  over `surface`.

## State management
None new. Data already arrives via `StockBalanceController.runReport()`. The only
controller-adjacent change is reconciling `_skipFields` with the real report
fieldnames so standard columns (`balance_value`, `valuation_rate`,
`reserved_stock`, dimension/rack) are consumed explicitly instead of leaking into
chips — this also fixes the current bug where the hero badge and a "Balance Qty"
chip show different numbers.

## Design tokens (reference values from `ds.css`)
- **State accents:** healthy `#38a160` / `#1f5e34`, watch `#f0851b` / `#9e5409`,
  negative `#e03636` / `#9a2222`, empty `#98a1a9` / `#525c66`.
- **Tints:** accent at 13% alpha over surface; borders at ~26%.
- **Radius:** card 12, balance box / ledger / notes 8, full for bar/chips.
- **Type:** Inter; mono = Roboto Mono. Hero qty 24/700, ledger value 16/700,
  body 12.5–15.5, captions 9.5–11 uppercase.
- **Spacing:** 4px grid (9–14px between sections).

## Assets
Icons only — Material symbols already in the app (place, warning_amber,
inventory_2_outlined, person, filter_alt). No images.

## Files in this project
- `Stock Balance Report.html` (root + this folder) — the design.
- Implementation target: `lib/app/modules/stock/reports/stock_balance/
  stock_balance_screen.dart` (the `_BalanceTile`, `_Detail`, `_AttrChip`
  widgets and `_skipFields`).
