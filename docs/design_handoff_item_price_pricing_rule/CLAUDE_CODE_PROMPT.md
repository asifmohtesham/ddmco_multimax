# Claude Code prompt — Item Price + Pricing Rule (build)

Copy the fenced block into Claude Code, run from the Flutter project root
(`ddmco_multimax/`) on a branch cut from `origin/release/play-store` at or after
`273447f1` (2.20.0+63). Run it **after** Claude Design returns the mockups from
`CLAUDE_DESIGN_PROMPT.md`; save the exported HTML into this folder first (Claude Design
files are pulled via the Chrome-fetch trick, memory
`reference-claude-design-file-extraction`). All server facts are in `README.md`
(this folder).

---

```
You are working in the ddmco_multimax Flutter app (GetX + Material 3, ERPNext
v15 backend, live site Frappe 15.120 / ERPNext 15.121).

GOAL
Add two manager-facing DocType modules, list + form CRUD, faithful to ERPNext
v15: "Item Price" and "Pricing Rule", plus a read-mostly "Prices" tab on the
existing Item form. Visuals come from the Claude Design mockups in
docs/design_handoff_item_price_pricing_rule/ (HTML); behaviour and server
contract come from docs/design_handoff_item_price_pricing_rule/README.md. Where
the mockup and README disagree on behaviour, README wins; note each deviation
in that folder's README under a new "Build deviations" heading.

BEFORE ANYTHING
- git fetch origin --tags; confirm the branch contains 273447f1 and nobody has
  already shipped this (grep -r "Item Price" lib/ must be empty). If a remote
  claude/* branch already has it, stop and report.
- Use superpowers:writing-plans to turn this prompt into a task plan, then
  superpowers:subagent-driven-development to execute it. Tasks below are the
  intended split.

READ FIRST (patterns to copy — do not change their behaviour)
- CLAUDE.md, docs/doctype_list_view_conventions.md,
  docs/doctype_form_view_conventions.md, docs/app_bar_conventions.md,
  docs/versioning_conventions.md
- docs/design_handoff_item_price_pricing_rule/README.md   # facts + decisions
- CRUD reference (copy structure 1:1):
    lib/app/modules/todo/{todo_binding,todo_controller,todo_screen}.dart
    lib/app/modules/todo/widgets/{todo_list_app_bar,todo_filter_bottom_sheet}.dart
    lib/app/modules/todo/form/{todo_form_binding,todo_form_controller,todo_form_screen}.dart
    lib/app/data/providers/todo_provider.dart, lib/app/data/models/todo_model.dart
  (route args {'name','mode': new|edit|view}; _originalJson dirty snapshot;
   PopScope + GlobalDialog.showUnsavedChanges; saveDocument sends `modified`;
   OptimisticLockingMixin checkStaleAndBlock/handleVersionConflict;
   deleteDocument → performDelete split for tests; not-found fallback)
- lib/app/data/providers/api_provider.dart: getDocumentList (filters map +
  filterTuples incl. child-table 4-tuples), getDocument, createDocument,
  updateDocument, deleteDocument, getDocumentCount
- lib/app/shared/doctype_picker/* + work_order_form_controller.dart warehouse
  picker usage (showDocTypePickerBottomSheet / DocTypePickerConfig filters)
- Item form: lib/app/modules/item/form/{item_form_screen,item_form_controller,
  item_tab_controller}.dart — tabs, lazy onTabChanged (case 1/3/4), Re-order tab
- lib/app/modules/global_widgets/{status_pill,generic_document_card,
  doc_picker_field,doc_section_card,settings_controls,doctype_guard,
  app_nav_drawer}.dart
- lib/app/data/constants/{permission_entries,global_search_targets}.dart
- lib/app/data/routes/{app_routes,app_pages}.dart
- lib/app/data/utils/formatting_helper.dart (getCurrencySymbol, formatAmount)
- tests: test/unit/{todo_model,todo_form_controller,item_reorder_model,
  reorder_rules,status_pill_colour,global_search_targets}_test.dart,
  test/widget/{todo_form_screen,purchase_order_screen}_test.dart

SERVER CONTRACT (verified — design for it, do not fight it)
Item Price (not submittable, name = random hash, never display the name):
- Send ONLY: item_code, uom, packing_unit, price_list, customer, supplier,
  batch_no, price_list_rate, valid_from, valid_upto, lead_time_days, note.
  Server overwrites buying/selling/currency/item_name/item_description/
  reference. Unset links → null, not ''.
- Item picker: Item with has_variants=0, disabled=0 (templates are rejected:
  "Item Price cannot be created for the template item"). enableBarcodeScan.
- UOM picker: ONLY rows of the chosen Item's `uoms` child table (getDocument
  Item → uoms[].uom); default stock_uom. Any other UOM is rejected.
- Price List picker: enabled=1; show currency + Selling/Buying tag. Customer
  field only when the list is selling, Supplier only when buying (server
  clears the other anyway). Batch picker filtered item=item_code.
- valid_from defaults today; valid_upto optional, must be >= valid_from.
- Duplicate key is exact equality (item, list, uom, from, upto, customer,
  supplier, batch, packing_unit) — surface the server message verbatim in an
  InlineBanner (strip HTML tags from _server_messages / exception text).
- Item code is editable only in `new` mode (changing the item of a price is a
  new price; ponytail note).
Pricing Rule (not submittable, naming_series PRLE-.####, title reqd):
- Editable in v1: title, disable, apply_on (Item Code|Item Group|Brand|
  Transaction), items/item_groups/brands child rows (value + optional uom),
  selling, buying, applicable_for + its one link (customer, customer_group,
  territory, sales_partner, campaign, supplier, supplier_group),
  price_or_product_discount = 'Price', rate_or_discount (Rate|Discount
  Percentage|Discount Amount) + rate|discount_percentage|discount_amount,
  for_price_list (hidden + cleared when Rate), apply_discount_on
  (Transaction only), min_qty, max_qty, min_amt, max_amt, valid_from,
  valid_upto, company, currency, warehouse, mixed_conditions, is_cumulative,
  has_priority + priority (STRING "1".."20"), apply_multiple_pricing_rules.
- New doc defaults: apply_on 'Item Code', price_or_product_discount 'Price',
  rate_or_discount 'Discount Percentage', selling 1, valid_from today,
  company + currency from the single Company (fetch Company list once;
  default_currency). naming_series 'PRLE-.####'.
- applicable_for options depend on side: selling → Customer, Customer Group,
  Territory, Sales Partner, Campaign; buying → Supplier, Supplier Group. If
  the current value becomes invalid, clear it (mirror pricing_rule.js).
- for_price_list picker filters selling/buying/currency like the desk query.
- Read-only whole form when promotional_scheme is set (banner) or
  price_or_product_discount == 'Product' (banner "Edit free-item rules on
  desktop"). Show condition / coupon_code_based / is_recursive /
  margin_type / validate_applied_rule / threshold_percentage / 
  apply_discount_on_rate read-only when set; never send them.
- Server clears fields of unselected options on save; send the child table
  matching apply_on only (send [] for the others is fine).
- Child table rows: send without `name` for new rows (see ItemReorder.toJson).
Permissions (live DocPerm = stock v15):
- Item Price: read/write/create/delete = Sales Master Manager, Purchase
  Master Manager. Pricing Rule: Accounts/Sales/Purchase/Website/System
  Manager. PermissionService has no real 'delete' check → gate Delete on
  'write' (delete roles == write roles here; say so in a comment).
- Sales/Stock Users get 403 on Item Price reads: entries must hide, and any
  403 on the Item form Prices tab must degrade to hiding that section, never
  an error screen.

PURE LOGIC (write first, TDD — superpowers:test-driven-development)
lib/app/modules/pricing/pricing_logic.dart (no Flutter/GetX imports):
- enum ValidityState { active, upcoming, expired } +
  ValidityState validityOf(DateTime? from, DateTime? upto, DateTime today)
  (date-only compare; upto inclusive; from inclusive).
- String pricingStatusLabel({required bool disabled, ValidityState v}) →
  'Disabled' | 'Active' | 'Upcoming' | 'Expired'.
- String describePricingRule(PricingRule r, {String currencySymbol}) → the
  one-line summary. Grammar (match the designer's notes page if it differs,
  and record it): <what> [on <price list>] [for <party type> <party>]
  [on <n items|group X|brand X|the whole transaction>] [, min <q> pcs]
  [, <from> – <upto>]. what = "10% off" | "AED 5.00 off" | "Rate AED 20.00" |
  "Free item" (product). Everyone when applicable_for empty → omit "for".
- List<String> validatePricingRule(PricingRule r) mirroring the server
  messages in README §3 (title, targets empty, duplicate target, party
  missing, neither selling nor buying, side/party mismatch, min>max qty and
  amt, negative rate, rate_or_discount missing, upto<from, cumulative needs
  both dates, has_priority without priority). Same style as
  item/form/reorder_rules.dart.
- List<String> validateItemPrice(ItemPrice p) (item, uom, price list, rate
  >= 0 present, upto >= from).
Unit tests: test/unit/pricing_logic_test.dart — every branch above, plus
describePricingRule examples for Rate, Discount %, Discount Amount,
Transaction, Everyone, customer group, date range, product rule.

TASKS
1. Models — lib/app/data/models/item_price_model.dart (ItemPrice with
   fromJson/toJson/copyWith; toJson emits only the sendable fields above)
   and pricing_rule_model.dart (PricingRule + PricingRuleTarget{value, uom,
   name?}; fromJson reads items/item_groups/brands; toJson emits only the
   editable fields). Doubles via (x as num?)?.toDouble() ?? 0. Tests:
   test/unit/item_price_model_test.dart, pricing_rule_model_test.dart
   (round-trip, unset links → null, priority stays a String, child rows
   omit name when new).
2. Pure logic + tests (above).
3. Providers — lib/app/data/providers/item_price_provider.dart and
   pricing_rule_provider.dart, thin wrappers like todo_provider.dart:
   list (fields const), get, create, update, delete, count(filters).
   ItemPriceProvider.getItemUoms(itemCode) → getDocument('Item') uoms +
   stock_uom + has_variants + variant_of. PricingRuleProvider.
   rulesForItem(itemCode, variantOf) → getDocumentList('Pricing Rule',
   filterTuples: [['Pricing Rule Item Code','item_code','in',[code,
   variantOf?]]]) (dedupe by name).
4. StatusPill: add 'Upcoming' to the orange ramp; add Active/Upcoming/
   Expired/Disabled to GenericDocumentCard._statusAccentColor (green/orange/
   red/transparent) using the same colours the map already uses. Extend
   test/unit/status_pill_colour_test.dart.
5. Item Price list — lib/app/modules/pricing/item_price/{item_price_binding,
   item_price_controller,item_price_screen}.dart + widgets/. Conform to the
   list checklist (§5 of list conventions). Search: or-filter item_code like
   / item_name like, 500 ms debounce. Price-list chips from the three enabled
   lists (load Price List names once) with counts via getDocumentCount.
   Filter sheet: price list, validity (active/upcoming/expired → date
   filterTuples), scoped (customer set / supplier set). Order modified desc,
   page 20. Row = GenericDocumentCard(navigatesOnTap: true) per mockup:
   code + name, list, rate "${symbol} ${formatAmount(rate)}" / uom, pill only
   when not active, scope tags. FAB/New behind DocTypeGuard('Item Price',
   permType: 'create'). After returning from the form: refetch that row
   (remove on 404), like ToDo.
6. Item Price form — lib/app/modules/pricing/item_price/form/*. ToDo form
   structure; DocTypeFormHeader (title item_name, statusLabel validity);
   single scroll with DocSectionCards (Main, Validity, More options
   collapsed). Pickers per contract. Rate TextField numberWithOptions(
   decimal) + FilteringTextInputFormatter, prefix currency symbol of the
   chosen list. Route args also accept {'mode':'new','item_code':X} to
   prefill from the Item form (then load that item's UOMs). Save validates
   with validateItemPrice first; server error → InlineBanner. Delete in
   overflow behind DocTypeGuard(permType: 'write'). No realtime auto-save.
7. Pricing Rule list — lib/app/modules/pricing/pricing_rule/*. Status chips
   All/Active/Upcoming/Expired/Disabled (server filterTuples on disable and
   valid dates; counts via getDocumentCount), Selling/Buying filter. Row:
   title + describePricingRule (needs child targets: after each page load
   fetch the three child tables for the page's names with one
   getDocumentList per child doctype, parent in [...], fields parent +
   value; if that 403s, fall back to "on items" without a count). Empty
   state per mockup with "New pricing rule" behind create permission.
8. Pricing Rule form — tabs per mockup (DefaultTabController; isScrollable
   if 4+). Live summary card driven by an Obx over the draft model. Target
   editor: add via showDocTypePickerBottomSheet (Item has_variants any —
   rules may target templates; warn client-side when a template and its own
   variant are both added), optional UOM per row, remove, dedupe. Party
   picker changes doctype with applicable_for. Priority picker 1-20 + clear;
   soft warning (not blocking) when has_priority is off: "If another rule
   matches the same line with the same priority, the Delivery Note will not
   save." Validate with validatePricingRule before save; server error banner.
   Read-only modes per contract.
9. Item form Prices tab — ItemTabController length 5 → 6, new tab label
   "Prices" last, lazy load in onTabChanged case 5: if has_variants show
   FormEmptyState "Prices are set on variants"; else Item Price rows for
   item_code + rulesForItem(code, variant_of). Hide each section when its
   DocType read is denied (hasAccess false or 403). "+ Add price" behind
   DocTypeGuard('Item Price','create') → Item Price form new with item_code;
   reload the tab on return. Update any Item form tests that assert 5 tabs.
10. Wiring — routes ITEM_PRICE '/item-price', ITEM_PRICE_FORM
    '/item-price/form', PRICING_RULE '/pricing-rule', PRICING_RULE_FORM
    '/pricing-rule/form' (forms: Transition.rightToLeftWithFade).
    kSellingPermissions += (Item Price, read), (Pricing Rule, read) (create/
    write resolve on demand via getdoctype). Drawer Selling group: new
    `_NavSubheading('Pricing')` with Item Price (Icons.sell_outlined) and
    Pricing Rule (Icons.discount_outlined), each in DocTypeGuard.
    kGlobalSearchTargets += Pricing Rule (title search, _nameView). Do NOT add
    Item Price to global search (hash names) and do NOT add either to Quick
    Create or the dashboard chip slider (no drafts). Update
    global_search_targets_test expectations.
11. Widget tests — test/widget/item_price_form_screen_test.dart (new/edit/
    view modes, customer vs supplier visibility by list type, save disabled
    until dirty, banner on server error, light+dark no overflow),
    pricing_rule_form_screen_test.dart (party options switch with side,
    for_price_list hidden for Rate, read-only promo + product banners,
    summary updates), item_price_screen_test.dart + pricing_rule_screen_test
    (empty state, FAB hidden without create). Hand-written fakes like
    todo_form_controller_test (no mockito).

CONSTRAINTS
- No new packages. No `dart format` on existing files (hand-indent).
- Run `flutter analyze`, then `flutter test` — never both at once.
- Colours: AppColors ramp + context.scheme only (CLAUDE.md contrast rules);
  both themes. Async controls: AsyncFilledButton/AsyncIconButton or own Obx.
- Workers stored + cancelled in onClose; no ever() on error Rx as the only
  rebuild trigger (same-value sets are dropped).
- Money never summed across rows; 2 decimals; symbol from price list
  currency.
- Keep the diff minimal: reuse listed widgets; if something truly can't be
  reused, one-line comment why. Extract ToDo's _showOptionPicker to
  global_widgets only if a second caller needs it.
- Out of scope (ponytail — add when asked): free-item (Product) rule editing,
  dynamic condition/coupon/recursion/margin editing, effective-price preview
  (get_item_details / apply_price_list — args shape unverified live), "items
  without a price" report (needs server anti-join), bulk price update,
  Price List CRUD, realtime auto-save.

VERIFY (superpowers:verification-before-completion)
- analyze clean; full suite green (report counts).
- On-device smoke with a Sales Master Manager account AND a Sales-User-only
  account (entries hidden, Item Prices tab section hidden, no red screens).
  Side-by-side install per memory feedback-side-by-side-smoke-install
  (temporary applicationIdSuffix + label; revert before commit).
- Live round-trip on erp.multimax.cloud: create a Standard Selling price for a
  variant with valid_upto → edit → duplicate attempt shows server banner →
  delete. Create a disabled test Pricing Rule (disable=1 so it can never bite
  a real Delivery Note), edit, delete. Ask the user before any write to the
  live site.

DELIVERABLE
Item Price + Pricing Rule list/form CRUD under Selling › Pricing in the
drawer, Prices tab on Item, Pricing Rule in global search; permission-gated;
v15-faithful validation; tests green. Version bump is MINOR (new modules) —
follow docs/versioning_conventions.md at release time, not in this task.
```
