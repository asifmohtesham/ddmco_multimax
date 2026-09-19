# Sales Order DocType Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Sales Order module under Selling (list, Draft form + item sheet, Hold/Resume/Close/Re-open, Make → Delivery Note, and link-ups) that mirrors the Purchase Order module and follows ERPNext v15 behaviour.

**Architecture:** Mirror `lib/app/modules/purchase_order/**` file for file, under `lib/app/modules/selling/sales_order/`. Every business rule lives in one pure-Dart file, `sales_order_logic.dart`, which the unit tests target. Controllers call a thin `SalesOrderProvider` over `ApiProvider`. The server computes all money, statuses and dates; the client only posts editable fields. Make → DN maps and inserts the DN on the server, then opens our existing DN form by name.

**Tech Stack:** Flutter (pinned 3.44.4 in CI), GetX 4.7.2, Dio, flutter_test. ERPNext 15.121.1 / Frappe 15.120.1 on `erp.multimax.cloud`.

**Spec:** `docs/superpowers/specs/2026-09-19-sales-order-doctype-design.md`. Read it first; it holds every verified v15 fact this plan argues from.

## Global Constraints

- Branch `claude/sales-order-doctype` cut from `origin/release/play-store` @ 9074fe26 (2.21.4+68). Re-check `git branch --show-current` before every commit, tag and push.
- Release is **MINOR** (new module), so 2.21.4+68 → **2.22.0+69** unless a concurrent release took it. Fetch tags first.
- Never compute money client-side for persistence. `rate` comes from `erpnext.stock.get_item_details.get_item_details`; totals, VAT columns (`tax_amount`, `total_amount`), status and header `delivery_date` come back from the server after save. The sheet's `qty × rate` is labelled an estimate.
- Row `rate` is always editable (v15). `price_list_rate` is shown read-only and never sent.
- Permission gating fails closed. `null` or unresolved counts as denied. Submit, cancel and status changes use the per-doc `ApiProvider.hasDocPermission(doctype, name, ptype)`, never `PermissionService.hasAccess(permType: 'submit'|'cancel')`: that service probes any perm type other than create/write with a read-level `get_list`.
- `update_status` needs **submit** permission. Hold / Resume / Close / Re-open send `'On Hold'` / `'Draft'` / `'Closed'` / `'Draft'`. Hold first posts a required reason with `frappe.desk.form.utils.add_comment`.
- Header `delivery_date` rule (Sales, not skip_delivery_note): header or any row must have a date; every row date must be ≥ `transaction_date`. Rows without a date inherit it on the server.
- UI conventions (CLAUDE.md): AppColors x700 (light) / x300 (dark) ink ramp, never hard-coded white or grey; `Scrollbar` with a shared controller, nav-bar bottom padding and an "End of list" marker on lists; a `ListTile` inside a coloured `Container` needs a `Material(color: Colors.transparent)` wrapper, and never `dart format` those files. Rx reads that feed `headerSliverBuilder` are hoisted into the outer `Obx`. Never put an outer `Obx` around a widget that reads no Rx. Never use an error Rx as the only rebuild trigger. Reactive `DocTypeFormHeader.extraActions` carry their own `Obx`.
- Do not depend on the unreleased metadata-driven form renderer. Hand-build like PO.
- `flutter analyze` and `flutter test` run **sequentially, never concurrently** (they deadlock). A hung `flutter test` can lock the machine, so run the targeted test file first and the full suite once per task at most.
- Commit messages end with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.

## File map

| File | Status | Responsibility |
|---|---|---|
| `lib/app/modules/selling/sales_order/sales_order_logic.dart` | create | Pure rules: allowed actions, DN eligibility, payload, dirty diff, validation, item-details parsing, status-filter label, progress |
| `test/unit/sales_order_logic_test.dart` | create | Unit tests for the above |
| `lib/app/data/models/sales_order_model.dart` | create | `SalesOrder`, `SalesOrderItem` (fromJson + copyWith) |
| `test/unit/sales_order_model_test.dart` | create | fromJson parsing |
| `lib/app/data/providers/sales_order_provider.dart` | create | HTTP calls |
| `lib/app/modules/global_widgets/link_search_sheet.dart` | create | Shared debounced link picker (extracted from two private copies) |
| `lib/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_item_rate_filter_sheet.dart` | modify | Use shared `LinkSearchSheet`, delete private copy |
| `lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_filter_sheet.dart` | modify | Same; fixes its missing `Material(transparent)` |
| `lib/app/modules/global_widgets/status_pill.dart` | modify | Orange for `To Deliver and Bill` / `To Deliver` |
| `lib/app/modules/selling/sales_order/sales_order_binding.dart`, `sales_order_controller.dart`, `sales_order_screen.dart`, `widgets/sales_order_filter_bottom_sheet.dart` | create | List |
| `lib/app/modules/selling/sales_order/form/sales_order_form_binding.dart`, `sales_order_form_controller.dart`, `sales_order_form_screen.dart` | create | Form |
| `lib/app/modules/selling/sales_order/form/sales_order_item_form_controller.dart`, `form/widgets/sales_order_item_form_sheet.dart` | create | Item sheet |
| `lib/app/modules/selling/sales_order/form/widgets/hold_reason_sheet.dart` | create | Required hold-reason input |
| `lib/app/shared/item_card/item_card_data.dart` | modify | `ItemCardData.fromSalesOrderItem` |
| `lib/app/data/utils/app_constants.dart` | modify | `kSoItemSheetTag` |
| `lib/app/data/routes/app_routes.dart`, `app_pages.dart` | modify | `SALES_ORDER`, `SALES_ORDER_FORM` |
| `lib/app/modules/global_widgets/app_nav_drawer.dart` | modify | Selling › Sales Order above Pricing |
| `lib/app/data/constants/permission_entries.dart` | modify | `kSellingPermissions` read/create/write |
| `lib/app/data/constants/global_search_targets.dart` | modify | SO target |
| `lib/app/modules/home/widgets/dashboard_actionable_strip.dart`, `dashboard_actionable_preview.dart` | modify | SO chip + preview row |
| `lib/app/data/services/digest_service.dart`, `storage_service.dart` | modify | Draft SO digest entry + default-enabled key |
| `lib/app/modules/stock/reports/stock_balance/stock_balance_sheets.dart` | modify | Reservation row → SO form |
| `test/unit/actionable_filters_test.dart`, `dashboard_actionable_preview_test.dart`, `storage_digest_prefs_test.dart` | modify | New SO expectations |
| `test/widget/stock_balance_reservation_tap_test.dart` | create | Reservation row routes to SO form |

---

### Task 0: Baseline

**Files:** none (records results in the scratchpad).

- [ ] **Step 1: Confirm branch and base**

```bash
git branch --show-current            # claude/sales-order-doctype
git merge-base HEAD origin/release/play-store   # 9074fe26…
```

- [ ] **Step 2: Record the pre-change suite baseline** (sequential; nothing else running)

```bash
flutter analyze > "$SCRATCH/analyze_baseline.txt" 2>&1; tail -3 "$SCRATCH/analyze_baseline.txt"
flutter test --reporter expanded > "$SCRATCH/test_baseline.txt" 2>&1; tail -5 "$SCRATCH/test_baseline.txt"
grep -E "^\s*[0-9:]+ \+[0-9]+ ?-?[0-9]*: .* \[E\]" "$SCRATCH/test_baseline.txt" | sed 's/^.*: //' | sort -u > "$SCRATCH/test_baseline_failures.txt"
```

Expected: analyze issue count and the failing-test list recorded (memory: roughly 24 pre-existing failures). `$SCRATCH` = the session scratchpad dir. No commit.

---

### Task 1: Pure logic + model (TDD)

**Files:**
- Create: `lib/app/data/models/sales_order_model.dart`
- Create: `lib/app/modules/selling/sales_order/sales_order_logic.dart`
- Test: `test/unit/sales_order_model_test.dart`, `test/unit/sales_order_logic_test.dart`

**Interfaces:**
- Produces:
  - `class SalesOrder` (fields below), `SalesOrder.fromJson(Map<String,dynamic>)`, `SalesOrder copyWith({...})`, `static SalesOrder blank({required String transactionDate, required String company})`
  - `class SalesOrderItem` (fields below), `SalesOrderItem.fromJson`, `copyWith`, `bool get isLocal`
  - `enum SoAction { save, submit, cancel, hold, resume, close, reopen, makeDn }`
  - `class SoPerms { final bool? write, submit, cancel, createDn; }`
  - `Set<SoAction> allowedActions(SalesOrder so, SoPerms p)`
  - `bool canMakeDeliveryNote(SalesOrder so)`
  - `Map<String, dynamic> buildPayload(SalesOrder so)`
  - `bool isSoDirty(SalesOrder original, SalesOrder current)`
  - `Map<String, String> validateRow(SalesOrderItem row, String transactionDate)`
  - `Map<String, String> validateOrder(SalesOrder so)`
  - `ItemDetails parseItemDetails(dynamic message)` + `class ItemDetails`
  - `String statusFilterLabel(dynamic value)`
  - `double progressFraction(double percent)`
  - `const kSoOpenToDeliverStatuses = ['Draft', 'To Deliver and Bill', 'To Deliver']`

- [ ] **Step 1: Write the failing model test** at `test/unit/sales_order_model_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/sales_order_model.dart';

void main() {
  test('fromJson parses header, progress and rows', () {
    final so = SalesOrder.fromJson({
      'name': 'SAL-ORD-2026-00012',
      'customer': 'C1',
      'customer_name': 'Cust One',
      'transaction_date': '2026-09-19',
      'delivery_date': '2026-09-25',
      'order_type': 'Sales',
      'company': 'Multimax',
      'currency': 'AED',
      'selling_price_list': 'Standard Selling',
      'set_warehouse': null,
      'po_no': 'PO-9',
      'skip_delivery_note': 0,
      'status': 'To Deliver and Bill',
      'docstatus': 1,
      'per_delivered': 40,
      'per_billed': 0.0,
      'total_qty': 5,
      'grand_total': 105,
      'rounded_total': 105,
      'total_taxes_and_charges': 5,
      'owner': 'a@b.com',
      'modified': '2026-09-19 10:00:00',
      'items': [
        {
          'name': 'row1', 'item_code': 'I1', 'item_name': 'Item 1',
          'qty': 5, 'uom': 'Nos', 'stock_uom': 'Nos', 'conversion_factor': 1,
          'rate': 20, 'price_list_rate': 20, 'amount': 100,
          'delivery_date': '2026-09-25', 'warehouse': 'Stores - M',
          'delivered_qty': 2, 'delivered_by_supplier': 0,
          'tax_amount': 5, 'total_amount': 105,
        }
      ],
    });
    expect(so.docstatus, 1);
    expect(so.perDelivered, 40.0);
    expect(so.setWarehouse, isNull);
    expect(so.skipDeliveryNote, isFalse);
    expect(so.items.single.deliveredQty, 2.0);
    expect(so.items.single.deliveredBySupplier, isFalse);
    expect(so.items.single.totalAmount, 105.0);
    expect(so.items.single.isLocal, isFalse);
  });

  test('missing fields fall back to safe defaults', () {
    final so = SalesOrder.fromJson({'name': 'X'});
    expect(so.status, 'Draft');
    expect(so.orderType, 'Sales');
    expect(so.items, isEmpty);
    expect(so.currency, 'AED');
  });

  test('local rows are recognised', () {
    const row = SalesOrderItem(name: 'local_1', itemCode: 'I', itemName: 'I', qty: 1);
    expect(row.isLocal, isTrue);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/unit/sales_order_model_test.dart`
Expected: FAIL. `sales_order_model.dart` doesn't exist yet.

- [ ] **Step 3: Write the model** at `lib/app/data/models/sales_order_model.dart`

