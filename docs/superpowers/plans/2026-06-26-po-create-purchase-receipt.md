# Create Purchase Receipt from Purchase Order — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Create Purchase Receipt" action to the submitted Purchase Order form (header + Items tab) that launches the existing scan-driven, PO-bound Purchase Receipt flow, offering to resume an existing draft when one exists.

**Architecture:** Reuse the Purchase Receipt form's existing PO-binding (`purchaseOrder`/`supplier` nav args → `_initNewPurchaseReceipt` → per-scan link resolver + 417 recovery). The new work is confined to the Purchase Order form: a gated entry point, a draft-lookup provider call, and a resume-or-create sheet. No Purchase Receipt-side code changes.

**Tech Stack:** Flutter, GetX (state/DI/navigation), Dio (HTTP via `ApiProvider`), Frappe/ERPNext REST. Tests: `flutter_test`.

## Global Constraints

- KEEP MAROON theme; use `Theme.of(context).colorScheme` tokens, never hardcoded greys (dark-mode safe).
- Permission checks are **fail-closed**: deny on `null`/error, never default to allowed.
- Open-rows-only PO linking is owned by the existing resolver — do **not** add over-receipt behaviour.
- Frappe filter encoding via `ApiProvider.getDocumentList`: a 2-element value `[op, value]` becomes `[doctype, key, op, value]`; a scalar value becomes an equality filter.
- Route constants: `AppRoutes.PURCHASE_RECEIPT_FORM`, `AppRoutes.PURCHASE_ORDER_FORM`.
- `flutter analyze` must report 0 errors before each commit.

---

### Task 1: Pure helpers + unit tests

**Files:**
- Create: `lib/app/modules/purchase_order/form/po_receipt_helpers.dart`
- Test: `test/unit/po_receipt_helpers_test.dart`

**Interfaces:**
- Consumes: `PurchaseOrderItem` from `lib/app/data/models/purchase_order_model.dart` (fields used: `qty`, `receivedQty`).
- Produces:
  - `bool hasOpenReceiptQty(List<PurchaseOrderItem> items)`
  - `class DraftReceiptSummary { final String name; final String postingDate; const DraftReceiptSummary({required this.name, required this.postingDate}); }`
  - `List<String> parseDraftReceiptParents(dynamic responseData)`

- [ ] **Step 1: Write the failing test**

Create `test/unit/po_receipt_helpers_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/modules/purchase_order/form/po_receipt_helpers.dart';

PurchaseOrderItem _poItem({required double qty, required double received}) =>
    PurchaseOrderItem(
      name: 'row',
      itemCode: 'A',
      itemName: 'Item A',
      qty: qty,
      receivedQty: received,
      rate: 1,
      amount: qty,
    );

void main() {
  group('hasOpenReceiptQty', () {
    test('true when a line is partially received', () {
      expect(hasOpenReceiptQty([_poItem(qty: 10, received: 3)]), isTrue);
    });

    test('true when a line is not received at all', () {
      expect(hasOpenReceiptQty([_poItem(qty: 10, received: 0)]), isTrue);
    });

    test('false when every line is fully received', () {
      expect(hasOpenReceiptQty([_poItem(qty: 10, received: 10)]), isFalse);
    });

    test('false when over-received', () {
      expect(hasOpenReceiptQty([_poItem(qty: 10, received: 12)]), isFalse);
    });

    test('false for an empty list', () {
      expect(hasOpenReceiptQty(const []), isFalse);
    });
  });

  group('parseDraftReceiptParents', () {
    test('extracts distinct parents, order preserved', () {
      final data = {
        'data': [
          {'parent': 'PR-1'},
          {'parent': 'PR-2'},
          {'parent': 'PR-1'},
        ]
      };
      expect(parseDraftReceiptParents(data), ['PR-1', 'PR-2']);
    });

    test('skips blank/missing/non-string parents', () {
      final data = {
        'data': [
          {'parent': ''},
          {'parent': null},
          {'nope': 'x'},
          {'parent': 'PR-9'},
        ]
      };
      expect(parseDraftReceiptParents(data), ['PR-9']);
    });

    test('tolerates null / non-map / missing data key', () {
      expect(parseDraftReceiptParents(null), isEmpty);
      expect(parseDraftReceiptParents('oops'), isEmpty);
      expect(parseDraftReceiptParents({'data': 'notalist'}), isEmpty);
      expect(parseDraftReceiptParents({}), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/po_receipt_helpers_test.dart`
