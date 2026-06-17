# Stock Entry Submit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an ERPNext-mirrored Save→Submit primary action to the Stock Entry form that submits a clean draft (docstatus 0 → 1), gated by a per-document submit-permission pre-check and backed by server-side enforcement.

**Architecture:** A generic `frappe.client.has_permission` probe on `ApiProvider` feeds a `StockEntryProvider.canSubmit(name)` check. The form controller stores the result fail-closed in `canSubmitPerm`, exposes a pure `canSubmit` predicate, and runs `submitDocument()` (confirm → PUT docstatus:1 → refetch). The shared `DocTypeFormHeader` gains optional `onSubmit`/`canSubmit`/`isSubmitting` params that render a blue "Submit" button alongside the existing Save icon; the Stock Entry screen wires them up.

**Tech Stack:** Flutter, GetX, Dio, ERPNext/Frappe REST (`/api/method/frappe.client.has_permission`, `/api/resource`), flutter_test.

**Spec:** `docs/superpowers/specs/2026-06-17-stock-entry-submit-design.md`

---

## File Structure

- **Modify** `lib/app/data/providers/api_provider.dart` — add `hasDocPermission()` (network) + `parseHasDocPermissionResponse()` (pure static parser).
- **Modify** `lib/app/data/providers/stock_entry_provider.dart` — add `submitStockEntry()` + `canSubmit()`.
- **Modify** `lib/app/modules/stock_entry/form/stock_entry_form_controller.dart` — add `isSubmitting`, `canSubmitPerm`, static `computeCanSubmit()`, `canSubmit` getter, `submitDocument()`, `_refreshSubmitPermission()`; wire into `fetchDocument()`.
- **Modify** `lib/app/modules/global_widgets/doctype_form_header.dart` — add `onSubmit`/`canSubmit`/`isSubmitting`; render Submit button; update `shouldRebuild`.
- **Modify** `lib/app/modules/stock_entry/form/stock_entry_form_screen.dart` — pass the three new params to the header.
- **Create** `test/unit/has_doc_permission_response_test.dart` — parser tests.
- **Create** `test/unit/stock_entry_can_submit_test.dart` — `computeCanSubmit` truth-table tests.
- **Modify** `test/widget/doctype_form_header_test.dart` — Submit-button render tests.

---

## Task 1: `ApiProvider.hasDocPermission` + parser

**Files:**
- Modify: `lib/app/data/providers/api_provider.dart` (near the existing `hasPermission` / `parseHasPermissionResponse`, ~line 267-298)
- Test: `test/unit/has_doc_permission_response_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/unit/has_doc_permission_response_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

void main() {
  group('ApiProvider.parseHasDocPermissionResponse', () {
    // frappe.client.has_permission returns {"message": {"has_permission": 1}}.

    test('T-1: true when has_permission is int 1', () {
      expect(
        ApiProvider.parseHasDocPermissionResponse({
          'message': {'has_permission': 1},
        }),
        isTrue,
      );
    });

    test('T-2: true when has_permission is bool true', () {
      expect(
        ApiProvider.parseHasDocPermissionResponse({
          'message': {'has_permission': true},
        }),
        isTrue,
      );
    });

    test('T-3: false when has_permission is int 0', () {
      expect(
        ApiProvider.parseHasDocPermissionResponse({
          'message': {'has_permission': 0},
        }),
        isFalse,
      );
    });

    test('T-4: false when has_permission is bool false', () {
      expect(
        ApiProvider.parseHasDocPermissionResponse({
          'message': {'has_permission': false},
        }),
        isFalse,
      );
    });

    test('T-5: false when data is null', () {
      expect(ApiProvider.parseHasDocPermissionResponse(null), isFalse);
    });

    test('T-6: false when data is not a Map', () {
      expect(ApiProvider.parseHasDocPermissionResponse('OK'), isFalse);
    });

    test('T-7: false when message is absent', () {
      expect(
        ApiProvider.parseHasDocPermissionResponse({'other': 1}),
        isFalse,
      );
    });

    test('T-8: false when message is not a Map', () {
      expect(
        ApiProvider.parseHasDocPermissionResponse({'message': [1, 2]}),
        isFalse,
      );
    });

    test('T-9: false when has_permission key is absent', () {
      expect(
        ApiProvider.parseHasDocPermissionResponse({'message': {'x': 1}}),
        isFalse,
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/has_doc_permission_response_test.dart`
Expected: FAIL — `parseHasDocPermissionResponse` is not defined on `ApiProvider`.

