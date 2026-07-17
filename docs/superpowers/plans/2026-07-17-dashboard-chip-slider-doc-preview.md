# Dashboard Chip Slider + Document Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the shipped "Upcoming & actionable" count strip into a horizontally-scrolling DocType selector (adding Packing Slip, using full DocType names) that drives a 3-document preview with a View All button.

**Architecture:** `dashboard_actionable_strip.dart` keeps the enum/configs/filters/chip/slider; a new `dashboard_actionable_preview.dart` owns the row model, the pure row mapper, and the preview widgets — both controller-free and widget-testable. `HomeController` gains a selected-chip + a lazy, cached 3-document fetch issued straight through `ApiProvider.getDocumentList`. `PackingSlipController` gets the `onInit` filter-seed hook the other four already have.

**Tech Stack:** Flutter, GetX (state/DI/routing), Dio (`ApiProvider`), Frappe/ERPNext REST, `intl` (date formatting).

## Global Constraints

- **Chip order (verbatim):** Tasks · Purchase Order · Purchase Receipt · Stock Entry · Delivery Note · Packing Slip.
- **Labels:** full DocType names for the five documents; the ToDo chip's label is **`Tasks`**.
- **Actionable = Draft.** `actionableFiltersFor` is the single source of truth and feeds the count, the preview, AND the View All list, so all three agree.
- **Packing Slip `status` is a VIRTUAL field** — requesting or filtering it via `getDocumentList` raises a Frappe `FieldError`. PS **must** use `{'docstatus': 0}` (like Stock Entry) and must **never** request or filter `status`.
- **Chip states:** selected = primary tint + primary border; unselected = `scheme.fg` + `scheme.border`; **zero count = dim AND inert** (no InkWell, not selectable).
- **Default selection:** `Tasks`; if Tasks count is 0 → first `kActionableDocConfigs` doctype with a non-zero count; if all zero → none. Not persisted.
- **Owner always shown** in a document row's subtitle, in both scopes; display name via `userList`, else the email's local part.
- **No status pill in rows** — every previewed doc is a Draft, so it carries no information.
- **Contrast: theme tokens only** (`context.scheme.*`, `colorScheme.primary`); never `Colors.white`/`grey.shadeX`/`black87`. (`Colors.transparent` for a Material/InkWell wrapper is fine.)
- Widget files must NOT import `HomeController` (stay testable with a bare `MaterialApp(theme: ThemeData(brightness:))`).
- **Semver:** feature → **MINOR** bump per `docs/versioning_conventions.md`. Release is user-driven; this plan does not bump.
- DRY, YAGNI, TDD, frequent commits. Re-check `git branch --show-current` before each commit.

### Deviation from the spec (deliberate, applies to Tasks 1/4/5)

The spec said the preview would call each DocType's provider method and that
`'owner'` would be added to `PurchaseOrderProvider`. **`PurchaseOrderProvider`
and `PurchaseReceiptProvider` are not registered in `HomeBinding`**
(`home_binding.dart` registers only Bom/DeliveryNote/PackingSlip/PosUpload/ToDo/
Item/WorkOrder/JobCard/User/StockEntry), so `Get.find` on them from
`HomeController` would throw. Instead the preview queries
`ApiProvider.getDocumentList(doctype, fields: cfg.previewFields, …)` directly
(`ApiProvider` is permanent and already a `HomeController` dependency). This
needs no DI changes, fetches only the 4 fields a row shows, and removes the need
to touch `PurchaseOrderProvider` at all (dropped from this plan per YAGNI).

---

### Task 1: Configs, Packing Slip filter, and pure selection helper

**Files:**
- Modify: `lib/app/modules/home/widgets/dashboard_actionable_strip.dart`
- Test: `test/unit/actionable_filters_test.dart` (existing — extend)

**Interfaces:**
- Consumes: existing `ActionableScope`, `actionableCacheKey`, `AppRoutes`.
- Produces:
  - `class ActionableDocConfig { String doctype; String label; IconData icon; String listRoute; String formRoute; List<String> previewFields; }`
  - `const List<ActionableDocConfig> kActionableDocConfigs` (5 entries: PO, PR, SE, DN, PS)
  - `Map<String,dynamic> actionableFiltersFor(String doctype, ActionableScope scope, String? email)` (PS joins the docstatus branch)
  - `String? defaultActionableSelection(Map<String,int> counts, int todoCount)`
  - `ActionableChipData` gains `final bool selected` (defaults `false`)

- [ ] **Step 1: Write the failing test**

Append these groups to `test/unit/actionable_filters_test.dart`, and REPLACE the existing `kActionableDocConfigs` group with the version below (labels and length changed):

```dart
  group('actionableFiltersFor — Packing Slip', () {
    test('Packing Slip filters on docstatus 0, never status (virtual field)', () {
      final f = actionableFiltersFor('Packing Slip', ActionableScope.everyone, 'x@y.com');
      expect(f, {'docstatus': 0});
      expect(f.containsKey('status'), isFalse);
    });

    test('Packing Slip under mine adds owner and still uses docstatus', () {
      expect(actionableFiltersFor('Packing Slip', ActionableScope.mine, 'a@b.com'),
          {'docstatus': 0, 'owner': 'a@b.com'});
    });
  });

  group('kActionableDocConfigs', () {
    test('covers the five document DocTypes in strip order', () {
      expect(kActionableDocConfigs.map((c) => c.doctype).toList(), [
        'Purchase Order',
        'Purchase Receipt',
        'Stock Entry',
        'Delivery Note',
        'Packing Slip',
      ]);
    });

    test('labels are the full DocType names', () {
      for (final c in kActionableDocConfigs) {
        expect(c.label, c.doctype);
      }
    });

    test('every config carries preview fields incl. name and owner', () {
      for (final c in kActionableDocConfigs) {
        expect(c.previewFields, contains('name'));
        expect(c.previewFields, contains('owner'));
      }
    });

    test('Packing Slip never requests the virtual status field', () {
      final ps = kActionableDocConfigs.firstWhere((c) => c.doctype == 'Packing Slip');
      expect(ps.previewFields, isNot(contains('status')));
      expect(ps.previewFields, contains('delivery_note'));
    });
  });

  group('defaultActionableSelection', () {
    test('defaults to Tasks when there are open todos', () {
      expect(defaultActionableSelection({'Purchase Order': 5}, 2), 'ToDo');
    });

    test('falls through to the first doctype with work when Tasks is empty', () {
      expect(
        defaultActionableSelection(
            {'Purchase Order': 0, 'Purchase Receipt': 0, 'Stock Entry': 4}, 0),
        'Stock Entry',
      );
    });

    test('respects config order when several have work', () {
      expect(
        defaultActionableSelection({'Delivery Note': 9, 'Purchase Order': 3}, 0),
        'Purchase Order',
      );
    });

    test('returns null when nothing is actionable', () {
      expect(defaultActionableSelection({'Purchase Order': 0}, 0), isNull);
      expect(defaultActionableSelection({}, 0), isNull);
    });
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/unit/actionable_filters_test.dart`
Expected: FAIL — `defaultActionableSelection` undefined; `ActionableDocConfig` has no `previewFields`; Packing Slip filter returns `{'status': 'Draft'}`.

