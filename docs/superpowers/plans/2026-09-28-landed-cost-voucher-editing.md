# Landed Cost Voucher — Create, Edit & Submit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the read-only Landed Cost Voucher (LCV) viewer shipped in v2.27.0 into a full mobile flow: create a voucher, edit a draft (receipts + charges), save, and submit.

**Architecture:** The app edits only what a person decides — posting date, distribution basis, which Purchase Receipts, and which charges. ERPNext derives the rest on save: it fills the `items` table from the receipts *when that table is empty*, and re-spreads the charges across items on every save. So the app never edits item rows. When the set of receipts changes, it sends `items: []` so the server rebuilds them; otherwise it sends the existing rows back unchanged. All decision logic sits in one pure file (`lcv_rules.dart`) so it can be unit-tested without GetX.

**Tech Stack:** Flutter, GetX (controllers/bindings/Obx), Dio via `ApiProvider`, Frappe REST (`/api/resource/Landed Cost Voucher`), `flutter_test`.

**Spec:** No separate spec file. The decisions below were agreed in chat on 2026-09-28 and form the spec:

| Decision | Choice |
|---|---|
| Scope | Create + edit draft + save + submit. **Cancel stays in Desk.** |
| Distribution | `Qty` and `Amount` only. A voucher set to `Distribute Manually` (in Desk) opens **read-only** in the app. |
| Receipt types | `Purchase Receipt` only. Existing vouchers that link a Purchase Invoice still display. |

ERPNext v15 server behaviour this plan relies on (from `erpnext/stock/doctype/landed_cost_voucher/landed_cost_voucher.py`):
- `validate()` raises "Please enter Receipt Document" when `purchase_receipts` is empty.
- It rejects receipts that are not submitted or belong to another company.
- If `items` is empty it calls `get_items_from_purchase_receipts()`, then `set_applicable_charges_on_item()` distributes by Qty/Amount.
- `supplier`, `posting_date`, `grand_total` on receipt rows are **read-only and filled by Desk JavaScript**, not the server — so the app must fetch and send them itself.
- `expense_account` on a charge row is required when perpetual inventory is on (it is on this instance), and must belong to the voucher's company.

**Branch:** `feat/landed-cost-voucher-editing`, cut from `origin/release/play-store` at `724fb9a3` (v2.27.0+88). **Do not** build on the old `landed-cost-voucher` branch; it holds debug commits and was superseded.

## Global Constraints

- Follow `CLAUDE.md` — GetX patterns, the async-feedback rule (guard + disable + visible spinner), and the contrast rules (no hardcoded surface/ink colours; use `colorScheme.surface`, `scheme.text`/`textMuted`).
- Header observables must be read in the `Obx` builder body, **not** inside `headerSliverBuilder` (NestedScrollView calls that closure later, so Obx would not track it) — see `stock_entry_form_screen.dart:47-51`.
- Save and Submit are mutually exclusive in the header: Save appears only while dirty; Submit only on a clean, saved draft (SE convention).
- Company is never editable in the app; a new voucher takes `StorageService.getCompany()`.
- Receipt rows use `receipt_document_type: 'Purchase Receipt'`.
- Version bump: **MINOR** → `2.28.0+89` (new flow) — follow `docs/versioning_conventions.md`.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Receipts change after items were loaded** — ERPNext only rebuilds items when the table is empty, so a stale item list would be distributed against the wrong receipts. Expect: any receipt add/remove sends `items: []`. *Pinned in Task 1 (payload) and Task 3 (controller).*
2. **A draft, cancelled, or other-company Purchase Receipt is picked** — expect a clear message, and the row is not added (not a server error on save). *Pinned in Task 1 and Task 3.*
3. **Voucher set to "Distribute Manually" in Desk** — saving from the app would overwrite hand-entered per-item charges. Expect: read-only, with an explanation. *Pinned in Task 1 and Task 4.*
4. **Double-tap on Save or Submit** — expect exactly one request. *Pinned in Task 3.*
5. **Someone edited the voucher in Desk meanwhile** — expect the version-conflict dialog, not a silent overwrite; this requires `modified` in the save body. *Pinned in Task 1 (payload carries `modified`); the dialog itself is the existing `OptimisticLockingMixin`.*

---

## File Structure

| File | Responsibility |
|---|---|
| Create `lib/app/modules/landed_cost_voucher/form/lcv_rules.dart` | Pure rules: editability, submit gate, receipt rejection, save blockers, save payload. |
| Modify `lib/app/data/providers/landed_cost_voucher_provider.dart` | Add create/update/submit/canSubmit, receipt summary, default charge account. |
| Create `test/helpers/fake_lcv_provider.dart` | Shared in-memory provider fake + sample voucher for all LCV tests. |
| Modify `lib/app/modules/landed_cost_voucher/form/landed_cost_voucher_form_controller.dart` | Draft state, add/remove receipts & charges, save, submit. |
| Create `lib/app/modules/landed_cost_voucher/form/widgets/lcv_charge_sheet.dart` | Bottom sheet to add/edit one charge. |
| Modify `lib/app/modules/landed_cost_voucher/form/landed_cost_voucher_form_screen.dart` | Wire header Save/Submit, editable Details/Receipts/Taxes tabs. |
| Modify `lib/app/modules/landed_cost_voucher/landed_cost_voucher_screen.dart` + `landed_cost_voucher_controller.dart` | Create FAB (guarded), refresh after returning from form. |
| Modify `lib/app/data/constants/permission_entries.dart` | Resolve LCV `create`/`write` at login. |
| Tests: `test/unit/lcv_rules_test.dart`, `test/unit/lcv_form_controller_test.dart`, `test/widget/lcv_charge_sheet_test.dart`, `test/widget/landed_cost_voucher_viewer_test.dart` (updated) | |

---

### Task 1: Pure rules and save payload

**Files:**
- Create: `lib/app/modules/landed_cost_voucher/form/lcv_rules.dart`
- Test: `test/unit/lcv_rules_test.dart`

**Interfaces:**
- Consumes: `LandedCostPurchaseReceipt`, `LandedCostTaxesAndCharges`, `LandedCostItem` from `lib/app/data/models/landed_cost_voucher_model.dart` (unchanged).
- Produces:
  - `const String kLcvReceiptType = 'Purchase Receipt'`
  - `const String kLcvManualDistribution = 'Distribute Manually'`
  - `const List<String> kLcvDistributionOptions = ['Qty', 'Amount']`
  - `bool lcvIsEditable({required int? docStatus, required String distributeChargesBasedOn})`
  - `bool lcvCanSubmit({required bool isNew, required int? docStatus, required bool isDirty, required bool isSaving, required bool isSubmitting, required bool canSubmitPerm})`
  - `String? lcvReceiptRejection({required Map<String, dynamic> receipt, required String company, required Iterable<String> alreadyAdded})`
  - `String? lcvSaveBlocker({required List<LandedCostPurchaseReceipt> receipts, required List<LandedCostTaxesAndCharges> charges})`
  - `Map<String, dynamic> buildLcvPayload({required String company, required String postingDate, required String distributeChargesBasedOn, required List<LandedCostPurchaseReceipt> receipts, required List<LandedCostTaxesAndCharges> charges, required List<LandedCostItem> items, required bool receiptsChanged, String? modified})`

- [ ] **Step 1: Write the failing test**