- [ ] **Step 3: Implement the parser + network method**

In `lib/app/data/providers/api_provider.dart`, immediately AFTER the existing
`parseHasPermissionResponse` static method (the one that ends `return data['message'] is List;`), add:

```dart
  /// Checks whether the current session user has [ptype] permission on the
  /// specific document [name] of [doctype], via `frappe.client.has_permission`.
  ///
  /// Frappe v15 requires a docname for this method, so it is only meaningful
  /// for already-saved documents (e.g. submitting a saved draft).
  Future<Response> hasDocPermission(
      String doctype, String name, String ptype) async {
    if (!_dioInitialised) await _initDio();
    return await _dio.get(
      '/api/method/frappe.client.has_permission',
      queryParameters: {
        'doctype':   doctype,
        'docname':   name,
        'perm_type': ptype,
      },
    );
  }

  /// Parses a `frappe.client.has_permission` response into a [bool].
  ///
  /// Expected shape: `{"message": {"has_permission": 1|true}}`.
  /// Anything else (null, non-Map, missing keys, falsy value) → `false`
  /// (fail-closed). Exposed as a public static method so unit tests can
  /// exercise it without a live HTTP connection.
  static bool parseHasDocPermissionResponse(dynamic data) {
    if (data is! Map) return false;
    final message = data['message'];
    if (message is! Map) return false;
    final value = message['has_permission'];
    return value == true || value == 1;
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/has_doc_permission_response_test.dart`
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/app/data/providers/api_provider.dart test/unit/has_doc_permission_response_test.dart
git commit -m "feat(api): add hasDocPermission probe + fail-closed parser"
```

---

## Task 2: `StockEntryProvider.submitStockEntry` + `canSubmit`

**Files:**
- Modify: `lib/app/data/providers/stock_entry_provider.dart` (add methods inside the `StockEntryProvider` class, e.g. after `updateStockEntry`, ~line 58)

> No standalone unit test: these are thin network wrappers over already-tested
> primitives (`submitDocument` and `parseHasDocPermissionResponse`). They are
> verified by `flutter analyze` here and exercised in the smoke test at the end.

- [ ] **Step 1: Add the import**

At the top of `lib/app/data/providers/stock_entry_provider.dart`, the file already imports
`api_provider.dart`. Confirm this line exists (no change if present):

```dart
import 'package:multimax/app/data/providers/api_provider.dart';
```

- [ ] **Step 2: Add the two methods**

Inside `class StockEntryProvider`, after `updateStockEntry(...)`:

```dart
  /// Submit a saved Stock Entry (docstatus 0 → 1).
  Future<Response> submitStockEntry(String name) async {
    return _apiProvider.submitDocument('Stock Entry', name);
  }

  /// Whether the current session user may submit the specific Stock Entry
  /// [name]. Fail-closed: returns `false` on any network/permission error.
  Future<bool> canSubmit(String name) async {
    try {
      final res =
          await _apiProvider.hasDocPermission('Stock Entry', name, 'submit');
      return ApiProvider.parseHasDocPermissionResponse(res.data);
    } catch (_) {
      return false;
    }
  }