Expected: FAIL — `po_receipt_helpers.dart` does not exist (compile/URI error).

- [ ] **Step 3: Write minimal implementation**

Create `lib/app/modules/purchase_order/form/po_receipt_helpers.dart`:

```dart
import 'package:multimax/app/data/models/purchase_order_model.dart';

/// True when at least one PO line still has quantity left to receive
/// (received_qty < qty). Drives the "Create Purchase Receipt" action's
/// visibility — the action is hidden once the PO is fully received.
bool hasOpenReceiptQty(List<PurchaseOrderItem> items) =>
    items.any((i) => i.receivedQty < i.qty);

/// A draft Purchase Receipt linked to a Purchase Order, summarised for the
/// resume-or-create sheet.
class DraftReceiptSummary {
  final String name;
  final String postingDate;
  const DraftReceiptSummary({required this.name, required this.postingDate});
}

/// Distinct, order-preserving `parent` names from a `Purchase Receipt Item`
/// child-list response (`{"data": [{"parent": "..."}]}`). Tolerant of null,
/// non-Map payloads, and missing/blank parents.
List<String> parseDraftReceiptParents(dynamic responseData) {
  if (responseData is! Map) return const [];
  final rows = responseData['data'];
  if (rows is! List) return const [];
  final seen = <String>{};
  final out = <String>[];
  for (final r in rows) {
    if (r is! Map) continue;
    final p = r['parent'];
    if (p is! String || p.isEmpty) continue;
    if (seen.add(p)) out.add(p);
  }
  return out;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/po_receipt_helpers_test.dart`
Expected: PASS (all cases green).

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/purchase_order/form/po_receipt_helpers.dart test/unit/po_receipt_helpers_test.dart
git commit -m "feat(po): add pure helpers for receipt open-qty + draft parsing"
```

---

### Task 2: Provider — open-draft lookup

**Files:**
- Modify: `lib/app/data/providers/purchase_order_provider.dart`

**Interfaces:**
- Consumes: `parseDraftReceiptParents`, `DraftReceiptSummary` (Task 1); `ApiProvider.getDocumentList`.
- Produces: `Future<List<DraftReceiptSummary>> PurchaseOrderProvider.getOpenDraftReceiptsForPo(String poName)`.

This task is thin HTTP glue over the Task 1 parser (already unit-tested). The repo does not mock Dio in provider tests, so there is no new automated test here; correctness of the parse path is covered by Task 1, and the end-to-end path is covered by the smoke checklist in Task 6.

- [ ] **Step 1: Add the import**

At the top of `lib/app/data/providers/purchase_order_provider.dart`, after the existing imports:

```dart
import 'package:multimax/app/modules/purchase_order/form/po_receipt_helpers.dart';
```

- [ ] **Step 2: Add the method**

Inside `class PurchaseOrderProvider`, after `updatePurchaseOrder`:

```dart
  /// Open (draft, docstatus 0) Purchase Receipts that reference [poName]
  /// through any of their items, summarised for the resume-or-create sheet.
  ///
  /// Two calls: (1) the `Purchase Receipt Item` child rows carrying this PO
  /// (child rows mirror the parent's docstatus, so `docstatus == 0` selects
  /// rows of draft receipts), reduced to distinct parents; (2) those parents'
  /// headers for their posting dates. Returns an empty list when none exist.
  /// Network/parse failures propagate to the caller, which treats them as
  /// fail-open (create-new).
  Future<List<DraftReceiptSummary>> getOpenDraftReceiptsForPo(
      String poName) async {
    final childResp = await _apiProvider.getDocumentList(
      'Purchase Receipt Item',
      limit: 0,
      filters: {
        'purchase_order': poName,
        'docstatus': 0,
      },
      fields: ['parent'],
    );

    final parents = parseDraftReceiptParents(childResp.data);
    if (parents.isEmpty) return const [];

    final headerResp = await _apiProvider.getDocumentList(
      'Purchase Receipt',
      limit: 0,
      filters: {
        'name': ['in', parents],
      },
      fields: ['name', 'posting_date'],
    );

    final data = headerResp.data;
    final rows = (data is Map && data['data'] is List)
        ? data['data'] as List
        : const [];

    return rows
        .whereType<Map>()
        .map((r) => DraftReceiptSummary(
              name: (r['name'] ?? '').toString(),
              postingDate: (r['posting_date'] ?? '').toString(),
            ))
        .where((d) => d.name.isNotEmpty)
        .toList();
  }