- [ ] **Step 3: Implement**

In `dashboard_actionable_strip.dart`, replace `actionableFiltersFor`'s doc comment + body, the `ActionableDocConfig` class, `kActionableDocConfigs`, and `ActionableChipData`, and add `defaultActionableSelection`:

```dart
/// Frappe filter map for the "still a Draft" documents of [doctype]. Used for
/// the `get_count` query, the 3-document preview, AND the tap-target list, so a
/// chip's count, its preview, and its opened list always agree.
///
/// PO/PR/DN filter on `status == 'Draft'` (equivalent to docstatus 0 for these
/// submittables, and it renders a removable "Status: Draft" chip on the list).
/// Stock Entry has no `status` field, and Packing Slip's `status` is a VIRTUAL
/// field that raises a Frappe FieldError when queried — both filter on
/// `docstatus == 0`. Under [ActionableScope.mine] a non-empty [email] adds an
/// `owner` equality.
Map<String, dynamic> actionableFiltersFor(
    String doctype, ActionableScope scope, String? email) {
  final filters = <String, dynamic>{};
  if (doctype == 'Stock Entry' || doctype == 'Packing Slip') {
    filters['docstatus'] = 0;
  } else {
    filters['status'] = 'Draft';
  }
  if (scope == ActionableScope.mine && email != null && email.isNotEmpty) {
    filters['owner'] = email;
  }
  return filters;
}

/// Static identity of one document chip. [label] is the presentation label
/// (currently the full DocType name; the Tasks chip built in the screen uses a
/// different label, which is why this is a separate field). [previewFields] are
/// the ONLY fields the 3-document preview requests for this DocType.
class ActionableDocConfig {
  final String doctype;
  final String label;
  final IconData icon;
  final String listRoute;
  final String formRoute;
  final List<String> previewFields;
  const ActionableDocConfig({
    required this.doctype,
    required this.label,
    required this.icon,
    required this.listRoute,
    required this.formRoute,
    required this.previewFields,
  });
}

const List<ActionableDocConfig> kActionableDocConfigs = [
  ActionableDocConfig(
    doctype: 'Purchase Order',
    label: 'Purchase Order',
    icon: Icons.shopping_cart_outlined,
    listRoute: AppRoutes.PURCHASE_ORDER,
    formRoute: AppRoutes.PURCHASE_ORDER_FORM,
    previewFields: ['name', 'supplier', 'transaction_date', 'owner'],
  ),
  ActionableDocConfig(
    doctype: 'Purchase Receipt',
    label: 'Purchase Receipt',
    icon: Icons.receipt_long_outlined,
    listRoute: AppRoutes.PURCHASE_RECEIPT,
    formRoute: AppRoutes.PURCHASE_RECEIPT_FORM,
    previewFields: ['name', 'supplier', 'posting_date', 'owner'],
  ),
  ActionableDocConfig(
    doctype: 'Stock Entry',
    label: 'Stock Entry',
    icon: Icons.swap_horiz,
    listRoute: AppRoutes.STOCK_ENTRY,
    formRoute: AppRoutes.STOCK_ENTRY_FORM,
    previewFields: ['name', 'stock_entry_type', 'posting_date', 'owner'],
  ),
  ActionableDocConfig(
    doctype: 'Delivery Note',
    label: 'Delivery Note',
    icon: Icons.local_shipping_outlined,
    listRoute: AppRoutes.DELIVERY_NOTE,
    formRoute: AppRoutes.DELIVERY_NOTE_FORM,
    previewFields: ['name', 'customer', 'posting_date', 'owner'],
  ),
  // Packing Slip: `status` is virtual (FieldError if queried) and there is no
  // posting_date on its list — the row falls back to `creation`.
  ActionableDocConfig(
    doctype: 'Packing Slip',
    label: 'Packing Slip',
    icon: Icons.inventory_2_outlined,
    listRoute: AppRoutes.PACKING_SLIP,
    formRoute: AppRoutes.PACKING_SLIP_FORM,
    previewFields: ['name', 'delivery_note', 'creation', 'owner'],
  ),
];

/// The chip selected on load: 'ToDo' (Tasks) when it has work, else the first
/// [kActionableDocConfigs] doctype with a non-zero count, else null (every chip
/// is muted/inert, so nothing is selectable).
String? defaultActionableSelection(Map<String, int> counts, int todoCount) {
  if (todoCount > 0) return 'ToDo';
  for (final cfg in kActionableDocConfigs) {
    if ((counts[cfg.doctype] ?? 0) > 0) return cfg.doctype;
  }
  return null;
}

/// One rendered chip's data. [muted] (a zero count) renders dim with a null
/// [onTap] so the chip is non-interactive and cannot be selected.
class ActionableChipData {
  final String doctype;
  final String label;
  final IconData icon;
  final int count;
  final bool selected;
  final VoidCallback? onTap;
  const ActionableChipData({
    required this.doctype,
    required this.label,
    required this.icon,
    required this.count,
    required this.onTap,
    this.selected = false,
  });

  bool get muted => count == 0;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/unit/actionable_filters_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add lib/app/modules/home/widgets/dashboard_actionable_strip.dart test/unit/actionable_filters_test.dart
git commit -m "$(cat <<'EOF'
feat(dashboard): full-name chip configs, Packing Slip, default selection

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Selected chip state + horizontal slider

**Files:**
- Modify: `lib/app/modules/home/widgets/dashboard_actionable_strip.dart` (`ActionableCountChip`, `DashboardActionableStrip`)
- Test: `test/unit/dashboard_actionable_strip_test.dart` (existing — extend/replace)

**Interfaces:**
- Consumes (Task 1): `ActionableChipData` (with `selected`).
- Produces: `ActionableCountChip` renders selected/unselected/muted; `DashboardActionableStrip` scrolls horizontally (no `Wrap`). The strip stays dumb — selection is carried per-chip via `ActionableChipData.selected` + `onTap`, so there is no second source of truth.

- [ ] **Step 1: Write the failing test**

Replace the `DashboardActionableStrip` group in `test/unit/dashboard_actionable_strip_test.dart` and add a selected-chip test. Note `_chip` gains a `selected` argument:

```dart
ActionableChipData _chipSel(String label, int count, VoidCallback? onTap,
        {bool selected = false}) =>
    ActionableChipData(
        doctype: label,
        label: label,
        icon: Icons.circle,
        count: count,
        onTap: onTap,
        selected: selected);