```dart
/// Sales Order + rows. Parsing only: the payload the app posts is built by
/// `buildPayload` in sales_order_logic.dart so read-only / server-computed
/// fields (totals, VAT custom columns, status) can never leak into a save.
double _d(dynamic v) => (v as num?)?.toDouble() ?? 0.0;
String? _s(dynamic v) =>
    (v == null || v.toString().isEmpty) ? null : v.toString();
bool _b(dynamic v) => v == true || v == 1;

class SalesOrder {
  final String name;
  final String customer;
  final String customerName;
  final String transactionDate;
  final String? deliveryDate;
  final String orderType;
  final String? company;
  final String currency;
  final String? sellingPriceList;
  final String? setWarehouse;
  final String? poNo;
  final bool skipDeliveryNote;
  final String status;
  final int docstatus;
  final double perDelivered;
  final double perBilled;
  final double totalQty;
  final double totalTaxesAndCharges;
  final double grandTotal;
  final double roundedTotal;
  final String owner;
  final String modified;
  final List<SalesOrderItem> items;

  const SalesOrder({
    required this.name,
    this.customer = '',
    this.customerName = '',
    this.transactionDate = '',
    this.deliveryDate,
    this.orderType = 'Sales',
    this.company,
    this.currency = 'AED',
    this.sellingPriceList,
    this.setWarehouse,
    this.poNo,
    this.skipDeliveryNote = false,
    this.status = 'Draft',
    this.docstatus = 0,
    this.perDelivered = 0,
    this.perBilled = 0,
    this.totalQty = 0,
    this.totalTaxesAndCharges = 0,
    this.grandTotal = 0,
    this.roundedTotal = 0,
    this.owner = '',
    this.modified = '',
    this.items = const [],
  });

  static SalesOrder blank(
          {required String transactionDate, required String company}) =>
      SalesOrder(
        name: 'New Sales Order',
        transactionDate: transactionDate,
        company: company,
        status: 'Not Saved',
      );

  factory SalesOrder.fromJson(Map<String, dynamic> j) => SalesOrder(
        name: (j['name'] ?? '').toString(),
        customer: (j['customer'] ?? '').toString(),
        customerName: (j['customer_name'] ?? '').toString(),
        transactionDate: (j['transaction_date'] ?? '').toString(),
        deliveryDate: _s(j['delivery_date']),
        orderType: _s(j['order_type']) ?? 'Sales',
        company: _s(j['company']),
        currency: _s(j['currency']) ?? 'AED',
        sellingPriceList: _s(j['selling_price_list']),
        setWarehouse: _s(j['set_warehouse']),
        poNo: _s(j['po_no']),
        skipDeliveryNote: _b(j['skip_delivery_note']),
        status: _s(j['status']) ?? 'Draft',
        docstatus: (j['docstatus'] as num?)?.toInt() ?? 0,
        perDelivered: _d(j['per_delivered']),
        perBilled: _d(j['per_billed']),
        totalQty: _d(j['total_qty']),
        totalTaxesAndCharges: _d(j['total_taxes_and_charges']),
        grandTotal: _d(j['grand_total']),
        roundedTotal: _d(j['rounded_total']),
        owner: (j['owner'] ?? '').toString(),
        modified: (j['modified'] ?? '').toString(),
        items: ((j['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => SalesOrderItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  SalesOrder copyWith({
    String? customer,
    String? customerName,
    String? transactionDate,
    String? deliveryDate,
    String? orderType,
    String? company,
    String? currency,
    String? sellingPriceList,
    String? setWarehouse,
    String? poNo,
    String? status,
    List<SalesOrderItem>? items,
  }) =>
      SalesOrder(
        name: name,
        customer: customer ?? this.customer,
        customerName: customerName ?? this.customerName,
        transactionDate: transactionDate ?? this.transactionDate,
        deliveryDate: deliveryDate ?? this.deliveryDate,
        orderType: orderType ?? this.orderType,
        company: company ?? this.company,
        currency: currency ?? this.currency,
        sellingPriceList: sellingPriceList ?? this.sellingPriceList,
        setWarehouse: setWarehouse ?? this.setWarehouse,
        poNo: poNo ?? this.poNo,
        skipDeliveryNote: skipDeliveryNote,
        status: status ?? this.status,
        docstatus: docstatus,
        perDelivered: perDelivered,
        perBilled: perBilled,
        totalQty: totalQty,
        totalTaxesAndCharges: totalTaxesAndCharges,
        grandTotal: grandTotal,
        roundedTotal: roundedTotal,
        owner: owner,
        modified: modified,
        items: items ?? this.items,
      );
}

class SalesOrderItem {
  final String? name;
  final String itemCode;
  final String itemName;
  final double qty;
  final String? uom;
  final String? stockUom;
  final double conversionFactor;
  final double rate;
  final double priceListRate;
  final double amount;
  final String? deliveryDate;
  final String? warehouse;
  final double deliveredQty;
  final bool deliveredBySupplier;
  final double taxAmount;   // custom UAE VAT column (read-only)
  final double totalAmount; // custom UAE VAT column (read-only)

  const SalesOrderItem({
    this.name,
    required this.itemCode,
    required this.itemName,
    required this.qty,
    this.uom,
    this.stockUom,
    this.conversionFactor = 1,
    this.rate = 0,
    this.priceListRate = 0,
    this.amount = 0,
    this.deliveryDate,
    this.warehouse,
    this.deliveredQty = 0,
    this.deliveredBySupplier = false,
    this.taxAmount = 0,
    this.totalAmount = 0,
  });

  /// Rows added in the app carry a `local_<ms>` id until the first save.
  bool get isLocal => name?.startsWith('local_') ?? true;

  factory SalesOrderItem.fromJson(Map<String, dynamic> j) => SalesOrderItem(
        name: _s(j['name']),
        itemCode: (j['item_code'] ?? '').toString(),
        itemName: (j['item_name'] ?? '').toString(),
        qty: _d(j['qty']),
        uom: _s(j['uom']),
        stockUom: _s(j['stock_uom']),
        conversionFactor:
            j['conversion_factor'] == null ? 1 : _d(j['conversion_factor']),
        rate: _d(j['rate']),
        priceListRate: _d(j['price_list_rate']),
        amount: _d(j['amount']),
        deliveryDate: _s(j['delivery_date']),
        warehouse: _s(j['warehouse']),
        deliveredQty: _d(j['delivered_qty']),
        deliveredBySupplier: _b(j['delivered_by_supplier']),
        taxAmount: _d(j['tax_amount']),
        totalAmount: _d(j['total_amount']),
      );

  SalesOrderItem copyWith({
    double? qty,
    String? uom,
    double? conversionFactor,
    double? rate,
    double? priceListRate,
    String? deliveryDate,
    String? warehouse,
  }) =>
      SalesOrderItem(
        name: name,
        itemCode: itemCode,
        itemName: itemName,
        qty: qty ?? this.qty,
        uom: uom ?? this.uom,
        stockUom: stockUom,
        conversionFactor: conversionFactor ?? this.conversionFactor,
        rate: rate ?? this.rate,
        priceListRate: priceListRate ?? this.priceListRate,
        amount: (qty ?? this.qty) * (rate ?? this.rate), // provisional; server recomputes
        deliveryDate: deliveryDate ?? this.deliveryDate,
        warehouse: warehouse ?? this.warehouse,
        deliveredQty: deliveredQty,
        deliveredBySupplier: deliveredBySupplier,
        taxAmount: taxAmount,
        totalAmount: totalAmount,
      );
}
```

Note the `isLocal` edge: a row with `name == null` counts as local, so it posts without a `name` and the server assigns one.

- [ ] **Step 4: Run the model test to verify it passes**

Run: `flutter test test/unit/sales_order_model_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Write the failing logic test** at `test/unit/sales_order_logic_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/sales_order_model.dart';
import 'package:multimax/app/modules/selling/sales_order/sales_order_logic.dart';

SalesOrder so({
  int docstatus = 1,
  String status = 'To Deliver and Bill',
  double perDelivered = 0,
  double perBilled = 0,
  bool skipDn = false,
  List<SalesOrderItem>? items,
}) =>
    SalesOrder(
      name: 'SAL-ORD-2026-00001',
      customer: 'C1',
      transactionDate: '2026-09-19',
      company: 'Multimax',
      sellingPriceList: 'Standard Selling',
      docstatus: docstatus,
      status: status,
      perDelivered: perDelivered,
      perBilled: perBilled,
      skipDeliveryNote: skipDn,
      items: items ??
          const [SalesOrderItem(name: 'r1', itemCode: 'I1', itemName: 'I1', qty: 5)],
    );

const all = SoPerms(write: true, submit: true, cancel: true, createDn: true);

void main() {
  group('allowedActions', () {
    test('unresolved perms fail closed (empty set) on every state', () {
      const none = SoPerms();
      expect(allowedActions(so(docstatus: 0, status: 'Draft'), none), isEmpty);
      expect(allowedActions(so(), none), isEmpty);
      expect(allowedActions(so(status: 'On Hold'), none), isEmpty);
      expect(allowedActions(so(status: 'Closed'), none), isEmpty);
    });

    test('draft: save needs write, submit needs submit', () {
      final d = so(docstatus: 0, status: 'Draft');
      expect(allowedActions(d, all), {SoAction.save, SoAction.submit});
      expect(allowedActions(d, const SoPerms(write: true, submit: false)),
          {SoAction.save});
    });

    test('open submitted order: hold + close + cancel + makeDn', () {
      expect(allowedActions(so(), all), {
        SoAction.hold, SoAction.close, SoAction.cancel, SoAction.makeDn,
      });
    });

    test('status changes need submit, not write (update_status checks submit)', () {
      final a = allowedActions(
          so(), const SoPerms(write: true, submit: false, cancel: false, createDn: false));
      expect(a, isEmpty);
    });

    test('on hold: resume + close, no hold, no makeDn', () {
      expect(allowedActions(so(status: 'On Hold'), all),
          {SoAction.resume, SoAction.close, SoAction.cancel});
    });

    test('closed: reopen only (+cancel)', () {
      expect(allowedActions(so(status: 'Closed'), all),
          {SoAction.reopen, SoAction.cancel});
    });

    test('fully delivered and billed: no hold/close', () {
      final a = allowedActions(
          so(status: 'Completed', perDelivered: 100, perBilled: 100), all);
      expect(a.intersection({SoAction.hold, SoAction.close}), isEmpty);
    });

    test('cancelled: nothing', () {
      expect(allowedActions(so(docstatus: 2, status: 'Cancelled'), all), isEmpty);
    });
  });

  group('canMakeDeliveryNote', () {
    test('needs an undelivered, non-drop-ship row', () {
      expect(canMakeDeliveryNote(so()), isTrue);
      expect(
          canMakeDeliveryNote(so(items: const [
            SalesOrderItem(itemCode: 'I', itemName: 'I', qty: 5, deliveredQty: 5),
          ])),
          isFalse);
      expect(
          canMakeDeliveryNote(so(items: const [
            SalesOrderItem(itemCode: 'I', itemName: 'I', qty: 5, deliveredBySupplier: true),
          ])),
          isFalse);
    });

    test('blocked by skip_delivery_note, On Hold, Closed, draft', () {
      expect(canMakeDeliveryNote(so(skipDn: true)), isFalse);
      expect(canMakeDeliveryNote(so(status: 'On Hold')), isFalse);
      expect(canMakeDeliveryNote(so(status: 'Closed')), isFalse);
      expect(canMakeDeliveryNote(so(docstatus: 0, status: 'Draft')), isFalse);
    });
  });

  group('buildPayload', () {
    test('editable fields only; no totals, status or VAT columns', () {
      final p = buildPayload(so(docstatus: 0, status: 'Draft', items: const [
        SalesOrderItem(
          name: 'r1', itemCode: 'I1', itemName: 'I1', qty: 2, uom: 'Nos',
          conversionFactor: 1, rate: 10, priceListRate: 12, amount: 20,
          taxAmount: 1, totalAmount: 21, deliveryDate: '2026-09-25',
        ),
      ]));
      expect(p.keys.toSet(), {
        'customer', 'transaction_date', 'order_type', 'company',
        'selling_price_list', 'delivery_date', 'set_warehouse', 'po_no', 'items',
      });
      final row = (p['items'] as List).single as Map;
      expect(row, {
        'name': 'r1', 'item_code': 'I1', 'qty': 2.0, 'uom': 'Nos',
        'conversion_factor': 1.0, 'rate': 10.0,
        'delivery_date': '2026-09-25', 'warehouse': '',
      });
    });

    test('local row ids are stripped; cleared optionals are sent as empty', () {
      final p = buildPayload(so(docstatus: 0, items: const [
        SalesOrderItem(name: 'local_123', itemCode: 'I', itemName: 'I', qty: 1),
      ]));
      expect(((p['items'] as List).single as Map).containsKey('name'), isFalse);
      expect(p['po_no'], '');
      expect(p['set_warehouse'], '');
      expect(p['delivery_date'], '');
    });

    test('empty company / price list are omitted so the server fills them', () {
      final p = buildPayload(const SalesOrder(name: 'x', customer: 'C'));
      expect(p.containsKey('company'), isFalse);
      expect(p.containsKey('selling_price_list'), isFalse);
    });
  });

  group('isSoDirty', () {
    test('equal payloads are clean; an edited qty or header is dirty', () {
      final a = so(docstatus: 0);
      expect(isSoDirty(a, a.copyWith()), isFalse);
      expect(isSoDirty(a, a.copyWith(poNo: 'X')), isTrue);
      expect(
          isSoDirty(a, a.copyWith(items: [a.items.first.copyWith(qty: 9)])),
          isTrue);
    });

    test('server-only fields do not make it dirty', () {
      final a = so(docstatus: 0);
      final b = SalesOrder.fromJson({
        'name': a.name, 'customer': 'C1', 'transaction_date': '2026-09-19',
        'company': 'Multimax', 'selling_price_list': 'Standard Selling',
        'grand_total': 999, 'status': 'Draft',
        'items': [{'name': 'r1', 'item_code': 'I1', 'item_name': 'I1', 'qty': 5, 'tax_amount': 3}],
      });
      expect(isSoDirty(a, b), isFalse);
    });
  });

  group('validateRow', () {
    test('qty > 0 and item required', () {
      expect(
          validateRow(const SalesOrderItem(itemCode: '', itemName: '', qty: 0), '2026-09-19')
              .keys,
          containsAll(['item_code', 'qty']));
    });
    test('delivery date may be blank but not before the order date', () {
      const ok = SalesOrderItem(itemCode: 'I', itemName: 'I', qty: 1);
      expect(validateRow(ok, '2026-09-19'), isEmpty);
      expect(
          validateRow(ok.copyWith(deliveryDate: '2026-09-18'), '2026-09-19')
              .keys,
          ['delivery_date']);
      expect(validateRow(ok.copyWith(deliveryDate: '2026-09-19'), '2026-09-19'),
          isEmpty);
    });
  });

  group('validateOrder', () {
    test('customer and at least one item required', () {
      final e = validateOrder(const SalesOrder(name: 'x', transactionDate: '2026-09-19'));
      expect(e.keys, containsAll(['customer', 'items']));
    });
    test('Sales order needs a delivery date on header or any row', () {
      final noDate = so(docstatus: 0);
      expect(validateOrder(noDate).keys, contains('delivery_date'));
      expect(validateOrder(noDate.copyWith(deliveryDate: '2026-09-30')), isEmpty);
      expect(
          validateOrder(noDate.copyWith(items: [
            noDate.items.first.copyWith(deliveryDate: '2026-09-30'),
          ])),
          isEmpty);
    });
    test('Shopping Cart and skip_delivery_note need no date', () {
      expect(validateOrder(so(docstatus: 0).copyWith(orderType: 'Shopping Cart')),
          isEmpty);
      expect(validateOrder(so(docstatus: 0, skipDn: true)), isEmpty);
    });
    test('header date before order date is rejected', () {
      expect(
          validateOrder(so(docstatus: 0).copyWith(deliveryDate: '2026-09-01')).keys,
          contains('delivery_date'));
    });
  });

  group('parseItemDetails', () {
    test('maps server keys and tolerates missing ones', () {
      final d = parseItemDetails({
        'item_name': 'Widget', 'uom': 'Box', 'stock_uom': 'Nos',
        'conversion_factor': 12, 'price_list_rate': 50, 'rate': 45,
        'warehouse': 'Stores - M',
      });
      expect(d.itemName, 'Widget');
      expect(d.conversionFactor, 12.0);
      expect(d.rate, 45.0);
      expect(d.priceListRate, 50.0);
      final empty = parseItemDetails(null);
      expect(empty.rate, 0.0);
      expect(empty.conversionFactor, 1.0);
    });
  });

  group('statusFilterLabel / progressFraction', () {
    test('string and in-list filters', () {
      expect(statusFilterLabel('Draft'), 'Draft');
      expect(statusFilterLabel(['in', kSoOpenToDeliverStatuses]),
          'Draft, To Deliver and Bill, To Deliver');
    });
    test('progress is clamped to 0..1', () {
      expect(progressFraction(40), 0.4);
      expect(progressFraction(-5), 0.0);
      expect(progressFraction(130), 1.0);
    });
  });
}
```

- [ ] **Step 6: Run it to verify it fails**

Run: `flutter test test/unit/sales_order_logic_test.dart`
Expected: FAIL. `sales_order_logic.dart` doesn't exist yet.

- [ ] **Step 7: Write the logic** at `lib/app/modules/selling/sales_order/sales_order_logic.dart`

```dart
import 'dart:convert';