Create `test/unit/lcv_rules_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/landed_cost_voucher_model.dart';
import 'package:multimax/app/modules/landed_cost_voucher/form/lcv_rules.dart';

LandedCostPurchaseReceipt _receipt(String doc, {String? name}) =>
    LandedCostPurchaseReceipt(
      name: name,
      receiptDocumentType: kLcvReceiptType,
      receiptDocument: doc,
      supplier: 'Acme',
      postingDate: '2026-09-20',
      grandTotal: 1000,
    );

LandedCostTaxesAndCharges _charge({
  String? name,
  String description = 'Freight',
  double amount = 150,
  String? account = 'Freight - KA',
}) =>
    LandedCostTaxesAndCharges(
      name: name,
      description: description,
      amount: amount,
      expenseAccount: account,
      exchangeRate: 1,
      baseAmount: amount,
    );

final _item = LandedCostItem(
  name: 'row-item-1',
  itemCode: 'WATCH-001',
  receiptDocumentType: kLcvReceiptType,
  receiptDocument: 'MAT-PRE-0001',
  qty: 10,
  rate: 100,
  amount: 1000,
  applicableCharges: 150,
  purchaseReceiptItem: 'pri-1',
  costCenter: 'Main - KA',
);

void main() {
  group('lcvIsEditable', () {
    test('only drafts with an automatic basis are editable', () {
      expect(lcvIsEditable(docStatus: 0, distributeChargesBasedOn: 'Qty'), isTrue);
      expect(lcvIsEditable(docStatus: 0, distributeChargesBasedOn: 'Amount'), isTrue);
      expect(lcvIsEditable(docStatus: 1, distributeChargesBasedOn: 'Qty'), isFalse);
      expect(lcvIsEditable(docStatus: 2, distributeChargesBasedOn: 'Qty'), isFalse);
      expect(lcvIsEditable(docStatus: null, distributeChargesBasedOn: 'Qty'), isFalse);
    });

    test('a manually distributed draft stays read-only', () {
      expect(
        lcvIsEditable(docStatus: 0, distributeChargesBasedOn: kLcvManualDistribution),
        isFalse,
      );
    });
  });

  group('lcvCanSubmit', () {
    bool can({
      bool isNew = false,
      int? docStatus = 0,
      bool isDirty = false,
      bool isSaving = false,
      bool isSubmitting = false,
      bool perm = true,
    }) =>
        lcvCanSubmit(
          isNew: isNew,
          docStatus: docStatus,
          isDirty: isDirty,
          isSaving: isSaving,
          isSubmitting: isSubmitting,
          canSubmitPerm: perm,
        );

    test('a clean saved draft with permission can be submitted', () {
      expect(can(), isTrue);
    });

    test('anything else cannot', () {
      expect(can(isNew: true), isFalse);
      expect(can(docStatus: 1), isFalse);
      expect(can(isDirty: true), isFalse);
      expect(can(isSaving: true), isFalse);
      expect(can(isSubmitting: true), isFalse);
      expect(can(perm: false), isFalse);
    });
  });

  group('lcvReceiptRejection', () {
    Map<String, dynamic> pr({int docstatus = 1, String company = 'KA'}) => {
          'name': 'MAT-PRE-0002',
          'docstatus': docstatus,
          'company': company,
        };

    test('a submitted receipt of the same company is accepted', () {
      expect(
        lcvReceiptRejection(receipt: pr(), company: 'KA', alreadyAdded: const []),
        isNull,
      );
    });

    test('duplicates, drafts, cancelled and other-company receipts are rejected', () {
      expect(
        lcvReceiptRejection(
            receipt: pr(), company: 'KA', alreadyAdded: const ['MAT-PRE-0002']),
        contains('already'),
      );
      expect(
        lcvReceiptRejection(receipt: pr(docstatus: 0), company: 'KA', alreadyAdded: const []),
        contains('not submitted'),
      );
      expect(
        lcvReceiptRejection(receipt: pr(docstatus: 2), company: 'KA', alreadyAdded: const []),
        contains('not submitted'),
      );
      expect(
        lcvReceiptRejection(receipt: pr(company: 'Other'), company: 'KA', alreadyAdded: const []),
        contains('Other'),
      );
    });
  });

  group('lcvSaveBlocker', () {
    test('needs a receipt and a complete charge', () {
      expect(lcvSaveBlocker(receipts: const [], charges: [_charge()]),
          contains('Purchase Receipt'));
      expect(lcvSaveBlocker(receipts: [_receipt('A')], charges: const []),
          contains('charge'));
      expect(lcvSaveBlocker(receipts: [_receipt('A')], charges: [_charge(amount: 0)]),
          contains('amount'));
      expect(lcvSaveBlocker(receipts: [_receipt('A')], charges: [_charge(description: ' ')]),
          contains('description'));
      expect(lcvSaveBlocker(receipts: [_receipt('A')], charges: [_charge(account: null)]),
          contains('expense account'));
      expect(lcvSaveBlocker(receipts: [_receipt('A')], charges: [_charge()]), isNull);
    });
  });

  group('buildLcvPayload', () {
    Map<String, dynamic> build({required bool receiptsChanged, String? modified}) =>
        buildLcvPayload(
          company: 'KA',
          postingDate: '2026-09-28',
          distributeChargesBasedOn: 'Amount',
          receipts: [
            _receipt('MAT-PRE-0001', name: 'row-pr-1'),
            _receipt('MAT-PRE-0002', name: 'local_123'),
          ],
          charges: [_charge(name: 'row-tax-1'), _charge(name: 'local_456')],
          items: [_item],
          receiptsChanged: receiptsChanged,
          modified: modified,
        );

    test('changed receipts make the server rebuild items', () {
      expect(build(receiptsChanged: true)['items'], isEmpty);
    });

    test('unchanged receipts send the existing item rows back', () {
      final items = build(receiptsChanged: false)['items'] as List;
      expect(items.single['name'], 'row-item-1');
      expect(items.single['purchase_receipt_item'], 'pri-1');
    });

    test('server row names are kept and local ones dropped', () {
      final p = build(receiptsChanged: false);
      final prs = p['purchase_receipts'] as List;
      expect(prs[0]['name'], 'row-pr-1');
      expect(prs[1].containsKey('name'), isFalse);
      expect(prs[1]['receipt_document_type'], 'Purchase Receipt');
      expect(prs[1]['supplier'], 'Acme');
      final taxes = p['taxes'] as List;
      expect(taxes[0]['name'], 'row-tax-1');
      expect(taxes[1].containsKey('name'), isFalse);
      expect(taxes[1]['expense_account'], 'Freight - KA');
    });

    test('header fields and the optimistic-lock timestamp are sent', () {
      final p = build(receiptsChanged: false, modified: '2026-09-28 10:00:00.000');
      expect(p['company'], 'KA');
      expect(p['posting_date'], '2026-09-28');
      expect(p['distribute_charges_based_on'], 'Amount');
      expect(p['modified'], '2026-09-28 10:00:00.000');
      expect(build(receiptsChanged: false).containsKey('modified'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/lcv_rules_test.dart`
Expected: FAIL — compile error, `lcv_rules.dart` not found.

- [ ] **Step 3: Write the implementation**

Create `lib/app/modules/landed_cost_voucher/form/lcv_rules.dart`:

```dart
import 'package:multimax/app/data/models/landed_cost_voucher_model.dart';

/// The only receipt type the app links; Purchase Invoices stay in Desk.
const String kLcvReceiptType = 'Purchase Receipt';

const String kLcvManualDistribution = 'Distribute Manually';

/// Bases the app can edit. Manual distribution needs per-item charge entry,
/// which stays in Desk, so such vouchers open read-only.
const List<String> kLcvDistributionOptions = ['Qty', 'Amount'];

bool lcvIsEditable({
  required int? docStatus,
  required String distributeChargesBasedOn,
}) =>
    docStatus == 0 && distributeChargesBasedOn != kLcvManualDistribution;

/// A voucher may be submitted only when it is a saved, clean draft the user
/// is permitted to submit, with no save/submit already running.
bool lcvCanSubmit({
  required bool isNew,
  required int? docStatus,
  required bool isDirty,
  required bool isSaving,
  required bool isSubmitting,
  required bool canSubmitPerm,
}) =>
    !isNew &&
    docStatus == 0 &&
    !isDirty &&
    !isSaving &&
    !isSubmitting &&
    canSubmitPerm;

/// Why [receipt] (a Purchase Receipt summary with `name`, `docstatus` and
/// `company`) cannot be added, or null if it can. Mirrors the checks ERPNext
/// runs on save so the user hears about them at pick time.
String? lcvReceiptRejection({
  required Map<String, dynamic> receipt,
  required String company,
  required Iterable<String> alreadyAdded,
}) {
  final name = receipt['name'] as String? ?? '';
  if (alreadyAdded.contains(name)) return '$name is already on this voucher';
  if (receipt['docstatus'] != 1) return '$name is not submitted';
  final owner = receipt['company'] as String? ?? '';
  if (owner != company) return '$name belongs to $owner, not $company';
  return null;
}

/// The first reason the voucher cannot be saved yet, or null.
String? lcvSaveBlocker({
  required List<LandedCostPurchaseReceipt> receipts,
  required List<LandedCostTaxesAndCharges> charges,
}) {
  if (receipts.isEmpty) return 'Add at least one Purchase Receipt';
  if (charges.isEmpty) return 'Add at least one charge';
  for (final c in charges) {
    if (c.description.trim().isEmpty || c.amount <= 0) {
      return 'Every charge needs a description and an amount above zero';
    }
    if ((c.expenseAccount ?? '').isEmpty) {
      return 'Every charge needs an expense account';
    }
  }
  return null;
}

/// Builds the save body.
///
/// ERPNext fills `items` from the linked receipts only when that table is
/// empty, and re-spreads the charges across items on every save. So when
/// the receipt set changed we send `items: []` to make the server rebuild
/// them; otherwise we send the existing rows back untouched.
Map<String, dynamic> buildLcvPayload({
  required String company,
  required String postingDate,
  required String distributeChargesBasedOn,
  required List<LandedCostPurchaseReceipt> receipts,
  required List<LandedCostTaxesAndCharges> charges,
  required List<LandedCostItem> items,
  required bool receiptsChanged,
  String? modified,
}) {
  bool isServerRow(String? name) => name != null && !name.startsWith('local_');

  return {
    'company': company,
    'posting_date': postingDate,
    'distribute_charges_based_on': distributeChargesBasedOn,
    if (modified != null && modified.isNotEmpty) 'modified': modified,
    'purchase_receipts': [
      for (final r in receipts)
        {
          if (isServerRow(r.name)) 'name': r.name,
          'receipt_document_type': r.receiptDocumentType,
          'receipt_document': r.receiptDocument,
          if (r.supplier != null) 'supplier': r.supplier,
          if (r.postingDate != null) 'posting_date': r.postingDate,
          'grand_total': r.grandTotal,
        },
    ],
    'taxes': [
      for (final c in charges)
        {
          if (isServerRow(c.name)) 'name': c.name,
          'description': c.description,
          'amount': c.amount,
          if (c.expenseAccount != null) 'expense_account': c.expenseAccount,
        },
    ],
    'items': receiptsChanged
        ? <Map<String, dynamic>>[]
        : [for (final i in items) i.toJson()],
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/lcv_rules_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/landed_cost_voucher/form/lcv_rules.dart test/unit/lcv_rules_test.dart
git commit -m "feat(landed-cost-voucher): pure edit/submit rules and save payload

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Provider write methods + shared test fake

**Files:**
- Modify: `lib/app/data/providers/landed_cost_voucher_provider.dart`
- Create: `test/helpers/fake_lcv_provider.dart`
- Modify: `test/widget/landed_cost_voucher_viewer_test.dart` (use the shared fake)

**Interfaces:**
- Consumes: `ApiProvider.createDocument/updateDocument/submitDocument/getDocumentList/getDocument/hasDocPermission`, `ApiProvider.parseHasDocPermissionResponse` (all existing).
- Produces (on `LandedCostVoucherProvider`):
  - `Future<Response> createLandedCostVoucher(Map<String, dynamic> data)`
  - `Future<Response> updateLandedCostVoucher(String name, Map<String, dynamic> data)`
  - `Future<Response> submitLandedCostVoucher(String name)`
  - `Future<bool> canSubmit(String name)` — fail-closed `false` on error
  - `Future<Map<String, dynamic>?> getReceiptSummary(String receiptName)` — keys `name, supplier, posting_date, grand_total, company, docstatus`; null if not found
  - `Future<String?> getDefaultChargeAccount(String company)` — Company's `expenses_included_in_valuation`; null on any failure
- Produces (test helper): `Map<String, dynamic> sampleLcv({int docstatus = 1, String distribute = 'Qty'})`, `class FakeLcvProvider implements LandedCostVoucherProvider` with fields `voucher`, `receipts`, `saved`, `submitCalls`, `submitAllowed`, `saveGate`.

- [ ] **Step 1: Add the provider methods**

Append inside `LandedCostVoucherProvider` (after `getLandedCostVoucher`):

```dart
  Future<Response> createLandedCostVoucher(Map<String, dynamic> data) =>
      _apiProvider.createDocument('Landed Cost Voucher', data);

  Future<Response> updateLandedCostVoucher(
          String name, Map<String, dynamic> data) =>
      _apiProvider.updateDocument('Landed Cost Voucher', name, data);

  Future<Response> submitLandedCostVoucher(String name) =>
      _apiProvider.submitDocument('Landed Cost Voucher', name);

  Future<bool> canSubmit(String name) async {
    try {
      final res = await _apiProvider.hasDocPermission(
          'Landed Cost Voucher', name, 'submit');
      return ApiProvider.parseHasDocPermissionResponse(res.data);
    } catch (_) {
      return false;
    }
  }

  /// The fields Desk copies onto a receipt row (supplier, posting date,
  /// grand total) plus what the app needs to validate the pick. The server
  /// does not fill these, so the app must send them.
  Future<Map<String, dynamic>?> getReceiptSummary(String receiptName) async {
    final res = await _apiProvider.getDocumentList(
      'Purchase Receipt',
      filters: {'name': receiptName},
      fields: const [
        'name',
        'supplier',
        'posting_date',
        'grand_total',
        'company',
        'docstatus',
      ],
      limit: 1,
    );
    final rows = res.data?['data'] as List?;
    if (res.statusCode != 200 || rows == null || rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first as Map);
  }

  /// The company's "Expenses Included In Valuation" account — the usual
  /// home for landed costs — used to prefill a new charge. Null when the
  /// user cannot read Company or the field is unset.
  Future<String?> getDefaultChargeAccount(String company) async {
    try {
      final res = await _apiProvider.getDocument('Company', company);
      final account =
          res.data?['data']?['expenses_included_in_valuation'] as String?;
      return (account == null || account.isEmpty) ? null : account;
    } catch (_) {
      return null;
    }
  }
```

- [ ] **Step 2: Create the shared fake**

Create `test/helpers/fake_lcv_provider.dart`:

```dart
// test/helpers/fake_lcv_provider.dart
//
// In-memory LandedCostVoucherProvider shared by the LCV tests. Save calls
// record their payload and echo it back the way ERPNext would (items are
// rebuilt only when the payload sends an empty table).
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:multimax/app/data/providers/landed_cost_voucher_provider.dart';

Map<String, dynamic> sampleLcv({int docstatus = 1, String distribute = 'Qty'}) => {
      'name': 'MAT-LCV-2026-00001',
      'company': 'KA',
      'docstatus': docstatus,
      'status': docstatus == 1 ? 'Submitted' : 'Draft',
      'modified': '2026-09-26 10:00:00.000',
      'posting_date': '2026-09-26',
      'distribute_charges_based_on': distribute,
      'total_taxes_and_charges': 150.0,
      'purchase_receipts': [
        {
          'name': 'row-pr-1',
          'receipt_document_type': 'Purchase Receipt',
          'receipt_document': 'MAT-PRE-0001',
          'supplier': 'Acme',
          'grand_total': 1000.0,
        },
      ],
      'items': [
        {
          'name': 'row-item-1',
          'item_code': 'WATCH-001',
          'description': 'Steel watch',
          'receipt_document_type': 'Purchase Receipt',
          'receipt_document': 'MAT-PRE-0001',
          'qty': 10,
          'rate': 100.0,
          'amount': 1000.0,
          'applicable_charges': 150.0,
        },
      ],
      'taxes': [
        {
          'name': 'row-tax-1',
          'description': 'Freight',
          'amount': 150.0,
          'expense_account': 'Freight - KA',
        },
      ],
    };

Response<dynamic> _ok(dynamic data) => Response(
      requestOptions: RequestOptions(path: ''),
      statusCode: 200,
      data: {'data': data},
    );

class FakeLcvProvider implements LandedCostVoucherProvider {
  FakeLcvProvider({Map<String, dynamic>? voucher})
      : voucher = voucher ?? sampleLcv();

  Map<String, dynamic> voucher;

  /// Purchase Receipt summaries by name, for [getReceiptSummary].
  final Map<String, Map<String, dynamic>> receipts = {};

  /// Every create/update payload, in order.
  final List<Map<String, dynamic>> saved = [];
  int submitCalls = 0;
  bool submitAllowed = true;

  /// When set, create/update wait on it — lets a test hold a save in flight.
  Completer<void>? saveGate;

  Future<Response> _save(Map<String, dynamic> data, {String? newName}) async {
    saved.add(data);
    await saveGate?.future;
    voucher = {
      ...voucher,
      ...data,
      if (newName != null) 'name': newName,
      'docstatus': 0,
      'status': 'Draft',
      'modified': '2026-09-28 12:00:0${saved.length}.000',
    };
    return _ok(voucher);
  }

  @override
  Future<Response> getLandedCostVouchers({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    String orderBy = 'modified desc',
  }) async =>
      _ok([voucher]);

  @override
  Future<Response> getLandedCostVoucher(String name) async => _ok(voucher);

  @override
  Future<Response> createLandedCostVoucher(Map<String, dynamic> data) =>
      _save(data, newName: 'MAT-LCV-2026-00002');

  @override
  Future<Response> updateLandedCostVoucher(
          String name, Map<String, dynamic> data) =>
      _save(data);

  @override
  Future<Response> submitLandedCostVoucher(String name) async {
    submitCalls++;
    voucher = {...voucher, 'docstatus': 1, 'status': 'Submitted'};
    return _ok(voucher);
  }

  @override
  Future<bool> canSubmit(String name) async => submitAllowed;

  @override
  Future<Map<String, dynamic>?> getReceiptSummary(String receiptName) async =>
      receipts[receiptName];

  @override
  Future<String?> getDefaultChargeAccount(String company) async =>
      'Expenses Included In Valuation - $company';
}
```

- [ ] **Step 3: Point the viewer test at the shared fake**

In `test/widget/landed_cost_voucher_viewer_test.dart`:
- Delete the local `_voucher` map, the `_ok` helper, and the `_FakeLcvProvider` class.
- Add `import '../helpers/fake_lcv_provider.dart';`
- In `setUp`, replace `Get.put<LandedCostVoucherProvider>(_FakeLcvProvider());` with `Get.put<LandedCostVoucherProvider>(FakeLcvProvider());`
- In the model test, replace `LandedCostVoucher.fromJson(_voucher)` with `LandedCostVoucher.fromJson(sampleLcv())`.
- Remove the now-unused `package:dio/dio.dart` import if the analyzer flags it.

- [ ] **Step 4: Run analyzer and the existing viewer test**

Run: `flutter analyze lib/app/data/providers/landed_cost_voucher_provider.dart test/helpers/fake_lcv_provider.dart test/widget/landed_cost_voucher_viewer_test.dart && flutter test test/widget/landed_cost_voucher_viewer_test.dart`
Expected: No issues; all 4 existing tests PASS (behaviour unchanged).

- [ ] **Step 5: Commit**

```bash
git add lib/app/data/providers/landed_cost_voucher_provider.dart test/helpers/fake_lcv_provider.dart test/widget/landed_cost_voucher_viewer_test.dart
git commit -m "feat(landed-cost-voucher): provider create/update/submit and receipt lookup

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Form controller — draft state, save, submit