```

- [ ] **Step 3: Verify it compiles**

Run: `flutter analyze lib/app/data/providers/purchase_order_provider.dart`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add lib/app/data/providers/purchase_order_provider.dart
git commit -m "feat(po): provider lookup for open draft receipts linked to a PO"
```

---

### Task 3: Resume-or-create sheet widget

**Files:**
- Create: `lib/app/modules/purchase_order/form/widgets/purchase_receipt_resume_sheet.dart`
- Test: `test/widget/purchase_receipt_resume_sheet_test.dart`

**Interfaces:**
- Consumes: `DraftReceiptSummary` (Task 1).
- Produces: `class PurchaseReceiptResumeSheet extends StatelessWidget` with constructor
  `PurchaseReceiptResumeSheet({Key? key, required List<DraftReceiptSummary> drafts, required void Function(String name) onResume, required VoidCallback onCreateNew})`.

The widget is self-contained (explicit params, no `Get.find`) so it is trivially testable and decoupled from the controller.

- [ ] **Step 1: Write the failing test**

Create `test/widget/purchase_receipt_resume_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/purchase_order/form/po_receipt_helpers.dart';
import 'package:multimax/app/modules/purchase_order/form/widgets/purchase_receipt_resume_sheet.dart';

Widget _host({
  required List<DraftReceiptSummary> drafts,
  void Function(String)? onResume,
  VoidCallback? onCreateNew,
}) =>
    MaterialApp(
      home: Scaffold(
        body: PurchaseReceiptResumeSheet(
          drafts: drafts,
          onResume: onResume ?? (_) {},
          onCreateNew: onCreateNew ?? () {},
        ),
      ),
    );

void main() {
  const drafts = [
    DraftReceiptSummary(name: 'PR-0001', postingDate: '2026-06-26'),
    DraftReceiptSummary(name: 'PR-0002', postingDate: '2026-06-25'),
  ];

  testWidgets('lists each draft and a create-new action', (tester) async {
    await tester.pumpWidget(_host(drafts: drafts));
    expect(find.textContaining('PR-0001'), findsOneWidget);
    expect(find.textContaining('PR-0002'), findsOneWidget);
    expect(find.text('Start a new receipt'), findsOneWidget);
  });

  testWidgets('tapping a draft fires onResume with its name', (tester) async {
    String? resumed;
    await tester.pumpWidget(_host(drafts: drafts, onResume: (n) => resumed = n));
    await tester.tap(find.textContaining('PR-0002'));
    await tester.pumpAndSettle();
    expect(resumed, 'PR-0002');
  });

  testWidgets('tapping create-new fires onCreateNew', (tester) async {
    var created = false;
    await tester.pumpWidget(
        _host(drafts: drafts, onCreateNew: () => created = true));
    await tester.tap(find.text('Start a new receipt'));
    await tester.pumpAndSettle();
    expect(created, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/purchase_receipt_resume_sheet_test.dart`
Expected: FAIL — `purchase_receipt_resume_sheet.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `lib/app/modules/purchase_order/form/widgets/purchase_receipt_resume_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:multimax/app/modules/purchase_order/form/po_receipt_helpers.dart';