import 'package:multimax/app/data/models/sales_order_model.dart';

/// Pure Sales Order rules — no Flutter/GetX, every branch unit-tested.
/// Each rule cites the ERPNext v15 behaviour it mirrors; the verified facts
/// live in docs/superpowers/specs/2026-09-19-sales-order-doctype-design.md.

/// Statuses the dashboard chip / digest treat as "needs action".
const kSoOpenToDeliverStatuses = ['Draft', 'To Deliver and Bill', 'To Deliver'];

enum SoAction { save, submit, cancel, hold, resume, close, reopen, makeDn }

/// Resolved permissions. `null` = still loading / unknown → treated as denied.
class SoPerms {
  final bool? write;
  final bool? submit;
  final bool? cancel;
  final bool? createDn;
  const SoPerms({this.write, this.submit, this.cancel, this.createDn});
}

/// Mirrors v15 `sales_order.js` refresh(): status buttons need `submit`
/// (the whitelisted `update_status` calls has_permission(..., "submit")).
Set<SoAction> allowedActions(SalesOrder so, SoPerms p) {
  final out = <SoAction>{};
  if (so.docstatus == 0) {
    if (p.write == true) out.add(SoAction.save);
    if (p.submit == true) out.add(SoAction.submit);
    return out;
  }
  if (so.docstatus != 1) return out;

  if (p.cancel == true) out.add(SoAction.cancel);
  final notDone = so.perDelivered < 100 || so.perBilled < 100;
  if (p.submit == true) {
    switch (so.status) {
      case 'On Hold':
        out.add(SoAction.resume);
        if (notDone) out.add(SoAction.close);
      case 'Closed':
        out.add(SoAction.reopen);
      default:
        if (notDone) out.addAll({SoAction.hold, SoAction.close});
    }
  }
  if (p.createDn == true && canMakeDeliveryNote(so)) out.add(SoAction.makeDn);
  return out;
}

/// v15: status ∉ {Closed, On Hold}, not skip_delivery_note, and some row with
/// `delivered_by_supplier == 0 && qty > delivered_qty`.
bool canMakeDeliveryNote(SalesOrder so) =>
    so.docstatus == 1 &&
    so.status != 'Closed' &&
    so.status != 'On Hold' &&
    !so.skipDeliveryNote &&
    so.items.any((i) => !i.deliveredBySupplier && i.qty > i.deliveredQty);

/// The only body the app ever POSTs/PUTs. Optional user-editable fields are
/// always sent ('' when cleared) so a PUT can clear them; company / price list
/// are omitted when unknown so the server's set_missing_values fills them.
Map<String, dynamic> buildPayload(SalesOrder so) {
  final m = <String, dynamic>{
    'customer': so.customer,
    'transaction_date': so.transactionDate,
    'order_type': so.orderType,
    'delivery_date': so.deliveryDate ?? '',
    'set_warehouse': so.setWarehouse ?? '',
    'po_no': so.poNo ?? '',
    'items': so.items.map(_rowPayload).toList(),
  };
  if ((so.company ?? '').isNotEmpty) m['company'] = so.company;
  if ((so.sellingPriceList ?? '').isNotEmpty) {
    m['selling_price_list'] = so.sellingPriceList;
  }
  return m;
}

Map<String, dynamic> _rowPayload(SalesOrderItem i) => {
      if (!i.isLocal) 'name': i.name,
      'item_code': i.itemCode,
      'qty': i.qty,
      'uom': i.uom,
      'conversion_factor': i.conversionFactor,
      'rate': i.rate,
      'delivery_date': i.deliveryDate ?? '',
      'warehouse': i.warehouse ?? '',
    };

/// Dirty = the posted payloads differ (same JSON-compare approach as PO).
bool isSoDirty(SalesOrder original, SalesOrder current) =>
    jsonEncode(buildPayload(original)) != jsonEncode(buildPayload(current));

bool _before(String a, String b) {
  final da = DateTime.tryParse(a), db = DateTime.tryParse(b);
  return da != null && db != null && da.isBefore(db);
}

Map<String, String> validateRow(SalesOrderItem row, String transactionDate) {
  final e = <String, String>{};
  if (row.itemCode.isEmpty) e['item_code'] = 'Item is required';
  if (row.qty <= 0) e['qty'] = 'Quantity must be greater than 0';
  final d = row.deliveryDate ?? '';
  if (d.isNotEmpty && _before(d, transactionDate)) {
    // v15 server text, so client and server errors read the same.
    e['delivery_date'] = 'Expected Delivery Date should be after Sales Order Date';
  }
  return e;
}

/// Header-level checks mirroring v15 validate + validate_delivery_date.
Map<String, String> validateOrder(SalesOrder so) {
  final e = <String, String>{};
  if (so.customer.isEmpty) e['customer'] = 'Customer is required';
  if (so.items.isEmpty) e['items'] = 'Add at least one item';
  final needsDate = so.orderType == 'Sales' && !so.skipDeliveryNote;
  final header = so.deliveryDate ?? '';
  final anyRow = so.items.any((i) => (i.deliveryDate ?? '').isNotEmpty);
  if (needsDate && header.isEmpty && !anyRow) {
    e['delivery_date'] = 'Please enter Delivery Date';
  } else if (header.isNotEmpty && _before(header, so.transactionDate)) {
    e['delivery_date'] = 'Expected Delivery Date should be after Sales Order Date';
  }
  return e;
}

/// Typed view of `get_item_details` → message.
class ItemDetails {
  final String itemName;
  final String? uom;
  final String? stockUom;
  final double conversionFactor;
  final double priceListRate;
  final double rate;
  final String? warehouse;
  const ItemDetails({
    this.itemName = '',
    this.uom,
    this.stockUom,
    this.conversionFactor = 1,
    this.priceListRate = 0,
    this.rate = 0,
    this.warehouse,
  });
}

ItemDetails parseItemDetails(dynamic message) {
  if (message is! Map) return const ItemDetails();
  double d(String k, double fb) => (message[k] as num?)?.toDouble() ?? fb;
  String? s(String k) {
    final v = message[k];
    return (v == null || v.toString().isEmpty) ? null : v.toString();
  }

  return ItemDetails(
    itemName: s('item_name') ?? '',
    uom: s('uom'),
    stockUom: s('stock_uom'),
    conversionFactor: d('conversion_factor', 1),
    priceListRate: d('price_list_rate', 0),
    rate: d('rate', 0),
    warehouse: s('warehouse'),
  );
}

/// Chip text for a `status` filter: `'Draft'` or `['in', [...]]`.
String statusFilterLabel(dynamic value) {
  if (value is List && value.length == 2 && value[1] is List) {
    return (value[1] as List).join(', ');
  }
  return value.toString();
}

double progressFraction(double percent) => (percent / 100).clamp(0.0, 1.0);
```

- [ ] **Step 8: Run both tests to verify they pass**

Run: `flutter test test/unit/sales_order_model_test.dart test/unit/sales_order_logic_test.dart`
Expected: PASS (all).

- [ ] **Step 9: Commit**

```bash
git branch --show-current   # claude/sales-order-doctype
git add lib/app/data/models/sales_order_model.dart lib/app/modules/selling/sales_order/sales_order_logic.dart test/unit/sales_order_model_test.dart test/unit/sales_order_logic_test.dart
git commit -m "feat(sales-order): pure model and v15 rules with tests

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Provider + shared LinkSearchSheet + StatusPill tones

**Files:**
- Create: `lib/app/data/providers/sales_order_provider.dart`
- Create: `lib/app/modules/global_widgets/link_search_sheet.dart`
- Modify: `lib/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_item_rate_filter_sheet.dart` (delete `_LinkSearchSheet` + state class from line ~286 to EOF; replace `_LinkSearchSheet(` with `LinkSearchSheet(`; add import)
- Modify: `lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_filter_sheet.dart` (same, from line ~270)
- Modify: `lib/app/modules/global_widgets/status_pill.dart:44-45`

**Interfaces:**
- Consumes: `ApiProvider.getDocumentList/getDocument/createDocument/updateDocument/submitDocument/callMethodPost/hasDocPermission/parseHasDocPermissionResponse` (existing).
- Produces:
  - `SalesOrderProvider` with: `Future<Response> getSalesOrders({int limit, int limitStart, Map<String,dynamic>? filters, String orderBy})`, `getSalesOrder(String)`, `create(Map)`, `update(String, Map)`, `submit(String)`, `cancel(String)`, `updateStatus(String name, String status)`, `addHoldReason(String name, String reason, String email)`, `Future<String> makeDeliveryNote(String name)`, `Future<ItemDetails> getItemDetails(Map<String,dynamic> args)`, `Future<Map<String,dynamic>> getPartyDetails({required String customer, required String company})`, `Future<bool> hasDocPerm(String name, String ptype)`
  - `class LinkSearchSheet` `({required String title, required Future<List<String>> Function(String) onSearch, required ValueChanged<String> onSelected})`
  - `Future<void> showLinkSearchSheet({required String doctype, required String title, required ValueChanged<String> onSelected})`

- [ ] **Step 1: Create the provider**

```dart
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/selling/sales_order/sales_order_logic.dart';

/// Sales Order HTTP calls. Method paths verified live on ERPNext 15.121.1.
class SalesOrderProvider {
  final ApiProvider _api = Get.find<ApiProvider>();
  static const _so = 'erpnext.selling.doctype.sales_order.sales_order';

  static const listFields = [
    'name', 'customer', 'customer_name', 'status', 'docstatus',
    'transaction_date', 'delivery_date', 'grand_total', 'currency',
    'per_delivered', 'per_billed', 'owner', 'modified',
  ];

  Future<Response> getSalesOrders({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    Map<String, dynamic>? orFilters,
    String orderBy = 'modified desc',
  }) =>
      _api.getDocumentList('Sales Order',
          limit: limit,
          limitStart: limitStart,
          filters: filters,
          orFilters: orFilters,
          fields: listFields,
          orderBy: orderBy);

  Future<Response> getSalesOrder(String name) =>
      _api.getDocument('Sales Order', name);

  Future<Response> create(Map<String, dynamic> data) =>
      _api.createDocument('Sales Order', data);

  Future<Response> update(String name, Map<String, dynamic> data) =>
      _api.updateDocument('Sales Order', name, data);

  Future<Response> submit(String name) =>
      _api.submitDocument('Sales Order', name);

  Future<Response> cancel(String name) => _api.callMethodPost(
      'frappe.client.cancel',
      params: {'doctype': 'Sales Order', 'name': name});

  /// status ∈ {'On Hold', 'Closed', 'Draft'} ('Draft' = Resume / Re-open).
  Future<Response> updateStatus(String name, String status) =>
      _api.callMethodPost('$_so.update_status',
          params: {'status': status, 'name': name});

  /// Desk posts the hold reason as a comment before update_status('On Hold').
  Future<Response> addHoldReason(String name, String reason, String email) =>
      _api.callMethodPost('frappe.desk.form.utils.add_comment', params: {
        'reference_doctype': 'Sales Order',
        'reference_name': name,
        'content': 'Reason for hold: $reason',
        'comment_email': email,
        'comment_by': email,
      });

  /// Server-maps the SO to a DN, inserts it as a Draft, returns its name.
  Future<String> makeDeliveryNote(String name) async {
    final mapped = await _api.callMethodPost('$_so.make_delivery_note',
        params: {'source_name': name});
    final doc = (mapped.data as Map)['message'];
    final res = await _api.callMethodPost('frappe.client.insert',
        params: {'doc': jsonEncode(doc)});
    return ((res.data as Map)['message'] as Map)['name'].toString();
  }

  Future<ItemDetails> getItemDetails(Map<String, dynamic> args) async {
    final res = await _api.callMethodPost(
        'erpnext.stock.get_item_details.get_item_details',
        params: {'args': jsonEncode(args)});
    return parseItemDetails((res.data as Map?)?['message']);
  }

  /// Customer defaults desk applies on customer change (price list, currency).
  Future<Map<String, dynamic>> getPartyDetails(
      {required String customer, required String company}) async {
    final res = await _api.callMethodPost(
        'erpnext.accounts.party.get_party_details', params: {
      'party': customer,
      'party_type': 'Customer',
      'company': company,
      'doctype': 'Sales Order',
    });
    final m = (res.data as Map?)?['message'];
    return m is Map ? Map<String, dynamic>.from(m) : {};
  }

  /// Per-document permission (submit / cancel). Fail-closed on any error.
  Future<bool> hasDocPerm(String name, String ptype) async {
    try {
      final res = await _api.hasDocPermission('Sales Order', name, ptype);
      return ApiProvider.parseHasDocPermissionResponse(res.data);
    } catch (_) {
      return false;
    }
  }
}
```