**Files:**
- Modify (full rewrite): `lib/app/modules/landed_cost_voucher/form/landed_cost_voucher_form_controller.dart`
- Test: `test/unit/lcv_form_controller_test.dart`

**Interfaces:**
- Consumes: everything from Task 1 and Task 2; `OptimisticLockingMixin` (`checkStaleAndBlock`, `handleVersionConflict`, abstract `reloadDocument`); `PermissionService.hasAccess(doctype, permType:)`; `StorageService.getCompany()`; `GlobalSnackbar.success/error/warning(message:)`; `GlobalDialog.confirm(...)`, `GlobalDialog.showUnsavedChanges(onDiscard:)`; `SaveResult` from `lib/app/data/enums/save_result.dart`.
- Produces (used by Task 4/5):
  - ctor `LandedCostVoucherFormController({String? name, String? mode, String? defaultCompany})` — defaults read `Get.arguments['name'|'mode']`
  - `String name`, `String mode`, `bool get isNew`
  - Rx: `isLoading`, `isSaving`, `isSubmitting`, `isDirty`, `isAddingReceipt`, `canSubmitPerm`, `saveResult`, `voucher`, `docMeta`, `isMetaLoaded`, `postingDate` (RxString), `distributeChargesBasedOn` (RxString), `receipts` (RxList), `charges` (RxList)
  - getters: `company`, `totalCharges`, `isEditable`, `isManualDistribution`, `canSubmit`
  - methods: `fetchDocument()`, `reloadDocument()`, `setPostingDate(String)`, `setDistribution(String)`, `addReceipt(String)`, `removeReceipt(LandedCostPurchaseReceipt)`, `upsertCharge(LandedCostTaxesAndCharges, {int? index})`, `removeCharge(int)`, `defaultChargeAccount()`, `saveDocument()`, `submitDocument()` (asks), `performSubmit()` (no dialog), `confirmDiscard()`

- [ ] **Step 1: Write the failing test**

Create `test/unit/lcv_form_controller_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/landed_cost_voucher_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/landed_cost_voucher_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/landed_cost_voucher/form/landed_cost_voucher_form_controller.dart';

import '../helpers/fake_lcv_provider.dart';

class _StubPermissionService extends PermissionService {
  @override
  bool? hasAccess(String doctype, {String permType = 'read'}) => true;
}

LandedCostTaxesAndCharges _charge() => LandedCostTaxesAndCharges(
      description: 'Customs',
      amount: 80,
      expenseAccount: 'Customs - KA',
      exchangeRate: 1,
      baseAmount: 80,
    );

void main() {
  late FakeLcvProvider fake;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => r'C:\temp\test_cookies',
    );
  });

  setUp(() {
    Get.testMode = true;
    Get.put(ApiProvider());
    Get.put<PermissionService>(_StubPermissionService());
    fake = FakeLcvProvider(voucher: sampleLcv(docstatus: 0))
      ..receipts['MAT-PRE-0002'] = {
        'name': 'MAT-PRE-0002',
        'supplier': 'Globex',
        'posting_date': '2026-09-21',
        'grand_total': 500.0,
        'company': 'KA',
        'docstatus': 1,
      }
      ..receipts['MAT-PRE-DRAFT'] = {
        'name': 'MAT-PRE-DRAFT',
        'company': 'KA',
        'docstatus': 0,
      };
    Get.put<LandedCostVoucherProvider>(fake);
  });
  tearDown(Get.reset);

  /// Controllers show snackbars, which need an overlay; host them in an app.
  Future<LandedCostVoucherFormController> start(
    WidgetTester tester, {
    String name = 'MAT-LCV-2026-00001',
    String mode = 'edit',
  }) async {
    await tester.pumpWidget(const GetMaterialApp(home: SizedBox()));
    final c = Get.put(LandedCostVoucherFormController(
        name: name, mode: mode, defaultCompany: 'KA'));
    await tester.pumpAndSettle();
    return c;
  }

  /// Let snackbar timers run out so the test ends with none pending.
  Future<void> settle(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 5));

  testWidgets('loads a draft as editable and clean', (tester) async {
    final c = await start(tester);
    expect(c.isEditable, isTrue);
    expect(c.isDirty.value, isFalse);
    expect(c.receipts.single.receiptDocument, 'MAT-PRE-0001');
    expect(c.canSubmit, isTrue);
    await settle(tester);
  });

  testWidgets('adding a receipt fills its details and makes items rebuild',
      (tester) async {
    final c = await start(tester);
    await c.addReceipt('MAT-PRE-0002');
    expect(c.receipts.last.supplier, 'Globex');
    expect(c.receipts.last.grandTotal, 500.0);
    expect(c.isDirty.value, isTrue);
    expect(c.canSubmit, isFalse);

    await c.saveDocument();
    expect(fake.saved.single['items'], isEmpty);
    expect(fake.saved.single['modified'], '2026-09-26 10:00:00.000');
    expect(c.isDirty.value, isFalse);
    await settle(tester);
  });

  testWidgets('a draft receipt is rejected and nothing is added',
      (tester) async {
    final c = await start(tester);
    await c.addReceipt('MAT-PRE-DRAFT');
    expect(c.receipts.length, 1);
    expect(c.isDirty.value, isFalse);
    await settle(tester);
  });

  testWidgets('a charge-only edit keeps the existing item rows',
      (tester) async {
    final c = await start(tester);
    c.upsertCharge(_charge());
    await c.saveDocument();
    final items = fake.saved.single['items'] as List;
    expect(items.single['name'], 'row-item-1');
    expect((fake.saved.single['taxes'] as List).length, 2);
    await settle(tester);
  });

  testWidgets('a double-tapped save sends one request', (tester) async {
    final c = await start(tester);
    c.upsertCharge(_charge());
    fake.saveGate = Completer<void>();
    final first = c.saveDocument();
    final second = c.saveDocument();
    fake.saveGate!.complete();
    await Future.wait([first, second]);
    expect(fake.saved.length, 1);
    await settle(tester);
  });

  testWidgets('a new voucher is created, then becomes an edit',
      (tester) async {
    final c = await start(tester, name: '', mode: 'new');
    expect(c.company, 'KA');
    expect(c.isEditable, isTrue);
    await c.addReceipt('MAT-PRE-0002');
    c.upsertCharge(_charge());
    await c.saveDocument();
    expect(fake.saved.single.containsKey('modified'), isFalse);
    expect(c.name, 'MAT-LCV-2026-00002');
    expect(c.isNew, isFalse);
    await settle(tester);
  });

  testWidgets('save is blocked until the voucher is complete',
      (tester) async {
    final c = await start(tester, name: '', mode: 'new');
    c.upsertCharge(_charge());
    await c.saveDocument();
    expect(fake.saved, isEmpty);
    await settle(tester);
  });

  testWidgets('submit runs once and leaves the voucher read-only',
      (tester) async {
    final c = await start(tester);
    await Future.wait([c.performSubmit(), c.performSubmit()]);
    expect(fake.submitCalls, 1);
    expect(c.voucher.value!.docstatus, 1);
    expect(c.isEditable, isFalse);
    await settle(tester);
  });

  testWidgets('a manually distributed draft is read-only', (tester) async {
    fake.voucher = sampleLcv(docstatus: 0, distribute: 'Distribute Manually');
    final c = await start(tester);
    expect(c.isEditable, isFalse);
    await c.addReceipt('MAT-PRE-0002');
    expect(c.receipts.length, 1);
    await settle(tester);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/lcv_form_controller_test.dart`
Expected: FAIL — compile errors (no such constructor params / methods).

- [ ] **Step 3: Rewrite the controller**

Replace the whole of `lib/app/modules/landed_cost_voucher/form/landed_cost_voucher_form_controller.dart` with:

```dart
import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:intl/intl.dart';
import 'package:multimax/app/data/enums/save_result.dart';
import 'package:multimax/app/data/mixins/optimistic_locking_mixin.dart';
import 'package:multimax/app/data/models/landed_cost_voucher_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/landed_cost_voucher_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/landed_cost_voucher/form/lcv_rules.dart';

/// Loads, creates, edits and submits one Landed Cost Voucher.
///
/// The app edits the header, the receipt list and the charges. ERPNext
/// derives the item rows and each item's share of the charges on save, so
/// this controller never edits items — see [buildLcvPayload]. Cancel stays
/// in Desk.
class LandedCostVoucherFormController extends GetxController
    with OptimisticLockingMixin {
  LandedCostVoucherFormController({
    String? name,
    String? mode,
    String? defaultCompany,
  })  : name = name ?? Get.arguments?['name'] ?? '',
        mode = mode ?? Get.arguments?['mode'] ?? 'view',
        _defaultCompany = defaultCompany;

  final LandedCostVoucherProvider _provider =
      Get.find<LandedCostVoucherProvider>();
  final String? _defaultCompany;

  String name;
  String mode;
  bool get isNew => mode == 'new';

  final isLoading = true.obs;
  final isSaving = false.obs;
  final isSubmitting = false.obs;
  final isDirty = false.obs;
  final isAddingReceipt = false.obs;
  final canSubmitPerm = false.obs;
  final saveResult = SaveResult.idle.obs;

  final voucher = Rx<LandedCostVoucher?>(null);
  final docMeta = <String, dynamic>{}.obs;
  final isMetaLoaded = false.obs;

  // Editable draft state, re-seeded from [voucher] on every load.
  final postingDate = ''.obs;
  final distributeChargesBasedOn = 'Qty'.obs;
  final receipts = <LandedCostPurchaseReceipt>[].obs;
  final charges = <LandedCostTaxesAndCharges>[].obs;

  /// Set when a receipt is added or removed since the last load; tells
  /// [buildLcvPayload] to have the server rebuild the item rows.
  bool _receiptsChanged = false;
  String? _defaultChargeAccount;

  String get company => voucher.value?.company ?? '';

  double get totalCharges => charges.fold(0.0, (sum, c) => sum + c.amount);

  bool get _canWrite =>
      isNew ||
      Get.find<PermissionService>()
              .hasAccess('Landed Cost Voucher', permType: 'write') ==
          true;

  bool get isEditable =>
      _canWrite &&
      lcvIsEditable(
        docStatus: voucher.value?.docstatus,
        distributeChargesBasedOn: distributeChargesBasedOn.value,
      );

  bool get isManualDistribution =>
      distributeChargesBasedOn.value == kLcvManualDistribution;

  bool get canSubmit => lcvCanSubmit(
        isNew: isNew,
        docStatus: voucher.value?.docstatus,
        isDirty: isDirty.value,
        isSaving: isSaving.value,
        isSubmitting: isSubmitting.value,
        canSubmitPerm: canSubmitPerm.value,
      );

  @override
  void onInit() {
    super.onInit();
    _fetchMeta();
    if (isNew) {
      _initNew();
    } else {
      fetchDocument();
    }
  }

  Future<void> _fetchMeta() async {
    try {
      final res =
          await Get.find<ApiProvider>().getDocTypeMeta('Landed Cost Voucher');
      if (res.statusCode == 200 &&
          res.data['docs'] != null &&
          res.data['docs'].isNotEmpty) {
        docMeta.value = res.data['docs'][0];
        isMetaLoaded.value = true;
      }
    } catch (e) {
      // Labels fall back to their defaults when meta cannot be loaded.
    }
  }

  void _initNew() {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final v = LandedCostVoucher(
      name: 'New Landed Cost Voucher',
      owner: null,
      creation: today,
      modified: '',
      status: 'Draft',
      docstatus: 0,
      company: _defaultCompany ?? Get.find<StorageService>().getCompany(),
      postingDate: today,
      distributeChargesBasedOn: kLcvDistributionOptions.first,
      totalTaxesAndCharges: 0,
      purchaseReceipts: [],
      items: [],
      taxes: [],
    );
    voucher.value = v;
    _loadDraft(v);
    isLoading.value = false;
  }

  void _loadDraft(LandedCostVoucher v) {
    postingDate.value = v.postingDate;
    distributeChargesBasedOn.value = v.distributeChargesBasedOn;
    receipts.assignAll(v.purchaseReceipts);
    charges.assignAll(v.taxes);
    _receiptsChanged = false;
    isDirty.value = false;
  }

  Future<void> fetchDocument() async {
    isLoading.value = true;
    try {
      final response = await _provider.getLandedCostVoucher(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        final v = LandedCostVoucher.fromJson(response.data['data']);
        voucher.value = v;
        _loadDraft(v);
      } else {
        GlobalSnackbar.error(message: 'Failed to load document');
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Error loading document: $e');
    } finally {
      isLoading.value = false;
    }
    await _refreshSubmitPermission();
  }

  /// Only saved drafts can be submitted; everything else is fail-closed.
  Future<void> _refreshSubmitPermission() async {
    final v = voucher.value;
    if (isNew || v == null || v.docstatus != 0) {
      canSubmitPerm.value = false;
      return;
    }
    canSubmitPerm.value = await _provider.canSubmit(name);
  }

  @override
  Future<void> reloadDocument() async {
    await fetchDocument();
    GlobalSnackbar.success(message: 'Document reloaded');
  }

  void _markDirty() {
    if (!isLoading.value && isEditable) isDirty.value = true;
  }

  // ── Header fields ───────────────────────────────────────────────────────

  void setPostingDate(String date) {
    if (!isEditable || date == postingDate.value) return;
    postingDate.value = date;
    _markDirty();
  }

  void setDistribution(String basis) {
    if (!isEditable || !kLcvDistributionOptions.contains(basis)) return;
    if (basis == distributeChargesBasedOn.value) return;
    distributeChargesBasedOn.value = basis;
    _markDirty();
  }

  // ── Receipts ────────────────────────────────────────────────────────────

  /// Looks up [receiptName], checks it the way ERPNext will on save, and adds
  /// it with the supplier/date/total Desk would have filled in.
  Future<void> addReceipt(String receiptName) async {
    if (!isEditable || isAddingReceipt.value) return;
    if (checkStaleAndBlock()) return;
    isAddingReceipt.value = true;
    try {
      final summary = await _provider.getReceiptSummary(receiptName);
      if (summary == null) {
        GlobalSnackbar.error(message: 'Could not load $receiptName');
        return;
      }
      final rejection = lcvReceiptRejection(
        receipt: summary,
        company: company,
        alreadyAdded: receipts.map((r) => r.receiptDocument),
      );
      if (rejection != null) {
        GlobalSnackbar.warning(message: rejection);
        return;
      }
      receipts.add(LandedCostPurchaseReceipt(
        name: 'local_${DateTime.now().microsecondsSinceEpoch}',
        receiptDocumentType: kLcvReceiptType,
        receiptDocument: receiptName,
        supplier: summary['supplier'] as String?,
        postingDate: summary['posting_date'] as String?,
        grandTotal: (summary['grand_total'] as num?)?.toDouble() ?? 0.0,
      ));
      _receiptsChanged = true;
      _markDirty();
    } catch (e) {
      GlobalSnackbar.error(message: 'Could not load $receiptName: $e');
    } finally {
      isAddingReceipt.value = false;
    }
  }

  void removeReceipt(LandedCostPurchaseReceipt receipt) {
    if (!isEditable) return;
    receipts.remove(receipt);
    _receiptsChanged = true;
    _markDirty();
  }

  // ── Charges ─────────────────────────────────────────────────────────────

  void upsertCharge(LandedCostTaxesAndCharges charge, {int? index}) {
    if (!isEditable) return;
    if (index == null) {
      charges.add(charge);
    } else {
      charges[index] = charge;
    }
    _markDirty();
  }

  void removeCharge(int index) {
    if (!isEditable) return;
    charges.removeAt(index);
    _markDirty();
  }

  Future<String?> defaultChargeAccount() async =>
      _defaultChargeAccount ??= await _provider.getDefaultChargeAccount(company);

  // ── Save / Submit ───────────────────────────────────────────────────────

  Future<void> saveDocument() async {
    if (isSaving.value || !isEditable) return;
    if (checkStaleAndBlock()) return;
    final blocker = lcvSaveBlocker(receipts: receipts, charges: charges);
    if (blocker != null) {
      GlobalSnackbar.warning(message: blocker);
      return;
    }

    isSaving.value = true;
    final data = buildLcvPayload(
      company: company,
      postingDate: postingDate.value,
      distributeChargesBasedOn: distributeChargesBasedOn.value,
      receipts: receipts,
      charges: charges,
      items: voucher.value?.items ?? const [],
      receiptsChanged: _receiptsChanged,
      modified: isNew ? null : voucher.value?.modified,
    );

    try {
      final res = isNew
          ? await _provider.createLandedCostVoucher(data)
          : await _provider.updateLandedCostVoucher(name, data);
      if (res.statusCode == 200 && res.data['data'] != null) {
        if (isNew) {
          name = res.data['data']['name'] as String;
          mode = 'edit';
        }
        // Reload so the user sees the items and allocated charges ERPNext
        // just computed.
        await fetchDocument();
        saveResult.value = SaveResult.success;
        GlobalSnackbar.success(message: 'Landed Cost Voucher saved');
      } else {
        saveResult.value = SaveResult.error;
        GlobalSnackbar.error(message: 'Failed to save Landed Cost Voucher');
      }
    } on DioException catch (e) {
      if (handleVersionConflict(e)) return;
      saveResult.value = SaveResult.error;
      GlobalSnackbar.error(message: _dioMessage(e, 'Save failed'));
    } catch (e) {
      saveResult.value = SaveResult.error;
      GlobalSnackbar.error(message: 'Save failed: $e');
    } finally {
      isSaving.value = false;
    }
  }

  /// Header Submit: confirm like Desk does, then [performSubmit].
  Future<void> submitDocument() async {
    if (!canSubmit) return;
    final confirmed = await GlobalDialog.confirm(
      title: 'Confirm',
      message: 'Permanently Submit $name? '
          'This updates the valuation of the linked receipts.',
      confirmText: 'Yes',
    );
    if (confirmed != true) return;
    await performSubmit();
  }

  Future<void> performSubmit() async {
    if (!canSubmit) return;
    isSubmitting.value = true;
    try {
      final res = await _provider.submitLandedCostVoucher(name);
      if (res.statusCode == 200) {
        await fetchDocument(); // docstatus 1 → read-only, perm refreshed
        GlobalSnackbar.success(message: 'Landed Cost Voucher $name submitted');
      } else {
        GlobalSnackbar.error(message: 'Failed to submit Landed Cost Voucher');
      }
    } on DioException catch (e) {
      if (handleVersionConflict(e)) return;
      GlobalSnackbar.error(message: _dioMessage(e, 'Submit failed'));
    } catch (e) {
      GlobalSnackbar.error(message: 'Submit failed: $e');
    } finally {
      isSubmitting.value = false;
    }
  }

  static String _dioMessage(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map) {
      if (data['exception'] != null) {
        return data['exception'].toString().split(':').last.trim();
      }
      if (data['_server_messages'] != null) {
        return 'Validation Error: Check form details';
      }
    }
    return fallback;
  }

  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        isDirty.value = false;
        Get.back();
      },
    );
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/unit/lcv_form_controller_test.dart test/unit/lcv_rules_test.dart test/widget/landed_cost_voucher_viewer_test.dart`
Expected: all PASS. If a test fails with "A Timer is still pending", raise the `settle` duration to cover the snackbar's display time — don't delete the snackbar.

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/landed_cost_voucher/form/landed_cost_voucher_form_controller.dart test/unit/lcv_form_controller_test.dart
git commit -m "feat(landed-cost-voucher): editable draft state, save and submit

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Charge sheet + editable form screen