void _stripTests() {
  group('DashboardActionableStrip', () {
    testWidgets('renders one chip per data entry', (t) async {
      await _pump(t, DashboardActionableStrip(isLoading: false, chips: [
        _chipSel('Purchase Order', 1, () {}),
        _chipSel('Delivery Note', 0, null),
      ]));
      expect(find.byType(ActionableCountChip), findsNWidgets(2));
    });

    testWidgets('scrolls horizontally and never wraps', (t) async {
      await _pump(t, DashboardActionableStrip(isLoading: false, chips: [
        for (final l in ['Tasks', 'Purchase Order', 'Purchase Receipt',
                         'Stock Entry', 'Delivery Note', 'Packing Slip'])
          _chipSel(l, 3, () {}),
      ]));
      expect(find.byType(Wrap), findsNothing);
      final sv = tester_scrollView(t);
      expect(sv.scrollDirection, Axis.horizontal);
    });

    testWidgets('isLoading shows placeholders, not chips', (t) async {
      await _pump(t, const DashboardActionableStrip(isLoading: true, chips: []));
      expect(find.byType(ActionableCountChip), findsNothing);
      expect(find.byKey(const ValueKey('actionable-strip-loading')), findsOneWidget);
    });
  });

  group('ActionableCountChip selection', () {
    testWidgets('selected chip reports its doctype on tap', (t) async {
      String? tapped;
      await _pump(t, ActionableCountChip(
          data: _chipSel('Stock Entry', 2, () => tapped = 'Stock Entry')));
      await t.tap(find.byType(ActionableCountChip));
      expect(tapped, 'Stock Entry');
    });

    testWidgets('muted chip is not selectable (no ink well)', (t) async {
      await _pump(t, ActionableCountChip(data: _chipSel('Purchase Receipt', 0, null)));
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('selected renders differently from unselected', (t) async {
      await _pump(t, Column(children: [
        ActionableCountChip(data: _chipSel('A', 1, () {}, selected: true)),
        ActionableCountChip(data: _chipSel('B', 1, () {}, selected: false)),
      ]));
      final boxes = t.widgetList<Container>(find.descendant(
              of: find.byType(ActionableCountChip), matching: find.byType(Container)))
          .map((c) => (c.decoration as BoxDecoration).color)
          .toList();
      expect(boxes.first, isNot(equals(boxes.last)));
    });
  });
}

SingleChildScrollView tester_scrollView(WidgetTester t) =>
    t.widget<SingleChildScrollView>(find.byType(SingleChildScrollView).first);
```

Call `_stripTests();` from `main()` in place of the old `DashboardActionableStrip` group, and keep the existing `ActionableCountChip`/`ActionableScopeToggle` groups (update their `_chip(...)` helper calls to `_chipSel(...)` if the old helper is removed).

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/unit/dashboard_actionable_strip_test.dart`
Expected: FAIL — `selected` is not a parameter of `ActionableChipData` (until Task 1 is present it also fails to compile); `Wrap` still found; no `SingleChildScrollView`.

- [ ] **Step 3: Implement**

Replace `ActionableCountChip.build`'s `content` decoration/ink colours and the whole `DashboardActionableStrip`:

```dart
  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final cs = Theme.of(context).colorScheme;
    final muted = data.muted;
    final selected = data.selected;

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? cs.primary.withValues(alpha: 0.13) : scheme.fg,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: selected ? cs.primary : scheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(data.icon,
              size: 16, color: muted ? scheme.textSubtle : cs.primary),
          const SizedBox(width: 6),
          Text(
            data.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: muted
                  ? scheme.textMuted
                  : (selected ? cs.primary : scheme.text),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${data.count}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: muted ? scheme.textSubtle : cs.primary,
            ),
          ),
        ],
      ),
    );

    if (muted || data.onTap == null) {
      return content;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: content,
      ),
    );
  }
```

```dart
/// The horizontally-scrolling row of actionable chips — a DocType selector.
/// Never wraps (the previous Wrap spilled onto a second row). Shows muted
/// placeholder pills while [isLoading]. Selection is carried per-chip via
/// [ActionableChipData.selected] / [ActionableChipData.onTap].
class DashboardActionableStrip extends StatelessWidget {
  final List<ActionableChipData> chips;
  final bool isLoading;
  const DashboardActionableStrip({
    super.key,
    required this.chips,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;

    if (isLoading) {
      return SingleChildScrollView(
        key: const ValueKey('actionable-strip-loading'),
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Row(
          children: [
            for (var i = 0; i < 5; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Container(
                width: 96,
                height: 34,
                decoration: BoxDecoration(
                  color: scheme.subtle,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(color: scheme.border),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return SingleChildScrollView(
      key: const ValueKey('actionable-strip'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            ActionableCountChip(data: chips[i]),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/unit/dashboard_actionable_strip_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add lib/app/modules/home/widgets/dashboard_actionable_strip.dart test/unit/dashboard_actionable_strip_test.dart
git commit -m "$(cat <<'EOF'
feat(dashboard): chip selection state and horizontal chip slider

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Document preview — row model, mapper, and widgets

**Files:**
- Create: `lib/app/modules/home/widgets/dashboard_actionable_preview.dart`
- Test: `test/unit/dashboard_actionable_preview_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks (pure + widgets).
- Produces:
  - `class ActionableDocRowData { String name; String subtitle; VoidCallback? onTap; }`
  - `String ownerLabelFor(String email, Map<String,String> namesByEmail)`
  - `ActionableDocRowData docRowFor(String doctype, Map<String,dynamic> json, String Function(String) ownerLabel, {VoidCallback? onTap})`
  - `class ActionableDocRow extends StatelessWidget { ActionableDocRowData data; }`
  - `class ActionableDocPreview extends StatelessWidget { List<ActionableDocRowData> rows; bool isLoading; VoidCallback onViewAll; }`

- [ ] **Step 1: Write the failing test**

```dart
// test/unit/dashboard_actionable_preview_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/home/widgets/dashboard_actionable_preview.dart';

Future<void> _pump(WidgetTester t, Widget child,
        {Brightness b = Brightness.light}) =>
    t.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: b),
      home: Scaffold(body: child),
    ));

String _owner(String e) => ownerLabelFor(e, const {'jawwad@x.com': 'Jawwad Ahmed'});

void main() {
  group('ownerLabelFor', () {
    test('known user resolves to the display name', () {
      expect(ownerLabelFor('jawwad@x.com', const {'jawwad@x.com': 'Jawwad Ahmed'}),
          'Jawwad Ahmed');
    });

    test('unknown user falls back to the email local part', () {
      expect(ownerLabelFor('someone@x.com', const {}), 'someone');
    });

    test('empty email yields empty label', () {
      expect(ownerLabelFor('', const {}), '');
    });

    test('malformed email (no @) returns as-is', () {
      expect(ownerLabelFor('administrator', const {}), 'administrator');
    });
  });

  group('docRowFor', () {
    test('Purchase Order: supplier, owner, transaction_date', () {
      final r = docRowFor('Purchase Order', {
        'name': 'PO-0421',
        'supplier': 'Acme Corp',
        'transaction_date': '2026-07-12',
        'owner': 'jawwad@x.com',
      }, _owner);
      expect(r.name, 'PO-0421');
      expect(r.subtitle, 'Acme Corp · Jawwad Ahmed · 12 Jul');
    });

    test('Delivery Note uses customer + posting_date', () {
      final r = docRowFor('Delivery Note', {
        'name': 'DN-0198',
        'customer': 'Zenith Ltd',
        'posting_date': '2026-07-11',
        'owner': 'unknown@x.com',
      }, _owner);
      expect(r.subtitle, 'Zenith Ltd · unknown · 11 Jul');
    });

    test('Stock Entry uses stock_entry_type', () {
      final r = docRowFor('Stock Entry', {
        'name': 'SE-0031',
        'stock_entry_type': 'Material Issue',
        'posting_date': '2026-07-10',
        'owner': 'jawwad@x.com',
      }, _owner);
      expect(r.subtitle, 'Material Issue · Jawwad Ahmed · 10 Jul');
    });

    test('Packing Slip uses delivery_note and falls back to creation', () {
      final r = docRowFor('Packing Slip', {
        'name': 'PS-0009',
        'delivery_note': 'DN-0198',
        'creation': '2026-07-09 08:30:00',
        'owner': 'jawwad@x.com',
      }, _owner);
      expect(r.subtitle, 'DN-0198 · Jawwad Ahmed · 9 Jul');
    });

    test('empty segments are omitted — no stray separators', () {
      final r = docRowFor('Purchase Receipt', {
        'name': 'PR-0087',
        'supplier': '',
        'posting_date': '',
        'owner': '',
      }, _owner);
      expect(r.name, 'PR-0087');
      expect(r.subtitle, '');
    });

    test('unparseable date is dropped rather than rendered raw', () {
      final r = docRowFor('Purchase Order', {
        'name': 'PO-1',
        'supplier': 'Acme',
        'transaction_date': 'not-a-date',
        'owner': '',
      }, _owner);
      expect(r.subtitle, 'Acme');
    });
  });

  group('ActionableDocPreview', () {
    testWidgets('renders a row per entry plus View All', (t) async {
      await _pump(t, ActionableDocPreview(
        isLoading: false,
        onViewAll: () {},
        rows: const [
          ActionableDocRowData(name: 'PO-1', subtitle: 'Acme · Jawwad · 12 Jul'),
          ActionableDocRowData(name: 'PO-2', subtitle: 'Bolt · Jawwad · 11 Jul'),
          ActionableDocRowData(name: 'PO-3', subtitle: 'Zen · Jawwad · 10 Jul'),
        ],
      ));
      expect(find.byType(ActionableDocRow), findsNWidgets(3));
      expect(find.text('View All'), findsOneWidget);
      expect(find.text('PO-1'), findsOneWidget);
      expect(find.text('Acme · Jawwad · 12 Jul'), findsOneWidget);
    });

    testWidgets('View All fires', (t) async {
      var tapped = false;
      await _pump(t, ActionableDocPreview(
        isLoading: false,
        onViewAll: () => tapped = true,
        rows: const [ActionableDocRowData(name: 'PO-1', subtitle: 's')],
      ));
      await t.tap(find.text('View All'));
      expect(tapped, isTrue);
    });

    testWidgets('row tap fires', (t) async {
      var tapped = false;
      await _pump(t, ActionableDocPreview(
        isLoading: false,
        onViewAll: () {},
        rows: [ActionableDocRowData(name: 'PO-1', subtitle: 's', onTap: () => tapped = true)],
      ));
      await t.tap(find.byType(ActionableDocRow));
      expect(tapped, isTrue);
    });

    testWidgets('isLoading shows a skeleton, not rows', (t) async {
      await _pump(t, ActionableDocPreview(
          isLoading: true, rows: const [], onViewAll: () {}));
      expect(find.byType(ActionableDocRow), findsNothing);
      expect(find.byKey(const ValueKey('actionable-preview-loading')), findsOneWidget);
    });

    testWidgets('empty and not loading collapses', (t) async {
      await _pump(t, ActionableDocPreview(
          isLoading: false, rows: const [], onViewAll: () {}));
      expect(find.byType(ActionableDocRow), findsNothing);
      expect(find.text('View All'), findsNothing);
    });

    testWidgets('renders in dark mode', (t) async {
      await _pump(t, ActionableDocPreview(
        isLoading: false,
        onViewAll: () {},
        rows: const [ActionableDocRowData(name: 'PO-1', subtitle: 'Acme · 12 Jul')],
      ), b: Brightness.dark);
      expect(find.text('PO-1'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/unit/dashboard_actionable_preview_test.dart`
Expected: FAIL — `Error: Not found: ...dashboard_actionable_preview.dart`.

- [ ] **Step 3: Implement**

```dart
// lib/app/modules/home/widgets/dashboard_actionable_preview.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// One previewed document row. [onTap] deep-links to that document's form.
class ActionableDocRowData {
  final String name;
  final String subtitle;
  final VoidCallback? onTap;
  const ActionableDocRowData({
    required this.name,
    required this.subtitle,
    this.onTap,
  });
}

/// Resolves an owner email to a display label: the user's full name when known,
/// otherwise the email's local part ('jawwad@x.com' -> 'jawwad'). Frappe stores
/// `owner` as an email; [namesByEmail] comes from the dashboard's loaded users,
/// which will not contain every owner under the Everyone scope.
String ownerLabelFor(String email, Map<String, String> namesByEmail) {
  if (email.isEmpty) return '';
  final name = namesByEmail[email];
  if (name != null && name.isNotEmpty) return name;
  final at = email.indexOf('@');
  return at > 0 ? email.substring(0, at) : email;
}

/// Short human date ('12 Jul'); empty when absent or unparseable.
String _shortDate(String raw) {
  if (raw.isEmpty) return '';
  final d = DateTime.tryParse(raw);
  return d == null ? '' : DateFormat('d MMM').format(d);
}

/// Maps a raw Frappe list row to a preview row for [doctype].
///
/// Every previewed document is a Draft (that IS the actionable definition), so
/// no status is rendered — the subtitle is `<party> · <owner> · <date>` with
/// empty segments omitted. Packing Slip has no posting_date on its list, so it
/// falls back to `creation`.
ActionableDocRowData docRowFor(
  String doctype,
  Map<String, dynamic> json,
  String Function(String) ownerLabel, {
  VoidCallback? onTap,
}) {
  String s(String key) => (json[key] ?? '').toString();

  String party;
  String date;
  switch (doctype) {
    case 'Purchase Order':
      party = s('supplier');
      date = _shortDate(s('transaction_date'));
      break;
    case 'Purchase Receipt':
      party = s('supplier');
      date = _shortDate(s('posting_date'));
      break;
    case 'Stock Entry':
      party = s('stock_entry_type');
      date = _shortDate(s('posting_date'));
      break;
    case 'Delivery Note':
      party = s('customer');
      date = _shortDate(s('posting_date'));
      break;
    case 'Packing Slip':
      party = s('delivery_note');
      date = _shortDate(s('creation'));
      break;
    default:
      party = '';
      date = _shortDate(s('creation'));
  }

  final segments = [party, ownerLabel(s('owner')), date]
      .where((p) => p.isNotEmpty)
      .toList();

  return ActionableDocRowData(
    name: s('name'),
    subtitle: segments.join(' · '),
    onTap: onTap,
  );
}

/// A single previewed document: id + `party · owner · date` + chevron.
class ActionableDocRow extends StatelessWidget {
  final ActionableDocRowData data;
  const ActionableDocRow({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;

    return Material(
      color: scheme.fg,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: scheme.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                        color: scheme.text,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (data.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        data.subtitle,
                        style: TextStyle(fontSize: 12, color: scheme.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: scheme.textSubtle, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// The selected chip's document preview: up to three rows then a View All
/// button. Shows a skeleton while [isLoading]; collapses when there is nothing
/// to show.
class ActionableDocPreview extends StatelessWidget {
  final List<ActionableDocRowData> rows;
  final bool isLoading;
  final VoidCallback onViewAll;
  const ActionableDocPreview({
    super.key,
    required this.rows,
    required this.isLoading,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;

    if (isLoading) {
      return Column(
        key: const ValueKey('actionable-preview-loading'),
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(height: 9),
            Container(
              height: 58,
              decoration: BoxDecoration(
                color: scheme.subtle,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: scheme.border),
              ),
            ),
          ],
        ],
      );
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 9),
          ActionableDocRow(data: rows[i]),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: onViewAll,
            child: const Text('View All'),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/unit/dashboard_actionable_preview_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add lib/app/modules/home/widgets/dashboard_actionable_preview.dart test/unit/dashboard_actionable_preview_test.dart
git commit -m "$(cat <<'EOF'
feat(dashboard): document preview row mapper and widgets

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Packing Slip list honours the `filters` route arg

**Files:**
- Modify: `lib/app/modules/packing_slip/packing_slip_controller.dart` (`onInit`, ~lines 66-71)

**Interfaces:**
- Consumes: the `{'filters': …}` route argument produced by `HomeController.openActionableList` (Task 5) and the controller's existing `activeFilters` / `applyFilters`.
- Produces: nothing new — behavioural change only.

> **Why `onInit` and not `onReady`:** `onInit` already calls `fetchPackingSlips()`. Seeding the filter in `onReady` would fire a SECOND, filtered fetch that races the unfiltered `onInit` one (this exact bug was found and fixed on the other four controllers). Seeding before the initial fetch means one, already-filtered request.
>
> **Verification:** GetX `onInit`/route-argument behaviour is not unit-tested in this repo; this task is verified by `flutter analyze` and the on-device drive in Task 6.

- [ ] **Step 1: Seed the filter before the initial fetch**

Replace `onInit` in `packing_slip_controller.dart`:

```dart
  @override
  void onInit() {
    super.onInit();
    _homeController.activeScreen.value = ActiveScreen.packingSlip;
    // Seed a deep-linked filter BEFORE the initial fetch so only one, already
    // filtered, request runs (an onReady applyFilters would race this fetch).
    final args = Get.arguments;
    if (args is Map && args['filters'] is Map) {
      activeFilters.value = Map<String, dynamic>.from(args['filters'] as Map);
    }
    fetchPackingSlips();
  }
```

Leave `onReady` (its `openCreate` branch), `applyFilters`, and all fetch logic untouched.

- [ ] **Step 2: Verify the analyzer**

Run: `flutter analyze lib/app/modules/packing_slip/packing_slip_controller.dart`
Expected: no new errors/warnings for this file.

- [ ] **Step 3: Commit**

```bash
git branch --show-current
git add lib/app/modules/packing_slip/packing_slip_controller.dart
git commit -m "$(cat <<'EOF'
feat(packing-slip): honor a `filters` route arg to open a pre-filtered list

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: HomeController — selection state and cached preview fetch

**Files:**
- Modify: `lib/app/modules/home/home_controller.dart`

**Interfaces:**
- Consumes (Tasks 1/3): `kActionableDocConfigs`, `ActionableDocConfig` (`doctype`, `formRoute`, `listRoute`, `previewFields`), `actionableFiltersFor`, `actionableCacheKey`, `defaultActionableSelection`, `ActionableDocRowData`, `docRowFor`, `ownerLabelFor`.
- Produces (used by Task 6): `RxnString selectedActionable`, `RxList<ActionableDocRowData> previewDocs`, `RxBool isLoadingPreview`, `Map<String,String> get namesByEmail`, `void selectActionable(String doctype)`, `Future<void> fetchPreviewDocs({bool force})`.

> **Verification:** as with the shipped counts work, the pure pieces are covered by Tasks 1/3; this wiring is verified by `flutter analyze` + the full suite + Task 6's on-device drive.

- [ ] **Step 1: Add the import and state**

Add to the imports of `home_controller.dart`:

```dart
import 'package:multimax/app/modules/home/widgets/dashboard_actionable_preview.dart';
```

Add beside the existing actionable state (near `_actionableCountCache`):

```dart
  /// The doctype whose 3-document preview is shown ('ToDo' = the Tasks chip).
  /// Null when nothing is actionable. Transient — not persisted.
  final selectedActionable = RxnString();

  /// The selected doctype's preview rows (empty for 'ToDo', whose rows render
  /// as DashboardTodoCards from [upcomingTodos]).
  final previewDocs = <ActionableDocRowData>[].obs;

  /// True while the selected doctype's preview fetch is in flight.
  final isLoadingPreview = false.obs;

  /// Preview cache keyed by '<doctype>::<actionableCacheKey(scope, email)>'.
  final Map<String, List<ActionableDocRowData>> _previewCache = {};

  /// Display names for owner resolution, keyed by email, from the loaded users.
  Map<String, String> get namesByEmail => {
        for (final u in userList)
          if (u.email.isNotEmpty) u.email: u.name,
      };
```

- [ ] **Step 2: Add selection + preview fetch**

Add these methods after `fetchActionableCounts`:

```dart
  /// Selects a chip and loads its preview. 'ToDo' renders from [upcomingTodos]
  /// and needs no fetch.
  void selectActionable(String doctype) {
    if (selectedActionable.value == doctype) return;
    selectedActionable.value = doctype;
    fetchPreviewDocs();
  }

  /// Applies the default chip when nothing is selected or the current selection
  /// no longer has work, then refreshes the preview. Called after counts and
  /// todos land.
  void _applyDefaultSelection() {
    final current = selectedActionable.value;
    final stillHasWork = current != null &&
        (current == 'ToDo'
            ? openTodoCount.value > 0
            : (actionableCounts[current] ?? 0) > 0);
    if (!stillHasWork) {
      selectedActionable.value =
          defaultActionableSelection(actionableCounts, openTodoCount.value);
    }
    fetchPreviewDocs(force: true);
  }

  /// Fetches the selected doctype's first 3 Draft documents, using the SAME
  /// filter as its count and its View All list. Served from cache unless
  /// [force]. Queries ApiProvider directly (PO/PR providers are not registered
  /// in HomeBinding) requesting only the fields a row renders.
  Future<void> fetchPreviewDocs({bool force = false}) async {
    final doctype = selectedActionable.value;
    if (doctype == null || doctype == 'ToDo') {
      previewDocs.clear();
      isLoadingPreview.value = false;
      return;
    }
    final cfg = kActionableDocConfigs.firstWhereOrNull((c) => c.doctype == doctype);
    if (cfg == null) {
      previewDocs.clear();
      return;
    }

    final scope = actionableScope.value;
    final email = selectedFilterUser.value?.email ??
        _authController.currentUser.value?.email;
    final key = '$doctype::${actionableCacheKey(scope, email)}';

    if (force) _previewCache.clear();

    final cached = _previewCache[key];
    if (cached != null) {
      previewDocs.assignAll(cached);
      isLoadingPreview.value = false;
      return;
    }

    isLoadingPreview.value = true;
    try {
      final res = await _apiProvider.getDocumentList(
        doctype,
        filters: actionableFiltersFor(doctype, scope, email),
        fields: cfg.previewFields,
        limit: 3,
        orderBy: 'creation desc',
      );
      final rows = <ActionableDocRowData>[];
      if (res.statusCode == 200 && res.data['data'] != null) {
        final names = namesByEmail;
        for (final e in (res.data['data'] as List)) {
          final json = Map<String, dynamic>.from(e as Map);
          rows.add(docRowFor(
            doctype,
            json,
            (owner) => ownerLabelFor(owner, names),
            onTap: () => Get.toNamed(
              cfg.formRoute,
              arguments: {'name': (json['name'] ?? '').toString(), 'mode': 'view'},
            ),
          ));
        }
      }
      _previewCache[key] = rows;
      // Guard against a chip change landing before this fetch returns.
      if (doctype == selectedActionable.value) previewDocs.assignAll(rows);
    } catch (e) {
      print('Error fetching preview docs: $e');
    } finally {
      if (doctype == selectedActionable.value) isLoadingPreview.value = false;
    }
  }
```

- [ ] **Step 3: Refresh the preview on scope change and after load**

In `setActionableScope`, add a preview refresh after the counts refresh (the preview filter is scope-dependent):

```dart
  void setActionableScope(ActionableScope scope) {
    if (actionableScope.value == scope) return;
    actionableScope.value = scope;
    _storageService.saveDashboardActionableScope(actionableScopeToString(scope));
    fetchActionableCounts();
    fetchPreviewDocs();
  }
```

In `fetchDashboardData`, apply the default selection once counts and todos have landed — change the trailing `await Future.wait([...])` to:

```dart
      await Future.wait([
        _fetchActiveWipJc(),
        fetchUpcomingTodos(),
        fetchActionableCounts(force: true),
      ]);
      _applyDefaultSelection();
```

- [ ] **Step 4: Verify the analyzer and full suite**

Run: `flutter analyze`
Expected: no new errors (`avoid_print` info on the new `print` is consistent with this file's existing convention).

Run: `flutter test`
Expected: no NEW failures beyond the ~24 pre-existing unrelated ones.

> **Do NOT run `flutter analyze` and `flutter test` at the same time in this worktree — they deadlock the Dart build lock on this machine. Run them one after the other.**

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add lib/app/modules/home/home_controller.dart
git commit -m "$(cat <<'EOF'
feat(dashboard): chip selection state and cached document preview fetch

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Screen integration — slider, preview, Tasks cap

**Files:**
- Modify: `lib/app/modules/home/home_screen.dart` (`_buildUpcomingActionable` ~301-349, `_actionableChips` ~351-378)
- Modify: `lib/app/modules/home/widgets/dashboard_todo_card.dart` (`selectUpcomingTodos` default `max`)
- Test: `test/unit/dashboard_todo_card_test.dart` (existing — update)

**Interfaces:**
- Consumes: `DashboardActionableStrip`, `ActionableChipData`, `kActionableDocConfigs` (Tasks 1/2); `ActionableDocPreview` (Task 3); `controller.selectedActionable` / `previewDocs` / `isLoadingPreview` / `selectActionable` / `openActionableList` (Task 5).

- [ ] **Step 1: Write the failing test (Tasks cap 5 → 3)**

In `test/unit/dashboard_todo_card_test.dart`, the ordering test calls `selectUpcomingTodos(todos)` with 4 todos and expects 4 back — it must pass `max: 5` explicitly now that the default is 3. Replace the `selectUpcomingTodos` group's first test and add a default-cap test:

```dart
    test('orders dated todos ascending and puts dateless last', () {
      final todos = [
        _todo(name: 'no-date-1'),
        _todo(name: 'late', date: '2026-08-01'),
        _todo(name: 'soon', date: '2026-07-12'),
        _todo(name: 'no-date-2'),
      ];
      final result = selectUpcomingTodos(todos, max: 5);
      expect(result.map((t) => t.name).toList(),
          ['soon', 'late', 'no-date-1', 'no-date-2']);
    });

    test('defaults to a cap of 3 (the dashboard preview size)', () {
      final todos = List.generate(
          8, (i) => _todo(name: 'td-$i', date: '2026-07-1${i + 1}'));
      expect(selectUpcomingTodos(todos).length, 3);
    });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/unit/dashboard_todo_card_test.dart`
Expected: FAIL — `defaults to a cap of 3` returns 5.

- [ ] **Step 3: Change the default cap**

In `lib/app/modules/home/widgets/dashboard_todo_card.dart`, change the signature and its doc comment:

```dart
/// Orders ToDos for the dashboard: dated tasks first (soonest due date first),
/// dateless tasks after (keeping their incoming order), capped at [max] — three
/// by default, matching the dashboard's 3-document preview.
///
/// The server query orders by `date asc`, but MariaDB sorts NULL/empty dates
/// FIRST in ascending order — this reorder puts them last where they belong.
List<ToDo> selectUpcomingTodos(List<ToDo> todos, {int max = 3}) {
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/unit/dashboard_todo_card_test.dart`
Expected: PASS.

- [ ] **Step 5: Wire the slider + preview into the screen**

Add the import to `home_screen.dart`:

```dart
import 'package:multimax/app/modules/home/widgets/dashboard_actionable_preview.dart';
```

Replace `_buildUpcomingActionable` and `_actionableChips` entirely:

```dart
  // ---------------------------------------------------------------------------
  // Upcoming & actionable — a horizontal DocType chip slider (Draft counts
  // across PO/PR/SE/DN/PS + open ToDos) driving a 3-document preview.
  // ---------------------------------------------------------------------------
  Widget _buildUpcomingActionable(BuildContext context) {
    return Obx(() {
      final chips = _actionableChips(context);
      final loading = controller.isLoadingActionable.value;
      final selected = controller.selectedActionable.value;
      final todos = controller.upcomingTodos;

      // Nothing to show and nothing loading → collapse entirely.
      if (chips.isEmpty && !loading) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            context,
            'Upcoming & actionable',
            trailing: ActionableScopeToggle(
              scope: controller.actionableScope.value,
              onChanged: controller.setActionableScope,
            ),
          ),
          const SizedBox(height: 11),
          DashboardActionableStrip(chips: chips, isLoading: loading),
          if (selected == 'ToDo' && todos.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (var i = 0; i < todos.length; i++) ...[
              if (i > 0) const SizedBox(height: 9),
              DashboardTodoCard(
                todo: todos[i],
                onTap: () => Get.toNamed(
                  AppRoutes.TODO_FORM,
                  arguments: {'name': todos[i].name, 'mode': 'view'},
                ),
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: controller.goToToDo,
                child: const Text('View All'),
              ),
            ),
          ] else if (selected != null && selected != 'ToDo') ...[
            const SizedBox(height: 14),
            ActionableDocPreview(
              rows: controller.previewDocs.toList(),
              isLoading: controller.isLoadingPreview.value,
              onViewAll: () => controller.openActionableList(selected),
            ),
          ],
          const SizedBox(height: 6),
        ],
      );
    });
  }

  /// Chip data in slider order: Tasks first (personal, gated on ToDo access),
  /// then one per accessible document DocType present in [actionableCounts].
  /// A zero count → null onTap, so the chip is muted and cannot be selected.
  List<ActionableChipData> _actionableChips(BuildContext context) {
    final chips = <ActionableChipData>[];
    final selected = controller.selectedActionable.value;

    if (Get.find<PermissionService>().hasAccess('ToDo') == true) {
      final count = controller.openTodoCount.value;
      chips.add(ActionableChipData(
        doctype: 'ToDo',
        label: 'Tasks',
        icon: Icons.check_circle_outline,
        count: count,
        selected: selected == 'ToDo',
        onTap: count == 0 ? null : () => controller.selectActionable('ToDo'),
      ));
    }

    for (final cfg in kActionableDocConfigs) {
      if (!controller.actionableCounts.containsKey(cfg.doctype)) continue;
      final count = controller.actionableCounts[cfg.doctype] ?? 0;
      chips.add(ActionableChipData(
        doctype: cfg.doctype,
        label: cfg.label,
        icon: cfg.icon,
        count: count,
        selected: selected == cfg.doctype,
        onTap: count == 0 ? null : () => controller.selectActionable(cfg.doctype),
      ));
    }
    return chips;
  }
```

- [ ] **Step 6: Verify the analyzer and full suite**

Run: `flutter analyze`
Expected: no new errors/warnings; no dangling references.

Run: `flutter test`
Expected: new preview/strip/filter tests green; no NEW failures beyond the ~24 pre-existing.

> Run analyze and test SEQUENTIALLY — never concurrently in this worktree (Dart build-lock deadlock).

- [ ] **Step 7: Verify on-device (use the `verify` / `run` skill)**

Drive the app and confirm:
1. The strip is one horizontal row that scrolls (never wraps) with six chips using full DocType names + counts; `Tasks` is selected by default and its 3 ToDo cards render with a `View All`.
2. Tapping `Delivery Note` selects it and shows its 3 Draft DNs as `name` + `customer · owner · date`; `View All` opens the DN list showing only Drafts.
3. `Packing Slip` works — it loads without a Frappe `FieldError` (its virtual `status` must never be queried), rows show `delivery_note · owner · date`, and View All opens the PS list filtered to Drafts.
4. A zero-count chip is dim and cannot be selected.
5. Mine ⇄ Everyone changes the counts AND the previewed rows; owner shows in both scopes.
6. Dark mode: chips, rows and skeletons are legible.

- [ ] **Step 8: Commit**

```bash
git branch --show-current
git add lib/app/modules/home/home_screen.dart lib/app/modules/home/widgets/dashboard_todo_card.dart test/unit/dashboard_todo_card_test.dart
git commit -m "$(cat <<'EOF'
feat(dashboard): chip slider selects a DocType and previews 3 documents

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review

**Spec coverage:**
- §2 slider (horizontal, order, full names, counts, states, toggle) → Tasks 1 (configs/labels), 2 (slider/states), 6 (order incl. Tasks, toggle retained).
- §3 selection model (default Tasks, fall-through, none-when-all-zero, not persisted) → Task 1 (`defaultActionableSelection` + tests), Task 5 (`_applyDefaultSelection`).
- §4 preview (3 docs, ordering, row tap, View All, loading, row content table, owner) → Tasks 3 (mapper/widgets), 5 (fetch, `limit: 3`, `creation desc`, form-route tap), 6 (wiring, Tasks cap 3).
- §5 Packing Slip (config, docstatus-not-status, onInit hook) → Tasks 1 and 4.
- §6 data flow (counts unchanged, lazy cached preview, same-filter guarantee, access gate) → Task 5.
- §7 components → Tasks 1-3, 5, 6.
- §8 testing → Tasks 1, 2, 3, 6.

**Deviations from the spec (deliberate, flagged):**
1. **Preview fetches via `ApiProvider.getDocumentList`, not the per-DocType providers** — `PurchaseOrderProvider`/`PurchaseReceiptProvider` are not registered in `HomeBinding`, so `Get.find` would throw. This also fetches only the 4 rendered fields.
2. **`PurchaseOrderProvider` is NOT modified** — the spec added `'owner'` to it only so the preview could use it; with (1) the preview requests `owner` itself, so the change is unnecessary (YAGNI).
3. **`DashboardActionableStrip` does not take `selectedDoctype`/`onSelect`** — selection rides on `ActionableChipData.selected`/`onTap` (as the shipped chip already carries `onTap`), avoiding two sources of truth.

**Placeholder scan:** none — every code step contains complete code; no TBD/TODO/"handle edge cases".

**Type consistency:** `ActionableDocConfig` (named params incl. `formRoute`/`previewFields`), `ActionableChipData.selected`, `defaultActionableSelection`, `ActionableDocRowData{name,subtitle,onTap}`, `docRowFor(doctype, json, ownerLabel, {onTap})`, `ownerLabelFor(email, namesByEmail)`, `ActionableDocPreview{rows,isLoading,onViewAll}`, `selectedActionable`/`previewDocs`/`isLoadingPreview`/`selectActionable`/`fetchPreviewDocs` are used identically across Tasks 1→6.

## Out of Scope
- Changing the actionable definition (still Draft only), the `showTasksFirst` persona rule, owner on the Tasks card, persisting the selected chip, and any list-screen change beyond the PS `onInit` hook.
- The version bump + release (user-driven; **MINOR** per Global Constraints).