/// Bottom sheet shown when a Purchase Order already has open draft Purchase
/// Receipt(s). Lets the user resume one of them or start a fresh receipt.
/// Purely presentational — all behaviour flows through [onResume] / [onCreateNew].
class PurchaseReceiptResumeSheet extends StatelessWidget {
  final List<DraftReceiptSummary> drafts;
  final void Function(String name) onResume;
  final VoidCallback onCreateNew;

  const PurchaseReceiptResumeSheet({
    super.key,
    required this.drafts,
    required this.onResume,
    required this.onCreateNew,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28.0)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
              alignment: Alignment.center,
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Text(
                'Draft Receipt Exists',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'This Purchase Order already has an unsubmitted receipt. '
                'Resume it, or start a new one.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),

            const SizedBox(height: 4),
            Divider(height: 1, color: cs.outlineVariant),

            // Draft list
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: drafts.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  indent: 72,
                  endIndent: 16,
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
                itemBuilder: (context, index) {
                  final d = drafts[index];
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: cs.primaryContainer,
                      foregroundColor: cs.onPrimaryContainer,
                      child: const Icon(Icons.edit_document, size: 20),
                    ),
                    title: Text(
                      d.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        color: cs.onSurface,
                      ),
                    ),
                    subtitle: d.postingDate.isEmpty
                        ? null
                        : Text(
                            d.postingDate,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                    trailing:
                        Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                    onTap: () => onResume(d.name),
                  );
                },
              ),
            ),

            Divider(height: 1, color: cs.outlineVariant),

            // Create-new action
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: FilledButton.icon(
                onPressed: onCreateNew,
                icon: const Icon(Icons.add),
                label: const Text('Start a new receipt'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/purchase_receipt_resume_sheet_test.dart`
Expected: PASS (all three widget tests green).

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/purchase_order/form/widgets/purchase_receipt_resume_sheet.dart test/widget/purchase_receipt_resume_sheet_test.dart
git commit -m "feat(po): resume-or-create draft receipt sheet"
```

---

### Task 4: Controller wiring

**Files:**
- Modify: `lib/app/modules/purchase_order/form/purchase_order_form_controller.dart`

**Interfaces:**
- Consumes: `hasOpenReceiptQty`, `DraftReceiptSummary` (Task 1); `PurchaseOrderProvider.getOpenDraftReceiptsForPo` (Task 2); `PurchaseReceiptResumeSheet` (Task 3); `PermissionService.hasAccess`; `AppRoutes.PURCHASE_RECEIPT_FORM`; `GlobalSnackbar`.
- Produces (used by Task 5):
  - `bool get hasOpenQty`
  - `bool get canCreateReceipt`
  - `Future<void> createPurchaseReceipt()`

- [ ] **Step 1: Add imports**

At the top of `lib/app/modules/purchase_order/form/purchase_order_form_controller.dart`, with the other imports:

```dart
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/purchase_order/form/po_receipt_helpers.dart';
import 'package:multimax/app/modules/purchase_order/form/widgets/purchase_receipt_resume_sheet.dart';
```

- [ ] **Step 2: Register the PermissionService dependency**

In the field block near the other `Get.find` services (after `_dataWedgeService`):

```dart
  final PermissionService _permissionService = Get.find<PermissionService>();
```

- [ ] **Step 3: Add getters + the action method**

Add this block immediately after the `bool get isEditable => ...` line:

```dart
  // ── Create Purchase Receipt action ──────────────────────────────────────────
  bool get hasOpenQty =>
      hasOpenReceiptQty(purchaseOrder.value?.items ?? const []);

  /// Whether the "Create Purchase Receipt" surfaces should be shown.
  /// Submitted, not closed, has open qty, and the user has PR create access.
  /// Fail-closed: a loading/`null` permission probe reads as not-allowed.
  bool get canCreateReceipt {
    final po = purchaseOrder.value;
    if (po == null) return false;
    if (po.docstatus != 1) return false;
    if (po.status == 'Closed') return false;
    if (!hasOpenQty) return false;
    return _permissionService.hasAccess('Purchase Receipt',
            permType: 'create') ==
        true;
  }

  /// Launches the PO-bound Purchase Receipt flow: offers to resume an open
  /// draft receipt if one exists, else opens a new receipt linked to this PO.
  Future<void> createPurchaseReceipt() async {
    final po = purchaseOrder.value;
    if (po == null) return;

    // Defence-in-depth: the surfaces are already gated, but never proceed
    // without create access.
    if (_permissionService.hasAccess('Purchase Receipt', permType: 'create') !=
        true) {
      GlobalSnackbar.warning(
          message: "You don't have permission to create a Purchase Receipt.");
      return;
    }

    List<DraftReceiptSummary> drafts = const [];
    try {
      drafts = await _provider.getOpenDraftReceiptsForPo(po.name);
    } catch (_) {
      // Fail-open: resume is a convenience, never a blocker for receiving.
      drafts = const [];
    }

    if (drafts.isEmpty) {
      _goToNewReceipt(po);
      return;
    }

    await Get.bottomSheet(
      PurchaseReceiptResumeSheet(
        drafts: drafts,
        onResume: (name) {
          Get.back();
          Get.toNamed(AppRoutes.PURCHASE_RECEIPT_FORM,
              arguments: {'name': name, 'mode': 'edit'});
        },
        onCreateNew: () {
          Get.back();
          _goToNewReceipt(po);
        },
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  void _goToNewReceipt(PurchaseOrder po) {
    Get.toNamed(AppRoutes.PURCHASE_RECEIPT_FORM, arguments: {
      'name': '',
      'mode': 'new',
      'purchaseOrder': po.name,
      'supplier': po.supplier,
    });
  }
```

- [ ] **Step 4: Verify it compiles**

Run: `flutter analyze lib/app/modules/purchase_order/form/purchase_order_form_controller.dart`
Expected: No errors. (`PurchaseOrder` is already imported via `purchase_order_model.dart`; `AppRoutes`, `GlobalSnackbar`, `Colors` are already imported in this file.)

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/purchase_order/form/purchase_order_form_controller.dart
git commit -m "feat(po): controller action to create/resume PO-bound receipt"
```

---

### Task 5: Screen wiring — header action + Items-tab button

**Files:**
- Modify: `lib/app/modules/purchase_order/form/purchase_order_form_screen.dart`

**Interfaces:**
- Consumes: `controller.canCreateReceipt`, `controller.createPurchaseReceipt()` (Task 4).
- Produces: user-visible entry points (no new code interface).

Both surfaces are evaluated inside the top-level `Obx` in `build` (the whole body is already reactive), so `canCreateReceipt` — which reads `purchaseOrder` and the reactive permission cache — updates the UI automatically. The Items-tab button and the `BarcodeInputWidget` are mutually exclusive: the button needs `docstatus == 1`, the scan field needs `isEditable` (`docstatus == 0`).

- [ ] **Step 1: Add the header action**

In `_build`'s `DocTypeFormHeader`, replace the `extraActions` list:

```dart
                  extraActions: [
                    RealtimeSyncStatusIcon(
                      isConnected: controller.isRealtimeConnected,
                      isSyncing:   controller.isRemoteSyncing,
                    ),
                  ],
```

with:

```dart
                  extraActions: [
                    if (controller.canCreateReceipt)
                      IconButton(
                        tooltip: 'Create Purchase Receipt',
                        icon: const Icon(Icons.receipt_long),
                        onPressed: controller.createPurchaseReceipt,
                      ),
                    RealtimeSyncStatusIcon(
                      isConnected: controller.isRealtimeConnected,
                      isSyncing:   controller.isRemoteSyncing,
                    ),
                  ],
```

- [ ] **Step 2: Add the Items-tab button**

In `_buildItemsView`, the trailing children currently are:

```dart
        if (controller.isEditable)
          Obx(() => BarcodeInputWidget(
            onScan:      (code) => controller.scanBarcode(code),
            isLoading:   controller.isScanning.value,
            controller:  controller.barcodeController,
            hintText:    'Scan Item Code',
            activeRoute: AppRoutes.PURCHASE_ORDER_FORM,
          )),
        SizedBox(height: MediaQuery.viewInsetsOf(context).bottom),
```

Insert the button between the `BarcodeInputWidget` block and the `SizedBox`:

```dart
        if (controller.isEditable)
          Obx(() => BarcodeInputWidget(
            onScan:      (code) => controller.scanBarcode(code),
            isLoading:   controller.isScanning.value,
            controller:  controller.barcodeController,
            hintText:    'Scan Item Code',
            activeRoute: AppRoutes.PURCHASE_ORDER_FORM,
          )),
        if (controller.canCreateReceipt)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.icon(
                onPressed: controller.createPurchaseReceipt,
                icon: const Icon(Icons.receipt_long),
                label: const Text('Create Purchase Receipt'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ),
        SizedBox(height: MediaQuery.viewInsetsOf(context).bottom),
```

- [ ] **Step 3: Verify it compiles**

Run: `flutter analyze lib/app/modules/purchase_order/form/purchase_order_form_screen.dart`
Expected: No errors. (`Icons`, `FilledButton`, `SafeArea`, `Padding` come from the already-imported `material.dart`.)

- [ ] **Step 4: Commit**

```bash
git add lib/app/modules/purchase_order/form/purchase_order_form_screen.dart
git commit -m "feat(po): header + Items-tab entry points for Create Purchase Receipt"
```

---

### Task 6: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Analyze the whole project**

Run: `flutter analyze`
Expected: 0 errors. (Pre-existing warnings/infos unrelated to this change may remain; no new errors.)

- [ ] **Step 2: Run the new tests**

Run: `flutter test test/unit/po_receipt_helpers_test.dart test/widget/purchase_receipt_resume_sheet_test.dart`
Expected: All PASS.

- [ ] **Step 3: Run the full suite**

Run: `flutter test`
Expected: No new failures introduced by this change. (Per project memory, `status_pill` / `doctype_form_header` suites have pre-existing failures on `release/play-store` — confirm the count is unchanged, not increased.)

- [ ] **Step 4: On-device smoke checklist (manual)**

Verify on a connected device/emulator:
1. Submitted PO with open qty → **both** the header `receipt_long` icon and the Items-tab "Create Purchase Receipt" button appear.
2. Draft PO (`docstatus 0`) → neither surface appears (scan field shows instead).
3. Fully-received PO → neither surface appears.
4. Tap action, no existing draft → opens a new PR bound to the PO; scanning a PO item links it (PO Qty chip/progress shows); scanning an item not on the PO is rejected.
5. With an existing draft PR for the PO → resume sheet lists it; "Resume" opens it in edit mode; "Start a new receipt" opens a fresh PR.
6. User without PR create access → neither surface appears (fail-closed).

- [ ] **Step 5: No commit** (verification only). If any step fails, return to the owning task.

---

## Self-Review

**Spec coverage:**
- Both entry points (header + Items tab) → Task 5. ✓
- Visibility gating (submitted, not closed, open qty, permission, hidden when fully received) → `canCreateReceipt` Task 4; surfaces Task 5. ✓
- Tap behaviour (permission re-assert, draft check, resume/create-new, lookup fail-open) → Task 4. ✓
- Provider open-draft lookup (child query → distinct parents → header fetch) → Task 2. ✓
- Resume-or-create sheet → Task 3. ✓
- Pure helpers `hasOpenReceiptQty` / `parseDraftReceiptParents` + tests → Task 1. ✓
- Reuse PR form/route/resolver/417 unchanged → confirmed; no tasks touch them. ✓
- Permission via `PermissionService.hasAccess(..., 'create')`, fail-closed → Tasks 4. ✓

**Placeholder scan:** No TBD/TODO; every code step contains full code. ✓

**Type consistency:** `DraftReceiptSummary(name, postingDate)`, `hasOpenReceiptQty(List<PurchaseOrderItem>)`, `parseDraftReceiptParents(dynamic)`, `getOpenDraftReceiptsForPo(String) → Future<List<DraftReceiptSummary>>`, `PurchaseReceiptResumeSheet({drafts, onResume(String), onCreateNew})`, `canCreateReceipt`/`hasOpenQty`/`createPurchaseReceipt()` — names/signatures match across Tasks 1→5. ✓