**Files:**
- Create: `lib/app/modules/landed_cost_voucher/form/widgets/lcv_charge_sheet.dart`
- Modify (full rewrite): `lib/app/modules/landed_cost_voucher/form/landed_cost_voucher_form_screen.dart`
- Test: `test/widget/lcv_charge_sheet_test.dart`; extend `test/widget/landed_cost_voucher_viewer_test.dart`

**Interfaces:**
- Consumes: Task 3 controller API; `LinkFieldWidget(controller:, labelText:, hintText:, prefixIcon:, onTap:, isRequired:)`; `showLinkSearchSheet(doctype:, title:, onSelected:, filters:)`; `showOptionPickerSheet(context, title:, options:, selected:, onSelected:)`; `DocPickerField(label:, icon:, value:, onTap:)`; `DocTypeFormHeader` (save/submit params).
- Produces: `Future<void> showLcvChargeSheet({required String company, LandedCostTaxesAndCharges? initial, Future<String?> Function()? defaultAccount, required ValueChanged<LandedCostTaxesAndCharges> onSaved})` and widget `LcvChargeSheet` (same params except `onSaved` is called then the sheet pops).

- [ ] **Step 1: Write the failing charge-sheet test**

Create `test/widget/lcv_charge_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/landed_cost_voucher_model.dart';
import 'package:multimax/app/modules/landed_cost_voucher/form/widgets/lcv_charge_sheet.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget sheet) =>
      tester.pumpWidget(GetMaterialApp(home: Scaffold(body: sheet)));

  testWidgets('save is enabled only once the charge is complete, and it '
      'returns the charge', (tester) async {
    LandedCostTaxesAndCharges? result;
    await pump(
      tester,
      LcvChargeSheet(
        company: 'KA',
        defaultAccount: () async => 'Expenses Included In Valuation - KA',
        onSaved: (c) => result = c,
      ),
    );
    await tester.pumpAndSettle();

    FilledButton save() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save Charge'));
    expect(save().onPressed, isNull);

    await tester.enterText(find.widgetWithText(TextField, 'Description *'), 'Freight');
    await tester.enterText(find.widgetWithText(TextField, 'Amount *'), '120.5');
    await tester.pump();
    expect(save().onPressed, isNotNull);

    await tester.tap(find.text('Save Charge'));
    await tester.pumpAndSettle();
    expect(result!.description, 'Freight');
    expect(result!.amount, 120.5);
    expect(result!.expenseAccount, 'Expenses Included In Valuation - KA');
  });

  testWidgets('editing keeps the server row name', (tester) async {
    LandedCostTaxesAndCharges? result;
    await pump(
      tester,
      LcvChargeSheet(
        company: 'KA',
        initial: LandedCostTaxesAndCharges(
          name: 'row-tax-1',
          description: 'Freight',
          amount: 150,
          expenseAccount: 'Freight - KA',
          exchangeRate: 1,
          baseAmount: 150,
        ),
        onSaved: (c) => result = c,
      ),
    );
    await tester.enterText(find.widgetWithText(TextField, 'Amount *'), '175');
    await tester.pump();
    await tester.tap(find.text('Save Charge'));
    await tester.pumpAndSettle();
    expect(result!.name, 'row-tax-1');
    expect(result!.amount, 175);
    expect(result!.expenseAccount, 'Freight - KA');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/widget/lcv_charge_sheet_test.dart`
Expected: FAIL — `lcv_charge_sheet.dart` not found.

- [ ] **Step 3: Create the charge sheet**

Create `lib/app/modules/landed_cost_voucher/form/widgets/lcv_charge_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/landed_cost_voucher_model.dart';
import 'package:multimax/app/modules/global_widgets/link_field_widget.dart';
import 'package:multimax/app/modules/global_widgets/link_search_sheet.dart';

Future<void> showLcvChargeSheet({
  required String company,
  LandedCostTaxesAndCharges? initial,
  Future<String?> Function()? defaultAccount,
  required ValueChanged<LandedCostTaxesAndCharges> onSaved,
}) =>
    Get.bottomSheet(
      LcvChargeSheet(
        company: company,
        initial: initial,
        defaultAccount: defaultAccount,
        onSaved: onSaved,
      ),
      isScrollControlled: true,
    );

/// Add or edit one landed-cost charge: description, amount, expense account.
/// A new charge's account is prefilled from [defaultAccount].
class LcvChargeSheet extends StatefulWidget {
  final String company;
  final LandedCostTaxesAndCharges? initial;
  final Future<String?> Function()? defaultAccount;
  final ValueChanged<LandedCostTaxesAndCharges> onSaved;

  const LcvChargeSheet({
    super.key,
    required this.company,
    this.initial,
    this.defaultAccount,
    required this.onSaved,
  });

  @override
  State<LcvChargeSheet> createState() => _LcvChargeSheetState();
}

class _LcvChargeSheetState extends State<LcvChargeSheet> {
  late final TextEditingController _description;
  late final TextEditingController _amount;
  late final TextEditingController _account;

  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    _description = TextEditingController(text: c?.description ?? '');
    _amount = TextEditingController(
        text: c == null ? '' : c.amount.toString());
    _account = TextEditingController(text: c?.expenseAccount ?? '');
    for (final t in [_description, _amount, _account]) {
      t.addListener(() => setState(() {}));
    }
    if (c == null && widget.defaultAccount != null) {
      widget.defaultAccount!().then((acc) {
        if (mounted && acc != null && _account.text.isEmpty) {
          _account.text = acc;
        }
      });
    }
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    _account.dispose();
    super.dispose();
  }

  double get _amountValue => double.tryParse(_amount.text.trim()) ?? 0;

  bool get _valid =>
      _description.text.trim().isNotEmpty &&
      _amountValue > 0 &&
      _account.text.isNotEmpty;

  void _save() {
    final base = widget.initial;
    widget.onSaved(LandedCostTaxesAndCharges(
      name: base?.name ?? 'local_${DateTime.now().microsecondsSinceEpoch}',
      description: _description.text.trim(),
      amount: _amountValue,
      expenseAccount: _account.text,
      accountCurrency: base?.accountCurrency,
      exchangeRate: base?.exchangeRate ?? 1,
      baseAmount: _amountValue * (base?.exchangeRate ?? 1),
    ));
    // maybePop: never pops the root route when the sheet is hosted directly
    // (widget tests).
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.initial == null ? 'Add Charge' : 'Edit Charge',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Description *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(labelText: 'Amount *'),
            ),
            const SizedBox(height: 12),
            LinkFieldWidget(
              controller: _account,
              labelText: 'Expense Account',
              hintText: 'Select Account',
              prefixIcon: Icons.account_balance_outlined,
              isRequired: true,
              onTap: () => showLinkSearchSheet(
                doctype: 'Account',
                title: 'Expense Account',
                filters: {'company': widget.company, 'is_group': 0},
                onSelected: (acc) => _account.text = acc,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _valid ? _save : null,
              child: const Text('Save Charge'),
            ),
          ],
        ),
      ),
    );
  }
}
```

> Check `LinkSearchSheet`'s row tap: if it does not pop itself before calling `onSelected`, add `Get.back()` inside the `onSelected` lambda above. Read `link_search_sheet.dart`'s `ListTile.onTap` to decide.

- [ ] **Step 4: Run the charge-sheet test**

Run: `flutter test test/widget/lcv_charge_sheet_test.dart`
Expected: PASS.

