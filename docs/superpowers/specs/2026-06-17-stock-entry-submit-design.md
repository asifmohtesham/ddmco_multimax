# Stock Entry Submit — Design

**Date:** 2026-06-17
**Status:** Approved for planning
**Module:** `lib/app/modules/stock_entry`

## Problem

The Stock Entry form supports create/update (`saveDocument`) but offers **no way to
submit** a draft (docstatus 0 → 1). Users must leave the app to submit in ERPNext
desk. We want an in-app Submit action that mirrors ERPNext desk behaviour and
respects ERPNext roles and permissions.

## Goals

- Add a Submit action to the Stock Entry form, available for **all** draft Stock
  Entries regardless of source (manual, Material Request, POS Upload, Work Order,
  Manufacture).
- Mirror ERPNext desk's morphing primary action: while there are unsaved changes the
  primary action is **Save**; once saved (clean draft) it becomes **Submit**.
- Validate ERPNext submit permission for the specific document before offering
  Submit (pre-check), while keeping the server as the source of truth
  (server-enforced).
- Place Save and Submit together in the header toolbar (matches ERPNext desk and the
  existing Save location).

## Non-Goals

- No change to Work Order / Job Card submit flows (they keep their existing
  body-button submit). The new shared-header params are opt-in and default off.
- No cancel/amend (docstatus 1 → 2) support.
- No bulk submit from the list screen.

## Behaviour

Single primary action cluster in the header toolbar, morphing by document state:

| Document state                                              | Save icon        | Submit button        |
| ---------------------------------------------------------- | ---------------- | -------------------- |
| New or dirty (`isDirty`, docstatus 0)                      | Active / filled  | Hidden               |
| Clean saved draft (docstatus 0, `!isDirty`) **+ perm**     | Idle             | Shown (labeled)      |
| Clean saved draft, **no** submit permission                | Idle             | Hidden (fail-closed) |
| Submitted (docstatus 1)                                    | Hidden (read-only) | Hidden             |

Submit is gated on a **clean** draft, so the natural flow is: edit → **Save** →
the action set flips to **Submit** (the ERPNext desk flow). The existing header
Save icon keeps its current behaviour.

Tapping Submit shows a confirmation dialog that matches ERPNext desk's submit
prompt — a "Confirm" dialog reading **"Permanently Submit {name}?"** with a **Yes**
confirm button (blue / primary). On success the document is refetched (now
docstatus 1, read-only) and a success snackbar is shown.

## Permission Validation (pre-check + server-enforced)

- **Pre-check:** after a draft document is loaded, query ERPNext
  `frappe.client.has_permission('Stock Entry', <docname>, 'submit')`. Because the
  draft already has a document name, this validates the *actual* document — role
  permissions **and** row-level / user permissions — not just a coarse role check.
- The result is stored in `canSubmitPerm` (RxBool, **defaults `false` / fail-closed**)
  and refreshed inside `fetchDocument()` whenever the loaded doc is a draft with a
  non-empty name.
- **Server-enforced:** `submitDocument()` still handles a server-side rejection
  (HTTP 403 / `_server_messages` / `exception`) with a clean error snackbar even if
  the pre-check passed. The server remains the source of truth.

## Components

### `lib/app/data/providers/api_provider.dart`

Add a generic document-level permission probe:

```dart
/// Checks whether the current session user has [ptype] permission on a
/// specific document via frappe.client.has_permission.
Future<Response> hasDocPermission(String doctype, String name, String ptype);
```

Calls `GET /api/method/frappe.client.has_permission` with
`doctype`, `docname` (= name), and `perm_type` = `ptype`.

Add a static parser (testable without HTTP), fail-closed:

```dart
/// Parses a frappe.client.has_permission response into a bool.
/// Expected shape: {"message": {"has_permission": 1|true}}.
/// Anything else (null, non-Map, missing key, false) → false.
static bool parseHasDocPermissionResponse(dynamic data);
```

### `lib/app/data/providers/stock_entry_provider.dart`

```dart
/// Submit a saved Stock Entry (docstatus 0 → 1).
Future<Response> submitStockEntry(String name) =>
    _apiProvider.submitDocument('Stock Entry', name);

/// Whether the current user may submit the specific Stock Entry [name].
Future<bool> canSubmit(String name);
```

`canSubmit` calls `_apiProvider.hasDocPermission('Stock Entry', name, 'submit')`,
returns `ApiProvider.parseHasDocPermissionResponse(res.data)`, and returns `false`
on any `DioException`/error (fail-closed).

### `lib/app/modules/stock_entry/form/stock_entry_form_controller.dart`

New state:

```dart
var isSubmitting  = false.obs;
var canSubmitPerm = false.obs; // fail-closed default
```

New computed getter:

