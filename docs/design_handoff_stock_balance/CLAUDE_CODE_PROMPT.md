# Claude Code prompt — Stock Balance tile redesign

Copy everything in the fenced block below into Claude Code, run from the Flutter
project root (`ddmco_multimax/`). The HTML reference and full spec are alongside
this file in `design_handoff_stock_balance/`.

---

```
You are working in the ddmco_multimax Flutter app (GetX + Material 3).

GOAL
Redesign the Stock Balance report result tile so operational information reads
in a clear hierarchy instead of a flat row of identical chips. This is a
PRESENTATION-ONLY change. Do not change networking, the controller's data
flow, or routing. A pixel reference is in
design_handoff_stock_balance/Stock Balance Report.html — open it to see the
target. It is rendered in the Multimax design-system blue language; in the app,
use the existing Theme.of(context).colorScheme tokens plus the small status
palette defined below — do NOT re-theme the app.

FILES
- Edit:  lib/app/modules/stock/reports/stock_balance/stock_balance_screen.dart
         (the _BalanceTile, _Detail and _AttrChip private widgets + _skipFields)
- Read for context (do not change behaviour):
         lib/app/modules/stock/reports/stock_balance/stock_balance_controller.dart
         lib/app/modules/global_widgets/doctype_list_header.dart

DATA (already present on each `row` Map<String,dynamic>)
- item_code, item_name, warehouse, stock_uom
- opening_qty, in_qty, out_qty, balance_qty          (movement ledger)
- valuation_rate, balance_value, reserved_stock      (valuation + commitment)
- customer_code                                      (added by the controller)
- the rack / dimension column (dimension-wise mode)  (e.g. "KA-WH-DXB3-BLOCK 1")
NOTE: confirm the EXACT fieldnames against a live report response before relying
on them. The current _skipFields lists 'balance_val' and 'valuation_rate', but
the response appears to emit 'balance_value' and a dimension-wise 'balance_qty'
column — that mismatch is why "Balance Value", "Valuation Rate" and a second
"Balance Qty" currently leak into the chip row and why the hero badge disagrees
with a chip. Whatever the real names are, add them all to _skipFields so NO
standard column renders as a chip; consume them explicitly in the new tile.

NEW TILE LAYOUT (top → bottom), inside the existing Material card (radius 12,
elevation 1, 14px padding, a 3px left accent bar in the state colour):

1. HEAD — Row, spaceBetween, crossAxis start.
   Left column: item_code (monospace 12, w600, onSurfaceVariant) over
   item_name (15.5, w600, onSurface, ellipsis 1 line).
   Right: a rounded "balance" box (radius 8, 6x11 padding, tinted bg =
   stateColor @13% alpha on surface, 1px border @26%): the balance number
   (24, w700, stateFg, tabular figures) over stock_uom (10, w600, uppercase,
   letter-spacing .06, muted). Whole numbers show no decimals; negatives keep
   the minus.

2. LOCATION LINE — Row, 9px top margin, 12.5 muted text: a location pin icon
   (Icons.place, 14, onSurfaceVariant), then warehouse (w600 onSurface), a
   subtle "·" separator, then `Rack <b>NAME</b>`. If no rack/dimension value,
   show "No rack assigned" in italic subtle text.

3. LEDGER STRIP — a 4-column grid inside a rounded inset (surfaceVariant bg,
   1px border, radius 8, hairline dividers between cells). Cells: Opening, In,
   Out, Balance. Each: caption (9.5, w600, uppercase, subtle) over value (16,
   w700, tabular). In value is green.shade700 and prefixed "+"; Out is
   red.shade700 and prefixed "−" (U+2212); a zero In/Out renders muted with no
   sign. The Balance cell has a faint stateColor @9% bg and its value uses
   stateFg.

4. COMMITMENT — choose ONE based on state:
   • balance_qty > 0  → availability bar: a 7px rounded track split into
     free (green) and reserved (orange) segments by width
     (reserved/balance, available = balance − reserved). Below it, two labels
     with 8px square swatches: "Available <b>N</b>" (green) and
     "Reserved <b>N</b>" (orange).
   • balance_qty < 0  → a red status note row (Icons.warning_amber, tinted bg):
     "Negative stock — issued beyond on-hand qty".
   • balance_qty == 0 → a neutral status note (Icons.inventory_2_outlined,
     surfaceVariant bg): "Out of stock — no movement in period".

5. META FOOTER — a 1px dashed top divider, then a Wrap (11.5 subtle): 
   "Rate <b>{currency} {valuation_rate}</b>", "Value <b>{currency}
   {balance_value}</b>", and pushed to the trailing edge a small monospace
   customer-code tag (person icon + code, surfaceVariant chip). When rate/value
   are 0 render them muted (subtle, not bold). DROP the Company field entirely.

STATE LOGIC (compute once per tile)
  final b = balance_qty, r = reserved_stock (default 0);
  if (b < 0)              state = negative;     // red
  else if (b == 0)        state = empty;        // gray / outline
  else if (r >= b * 0.8)  state = watch;        // orange — heavily committed
  else                    state = ok;           // green — healthy & free

STATUS PALETTE (define as a small enum→(accent, fg, tintBg) helper; pull bases
from colorScheme where sensible, else Material shades):
  ok     → green.shade600  / green.shade700  
  watch  → orange.shade600 / orange.shade800 
  neg    → colorScheme.error / red.shade700  
  empty  → outline / onSurfaceVariant        
Tint backgrounds = accent.withValues(alpha: 0.13) composited over surface.

NUMBER FORMATTING
Reuse the existing whole-number rule (no ".0"); format qty with the app's
formatting_helper if one exists (lib/app/data/utils/formatting_helper.dart).
Use the company default currency symbol for rate/value if available, else a
plain number — do not hard-code "AED" unless the codebase already exposes it.

CONSTRAINTS
- Keep _BalanceTile a private StatelessWidget in the same file; you may add small
  private sub-widgets (e.g. _Ledger, _AvailabilityBar, _StatusNote, _MetaFooter).
- Match the app's existing spacing/min-tap conventions; no fixed white/black
  colours — everything theme-derived so dark mode works.
- Run `flutter analyze` and fix all new warnings. Add/adjust a widget test under
  test/widget/ that renders each of the four states without overflow.
- Verify against the four reference cards in the HTML (healthy, heavily-reserved,
  negative, out-of-stock).

DELIVERABLE
The updated stock_balance_screen.dart compiling cleanly, the four states
rendering as in the reference, no standard column leaking into chips, and a
passing widget test.
```