- [ ] **Step 5: Extend the viewer test with the editing expectations (failing first)**

In `test/widget/landed_cost_voucher_viewer_test.dart`, add these tests inside `main()`:

```dart
  testWidgets('a draft shows editing controls; save appears once dirty',
      (tester) async {
    (Get.find<LandedCostVoucherProvider>() as FakeLcvProvider).voucher =
        sampleLcv(docstatus: 0);
    final c = Get.put(LandedCostVoucherFormController(
        name: 'MAT-LCV-2026-00001', mode: 'edit', defaultCompany: 'KA'));
    await tester.pumpWidget(
        const GetMaterialApp(home: LandedCostVoucherFormScreen()));
    await tester.pumpAndSettle();

    DocTypeFormHeader header() =>
        tester.widget<DocTypeFormHeader>(find.byType(DocTypeFormHeader));
    expect(header().canSave, isFalse);
    expect(header().canSubmit, isTrue);

    await tester.tap(find.text('Purchase Receipts'));
    await tester.pumpAndSettle();
    expect(find.text('Add Purchase Receipt'), findsOneWidget);

    await tester.tap(find.text('Taxes'));
    await tester.pumpAndSettle();
    expect(find.text('Add Charge'), findsOneWidget);

    c.removeCharge(0);
    await tester.pump();
    expect(header().canSave, isTrue);
    expect(header().canSubmit, isFalse);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a manually distributed draft explains why it is read-only',
      (tester) async {
    (Get.find<LandedCostVoucherProvider>() as FakeLcvProvider).voucher =
        sampleLcv(docstatus: 0, distribute: 'Distribute Manually');
    Get.put(LandedCostVoucherFormController(
        name: 'MAT-LCV-2026-00001', mode: 'edit', defaultCompany: 'KA'));
    await tester.pumpWidget(
        const GetMaterialApp(home: LandedCostVoucherFormScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('distributed manually'), findsOneWidget);
    expect(tester.widget<DocTypeFormHeader>(find.byType(DocTypeFormHeader)).onSave,
        isNull);
    await tester.tap(find.text('Taxes'));
    await tester.pumpAndSettle();
    expect(find.text('Add Charge'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });
```

Also rename the existing test `'voucher view has no save and shows allocated charges'` to `'a submitted voucher has no save and shows allocated charges'` (its expectations still hold: the default `sampleLcv()` is submitted).

Run: `flutter test test/widget/landed_cost_voucher_viewer_test.dart`
Expected: the two new tests FAIL (no "Add Purchase Receipt" / banner yet).

- [ ] **Step 6: Rewrite the form screen**

Replace the whole of `lib/app/modules/landed_cost_voucher/form/landed_cost_voucher_form_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/landed_cost_voucher_model.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/doc_picker_field.dart';
import 'package:multimax/app/modules/global_widgets/doc_section_card.dart';
import 'package:multimax/app/modules/global_widgets/doctype_form_header.dart';
import 'package:multimax/app/modules/global_widgets/link_search_sheet.dart';
import 'package:multimax/app/modules/global_widgets/option_picker_sheet.dart';
import 'package:multimax/app/modules/landed_cost_voucher/form/landed_cost_voucher_form_controller.dart';
import 'package:multimax/app/modules/landed_cost_voucher/form/lcv_rules.dart';
import 'package:multimax/app/modules/landed_cost_voucher/form/widgets/lcv_charge_sheet.dart';

/// One Landed Cost Voucher. Drafts are editable (receipts, charges, posting
/// date, Qty/Amount basis); ERPNext recomputes items and their allocated
/// charges on every save. Submitted, cancelled and manually distributed
/// vouchers are read-only. Cancel stays in Desk.
class LandedCostVoucherFormScreen
    extends GetView<LandedCostVoucherFormController> {
  const LandedCostVoucherFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final voucher = controller.voucher.value;
      final isLoading = controller.isLoading.value;
      // Read here, not inside headerSliverBuilder: NestedScrollView calls
      // that closure after this builder returns, so Obx would not track it.
      final editable = voucher != null && controller.isEditable;
      final isDirty = controller.isDirty.value;
      final isSaving = controller.isSaving.value;
      final saveResult = controller.saveResult.value;
      final isSubmitting = controller.isSubmitting.value;
      final canSubmit = controller.canSubmit;
      // The tab builders below run eagerly inside this Obx, so their reads of
      // receipts/charges/postingDate are tracked too.

      return PopScope(
        canPop: !isDirty,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          await controller.confirmDiscard();
        },
        child: DefaultTabController(
          length: 4, // Details, Purchase Receipts, Items, Taxes
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            body: NestedScrollView(
              headerSliverBuilder: (ctx, _) => [
                DocTypeFormHeader(
                  title: voucher?.name ?? 'Loading...',
                  docType: 'Landed Cost Voucher',
                  statusLabel: voucher?.status,
                  docStatus: voucher?.docstatus ?? 0,
                  onReload: isLoading || controller.isNew
                      ? null
                      : controller.reloadDocument,
                  // Save while dirty; Submit once clean (SE convention).
                  onSave: editable && isDirty ? controller.saveDocument : null,
                  canSave: editable && isDirty,
                  isSaving: isSaving,
                  saveResult: saveResult,
                  onSubmit: controller.submitDocument,
                  canSubmit: canSubmit,
                  isSubmitting: isSubmitting,
                  bottom: const TabBar(
                    isScrollable: true,
                    tabs: [
                      Tab(text: 'Details'),
                      Tab(text: 'Purchase Receipts'),
                      Tab(text: 'Items'),
                      Tab(text: 'Taxes'),
                    ],
                  ),
                ),
              ],
              body: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : voucher == null
                      ? const Center(child: Text('Document not found.'))
                      : TabBarView(
                          children: [
                            _buildDetailsView(context, editable),
                            _buildPurchaseReceiptsView(context, editable),
                            _buildItemsView(context),
                            _buildTaxesView(context, editable),
                          ],
                        ),
            ),
          ),
        ),
      );
    });
  }

  String _getLabel(String fieldname, String fallback) {
    if (controller.isMetaLoaded.value) {
      final fields = controller.docMeta['fields'] as List?;
      if (fields != null) {
        final field = fields.firstWhere(
            (f) => f['fieldname'] == fieldname,
            orElse: () => null);
        if (field != null && field['label'] != null) {
          return field['label'];
        }
      }
    }
    return fallback;
  }

  /// Bottom inset so the last row clears the system navigation bar.
  EdgeInsets _listPadding(BuildContext context, double all) =>
      EdgeInsets.fromLTRB(
          all, all, all, all + MediaQuery.of(context).padding.bottom);

  Future<void> _pickPostingDate(BuildContext context) async {
    DateTime initial;
    try {
      initial = DateFormat('yyyy-MM-dd').parse(controller.postingDate.value);
    } catch (_) {
      initial = DateTime.now();
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      controller.setPostingDate(DateFormat('yyyy-MM-dd').format(picked));
    }
  }

  Widget _buildDetailsView(BuildContext context, bool editable) {
    final v = controller.voucher.value;
    if (v == null) return const SizedBox();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return SingleChildScrollView(
      padding: _listPadding(context, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (v.docstatus == 0 && controller.isManualDistribution)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Charges on this voucher are distributed manually. '
                'Edit it in ERPNext Desk.',
                style: TextStyle(color: muted),
              ),
            ),
          DocSectionCard(
            title: 'General Information',
            children: [
              DocPickerField(
                label: _getLabel('company', 'Company'),
                value: v.company,
                icon: Icons.business,
              ),
              const SizedBox(height: 12),
              DocPickerField(
                label: _getLabel('posting_date', 'Posting Date'),
                value: controller.postingDate.value,
                icon: Icons.calendar_today_outlined,
                onTap: editable ? () => _pickPostingDate(context) : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          DocSectionCard(
            title: 'Settings',
            children: [
              DocPickerField(
                label: _getLabel('distribute_charges_based_on',
                    'Distribute Charges Based On'),
                value: controller.distributeChargesBasedOn.value,
                icon: Icons.calculate_outlined,
                onTap: editable
                    ? () => showOptionPickerSheet(
                          context,
                          title: 'Distribute Charges Based On',
                          options: kLcvDistributionOptions,
                          selected: controller.distributeChargesBasedOn.value,
                          onSelected: controller.setDistribution,
                        )
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          DocSectionCard(
            title: 'Totals',
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Taxes and Charges',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(FormattingHelper.formatAmount(controller.totalCharges)),
                ],
              ),
              if (v.totalVendorInvoicesCost != null) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total Vendor Invoices Cost',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(FormattingHelper.formatAmount(
                        v.totalVendorInvoicesCost ?? 0.0)),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _addButton(String label, VoidCallback? onPressed, {bool busy = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: OutlinedButton.icon(
          onPressed: busy ? null : onPressed,
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add),
          label: Text(label),
        ),
      );

  Widget _buildPurchaseReceiptsView(BuildContext context, bool editable) {
    final receipts = controller.receipts;
    return ListView(
      padding: _listPadding(context, 12),
      children: [
        if (editable)
          _addButton(
            'Add Purchase Receipt',
            () => showLinkSearchSheet(
              doctype: kLcvReceiptType,
              title: 'Purchase Receipt',
              filters: {'docstatus': 1, 'company': controller.company},
              onSelected: controller.addReceipt,
            ),
            busy: controller.isAddingReceipt.value,
          ),
        if (receipts.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 48),
            child: Center(child: Text('No Purchase Receipts')),
          ),
        for (final pr in receipts)
          Card(
            child: ListTile(
              title: Text(pr.receiptDocument),
              subtitle: Text(pr.supplier ?? 'No Supplier'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(FormattingHelper.formatAmount(pr.grandTotal)),
                  if (editable)
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.close),
                      onPressed: () => controller.removeReceipt(pr),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Each row shows the charge ERPNext allocated to that item — the figure
  /// a Landed Cost Voucher exists to produce. Items are server-derived, so
  /// after a receipt change they appear on the next save.
  Widget _buildItemsView(BuildContext context) {
    final v = controller.voucher.value;
    if (v == null || v.items.isEmpty) {
      return const Center(
          child: Text('No Items yet — they are filled in when you save'));
    }

    return ListView.builder(
      padding: _listPadding(context, 12),
      itemCount: v.items.length,
      itemBuilder: (context, index) {
        final item = v.items[index];
        return Card(
          child: ListTile(
            title: Text(item.itemCode),
            subtitle: Text(
              '${item.description ?? ''}\n'
              '${item.receiptDocument} · Qty ${FormattingHelper.formatQty(item.qty)}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            isThreeLine: true,
            trailing:
                Text(FormattingHelper.formatAmount(item.applicableCharges)),
          ),
        );
      },
    );
  }

  Widget _buildTaxesView(BuildContext context, bool editable) {
    final charges = controller.charges;

    void openSheet({LandedCostTaxesAndCharges? initial, int? index}) =>
        showLcvChargeSheet(
          company: controller.company,
          initial: initial,
          defaultAccount: controller.defaultChargeAccount,
          onSaved: (c) => controller.upsertCharge(c, index: index),
        );

    return ListView(
      padding: _listPadding(context, 12),
      children: [
        if (editable) _addButton('Add Charge', () => openSheet()),
        if (charges.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 48),
            child: Center(child: Text('No Taxes and Charges')),
          ),
        for (var i = 0; i < charges.length; i++)
          Card(
            child: ListTile(
              title: Text(charges[i].description),
              subtitle:
                  Text('Expense Account: ${charges[i].expenseAccount ?? 'N/A'}'),
              onTap: editable
                  ? () => openSheet(initial: charges[i], index: i)
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(FormattingHelper.formatAmount(charges[i].amount)),
                  if (editable)
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.close),
                      onPressed: () => controller.removeCharge(i),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 7: Run all LCV tests + analyzer**

Run: `flutter analyze lib/app/modules/landed_cost_voucher && flutter test test/widget/landed_cost_voucher_viewer_test.dart test/widget/lcv_charge_sheet_test.dart test/unit/lcv_form_controller_test.dart test/unit/lcv_rules_test.dart`
Expected: No issues; all PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/app/modules/landed_cost_voucher/form test/widget/lcv_charge_sheet_test.dart test/widget/landed_cost_voucher_viewer_test.dart
git commit -m "feat(landed-cost-voucher): edit receipts, charges and header on drafts

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Create entry point, permissions, list refresh

**Files:**
- Modify: `lib/app/modules/landed_cost_voucher/landed_cost_voucher_controller.dart`
- Modify: `lib/app/modules/landed_cost_voucher/landed_cost_voucher_screen.dart`
- Modify: `lib/app/data/constants/permission_entries.dart:21`
- Test: `test/widget/landed_cost_voucher_viewer_test.dart`

**Interfaces:**
- Consumes: `DocTypeGuard(doctype:, permType:, child:)`; `AppRoutes.LANDED_COST_VOUCHER_FORM`.
- Produces: `LandedCostVoucherController.openCreateForm()`, `LandedCostVoucherController.openVoucher(String name)`.

- [ ] **Step 1: Update the list test (failing first)**

In `test/widget/landed_cost_voucher_viewer_test.dart`, change the list test's name to `'list follows the list conventions and offers create'` and replace
`expect(find.byType(FloatingActionButton), findsNothing);` with
`expect(find.byType(FloatingActionButton), findsOneWidget);`.

Run: `flutter test test/widget/landed_cost_voucher_viewer_test.dart`
Expected: that test FAILS (no FAB yet).

- [ ] **Step 2: Add navigation helpers to the list controller**

In `landed_cost_voucher_controller.dart`, add `import 'package:multimax/app/data/routes/app_routes.dart';` and, after `clearFilters()`:

```dart
  void openCreateForm() => _openForm({'name': '', 'mode': 'new'});

  void openVoucher(String name) => _openForm({'name': name, 'mode': 'edit'});

  /// Refresh on return: the form may have created, saved or submitted.
  Future<void> _openForm(Map<String, String> args) async {
    await Get.toNamed(AppRoutes.LANDED_COST_VOUCHER_FORM, arguments: args);
    fetchLandedCostVouchers(clear: true);
  }