```

- [ ] **Step 3: Verify it analyzes clean**

Run: `flutter analyze lib/app/data/providers/stock_entry_provider.dart`
Expected: "No issues found!"

- [ ] **Step 4: Commit**

```bash
git add lib/app/data/providers/stock_entry_provider.dart
git commit -m "feat(stock-entry): provider submitStockEntry + canSubmit (fail-closed)"
```

---

## Task 3a: Pure `computeCanSubmit` predicate + tests

The controller cannot be instantiated in a unit test without registering its full
GetX dependency graph (its provider/service fields are `Get.find()` initializers).
So the submit-eligibility logic is extracted into a **pure static method** that takes
plain values and is tested directly.

**Files:**
- Modify: `lib/app/modules/stock_entry/form/stock_entry_form_controller.dart`
- Test: `test/unit/stock_entry_can_submit_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/unit/stock_entry_can_submit_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';

void main() {
  group('StockEntryFormController.computeCanSubmit', () {
    // A clean, saved draft with submit permission and nothing in flight.
    bool call({
      String mode = 'edit',
      int? docStatus = 0,
      bool isDirty = false,
      bool isSaving = false,
      bool isSubmitting = false,
      bool canSubmitPerm = true,
    }) =>
        StockEntryFormController.computeCanSubmit(
          mode: mode,
          docStatus: docStatus,
          isDirty: isDirty,
          isSaving: isSaving,
          isSubmitting: isSubmitting,
          canSubmitPerm: canSubmitPerm,
        );

    test('T-1: clean saved draft with permission → true', () {
      expect(call(), isTrue);
    });

    test('T-2: new document → false', () {
      expect(call(mode: 'new'), isFalse);
    });

    test('T-3: dirty draft → false', () {
      expect(call(isDirty: true), isFalse);
    });

    test('T-4: already submitted (docstatus 1) → false', () {
      expect(call(docStatus: 1), isFalse);
    });

    test('T-5: null docstatus → false', () {
      expect(call(docStatus: null), isFalse);
    });

    test('T-6: no submit permission → false', () {
      expect(call(canSubmitPerm: false), isFalse);
    });

    test('T-7: save in flight → false', () {
      expect(call(isSaving: true), isFalse);
    });

    test('T-8: submit in flight → false', () {
      expect(call(isSubmitting: true), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/stock_entry_can_submit_test.dart`
Expected: FAIL — `computeCanSubmit` is not defined.

- [ ] **Step 3: Add the static predicate**

In `lib/app/modules/stock_entry/form/stock_entry_form_controller.dart`, inside the
`StockEntryFormController` class, add near the existing `bool get isEditable` getter
(~line 121):

```dart
  /// Pure submit-eligibility predicate (no GetX state) so it is unit-testable.
  /// A Stock Entry may be submitted only when it is a saved, clean draft the
  /// current user is permitted to submit, with no save/submit already running.
  static bool computeCanSubmit({
    required String mode,
    required int? docStatus,
    required bool isDirty,
    required bool isSaving,
    required bool isSubmitting,
    required bool canSubmitPerm,
  }) {
    return mode != 'new' &&
        docStatus == 0 &&
        !isDirty &&
        !isSaving &&
        !isSubmitting &&
        canSubmitPerm;
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/stock_entry_can_submit_test.dart`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/stock_entry/form/stock_entry_form_controller.dart test/unit/stock_entry_can_submit_test.dart
git commit -m "feat(stock-entry): pure computeCanSubmit predicate + tests"
```

---

## Task 3b: Controller submit state, getter, action, and permission wiring

**Files:**
- Modify: `lib/app/modules/stock_entry/form/stock_entry_form_controller.dart`

> Verified by `flutter analyze` + the smoke test at the end (the controller's GetX
> dependency graph makes a direct unit test impractical; the testable logic already
> lives in `computeCanSubmit`, Task 3a).

- [ ] **Step 1: Add observable state**

Next to the other `*.obs` document-state fields (~line 63-72, after `var isSaving = false.obs;`), add:

```dart
  var isSubmitting  = false.obs;
  var canSubmitPerm = false.obs; // fail-closed default until pre-check confirms
```

- [ ] **Step 2: Add the `canSubmit` getter**

Immediately after the `computeCanSubmit` static method added in Task 3a, add the
instance getter that feeds it live GetX state:

```dart
  bool get canSubmit => computeCanSubmit(
        mode:          mode,
        docStatus:     stockEntry.value?.docstatus,
        isDirty:       isDirty.value,
        isSaving:      isSaving.value,
        isSubmitting:  isSubmitting.value,
        canSubmitPerm: canSubmitPerm.value,
      );
```

- [ ] **Step 3: Add the permission pre-check**

Add this method to the controller (e.g. just below `fetchDocument()`):

```dart
  /// Refreshes [canSubmitPerm] for the currently-loaded document.
  /// Only drafts with a real name can be submitted; everything else is
  /// fail-closed to `false`.
  Future<void> _refreshSubmitPermission() async {
    if (name.isEmpty || (stockEntry.value?.docstatus ?? 1) != 0) {
      canSubmitPerm.value = false;
      return;
    }
    canSubmitPerm.value = await _provider.canSubmit(name);
  }
```

- [ ] **Step 4: Wire the pre-check into `fetchDocument()`**

In `fetchDocument()`, inside the `if (response.statusCode == 200 && response.data['data'] != null)`
success branch, locate the existing line `isDirty.value = false;` (the one near the end of
that branch, ~line 685) and add the pre-check call right after it:

```dart
        isDirty.value = false;
        await _refreshSubmitPermission();
```

- [ ] **Step 5: Add `submitDocument()`**

Add this method to the controller (e.g. just after `saveDocument()`, ~line 1512). It
reuses the existing `_handleSaveDioError` for ERPNext error extraction and mirrors the
Work Order submit flow:

```dart
  // ── Submit ──────────────────────────────────────────────────────────────
  Future<void> submitDocument() async {
    if (!canSubmit) return;
    // Mirror ERPNext desk's submit prompt.
    final confirmed = await GlobalDialog.confirm(
      title:        'Confirm',
      message:      'Permanently Submit $name?',
      confirmText:  'Yes',
      confirmColor: Colors.blue,
    );
    if (confirmed != true) return;

    isSubmitting.value = true;
    try {
      final res = await _provider.submitStockEntry(name);
      if (res.statusCode == 200) {
        await fetchDocument(); // now docstatus 1, read-only; perm refreshed to false
        GlobalSnackbar.success(message: 'Stock Entry $name submitted');
      } else {
        GlobalSnackbar.error(message: 'Failed to submit Stock Entry');
      }
    } on DioException catch (e) {
      _handleSaveDioError(e);
    } catch (e) {
      GlobalSnackbar.error(message: 'Submit failed: $e');
    } finally {
      isSubmitting.value = false;
    }
  }
```

- [ ] **Step 6: Verify it analyzes clean**

Run: `flutter analyze lib/app/modules/stock_entry/form/stock_entry_form_controller.dart`
Expected: "No issues found!" (`Colors`, `DioException`, `GlobalDialog`, `GlobalSnackbar`
are already imported in this file.)

- [ ] **Step 7: Re-run the predicate test (regression)**

Run: `flutter test test/unit/stock_entry_can_submit_test.dart`
Expected: PASS (8 tests).

- [ ] **Step 8: Commit**

```bash
git add lib/app/modules/stock_entry/form/stock_entry_form_controller.dart
git commit -m "feat(stock-entry): submit action + per-document permission pre-check"
```

---

## Task 4: Submit button in `DocTypeFormHeader`

**Files:**
- Modify: `lib/app/modules/global_widgets/doctype_form_header.dart`
- Test: `test/widget/doctype_form_header_test.dart`

- [ ] **Step 1: Write the failing tests**

Append these tests inside the `group('DocTypeFormHeader', ...)` block in
`test/widget/doctype_form_header_test.dart` (before the closing `});` of the group):

```dart
    testWidgets('renders Submit button when onSubmit set and canSubmit true',
        (tester) async {
      await tester.pumpWidget(_wrapInSliver(
        DocTypeFormHeader(
          title: 'MAT-STE-0001',
          onSubmit: () {},
          canSubmit: true,
        ),
      ));
      expect(find.widgetWithText(FilledButton, 'Submit'), findsOneWidget);
    });

    testWidgets('hides Submit button when canSubmit false', (tester) async {
      await tester.pumpWidget(_wrapInSliver(
        DocTypeFormHeader(
          title: 'MAT-STE-0001',
          onSubmit: () {},
          canSubmit: false,
        ),
      ));
      expect(find.text('Submit'), findsNothing);
    });

    testWidgets('hides Submit button when onSubmit is null (backwards compat)',
        (tester) async {
      await tester.pumpWidget(_wrapInSliver(
        const DocTypeFormHeader(title: 'MAT-STE-0001', canSubmit: true),
      ));
      expect(find.text('Submit'), findsNothing);
    });

    testWidgets('shows spinner instead of label while submitting',
        (tester) async {
      await tester.pumpWidget(_wrapInSliver(
        DocTypeFormHeader(
          title: 'MAT-STE-0001',
          onSubmit: () {},
          canSubmit: true,
          isSubmitting: true,
        ),
      ));
      expect(find.text('Submit'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widget/doctype_form_header_test.dart`
Expected: FAIL — `onSubmit`, `canSubmit`, `isSubmitting` are not named params of
`DocTypeFormHeader` (compile error).

- [ ] **Step 3: Add the fields to the public widget**

In `lib/app/modules/global_widgets/doctype_form_header.dart`, in `class DocTypeFormHeader`,
after `final VoidCallback? onShare;` (~line 68) add:

```dart
  final VoidCallback? onSubmit;
```

After `final bool canSave;` (~line 70) add:

```dart
  final bool canSubmit;
```

After `final bool isSaving;` (~line 72) add:

```dart
  final bool isSubmitting;
```

In the constructor (`const DocTypeFormHeader({ ... })`, ~line 78-92), add these
defaulted params (e.g. after `this.onShare,` and after `this.isSaving = false,`):

```dart
    this.onSubmit,
    this.canSubmit    = false,
    this.isSubmitting = false,
```

- [ ] **Step 4: Forward them to the delegate**

In `DocTypeFormHeader.build` where `_DocTypeFormHeaderDelegate(...)` is constructed
(~line 101-114), add to the argument list:

```dart
        onSubmit:        onSubmit,
        canSubmit:       canSubmit,
        isSubmitting:    isSubmitting,
```

- [ ] **Step 5: Add matching fields to the delegate**

In `class _DocTypeFormHeaderDelegate`, after `final VoidCallback? onShare;` (~line 127) add:

```dart
  final VoidCallback? onSubmit;
  final bool canSubmit;
  final bool isSubmitting;
```

In the delegate constructor (~line 135-148), add:

```dart
    required this.onSubmit,
    required this.canSubmit,
    required this.isSubmitting,
```

- [ ] **Step 6: Render the Submit button**

In `_buildActions(BuildContext context)` (~line 352), insert the Submit button as the
FIRST entry of the `items` list so it sits left of Reload/Save — add it immediately
after `final items = <Widget>[`:

```dart
      if (onSubmit != null && canSubmit)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FilledButton(
            onPressed: isSubmitting ? null : onSubmit,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Submit'),
          ),
        ),
```

- [ ] **Step 7: Update `shouldRebuild`**

In `shouldRebuild(covariant _DocTypeFormHeaderDelegate old)` (~line 383), add these
comparisons to the returned boolean expression (before the final `;`):

```dart
           || canSubmit      != old.canSubmit
           || isSubmitting   != old.isSubmitting
           || (onSubmit != null) != (old.onSubmit != null)
```

- [ ] **Step 8: Run the header tests to verify they pass**

Run: `flutter test test/widget/doctype_form_header_test.dart`
Expected: PASS (existing tests + 4 new tests).

- [ ] **Step 9: Commit**

```bash
git add lib/app/modules/global_widgets/doctype_form_header.dart test/widget/doctype_form_header_test.dart
git commit -m "feat(header): optional Submit button (ERPNext btn-primary style)"
```

---

## Task 5: Wire the Stock Entry screen to the header

**Files:**
- Modify: `lib/app/modules/stock_entry/form/stock_entry_form_screen.dart` (~line 56-71)

- [ ] **Step 1: Pass the new params to `DocTypeFormHeader`**

In `stock_entry_form_screen.dart`, inside the existing `Obx(() { ... })` build (the
values are read reactively here, so the header rebuilds when they change), add to the
`DocTypeFormHeader(...)` constructor call (e.g. after `onReload: onReload,`, ~line 65):

```dart
                  onSubmit:     controller.submitDocument,
                  canSubmit:    controller.canSubmit,
                  isSubmitting: controller.isSubmitting.value,
```

> `controller.canSubmit` and `controller.isSubmitting.value` are read inside the
> existing `Obx`, so the button appears/disappears as the doc becomes a clean draft,
> the permission resolves, or a submit runs. `onSubmit` is passed unconditionally;
> visibility is driven entirely by `canSubmit`.

- [ ] **Step 2: Verify it analyzes clean**

Run: `flutter analyze lib/app/modules/stock_entry/form/stock_entry_form_screen.dart`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add lib/app/modules/stock_entry/form/stock_entry_form_screen.dart
git commit -m "feat(stock-entry): surface Submit action in form header"
```

---

## Task 6: Full verification

- [ ] **Step 1: Run the full test suite**

Run: `flutter test`
Expected: PASS. (Pre-existing unrelated failures in `status_pill`/`doctype_form_header`
have been noted historically — confirm any failures are NOT in the files this plan
touched: `has_doc_permission_response_test.dart`, `stock_entry_can_submit_test.dart`,
or the new `doctype_form_header_test.dart` Submit tests.)

- [ ] **Step 2: Analyze the whole project**

Run: `flutter analyze`
Expected: no NEW issues in the five modified `lib/` files.

- [ ] **Step 3: Manual smoke test (device/emulator)**

Run the app (`flutter run -d <device_id>`) and verify, on a **draft** Stock Entry:

1. Open a draft SE with no edits → header shows a blue **Submit** button next to Save.
2. Edit a field → Submit disappears, Save (filled) appears (the Save→Submit morph).
3. Save → Submit reappears once the draft is clean.
4. Tap Submit → "Confirm / Permanently Submit {name}? / Yes" dialog appears.
5. Confirm → document refetches, status becomes Submitted (docstatus 1), Submit and
   Save both disappear (read-only).
6. As a user **without** Stock Entry submit permission, the Submit button never appears
   on a clean draft (fail-closed pre-check).
7. (Optional, server-enforced path) If a draft passes the pre-check but the server
   rejects submit, an error snackbar shows the ERPNext message and the doc stays a draft.

- [ ] **Step 4: Final commit (if any manual-fix tweaks were needed)**

```bash
git add -A
git commit -m "test(stock-entry): verify submit flow end-to-end"
```

---

## Notes for the implementer

- **Imports already present** — no new imports are required in the controller
  (`Colors`, `DioException`, `GlobalDialog`, `GlobalSnackbar`) or the header
  (`material.dart`).
- **Fail-closed everywhere** — `canSubmitPerm` defaults `false`; `provider.canSubmit`
  and `parseHasDocPermissionResponse` both return `false` on any error/unexpected shape.
- **Server is the source of truth** — the pre-check only governs button *visibility*;
  `submitDocument()` still handles a server rejection via `_handleSaveDioError`.
- **Do not modify** Work Order / Job Card submit code — the new header params are
  opt-in and default off, so those screens are unaffected.