- [ ] **Step 2: Create `link_search_sheet.dart`.** Take the pos_dn version (it has the `Material(transparent)` fix) and make it public:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

/// Debounced search-as-you-type picker over a Link doctype's names.
/// Extracted from the POS & DN Item Rate / BOM Stock report filter sheets.
Future<void> showLinkSearchSheet({
  required String doctype,
  required String title,
  required ValueChanged<String> onSelected,
}) =>
    Get.bottomSheet(
      LinkSearchSheet(
        title: title,
        onSearch: (q) =>
            Get.find<ApiProvider>().searchLinkOptions(doctype, query: q),
        onSelected: onSelected,
      ),
      isScrollControlled: true,
    );

class LinkSearchSheet extends StatefulWidget {
  final String title;
  final Future<List<String>> Function(String query) onSearch;
  final ValueChanged<String> onSelected;
  const LinkSearchSheet({
    super.key,
    required this.title,
    required this.onSearch,
    required this.onSelected,
  });

  @override
  State<LinkSearchSheet> createState() => _LinkSearchSheetState();
}
```

Then paste the pos_dn `_LinkSearchSheetState` body **verbatim** (lines 300–385 of the original), changing only `State<_LinkSearchSheet>` to `State<LinkSearchSheet>`. Keep the `Material(color: Colors.transparent, child: ListView.separated(...))` wrap. **Do not run `dart format`** on these three files.

- [ ] **Step 3: Switch both report sheets to it.** In each file: add `import 'package:multimax/app/modules/global_widgets/link_search_sheet.dart';`, replace the constructor call `_LinkSearchSheet(` with `LinkSearchSheet(`, and delete the private `_LinkSearchSheet` and `_LinkSearchSheetState` classes. BOM's callback is `ValueChanged<String?>`, which is assignable to `ValueChanged<String>` (parameter contravariance), so leave its caller unchanged. Remove any `dart:async` import that becomes unused.

- [ ] **Step 4: StatusPill tones.** In `status_pill.dart`, in the orange group directly under `case 'To Receive':`, add:

```dart
      case 'To Deliver and Bill':
      case 'To Deliver':
```

- [ ] **Step 5: Verify**

Run: `flutter analyze lib/app/data/providers/sales_order_provider.dart lib/app/modules/global_widgets lib/app/modules/selling/reports lib/app/modules/manufacturing/reports`
Expected: no new issues versus baseline (no `unused_import`, no undefined `_LinkSearchSheet`).

- [ ] **Step 6: Commit**

```bash
git branch --show-current
git add lib/app/data/providers/sales_order_provider.dart lib/app/modules/global_widgets/link_search_sheet.dart lib/app/modules/global_widgets/status_pill.dart lib/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_item_rate_filter_sheet.dart lib/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_filter_sheet.dart
git commit -m "feat(sales-order): provider, shared LinkSearchSheet, SO status tones

Extracting the link picker also fixes the BOM report copy, which lacked the
Material(transparent) wrap around its ListTiles.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: List screen + routes

**Files:**
- Create: `lib/app/modules/selling/sales_order/sales_order_binding.dart`, `sales_order_controller.dart`, `sales_order_screen.dart`, `widgets/sales_order_filter_bottom_sheet.dart`
- Modify: `lib/app/data/routes/app_routes.dart` (add both route constants next to `PURCHASE_ORDER*`, lines 7-8 and 60-61)
- Modify: `lib/app/data/routes/app_pages.dart` (add the list `GetPage` after `PURCHASE_ORDER_FORM`, ~line 137; the form page is added in Task 4)

**Interfaces:**
- Consumes: `SalesOrderProvider.getSalesOrders`, `statusFilterLabel`, `progressFraction`, `showLinkSearchSheet`, `AuthenticationController.currentUser`.
- Produces: `SalesOrderController` with `activeFilters` (RxMap), `searchQuery`, `scope` (`Rx<ActionableScope>` reused from the dashboard strip for Mine/Everyone), `applyFilters`, `removeFilter`, `clearFilters`, `setStatusChip(String?)`, `fetch({bool isLoadMore, bool clear})`, `openCreate()`. Routes `AppRoutes.SALES_ORDER = '/sales-order'`, `AppRoutes.SALES_ORDER_FORM = '/sales-order/form'`.

- [ ] **Step 1: Routes.** In `app_routes.dart` add `static const SALES_ORDER = _Paths.SALES_ORDER;` and `static const SALES_ORDER_FORM = _Paths.SALES_ORDER_FORM;` to `AppRoutes`, and `static const SALES_ORDER = '/sales-order';` and `static const SALES_ORDER_FORM = '/sales-order/form';` to `_Paths`.

- [ ] **Step 2: Binding**

```dart
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/sales_order_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/modules/selling/sales_order/sales_order_controller.dart';

class SalesOrderBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SalesOrderProvider>(() => SalesOrderProvider(), fenix: true);
    Get.lazyPut<UserProvider>(() => UserProvider());
    Get.lazyPut<SalesOrderController>(() => SalesOrderController());
  }
}
```

- [ ] **Step 3: Controller.** Mirror `PurchaseOrderController` (paging, debounce, filters, error dialogs), with these differences:
  - No supplier/user/warehouse prefetch (customer uses `showLinkSearchSheet`; owner uses Mine/Everyone).
  - Search matches `name` **or** `customer_name` through `getDocumentList`'s existing `Map<String, dynamic>? orFilters` parameter (api_provider.dart:208). Add `Map<String, dynamic>? orFilters` to `SalesOrderProvider.getSalesOrders` and pass it through.
  - Owner filter: `activeFilters['owner']`, picked in the filter sheet with `UserPickerSheet`. The list controller lazily loads users with `UserProvider.getUsers()` (register `UserProvider` in the binding, as PO does). Mine/Everyone is the quick toggle; picking an explicit owner overrides it (the `mine` owner clause is added only when `activeFilters` has no `owner`).
  - `scope` persists nothing (YAGNI) and defaults to `ActionableScope.everyone`. `mine` adds `owner = currentUser.email`.
  - Delivery-date range is stored as `activeFilters['delivery_date'] = ['between', [from, to]]`.

```dart
import 'package:get/get.dart';
import 'package:multimax/app/data/models/sales_order_model.dart';
import 'package:multimax/app/data/providers/sales_order_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/modules/home/widgets/dashboard_actionable_strip.dart';

class SalesOrderController extends GetxController {
  final SalesOrderProvider _provider = Get.find<SalesOrderProvider>();

  final isLoading = true.obs;
  final isFetchingMore = false.obs;
  final hasMore = true.obs;
  final orders = <SalesOrder>[].obs;
  final activeFilters = <String, dynamic>{}.obs;
  final searchQuery = ''.obs;
  final scope = ActionableScope.everyone.obs;
  static const _limit = 20;
  int _page = 0;

  /// Quick status chips shown under the header (v15 status options).
  static const statusChips = [
    'Draft', 'To Deliver and Bill', 'To Deliver', 'To Bill',
    'On Hold', 'Completed', 'Closed', 'Cancelled',
  ];

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    if (args is Map && args['filters'] is Map) {
      activeFilters.assignAll(Map<String, dynamic>.from(args['filters'] as Map));
      if (activeFilters.containsKey('owner')) {
        scope.value = ActionableScope.mine;
        activeFilters.remove('owner');
      }
    }
    fetch(clear: true);
    debounce(searchQuery, (_) => fetch(clear: true),
        time: const Duration(milliseconds: 500));
  }

  String? get _email {
    try {
      return Get.find<AuthenticationController>().currentUser.value?.email;
    } catch (_) {
      return null;
    }
  }

  void onSearchChanged(String v) => searchQuery.value = v;

  void setScope(ActionableScope s) {
    if (scope.value == s) return;
    scope.value = s;
    fetch(clear: true);
  }

  /// Single-select quick chip; tapping the active chip clears it.
  void setStatusChip(String? status) {
    if (status == null || activeFilters['status'] == status) {
      activeFilters.remove('status');
    } else {
      activeFilters['status'] = status;
    }
    fetch(clear: true);
  }

  void applyFilters(Map<String, dynamic> f) {
    activeFilters.assignAll(f);
    fetch(clear: true);
  }

  void removeFilter(String key) {
    activeFilters.remove(key);
    fetch(clear: true);
  }

  void clearFilters() {
    activeFilters.clear();
    if (searchQuery.value.isEmpty) {
      fetch(clear: true);
    } else {
      searchQuery.value = '';
    }
  }

  Future<void> fetch({bool isLoadMore = false, bool clear = false}) async {
    if (isLoadMore) {
      if (isFetchingMore.value || !hasMore.value) return;
      isFetchingMore.value = true;
    } else {
      isLoading.value = true;
      if (clear) {
        _page = 0;
        hasMore.value = true;
      }
    }
    try {
      final f = Map<String, dynamic>.from(activeFilters);
      final email = _email;
      if (scope.value == ActionableScope.mine &&
          !f.containsKey('owner') && email != null && email.isNotEmpty) {
        f['owner'] = email;
      }
      final q = searchQuery.value.trim();
      final res = await _provider.getSalesOrders(
          limit: _limit,
          limitStart: _page * _limit,
          filters: f,
          orFilters: q.isEmpty
              ? null
              : {'name': ['like', '%$q%'], 'customer_name': ['like', '%$q%']});
      final data = (res.data is Map) ? res.data['data'] : null;
      if (res.statusCode == 200 && data is List) {
        final rows = data
            .map((e) => SalesOrder.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        if (rows.length < _limit) hasMore.value = false;
        isLoadMore ? orders.addAll(rows) : orders.assignAll(rows);
        _page++;
      } else {
        _error(isLoadMore, clear);
      }
    } catch (e) {
      _error(isLoadMore, clear, e.toString());
    } finally {
      isLoadMore ? isFetchingMore.value = false : isLoading.value = false;
    }
  }

  void _error(bool more, bool clear, [String? msg]) => GlobalDialog.showError(
        title: 'Could not load Sales Orders',
        message: msg ??
            'The server returned an unexpected response. '
                'Check your connection and try again.',
        onRetry: () => fetch(isLoadMore: more, clear: clear),
      );

  void openCreate() => Get.toNamed(AppRoutes.SALES_ORDER_FORM,
      arguments: {'name': '', 'mode': 'new'});

  void open(SalesOrder so) => Get.toNamed(AppRoutes.SALES_ORDER_FORM,
      arguments: {'name': so.name, 'mode': so.docstatus == 0 ? 'edit' : 'view'});
}
```

Users for the owner picker: copy PO's `users` / `isFetchingUsers` / `fetchUsers()` block, called from the filter sheet's `initState` rather than `onInit` (so the list doesn't pay for it up front).

- [ ] **Step 4: Screen.** Copy `purchase_order_screen.dart`'s structure (`AppShellScaffold`, `RefreshIndicator`, `CustomScrollView`, `DocTypeListHeader`, `ResultCountPill`, `DocCardSkeletonList`, `ListEmptyState`, `ListEndFooter`) with these changes:
  - Wrap the `CustomScrollView` in `Scrollbar(controller: _scrollController, child: …)` (CLAUDE.md list convention; PO lacks it).
  - FAB: `DocTypeGuard(doctype: 'Sales Order', permType: 'create', child: FloatingActionButton.extended(onPressed: controller.openCreate, icon: const Icon(Icons.add), label: const Text('New Sales Order')))`, with **no** `Obx` around it.
  - `_buildFilterChips` also shows `owner` (label `Owner: <display name or email>`).
  - `DocTypeListHeader(title: 'Sales Order', searchDoctype: 'Sales Order', …, bottom: _StatusChipBar(controller))`. `_StatusChipBar` is a `PreferredSizeWidget` (`preferredSize: Size.fromHeight(52)`) holding `SizedBox(height: 52, child: Obx(() => ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [ ActionableScopeToggle-style Mine/Everyone SegmentedButton, ...statusChips.map(ChoiceChip(selected: controller.activeFilters['status'] == s, onSelected: (_) => controller.setStatusChip(s))) ])))`. The memory gotcha says the `bottom:` chip `ListView` needs an explicit `SizedBox(height)`. For Mine/Everyone, reuse `ActionableScopeToggle(scope: controller.scope.value, onChanged: controller.setScope)` from `dashboard_actionable_strip.dart`.
  - `_buildFilterChips`: search, `status` (label `statusFilterLabel(filters['status'])`), `customer`, `delivery_date` (label `Delivery: from → to`).
  - Card: `GenericDocumentCard(title: so.name, subtitle: so.customerName.isNotEmpty ? so.customerName : so.customer, status: so.status, onTap: () => controller.open(so), stats: [transaction date icon stat, delivery date icon stat, grand total stat], expandedContent: null)` plus, when `docstatus == 1`, a `_ProgressRow` with two `LinearProgressIndicator`s (`value: progressFraction(so.perDelivered)` labelled "Delivered", `progressFraction(so.perBilled)` labelled "Billed"). Bar colours: `AppColors.green700/green300` (delivered) and `AppColors.blue700/blue300` (billed), picked by `Theme.of(context).brightness`. If `GenericDocumentCard` has no slot for extra content, put the progress row in `stats` as a widget; check its constructor first.
  - Last sliver item: `ListEndFooter(hasMore: controller.hasMore.value)`. Add bottom padding `SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 80))` for the FAB and nav bar.

- [ ] **Step 5: Filter sheet** `widgets/sales_order_filter_bottom_sheet.dart`, built on `GlobalFilterBottomSheet(title: 'Filter Sales Orders', sortOptions: const [], …, filterWidgets: [...], onApply, onClear, activeFilterCount)`. Local `RxnString customer, status, from, to` are seeded from `controller.activeFilters` in `initState`. The widgets are:
  - `DocPickerField(label: 'Customer', icon: Icons.person_outline, value: customer.value, onTap: () => showLinkSearchSheet(doctype: 'Customer', title: 'Select Customer', onSelected: (v) => customer.value = v))`
  - `DocPickerField(label: 'Status', icon: Icons.flag_outlined, value: status.value, onTap: () => showOptionPickerSheet(context, title: 'Status', options: SalesOrderController.statusChips, selected: status.value ?? '', onSelected: (v) => status.value = v))`
  - Two date `DocPickerField`s (From / To) opening `showDatePicker` and writing `yyyy-MM-dd`.
  - `DocPickerField(label: 'Owner', icon: Icons.person_search_outlined, value: ownerName.value, onTap: () => Get.bottomSheet(Obx(() => UserPickerSheet(title: 'Select Owner', users: controller.users, isLoading: controller.isFetchingUsers.value, onSelected: (id, display) { owner.value = id; ownerName.value = display; Get.back(); })), isScrollControlled: true))`

  `onApply` builds `{'customer': c, 'status': s, 'owner': o, 'delivery_date': ['between', [from, to]]}` (only the set keys; for one-sided ranges use `['>=', from]` / `['<=', to]`), then `controller.applyFilters(f); Get.back();`. Each `DocPickerField` sits in its own `Obx`.

- [ ] **Step 6: Register the list page** in `app_pages.dart`:

```dart
    GetPage(
      name: AppRoutes.SALES_ORDER,
      page: () => const SalesOrderScreen(),
      binding: SalesOrderBinding(),
    ),
```

- [ ] **Step 7: Verify**

Run: `flutter analyze lib/app/modules/selling lib/app/data/routes`
Expected: no new issues.

- [ ] **Step 8: Commit**

```bash
git branch --show-current
git add lib/app/modules/selling/sales_order lib/app/data/routes
git commit -m "feat(sales-order): list screen with status chips, Mine/Everyone, filters

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Form (header, items list, save, submit, cancel, dirty guard)

**Files:**
- Create: `lib/app/modules/selling/sales_order/form/sales_order_form_binding.dart`, `sales_order_form_controller.dart`, `sales_order_form_screen.dart`
- Modify: `lib/app/data/routes/app_pages.dart` (form `GetPage`, `transition: Transition.rightToLeftWithFade`)
- Modify: `lib/app/shared/item_card/item_card_data.dart` (add `fromSalesOrderItem`)
- Modify: `lib/app/data/utils/app_constants.dart` (add `const String kSoItemSheetTag = 'so_item_sheet';` under `kPoItemSheetTag`)

**Interfaces:**
- Consumes: Task 1 logic + model, Task 2 provider, `OptimisticLockingMixin`, `RealtimeSyncMixin`, `StorageService.getCompany()`, `GlobalDialog.confirm/showError/showUnsavedChanges`, `ItemFormController.parseServerMessage(dynamic)` (static, existing, in `lib/app/modules/item/form/item_form_controller.dart`).
- Produces: `SalesOrderFormController` with `so` (`Rx<SalesOrder?>`), `isEditable`, `isDirty`, `isSaving`, `isSubmitting`, `isActing` (`RxnString`, the action in flight), `banner` (`RxnString`, server error text), `actions` (`Set<SoAction>` getter), `saveDocument()`, `submitDocument()`, `cancelDocument()`, `setCustomer(String)`, `setHeader({...})`, `addItem(SalesOrderItem)`, `updateItem(SalesOrderItem)`, `deleteItem(SalesOrderItem)`, `openItemSheet({SalesOrderItem? row, String? itemCode})`, `confirmDiscard()`. Lifecycle and Make DN methods come in Task 6.

- [ ] **Step 1: `ItemCardData.fromSalesOrderItem`.** Add it next to `fromPurchaseOrderItem` and import `sales_order_model.dart`:

```dart
  factory ItemCardData.fromSalesOrderItem(
    SalesOrderItem item, {
    int? index,
    required bool isEditable,
    bool isHighlighted = false,
  }) {
    return ItemCardData(
      rowName:       item.name,
      index:         index,
      itemCode:      item.itemCode,
      itemName:      item.itemName.isNotEmpty ? item.itemName : null,
      qty:           item.qty,
      uom:           item.uom,
      targetQty:     item.deliveredQty,
      rate:          item.rate,
      amount:        item.amount,
      warehouse:     item.warehouse,
      toWarehouse:   null,
      qtyLabel:      'Qty',
      rateLabel:     'Rate',
      warehouseLabel: 'Warehouse',
      isEditable:    isEditable,
      isHighlighted: isHighlighted,
    );
  }
```

(Unlike PO, SO shows rate, amount and warehouse; they are the fields reps check. Check that `ItemCardData`'s constructor has no required params beyond these, such as `variantOf`; pass `null` for any that exist.)

- [ ] **Step 2: Binding**

```dart
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/sales_order_provider.dart';
import 'package:multimax/app/modules/selling/sales_order/form/sales_order_form_controller.dart';

class SalesOrderFormBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SalesOrderProvider>(() => SalesOrderProvider(), fenix: true);
    Get.lazyPut<SalesOrderFormController>(() => SalesOrderFormController());
  }
}
```

- [ ] **Step 3: Controller.** Mirror PO's form controller (args parsing, `OptimisticLockingMixin` + `RealtimeSyncMixin`, `saveResult` timer, highlight/scroll keys, `confirmDiscard`, item-sheet open/close with a tagged controller), with these SO-specific parts:

```dart
class SalesOrderFormController extends GetxController
    with OptimisticLockingMixin, RealtimeSyncMixin {
  final SalesOrderProvider _provider = Get.find<SalesOrderProvider>();
  final StorageService _storage = Get.find<StorageService>();
  final PermissionService _perm = Get.find<PermissionService>();

  // Mutable: after the first POST the controller adopts the saved name and
  // flips to 'edit' in place (Get.offNamed to the SAME route is dropped by
  // GetX's preventDuplicates, so we don't navigate).
  late String name;
  late String mode;
  SalesOrderFormController() {
    final a = Get.arguments;
    name = a is Map ? (a['name'] ?? '') : (a is String ? a : '');
    mode = a is Map ? (a['mode'] ?? 'view') : (a is String ? 'view' : 'new');
  }

  final isLoading = true.obs;
  @override final isSaving = false.obs;
  @override final isDirty = false.obs;
  final isSubmitting = false.obs;
  final isActing = RxnString();          // SoAction.name in flight
  final isItemSheetOpen = false.obs;
  final banner = RxnString();            // server error text, cleared on next action
  final so = Rx<SalesOrder?>(null);
  SalesOrder? _original;

  // Per-doc perms for submitted actions; null = unresolved (fail closed).
  final canSubmitPerm = RxnBool();
  final canCancelPerm = RxnBool();

  @override String get realtimeDoctype => 'Sales Order';
  @override String get realtimeDocname => name;

  bool get isEditable => (so.value?.docstatus ?? 1) == 0;

  SoPerms get perms => SoPerms(
        write: mode == 'new'
            ? _perm.hasAccess('Sales Order', permType: 'create')
            : _perm.hasAccess('Sales Order', permType: 'write'),
        submit: canSubmitPerm.value,
        cancel: canCancelPerm.value,
        createDn: _perm.hasAccess('Delivery Note', permType: 'create'),
      );

  Set<SoAction> get actions {
    final s = so.value;
    return s == null ? const {} : allowedActions(s, perms);
  }

  /// Header Save is enabled only when a save could succeed server-side.
  bool get canSaveNow {
    final s = so.value;
    return s != null && s.customer.isNotEmpty && s.items.isNotEmpty;
  }

  /// Draft may be submitted only when saved and clean (SE computeCanSubmit).
  bool get canSubmit =>
      actions.contains(SoAction.submit) &&
      mode != 'new' && !isDirty.value && !isSaving.value && !isSubmitting.value;

  @override
  void onInit() {
    super.onInit();
    if (mode == 'new') {
      final today = FormattingHelper.formatDate(DateTime.now());
      so.value = SalesOrder.blank(
          transactionDate: today, company: _storage.getCompany());
      _original = null;
      isDirty.value = true;
      isLoading.value = false;
    } else {
      fetchDocument().then((_) => initRealtimeSync());
    }
  }

  @override
  void onClose() {
    disposeRealtimeSync();
    super.onClose();
  }

  Future<void> fetchDocument() async {
    isLoading.value = true;
    try {
      final res = await _provider.getSalesOrder(name);
      final data = (res.data is Map) ? res.data['data'] : null;
      if (res.statusCode == 200 && data is Map) {
        _setLoaded(SalesOrder.fromJson(Map<String, dynamic>.from(data)));
        await _refreshDocPerms();
      } else {
        GlobalDialog.showError(
            title: 'Could not load Sales Order',
            message: 'The server returned an unexpected response.',
            onRetry: fetchDocument);
      }
    } catch (e) {
      GlobalDialog.showError(
          title: 'Could not load Sales Order',
          message: e.toString(),
          onRetry: fetchDocument);
    } finally {
      isLoading.value = false;
    }
  }

  void _setLoaded(SalesOrder s) {
    so.value = s;
    _original = s;
    isDirty.value = false;
  }

  /// Submit (draft) or submit+cancel (submitted) per document; fail-closed.
  Future<void> _refreshDocPerms() async {
    final s = so.value;
    if (s == null || s.name.isEmpty || s.docstatus == 2) {
      canSubmitPerm.value = false;
      canCancelPerm.value = false;
      return;
    }
    final r = await Future.wait([
      _provider.hasDocPerm(s.name, 'submit'),
      s.docstatus == 1 ? _provider.hasDocPerm(s.name, 'cancel') : Future.value(false),
    ]);
    canSubmitPerm.value = r[0];
    canCancelPerm.value = r[1];
  }

  @override
  Future<void> reloadDocument() async {
    isStale.value = false;
    await fetchDocument();
  }

  // ── Mutations ──────────────────────────────────────────────────────────
  void _apply(SalesOrder next) {
    so.value = next;
    isDirty.value = mode == 'new' || _original == null || isSoDirty(_original!, next);
    if (isDirty.value) scheduleAutoSave();
  }

  Future<void> setCustomer(String customer) async {
    final s = so.value;
    if (s == null || !isEditable) return;
    _apply(s.copyWith(customer: customer, customerName: customer));
    // Desk's customer trigger: pull price list + currency from the party.
    try {
      final p = await _provider.getPartyDetails(
          customer: customer, company: s.company ?? _storage.getCompany());
      final cur = so.value!;
      _apply(cur.copyWith(
        customerName: (p['customer_name'] ?? customer).toString(),
        sellingPriceList: p['selling_price_list']?.toString(),
        currency: p['currency']?.toString(),
      ));
    } catch (_) {
      // Fail-open: the server fills the price list on save.
    }
  }

  void setHeader({
    String? transactionDate,
    String? deliveryDate,
    String? orderType,
    String? setWarehouse,
    String? poNo,
  }) {
    final s = so.value;
    if (s == null || !isEditable) return;
    _apply(s.copyWith(
      transactionDate: transactionDate,
      deliveryDate: deliveryDate,
      orderType: orderType,
      setWarehouse: setWarehouse,
      poNo: poNo,
    ));
  }

  void addItem(SalesOrderItem row) {
    final s = so.value!;
    _apply(s.copyWith(items: [...s.items, row]));
    saveDocument();
  }

  void updateItem(SalesOrderItem row) {
    final s = so.value!;
    _apply(s.copyWith(
        items: s.items.map((i) => i.name == row.name ? row : i).toList()));
    saveDocument();
  }

  void deleteItem(SalesOrderItem row) {
    GlobalDialog.showConfirmation(
      title: 'Remove Item?',
      message: 'Remove ${row.itemCode} from this order?',
      onConfirm: () {
        final s = so.value!;
        _apply(s.copyWith(
            items: s.items.where((i) => i.name != row.name).toList()));
        saveDocument();
      },
    );
  }

  // ── Save ───────────────────────────────────────────────────────────────
  @override
  Future<void> saveDocument() async {
    final s = so.value;
    if (s == null || !isEditable) return;
    if (checkStaleAndBlock()) return;
    if (!isDirty.value && mode != 'new') return;
    if (isSaving.value) return;
    // `items` is reqd in the live meta, so a header-only draft can never save;
    // skip silently (autosave fires while the header is still being filled).
    if (!canSaveNow) return;

    final errors = validateOrder(s);
    if (errors.isNotEmpty) {
      banner.value = errors.values.join('\n');
      return;
    }
    banner.value = null;
    isSaving.value = true;
    try {
      final isNew = mode == 'new';
      final res = isNew
          ? await _provider.create(buildPayload(s))
          : await _provider.update(s.name, buildPayload(s));
      final data = (res.data is Map) ? res.data['data'] : null;
      if (res.statusCode == 200 && data is Map) {
        final saved = SalesOrder.fromJson(Map<String, dynamic>.from(data));
        if (isNew) {
          name = saved.name;
          mode = 'edit';
        }
        _setLoaded(saved);
        if (isNew) await startRealtimeSyncAfterCreate();
        await _refreshDocPerms();
        GlobalSnackbar.success(message: 'Sales Order saved');
      }
    } on DioException catch (e) {
      if (handleVersionConflict(e)) return;
      banner.value = ItemFormController.parseServerMessage(e.response?.data);
    } catch (e) {
      banner.value = e.toString();
    } finally {
      isSaving.value = false;
    }
  }

  // ── Submit / Cancel ─────────────────────────────────────────────────────
  Future<void> submitDocument() async {
    if (!canSubmit) return;
    final errors = validateOrder(so.value!);
    if (errors.isNotEmpty) {
      banner.value = errors.values.join('\n');
      return;
    }
    final ok = await GlobalDialog.confirm(
        title: 'Confirm',
        message: 'Permanently Submit $name?',
        confirmText: 'Yes',
        confirmColor: AppColors.blue600);
    if (ok != true) return;
    isSubmitting.value = true;
    banner.value = null;
    try {
      await _provider.submit(name);
      await fetchDocument();
      GlobalSnackbar.success(message: 'Sales Order $name submitted');
    } on DioException catch (e) {
      if (handleVersionConflict(e)) return;
      banner.value = ItemFormController.parseServerMessage(e.response?.data);
    } finally {
      isSubmitting.value = false;
    }
  }

  Future<void> cancelDocument() => _runAction(SoAction.cancel,
      confirm: 'Permanently Cancel $name?',
      call: () => _provider.cancel(name),
      done: 'Sales Order $name cancelled');

  /// Shared runner for cancel + lifecycle actions (Task 6 adds the others).
  Future<void> _runAction(
    SoAction a, {
    String? confirm,
    required Future<dynamic> Function() call,
    required String done,
  }) async {
    if (!actions.contains(a) || isActing.value != null) return;
    if (confirm != null) {
      final ok = await GlobalDialog.confirm(
          title: 'Confirm', message: confirm, confirmText: 'Yes',
          confirmColor: AppColors.red600);
      if (ok != true) return;
    }
    isActing.value = a.name;
    banner.value = null;
    try {
      await call();
      await fetchDocument();
      GlobalSnackbar.success(message: done);
    } on DioException catch (e) {
      banner.value = ItemFormController.parseServerMessage(e.response?.data);
    } catch (e) {
      banner.value = e.toString();
    } finally {
      isActing.value = null;
    }
  }

  Future<void> confirmDiscard() async => GlobalDialog.showUnsavedChanges(
        onDiscard: () {
          isDirty.value = false;
          Get.back();
        },
      );
}
```

Check whether `AppColors.red600` exists (`grep "red600" lib/app/data/constants/app_theme.dart`); if not, use `AppColors.red500`. `startRealtimeSyncAfterCreate()` is the existing `RealtimeSyncMixin` method (realtime_sync_mixin.dart:84), used exactly as PO uses it. The item sheet (`openItemSheet`) comes in Task 5.

- [ ] **Step 4: Screen.** Mirror `purchase_order_form_screen.dart`. **Hoist every Rx read into the outer `Obx`** (a sliver header's Rx reads aren't tracked):

```dart
return Obx(() {
  final s = controller.so.value;
  final isDirty = controller.isDirty.value;
  final isSaving = controller.isSaving.value;
  final saveResult = controller.saveResult.value;
  final isLoading = controller.isLoading.value;
  final actions = controller.actions;                 // reads perm RxMap + RxnBools
  final canSubmit = controller.canSubmit;
  final canSaveNow = controller.canSaveNow;
  final bannerText = controller.banner.value;
  ...
```

Layout:
- `PopScope(canPop: !isDirty, onPopInvokedWithResult: … controller.confirmDiscard())`
- `DefaultTabController(length: 2)` → `Scaffold` → `NestedScrollView(headerSliverBuilder: (ctx, _) => [SliverOverlapAbsorber(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(ctx), sliver: DocTypeFormHeader(title: s?.name ?? 'Loading...', docType: 'Sales Order', statusLabel: s?.status, canSave: isDirty && controller.isEditable && canSaveNow, docStatus: s?.docstatus ?? 0, isSaving: isSaving, saveResult: saveResult, onSave: …, onReload: …, extraActions: [ … Task 6 menu … , RealtimeSyncStatusIcon(...)], bottom: const TabBar(tabs: [Tab(text: 'Details'), Tab(text: 'Items')])))], body: …)`
- Each tab body is a `Builder` returning `CustomScrollView(slivers: [SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)), SliverPadding(...)])`, the per-tab injector pattern, so short tabs don't render blank under the pinned header.
- **Details tab**, top to bottom:
  - `InlineBanner(visible: bannerText != null, message: bannerText ?? '', type: BannerType.error)`
  - Status row: `StatusPill(status: s.status)`, and when `docstatus == 1` the two progress bars from Task 3 (extract `_ProgressRow` into `lib/app/modules/selling/sales_order/widgets/so_progress_row.dart` so both screens share it)
  - `DocPickerField(label: 'Customer', icon: Icons.person_outline, value: s.customerName.isNotEmpty ? s.customerName : s.customer, onTap: controller.isEditable ? () => showLinkSearchSheet(doctype: 'Customer', title: 'Select Customer', onSelected: controller.setCustomer) : null)`
  - Transaction Date and Delivery Date `DocPickerField`s (calendar icon, `showDatePicker`; Delivery firstDate = transaction date)
  - Order Type `DocPickerField` → `showOptionPickerSheet(options: ['Sales', 'Shopping Cart'])`
  - Price List `DocDetailRow` (read-only; comes from customer)
  - Set Warehouse `DocPickerField` → `showLinkSearchSheet(doctype: 'Warehouse', …)` (non-group warehouses are fine to pick; the server rejects group warehouses on SO rows, so no client filter)
  - Customer's PO No: `TextFormField` with the controller seeded once from `s.poNo`, `onChanged: (v) => controller.setHeader(poNo: v)`
  - Totals `DocDetailRow`s: Total Qty, Taxes (`totalTaxesAndCharges`), Grand Total, Rounded Total (formatted with `FormattingHelper.getCurrencySymbol(s.currency)`)
  - When `isEditable && canSubmit`: an `AsyncFilledButton(busy: controller.isSubmitting, onPressed: controller.submitDocument, icon: const Icon(Icons.check_circle_outline), label: 'Submit', loadingLabel: 'Submitting…')`
- **Items tab:** `FormEmptyState` when empty, else `DocItemCard(data: ItemCardData.fromSalesOrderItem(...), onTap: isEditable ? () => controller.openItemSheet(row: item) : null, onDelete: …)` rows inside `Dismissible`, as in PO. Swipe background uses `AppColors.red500` plus an `Icons.delete_outline` whose colour is `Theme.of(context).colorScheme.onError`, never `Colors.white`. When editable: a bottom bar with `BarcodeInputWidget` (scan → `ScanService.processScan` → `controller.openItemSheet(itemCode: …)`, copy PO's `scanBarcode` including `MultiItemSelectionSheet` and the DataWedge `_onRawScan` worker guarded by `Get.currentRoute == AppRoutes.SALES_ORDER_FORM`) and an "Add item" `OutlinedButton` that opens `showLinkSearchSheet(doctype: 'Item', title: 'Select Item', onSelected: (c) => controller.openItemSheet(itemCode: c))`. The list gets bottom padding of 80 + nav-bar inset.

- [ ] **Step 5: Register the form page** in `app_pages.dart`:

```dart
    GetPage(
      name: AppRoutes.SALES_ORDER_FORM,
      page: () => const SalesOrderFormScreen(),
      binding: SalesOrderFormBinding(),
      transition: Transition.rightToLeftWithFade,
    ),
```

- [ ] **Step 6: Verify**

Run: `flutter analyze lib/app/modules/selling lib/app/shared/item_card lib/app/data`
Expected: no new issues. (`openItemSheet` is referenced but defined in Task 5. Add a stub `void openItemSheet({SalesOrderItem? row, String? itemCode}) {}` now so this task compiles on its own; Task 5 replaces it.)

- [ ] **Step 7: Commit**

```bash
git branch --show-current
git add lib/app/modules/selling/sales_order lib/app/shared/item_card/item_card_data.dart lib/app/data/utils/app_constants.dart lib/app/data/routes/app_pages.dart
git commit -m "feat(sales-order): form with header, items, save/submit/cancel, dirty guard

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Item sheet with server-priced rows

**Files:**
- Create: `lib/app/modules/selling/sales_order/form/sales_order_item_form_controller.dart`
- Create: `lib/app/modules/selling/sales_order/form/widgets/sales_order_item_form_sheet.dart`
- Modify: `sales_order_form_controller.dart` (replace the `openItemSheet` stub)

**Interfaces:**
- Consumes: `ItemSheetControllerBase` (`qtyController`, `itemCode`, `itemName`, `editingItemName`, `isSheetValid`, `saveButtonState`, `initBaseListeners()`, `captureSnapshot()`, `setupAutoSubmit()`), `SalesOrderProvider.getItemDetails`, `validateRow`, `kSoItemSheetTag`.
- Produces: `SalesOrderItemFormController.initialise({required SalesOrderFormController parent, SalesOrderItem? row, String? itemCode})`; `SalesOrderItemFormSheet`.

- [ ] **Step 1: Item controller.** Mirror `PurchaseOrderItemFormController` (same overrides: `resolvedWarehouse`, `requiresBatch`/`requiresRack` false, `accentColor => AppColors.green600`, `isAddMode`, `qtyInfoText => ''`, `qtyInfoTooltip`, `adjustQty`, `deleteCurrentItem`, listener add/remove, post-frame dispose). SO-specific parts:

```dart
  late SalesOrderFormController _parent;
  SalesOrderItem? _snapshot;             // the row being edited; null in add mode

  final rateController = TextEditingController();
  final deliveryDateController = TextEditingController();
  final uom = RxnString();
  final warehouse = RxnString();
  final priceListRate = 0.0.obs;
  final conversionFactor = 1.0.obs;
  final sheetRate = 0.0.obs;
  final isFetchingDetails = false.obs;
  final detailsError = RxnString();
  final rowErrors = <String, String>{}.obs;   // from validateRow; drives field errors

  double get sheetAmount =>
      (double.tryParse(qtyController.text) ?? 0) * sheetRate.value; // estimate only

  Future<void> initialise({
    required SalesOrderFormController parent,
    SalesOrderItem? row,
    String? itemCode,
  }) async {
    _parent = parent;
    final so = parent.so.value!;
    editingItemName.value = row?.name;
    this.itemCode.value = row?.itemCode ?? itemCode ?? '';
    itemName.value = row?.itemName ?? '';
    qtyController.text = _fmtQty(row?.qty ?? 1);
    rateController.text = (row?.rate ?? 0).toStringAsFixed(2);
    sheetRate.value = row?.rate ?? 0;
    priceListRate.value = row?.priceListRate ?? 0;
    conversionFactor.value = row?.conversionFactor ?? 1;
    uom.value = row?.uom;
    warehouse.value = row?.warehouse ?? so.setWarehouse;
    // New rows inherit the header delivery date (desk behaviour).
    deliveryDateController.text = row?.deliveryDate ?? so.deliveryDate ?? '';
    _snapshot = row;
    initBaseListeners();
    _addListeners();
    captureSnapshot();
    if (row == null) await _loadDetails();
    validateSheet();
  }

  /// get_item_details: server price-list rate, UOM, conversion, default wh.
  /// ponytail: conversion_rate/plc_conversion_rate sent as 1 (all live
  /// docs are AED in AED); pass real exchange rates if a foreign-currency
  /// price list is ever used.
  Future<void> _loadDetails() async {
    final so = _parent.so.value!;
    isFetchingDetails.value = true;
    detailsError.value = null;
    try {
      final d = await Get.find<SalesOrderProvider>().getItemDetails({
        'item_code': itemCode.value,
        'doctype': 'Sales Order',
        'company': so.company,
        'customer': so.customer,
        'selling_price_list': so.sellingPriceList,
        'currency': so.currency,
        'price_list_currency': so.currency,
        'conversion_rate': 1,
        'plc_conversion_rate': 1,
        'transaction_date': so.transactionDate,
        'qty': double.tryParse(qtyController.text) ?? 1,
        'uom': uom.value,
        'warehouse': warehouse.value,
        'order_type': so.orderType,
      });
      if (itemName.value.isEmpty) itemName.value = d.itemName;
      uom.value = d.uom ?? d.stockUom;
      conversionFactor.value = d.conversionFactor;
      priceListRate.value = d.priceListRate;
      warehouse.value ??= d.warehouse;
      rateController.text = d.rate.toStringAsFixed(2); // listener updates sheetRate
    } catch (e) {
      // Fail open to manual entry; the server re-prices/validates on save.
      detailsError.value =
          'Could not load the price list rate. Enter the rate manually.';
    } finally {
      isFetchingDetails.value = false;
    }
  }

  SalesOrderItem _current() {
    final base = _snapshot ??
        SalesOrderItem(
          name: 'local_${DateTime.now().millisecondsSinceEpoch}',
          itemCode: itemCode.value,
          itemName: itemName.value,
          qty: 0,
        );
    return base.copyWith(
      qty: double.tryParse(qtyController.text) ?? 0,
      rate: double.tryParse(rateController.text) ?? 0,
      uom: uom.value,
      conversionFactor: conversionFactor.value,
      priceListRate: priceListRate.value,
      deliveryDate: deliveryDateController.text,
      warehouse: warehouse.value ?? '',
    );
  }

  @override
  void validateSheet() {
    if (!_parent.isEditable) {
      isSheetValid.value = false;
      return;
    }
    final row = _current();
    rowErrors.assignAll(
        validateRow(row, _parent.so.value!.transactionDate));
    final rateOk = (double.tryParse(rateController.text) ?? -1) >= 0;
    final changed = isAddMode ||
        _snapshot == null ||
        row.qty != _snapshot!.qty ||
        row.rate != _snapshot!.rate ||
        (row.deliveryDate ?? '') != (_snapshot!.deliveryDate ?? '') ||
        (row.warehouse ?? '') != (_snapshot!.warehouse ?? '');
    isSheetValid.value = rowErrors.isEmpty && rateOk && changed;
  }

  @override
  Future<void> submit() async {
    validateSheet();
    if (!isSheetValid.value) return;          // sheet stays open with errors
    final row = _current();
    isAddMode ? _parent.addItem(row) : _parent.updateItem(row);
    Get.back();
  }
```

`_addListeners()` / `_removeListeners()` attach `validateSheet` to `rateController` and `deliveryDateController`, and a `_onRateChanged` that sets `sheetRate.value = double.tryParse(rateController.text) ?? 0`, exactly like PO's `_initPOListeners`. `_fmtQty(double q)` renders whole numbers without decimals (`q == q.truncateToDouble() ? q.toInt().toString() : q.toString()`). `rowErrors` is a map, not an error Rx used as a rebuild trigger. The sheet reads `isSheetValid` and the field controllers too. Per the "same-value set never emits" gotcha, `assignAll` on an `RxMap` always notifies, which is fine.

- [ ] **Step 2: Sheet widget.** Mirror `PurchaseOrderItemFormSheet`: `Obx(() => UniversalItemFormSheet(controller: ctrl, scrollController: …, isSaveEnabled: formCtrl.isEditable, onSubmit: ctrl.submit, onScan: null, customFields: [...]))`. Don't add `SizedBox` spacers between custom fields; `GlobalItemFormSheet` already pads each one. The custom fields, in order:
  1. `Obx(() => InlineBanner(visible: ctrl.detailsError.value != null, message: ctrl.detailsError.value ?? '', type: BannerType.warning))`
  2. Delivery Date `GlobalItemFormSheet.buildInputGroup(label: 'Delivery Date', color: dark ? AppColors.orange300 : AppColors.orange700, child: TextFormField(controller: ctrl.deliveryDateController, readOnly: true, onTap: showDatePicker(firstDate: DateTime.parse(transactionDate), lastDate: +2y), decoration: InputDecoration(errorText: ctrl.rowErrors['delivery_date'], …)))` wrapped in `Obx`
  3. Rate `buildInputGroup(label: 'Rate', color: context.scheme.textMuted, child: Obx(() => TextFormField(controller: ctrl.rateController, keyboardType: decimal, decoration: InputDecoration(prefixIcon: ctrl.isFetchingDetails.value ? const Padding(padding: EdgeInsets.all(12), child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))) : const Icon(Icons.sell_outlined, size: 18), helperText: ctrl.priceListRate.value > 0 ? 'Price list: ${FormattingHelper.formatAmount(ctrl.priceListRate.value)}' : null))))`
  4. UOM + Warehouse row: two `DocPickerField`s in `Obx`. UOM is read-only and shows `ctrl.uom.value` (changing UOM needs a fresh conversion factor; out of scope). Warehouse opens `showLinkSearchSheet(doctype: 'Warehouse', onSelected: (w) { ctrl.warehouse.value = w; ctrl.validateSheet(); })`.
  5. Estimate tile: copy PO's amount tile with the label "Estimated Amount" and a subtitle `Text('Final total and VAT are calculated on save', style: TextStyle(fontSize: 11, color: blueInk))`.

- [ ] **Step 3: Replace the `openItemSheet` stub** in the form controller, mirroring PO `_openItemSheet`:

```dart
  Future<void> openItemSheet({SalesOrderItem? row, String? itemCode}) async {
    if (!isEditable || isItemSheetOpen.value || Get.isBottomSheetOpen == true) {
      return;
    }
    if (so.value!.customer.isEmpty) {
      banner.value = 'Select a customer first — item prices depend on it.';
      return;
    }
    Get.lazyPut<SalesOrderItemFormController>(
        () => SalesOrderItemFormController(),
        tag: kSoItemSheetTag, fenix: true);
    final ctrl = Get.find<SalesOrderItemFormController>(tag: kSoItemSheetTag);
    isItemSheetOpen.value = true;
    unawaited(ctrl.initialise(parent: this, row: row, itemCode: itemCode));
    await Get.bottomSheet(
      DraggableScrollableSheet(
        initialChildSize: 0.7, minChildSize: 0.4, maxChildSize: 0.95,
        expand: false,
        builder: (_, sc) => SalesOrderItemFormSheet(scrollController: sc),
      ),
      isScrollControlled: true,
    );
    isItemSheetOpen.value = false;
    Get.delete<SalesOrderItemFormController>(tag: kSoItemSheetTag);
  }
```

- [ ] **Step 4: Verify**

Run: `flutter analyze lib/app/modules/selling`, then `flutter test test/unit/sales_order_logic_test.dart`
Expected: no new issues; tests still PASS.

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add lib/app/modules/selling/sales_order
git commit -m "feat(sales-order): item sheet priced by get_item_details

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Lifecycle actions + Make → Delivery Note

**Files:**
- Create: `lib/app/modules/selling/sales_order/form/widgets/hold_reason_sheet.dart`
- Modify: `sales_order_form_controller.dart`, `sales_order_form_screen.dart`

**Interfaces:**
- Consumes: `_runAction` (Task 4), `SalesOrderProvider.updateStatus/addHoldReason/makeDeliveryNote`, `AuthenticationController.currentUser`.
- Produces: `hold()`, `resume()`, `close()`, `reopen()`, `makeDeliveryNote()` on the form controller; `Future<String?> showHoldReasonSheet()`.

- [ ] **Step 1: Hold-reason sheet.** It returns the trimmed text, or null on dismiss. It uses a `StatefulWidget` with a `TextEditingController` (multiline, `autofocus`), and the confirm button is enabled only when the text is non-blank (`ValueListenableBuilder` on the controller; no Rx):

```dart
Future<String?> showHoldReasonSheet() => Get.bottomSheet<String>(
      const _HoldReasonSheet(),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
```

Build the body on `OptionPickerSheetShell(title: 'Reason for Hold', child: …)` from `option_picker_sheet.dart`. Pad with `MediaQuery.viewInsetsOf(context).bottom` so the keyboard doesn't cover the field. Confirm calls `Get.back(result: controller.text.trim())`.

- [ ] **Step 2: Controller actions**

```dart
  String get _email =>
      Get.find<AuthenticationController>().currentUser.value?.email ?? '';

  Future<void> hold() async {
    if (!actions.contains(SoAction.hold)) return;
    final reason = await showHoldReasonSheet();
    if (reason == null || reason.isEmpty) return;
    await _runAction(SoAction.hold,
        call: () async {
          await _provider.addHoldReason(name, reason, _email);
          await _provider.updateStatus(name, 'On Hold');
        },
        done: 'Sales Order $name put on hold');
  }

  Future<void> resume() => _runAction(SoAction.resume,
      call: () => _provider.updateStatus(name, 'Draft'),
      done: 'Sales Order $name resumed');

  Future<void> close() => _runAction(SoAction.close,
      confirm: 'Close $name? It will stop counting as pending delivery.',
      call: () => _provider.updateStatus(name, 'Closed'),
      done: 'Sales Order $name closed');

  Future<void> reopen() => _runAction(SoAction.reopen,
      call: () => _provider.updateStatus(name, 'Draft'),
      done: 'Sales Order $name re-opened');

  final isMakingDn = false.obs;

  Future<void> makeDeliveryNote() async {
    if (!actions.contains(SoAction.makeDn) || isActing.value != null) return;
    isActing.value = SoAction.makeDn.name;
    isMakingDn.value = true;
    banner.value = null;
    try {
      final dn = await _provider.makeDeliveryNote(name);
      Get.toNamed(AppRoutes.DELIVERY_NOTE_FORM,
          arguments: {'name': dn, 'mode': 'edit'});
    } on DioException catch (e) {
      banner.value = ItemFormController.parseServerMessage(e.response?.data);
    } catch (e) {
      banner.value = e.toString();
    } finally {
      isActing.value = null;
      isMakingDn.value = false;
    }
  }
```

The hold confirm uses the sheet itself, so `_runAction` has no `confirm` here. Also check that `_runAction`'s `actions.contains(a)` is still true after the sheet closes. It will be, since nothing reloads in between.

- [ ] **Step 3: Screen action surface.** In `DocTypeFormHeader.extraActions`, before `RealtimeSyncStatusIcon`, add one `_SoActionsMenu` widget whose **own** `Obx` reads `controller.actions` and `controller.isActing.value` (the header's `shouldRebuild` keys on action count). It renders a `PopupMenuButton<SoAction>` (icon `Icons.more_vert`, or a 16px `CircularProgressIndicator` while `isActing != null`) with an entry for each allowed action except `save`/`submit`: Hold / Resume / Close / Re-open / Cancel / Create Delivery Note. It is hidden (`SizedBox.shrink()`) when the set is empty. `onSelected` switches to the matching controller method. The destructive entries (Close, Cancel) use `AppColors.red700` / `red300` text by brightness.

  Also, as with PO's receipt button: on the Details tab, when `actions.contains(SoAction.makeDn)`, show a full-width `AsyncFilledButton` "Create Delivery Note" at the bottom. Pass it `busy: controller.isMakingDn`.

- [ ] **Step 4: Verify**

Run: `flutter analyze lib/app/modules/selling`
Expected: no new issues.

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add lib/app/modules/selling/sales_order
git commit -m "feat(sales-order): hold/resume/close/re-open and make delivery note

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Link-ups (drawer, permissions, search, dashboard, digest, reservation)

**Files:**
- Modify: `lib/app/data/constants/permission_entries.dart:48-57`
- Modify: `lib/app/modules/global_widgets/app_nav_drawer.dart` (Selling group, ~line 417, after POS Upload and before `// ── Selling > Pricing`)
- Modify: `lib/app/data/constants/global_search_targets.dart` (after the Purchase Order target, ~line 98)
- Modify: `lib/app/modules/home/widgets/dashboard_actionable_strip.dart` (`actionableFiltersFor`, `kActionableDocConfigs`)
- Modify: `lib/app/modules/home/widgets/dashboard_actionable_preview.dart` (`docRowFor`)
- Modify: `lib/app/data/services/digest_service.dart` (`kDigestDoctypes`), `lib/app/data/services/storage_service.dart:198-205` (default keys)
- Modify: `lib/app/modules/stock/reports/stock_balance/stock_balance_sheets.dart:380-420`
- Test: `test/unit/actionable_filters_test.dart`, `test/unit/dashboard_actionable_preview_test.dart`, `test/unit/storage_digest_prefs_test.dart`, `test/widget/stock_balance_reservation_tap_test.dart`

**Interfaces:**
- Consumes: `AppRoutes.SALES_ORDER(_FORM)`, `kSoOpenToDeliverStatuses`.
- Produces: none.

- [ ] **Step 1: Write the failing tests first.** Add to `test/unit/actionable_filters_test.dart`:

```dart
    test('Sales Order filters on draft + to-deliver statuses', () {
      expect(actionableFiltersFor('Sales Order', ActionableScope.everyone, 'x@y.com'), {
        'status': ['in', ['Draft', 'To Deliver and Bill', 'To Deliver']],
      });
      expect(actionableFiltersFor('Sales Order', ActionableScope.mine, 'a@b.com'), {
        'status': ['in', ['Draft', 'To Deliver and Bill', 'To Deliver']],
        'owner': 'a@b.com',
      });
    });
```

Add to `test/unit/dashboard_actionable_preview_test.dart` (match the file's existing `docRowFor` call style):

```dart
    test('Sales Order row: customer · owner · delivery date · status', () {
      final row = docRowFor('Sales Order', {
        'name': 'SAL-ORD-2026-00012', 'customer_name': 'Cust One',
        'owner': 'a@b.com', 'delivery_date': '2026-09-25', 'status': 'To Deliver',
      }, (o) => 'A');
      expect(row.subtitle, 'Cust One · A · 25 Sep · To Deliver');
    });
```

In `test/unit/storage_digest_prefs_test.dart`, update the default-keys expectation to include `'sales_order'` after `'purchase_order'`. Open the file and edit the list literal it asserts.

Run: `flutter test test/unit/actionable_filters_test.dart test/unit/dashboard_actionable_preview_test.dart test/unit/storage_digest_prefs_test.dart`
Expected: the three new or changed expectations FAIL.

- [ ] **Step 2: Permissions.** Append to `kSellingPermissions`:

```dart
  (doctype: 'Sales Order',  permType: 'read'),   // Selling › Sales Order
  (doctype: 'Sales Order',  permType: 'create'), // New Sales Order FAB
  (doctype: 'Sales Order',  permType: 'write'),  // Draft edit
  // submit/cancel are checked per document (has_permission) — PermissionService
  // would probe them with a read-level get_list and wrongly pass Stock Users.
```

- [ ] **Step 3: Drawer.** Insert after the POS Upload `DocTypeGuard`:

```dart
                      DocTypeGuard(
                        doctype: 'Sales Order',
                        loading: skeleton,
                        child: _DrawerItem(
                          title: 'Sales Order',
                          icon: Icons.request_quote_rounded,
                          route: AppRoutes.SALES_ORDER,
                          currentRoute: currentRoute,
                        ),
                      ),
```

- [ ] **Step 4: Global search.** After the Purchase Order target:

```dart
  GlobalSearchTarget(
    doctype: 'Sales Order',
    label: 'Sales Orders',
    icon: Icons.request_quote_outlined,
    color: Colors.teal,
    route: AppRoutes.SALES_ORDER_FORM,
    argsFor: _nameView,
  ),
```

(`Colors.teal` follows the neighbouring targets' convention. Check that `test/unit/global_search_targets_test.dart` only asserts uniqueness; it does at line 12.)

- [ ] **Step 5: Dashboard strip.** In `actionableFiltersFor`, before the `else`, add a Sales Order branch, and update the doc comment:

```dart
  if (doctype == 'Stock Entry' || doctype == 'Packing Slip') {
    filters['docstatus'] = 0;
  } else if (doctype == 'Sales Order') {
    // Actionable SOs: still Draft, or submitted and awaiting delivery.
    filters['status'] = ['in', kSoOpenToDeliverStatuses];
  } else {
    filters['status'] = 'Draft';
  }
```

Import `sales_order_logic.dart` for `kSoOpenToDeliverStatuses`. Append to `kActionableDocConfigs`, **after Delivery Note and before Packing Slip**:

```dart
  ActionableDocConfig(
    doctype: 'Sales Order',
    label: 'Sales Order',
    icon: Icons.request_quote_outlined,
    listRoute: AppRoutes.SALES_ORDER,
    formRoute: AppRoutes.SALES_ORDER_FORM,
    previewFields: ['name', 'customer_name', 'delivery_date', 'status', 'owner'],
  ),
```

- [ ] **Step 6: Preview row.** In `docRowFor`, add a case, and append the status segment for SO only (every other previewed doctype is a Draft, but SO mixes statuses):

```dart
    case 'Sales Order':
      party = s('customer_name');
      date = _shortDate(s('delivery_date'));
      break;
```

and change the segments line to:

```dart
  final segments = [
    party,
    ownerLabel(s('owner')),
    date,
    if (doctype == 'Sales Order') s('status'),
  ].where((p) => p.isNotEmpty).toList();
```

- [ ] **Step 7: Digest.** In `kDigestDoctypes`, after `purchase_order`:

```dart
  DigestDoctype(
    key: 'sales_order',
    doctype: 'Sales Order',
    singular: 'draft Sales Order',
    plural: 'draft Sales Orders',
    filters: {'docstatus': 0},
  ),
```

In `StorageService.getDigestDoctypes` defaults, add `'sales_order'` after `'purchase_order'`. Existing users with a saved list won't get it until they tick it in Notification settings. Check that the settings screen renders every `kDigestDoctypes` entry: `grep -n "kDigestDoctypes" lib/app/modules/notification_settings -r`. If it hard-codes a list instead, add SO there.

- [ ] **Step 8: Run the Step 1 tests**

Run: `flutter test test/unit/actionable_filters_test.dart test/unit/dashboard_actionable_preview_test.dart test/unit/storage_digest_prefs_test.dart test/unit/home_controller_actionable_test.dart test/unit/notification_settings_controller_test.dart test/unit/digest_service_test.dart`
Expected: PASS. `home_controller_actionable_test` scales with `kActionableDocConfigs.length`, so it should pass unchanged. If a digest or notification test hard-codes the five keys, update its literal to include `sales_order`.

- [ ] **Step 9: Reservation row → SO. Write the failing widget test** at `test/widget/stock_balance_reservation_tap_test.dart`. First read `stock_balance_sheets.dart:340-360` and `:570-590` to get the exact public constructor of the reservations sheet (the class at line ~343 whose `reservations` field is `List<Map<String,dynamic>>`), then:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_sheets.dart';

void main() {
  testWidgets('tapping a reservation opens its Sales Order', (tester) async {
    Map? pushedArgs;
    await tester.pumpWidget(GetMaterialApp(
      getPages: [
        GetPage(name: '/', page: () => Scaffold(body: /* <ReservationsSheetClass>( */
          // itemCode: 'I1', itemName: 'Item 1', reserved: 5,
          // reservations: [{'voucher_no': 'SAL-ORD-2026-00012', 'status': 'Reserved', 'reserved': 5}],
          /* ) */ const SizedBox())),
        GetPage(name: AppRoutes.SALES_ORDER_FORM, page: () {
          pushedArgs = Get.arguments as Map?;
          return const Scaffold(body: Text('SO FORM'));
        }),
      ],
    ));
    await tester.tap(find.text('SAL-ORD-2026-00012'));
    await tester.pumpAndSettle();
    expect(find.text('SO FORM'), findsOneWidget);
    expect(pushedArgs, {'name': 'SAL-ORD-2026-00012', 'mode': 'view'});
  });
}
```

Replace the commented block with the real sheet constructor you read. The shape of the test is fixed: tapping the voucher text navigates to `SALES_ORDER_FORM` with `{name, mode: 'view'}`.

Run: `flutter test test/widget/stock_balance_reservation_tap_test.dart`
Expected: FAIL (the row isn't tappable).

- [ ] **Step 10: Make the row tappable.** In the reservations `itemBuilder` (~line 381), wrap the row's `Padding` in:

```dart
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: voucher.isEmpty
                              ? null
                              : () {
                                  Get.back(); // close the sheet first
                                  Get.toNamed(AppRoutes.SALES_ORDER_FORM,
                                      arguments: {'name': voucher, 'mode': 'view'});
                                },
                          child: Padding( … existing row … ),
                        ),
                      );
```

and add a trailing `Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant)` after the qty `Text`. Only do this when the SRE's `voucher_type` is Sales Order: check what `ApiProvider.getStockReservations` returns (line ~1905). If it selects `voucher_type`, guard with `r['voucher_type'] == 'Sales Order'`; if not, add `voucher_type` to its fields list. Add imports for `get` and `app_routes` if they're missing. Don't `dart format` this file.

Run: `flutter test test/widget/stock_balance_reservation_tap_test.dart`
Expected: PASS.

- [ ] **Step 11: Commit**

```bash
git branch --show-current
git add lib/app/data/constants lib/app/modules/global_widgets/app_nav_drawer.dart lib/app/modules/home/widgets lib/app/data/services lib/app/modules/stock/reports/stock_balance/stock_balance_sheets.dart lib/app/data/providers/api_provider.dart test/unit test/widget/stock_balance_reservation_tap_test.dart
git commit -m "feat(sales-order): drawer, search, dashboard chip, digest, reservation link

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: Full verification against baseline

- [ ] **Step 1: Analyze** (nothing else running)

```bash
flutter analyze > "$SCRATCH/analyze_after.txt" 2>&1; tail -3 "$SCRATCH/analyze_after.txt"
```

Expected: issue count ≤ baseline and no issues in any file this plan touched (`grep -E "sales_order|link_search_sheet|status_pill|stock_balance_sheets|dashboard_actionable|digest_service|permission_entries|global_search_targets|app_nav_drawer" "$SCRATCH/analyze_after.txt"` prints nothing).

- [ ] **Step 2: Full suite, after analyze has finished**

```bash
flutter test --reporter expanded > "$SCRATCH/test_after.txt" 2>&1; tail -5 "$SCRATCH/test_after.txt"
grep -E "^\s*[0-9:]+ \+[0-9]+ ?-?[0-9]*: .* \[E\]" "$SCRATCH/test_after.txt" | sed 's/^.*: //' | sort -u > "$SCRATCH/test_after_failures.txt"
comm -13 "$SCRATCH/test_baseline_failures.txt" "$SCRATCH/test_after_failures.txt"
```

Expected: `comm` prints nothing (no new failures). If "Failed to load" errors appear, see the memory note: `dart pub cache repair`, then rerun.

---

### Task 9: Device smoke (side-by-side install)

Temporary edits, **reverted before any commit**: in `android/app/build.gradle*` add `applicationIdSuffix ".smokeso"` to the build type used, and set the launcher label to `MM SO smoke`. The device is shared with other sessions, so check `adb shell dumpsys package com.ddmco.multimax.smokeso | grep versionCode` before assuming the installed build is ours. Never install over or uninstall `com.ddmco.multimax`.

Pre-smoke (server, done by the **user**): enable Stock Settings → Stock Reservation for the reservation step, and pick 3 items with **no** Item Reorder rows. Confirm with `frappe.client.get_count('Item Reorder', {parent: code})` = 0.

- [ ] **Step 1: Build and install**

```bash
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

- [ ] **Step 2: Checklist, run as Sales User (asrar) and as an account with System Manager + Sales User, in light and dark**
  - [ ] Drawer: Selling › Sales Order appears above Pricing. Global search finds an SO.
  - [ ] List: status chips, Mine/Everyone, filter sheet (customer, delivery range, status), search, "End of list", progress bars on submitted rows.
  - [ ] New SO: customer → price list fills; add 3+ items (rate prefilled from the price list, editable, estimate tile); Save → server totals and VAT columns render; header delivery date = latest row date.
  - [ ] Dirty guard: edit then back → discard prompt.
  - [ ] Validation: row date before order date → sheet stays open with the v15 message.
  - [ ] Submit → status To Deliver and Bill; menu shows Hold / Close / Cancel / Create DN.
  - [ ] Hold (reason required; comment visible on desk) → On Hold → Resume → back to To Deliver and Bill.
  - [ ] Close → Closed → Re-open.
  - [ ] Create Delivery Note → our DN form opens on a Draft DN linked to the SO.
  - [ ] Stock Balance → reserved chip → tap reservation → SO opens (reservation enabled; submit an SO with Reserve Stock ticked on desk first).
  - [ ] Dashboard: Sales Order chip counts Draft + To Deliver; preview rows open the SO.
  - [ ] A Stock User account: list is read-only, no FAB, no action menu.
- [ ] **Step 3: Clean up the live site.** Cancel the smoke SOs, delete the smoke draft DNs, and the **user** disables Stock Reservation again.
- [ ] **Step 4: Revert the temporary gradle/label edits.** `git diff android/` must be empty.

---

### Task 10: Release + memory

- [ ] **Step 1: Branch and tags**

```bash
git fetch origin --tags
git branch --show-current                        # claude/sales-order-doctype
git log --oneline origin/release/play-store -1   # still 9074fe26? if not, rebase onto it and rerun Task 8
git describe --tags --abbrev=0 origin/release/play-store
```

- [ ] **Step 2: Bump.** Follow `docs/versioning_conventions.md`: the range has `feat:`, so it's **MINOR**, giving `2.22.0+(B+1)` from the latest tag. If `dart run tool/bump_version.dart` suggests otherwise, override it with the MINOR flag. Commit as `chore(release): 2.22.0+69` (or whatever number is next).
- [ ] **Step 3: Land on release/play-store and tag.** Fast-forward `release/play-store` to this branch (or merge `--no-ff` if it moved), tag `v2.22.0+69`, and push the branch and the tag **together**:

```bash
git push origin release/play-store v2.22.0+69
```

- [ ] **Step 4: Watch CI** (`gh run list --workflow release.yml -L 1`, then `gh run watch <id>`) until it succeeds.
- [ ] **Step 5: Memory.** Write `project-sales-order-doctype.md` in the memory dir with the release version, tag, CI run id, smoke result, and these v15 gotchas: SM has no SO DocPerm; `update_status` needs submit; Resume/Re-open send Draft; Hold = add_comment + update_status; `editable_price_list_rate` only unlocks price_list_rate; the header delivery date is the latest row date; `PermissionService` can't answer submit/cancel. Add the one-line pointer to `MEMORY.md`.