```

- [ ] **Step 3: Add the FAB and use the helper on tap**

In `landed_cost_voucher_screen.dart`:
- Add `import 'package:multimax/app/modules/global_widgets/doctype_guard.dart';`
- Update the class doc comment to: `/// List of Landed Cost Vouchers. Users with create permission get a FAB; tapping a card opens it (drafts are editable).`
- Add to `AppShellScaffold(`:

```dart
      floatingActionButton: DocTypeGuard(
        doctype: 'Landed Cost Voucher',
        permType: 'create',
        child: FloatingActionButton.extended(
          onPressed: controller.openCreateForm,
          tooltip: 'New Landed Cost Voucher',
          icon: const Icon(Icons.add),
          label: const Text('New Voucher'),
        ),
      ),
```

- Replace the card's `onTap` body (`Get.toNamed(AppRoutes.LANDED_COST_VOUCHER_FORM, arguments: {'name': voucher.name});`) with `controller.openVoucher(voucher.name);`, and remove the now-unused `app_routes.dart` import if the analyzer flags it.

- [ ] **Step 4: Resolve create/write at login**

In `lib/app/data/constants/permission_entries.dart`, change the LCV line in `kStockPermissions` to:

```dart
  (doctype: 'Landed Cost Voucher', permType: 'read'),   // Stock → Tools
  (doctype: 'Landed Cost Voucher', permType: 'create'), // New LCV FAB
  (doctype: 'Landed Cost Voucher', permType: 'write'),  // LCV draft editing
```

- [ ] **Step 5: Run the full suite + analyzer**

Run: `flutter analyze && flutter test`
Expected: No new analyzer issues; all tests PASS (including `workspace_menu_test.dart` and `global_search_targets_test.dart`).

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/landed_cost_voucher lib/app/data/constants/permission_entries.dart test/widget/landed_cost_voucher_viewer_test.dart
git commit -m "feat(landed-cost-voucher): create FAB, permission gates, list refresh

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: On-device verification and release bump

**Files:**
- Modify: `pubspec.yaml` (version, via tool)

- [ ] **Step 1: On-device smoke test against a staging/test company** (a clean `flutter analyze` proves nothing about async feedback — `CLAUDE.md`). Run `flutter run -d <device_id>` and check each item:
  1. Stock → Tools → Landed Cost Vouchers shows **New Voucher** (for a user with create permission).
  2. New voucher → Purchase Receipts → **Add Purchase Receipt** lists only submitted receipts for the session company. Picking one shows supplier + total. Picking the same one again shows "already on this voucher".
  3. Taxes → **Add Charge**: the account prefills (or can be picked). Save Charge closes the sheet.
  4. The header shows **Save** (spinner visible on the maroon header while saving). After saving, the name becomes `MAT-LCV-…`, the Items tab lists items with allocated charges that add up to the total, and the header shows **Submit**.
  5. Add a second receipt → Save → Items now include that receipt's items (the rebuild path).
  6. Change basis Qty → Amount → Save → allocations change.
  7. Edit the same draft in Desk, then Save in the app → version-conflict dialog → Reload.
  8. Submit → confirm → status Submitted, all controls gone. Check in Desk that the Purchase Receipt's item valuation increased.
  9. A voucher set to "Distribute Manually" in Desk opens read-only with the explanation.
  10. Dark mode: the charge sheet and add buttons are legible.

- [ ] **Step 2: Bump version (MINOR)**

Read `docs/versioning_conventions.md`, then run:

```bash
dart run tool/bump_version.dart
```

Expected proposal: `2.28.0+89` (feat commits since `v2.27.0`). If it agrees, run:

```bash
dart run tool/bump_version.dart --write
```

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml
git commit -m "chore(release): bump version to 2.28.0+89

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Out of scope (deliberately)

- Cancel / amend (stays in Desk).
- `Distribute Manually` editing and per-item charge entry.
- Purchase Invoice receipts; vendor-invoice table.
- Realtime sync (`RealtimeSyncMixin`) and background auto-save — explicit Save only for a valuation-changing document.
- Cleanup of the old `landed-cost-voucher` branch (separate housekeeping).