```dart
bool get canSubmit =>
    mode != 'new' &&
    (stockEntry.value?.docstatus ?? 1) == 0 &&
    !isDirty.value &&
    !isSaving.value &&
    !isSubmitting.value &&
    canSubmitPerm.value;
```

Permission pre-check — invoked from `fetchDocument()` after a successful load when
the doc is a draft (`docstatus == 0`) with a non-empty `name`:

```dart
Future<void> _refreshSubmitPermission() async {
  if (name.isEmpty || (stockEntry.value?.docstatus ?? 1) != 0) {
    canSubmitPerm.value = false;
    return;
  }
  canSubmitPerm.value = await _provider.canSubmit(name);
}
```

Submit action (mirrors the Work Order `submitDocument()` pattern):

```dart
Future<void> submitDocument() async {
  if (!canSubmit) return;
  // Mirror ERPNext desk's submit prompt.
  final confirmed = await GlobalDialog.confirm(
    title: 'Confirm',
    message: 'Permanently Submit $name?',
    confirmText: 'Yes',
    confirmColor: Colors.blue,
  );
  if (confirmed != true) return;
  isSubmitting.value = true;
  try {
    final res = await _provider.submitStockEntry(name);
    if (res.statusCode == 200) {
      await fetchDocument();              // now docstatus 1, read-only
      GlobalSnackbar.success(message: 'Stock Entry $name submitted');
    } else {
      GlobalSnackbar.error(message: 'Failed to submit Stock Entry');
    }
  } on DioException catch (e) {
    _handleSaveDioError(e);               // reuse existing _server_messages/exception parsing
  } catch (e) {
    GlobalSnackbar.error(message: 'Submit failed: $e');
  } finally {
    isSubmitting.value = false;
  }
}
```

`_handleSaveDioError` is reused for consistent ERPNext error extraction.

### `lib/app/modules/global_widgets/doctype_form_header.dart` (shared)

Add three optional, nullable params (default off → no change for existing callers
WO / JC / others):

```dart
final VoidCallback? onSubmit;
final bool canSubmit;       // default false
final bool isSubmitting;    // default false
```

In `_buildActions`, when `onSubmit != null && canSubmit`, render a **labeled**
Submit button styled to match ERPNext desk's `btn-primary`: a filled **primary**
(blue) button with the text **"Submit"** and **no icon** (a small spinner replaces
the label while `isSubmitting`). Placed in the trailing actions alongside Save.
Update `shouldRebuild` to compare the new fields (`canSubmit`, `isSubmitting`, and
`(onSubmit != null) != (old.onSubmit != null)`).

### `lib/app/modules/stock_entry/form/stock_entry_form_screen.dart`

Pass the new params through to `DocTypeFormHeader`:

```dart
onSubmit:     controller.submitDocument,
canSubmit:    controller.canSubmit,
isSubmitting: controller.isSubmitting.value,
```

(read inside the existing `Obx`). No body footer; no `BottomScanBar` change.

## Data Flow

```
fetchDocument() ─ success ─► stockEntry set ─► _refreshSubmitPermission()
                                                   │
                                                   └─ provider.canSubmit(name)
                                                        └─ has_permission(...,'submit')
                                                             └─ canSubmitPerm = bool

header Obx ─► canSubmit getter ─► Submit button visible/enabled
   │
   └─ tap ─► submitDocument() ─► confirm ─► provider.submitStockEntry(name)
                                              └─ PUT docstatus:1
                                                   └─ fetchDocument() (docstatus 1)
```

## Error Handling

- Pre-check failure (network/403/parse) → `canSubmitPerm = false` → Submit hidden.
  No user-facing error (graceful: Submit simply isn't offered).
- Submit rejection → `_handleSaveDioError` extracts ERPNext `exception` /
  `_server_messages` and shows an error snackbar; document stays a draft.
- Version conflict on submit → handled by the existing `handleVersionConflict`
  path inside `_handleSaveDioError`.

## Testing

- **Controller** `canSubmit` truth table: new, dirty, clean+perm, clean+no-perm,
  submitted, in-flight (isSaving/isSubmitting) → expected booleans.
- **Parser** `parseHasDocPermissionResponse`: `{message:{has_permission:true}}` → true;
  `false`, `null`, non-Map, missing key → false (fail-closed).
- **Provider** `submitStockEntry` issues a docstatus:1 PUT to the Stock Entry resource.
- **Provider** `canSubmit` returns false on `DioException` (fail-closed).

## Risks / Notes

- Extending the shared `DocTypeFormHeader` is additive (nullable defaults), so WO/JC
  and other consumers are unaffected.
- Pre-check adds one extra request per draft load; acceptable (single lightweight
  call, only for drafts).
- `frappe.client.has_permission` requires a docname in Frappe v15 — satisfied here
  because Submit is only ever offered for an already-saved draft.
