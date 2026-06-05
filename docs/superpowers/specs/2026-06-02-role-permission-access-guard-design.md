# Role-Permission Access Guard — Design Spec

**Date:** 2026-06-02  
**Status:** Approved

---

## Problem

`PermissionService` calls `getDocument('DocType', doctype)` to read the DocType's `permissions` child table. Standard (non-System Manager) users cannot read DocType meta-documents, so Frappe returns HTTP 403. The current code catches that 403 and sets `_accessCache[doctype] = true` — meaning `DocTypeGuard` is effectively a no-op for every regular user; all nav drawer items and dashboard tiles are always shown regardless of actual role.

Separately, `perm_type` is hardcoded to `read` throughout, so report links (which Frappe gates on `perm_type=report` against the `ref_doctype`) cannot be guarded correctly.

Additional gaps:
- Four report links in the drawer (Batch-Wise Balance, Item Variant Details, BOM Search, Job Card Summary) have no guard at all.
- `_ModuleGroup` headers (Stock, Buying, Manufacturing, Selling) render even when all their children are inaccessible.
- Permissions are fetched lazily on first render, showing shimmer skeletons every time the drawer opens.

---

## Solution

Replace the DocType-definition fetch with **`frappe.client.has_permission`** — Frappe's built-in server-side permission check for the current session user. Extend the service to support any `permType`. Prefetch all needed permissions in parallel at login so the cache is warm before the home screen renders.

---

## Frappe API

```
GET /api/method/frappe.client.has_permission?doctype={doctype}&perm_type={permType}
```

- Checks the **current session user** server-side; no `user` param required.
- Returns `{"message": {"has_permission": 1}}` (granted) or `{"message": {"has_permission": 0}}` (denied).
- Always HTTP 200 for a logged-in user; 403 only for an expired/missing session.
- `throw=False` default means no exception is raised for denied access — just `0`.

**Report access (ERPNext default behaviour):** Frappe gates report execution on `perm_type=report` against the report's `ref_doctype`. The Report doc's "Has Role" table defaults to all-access when empty (true for all four standard reports here), so the binding check is the `report` permission on the `ref_doctype`.

---

## Architecture

### New file: `lib/app/data/constants/permission_entries.dart`

Single source of truth. Exports:

```dart
const kAppPermissions = [
  ...kTopLevelPermissions,
  ...kStockPermissions,
  ...kBuyingPermissions,
  ...kManufacturingPermissions,
  ...kSellingPermissions,
];

// Top-level drawer items (not inside any _ModuleGroup)
const kTopLevelPermissions = [
  (doctype: 'ToDo', permType: 'read'),
];

const kStockPermissions = [
  (doctype: 'Item',             permType: 'read'),
  (doctype: 'Batch',            permType: 'read'),
  (doctype: 'Material Request', permType: 'read'),
  (doctype: 'Stock Entry',      permType: 'read'),
  (doctype: 'Delivery Note',    permType: 'read'),
  (doctype: 'Packing Slip',     permType: 'read'),
  (doctype: 'Batch',            permType: 'report'),  // Batch-Wise Balance
  (doctype: 'Item',             permType: 'report'),  // Item Variant Details
];

const kBuyingPermissions = [
  (doctype: 'Purchase Order',   permType: 'read'),
  (doctype: 'Purchase Receipt', permType: 'read'),
];

const kManufacturingPermissions = [
  (doctype: 'BOM',      permType: 'read'),
  (doctype: 'Work Order', permType: 'read'),
  (doctype: 'Job Card', permType: 'read'),
  (doctype: 'BOM',      permType: 'report'),  // BOM Search
  (doctype: 'Job Card', permType: 'report'),  // Job Card Summary
];

const kSellingPermissions = [
  (doctype: 'POS Upload', permType: 'read'),
];
```

Both `_ModuleGroup` guard lists and `prefetchAll` reference these constants — no drift possible.

---

### `lib/app/data/providers/api_provider.dart`

Add one method:

```dart
Future<Response> hasPermission(String doctype, String permType) =>
    _dio.get(
      '/api/method/frappe.client.has_permission',
      queryParameters: {'doctype': doctype, 'perm_type': permType},
    );
```

---

### `lib/app/data/services/permission_service.dart`

Full rewrite:

- **Cache key:** `"$doctype:$permType"` — e.g. `"Stock Entry:read"`, `"Batch:report"`.
- **`_accessCache`:** `RxMap<String, bool>` — unchanged type, new key scheme.
- **`_pendingFetches`:** `Set<String>` keyed by `"$doctype:$permType"`.
- **Remove:** `_readPermissionsCache` (server handles role matching; no local role aggregation).
- **Replace** `_fetchDocTypePermissions` with `_fetchPermission(String doctype, String permType)` that calls `apiProvider.hasPermission(doctype, permType)` and writes `_accessCache[key]`.
- **Add** `prefetchAll(List<({String doctype, String permType})> entries)` — fires all `_fetchPermission` calls in parallel via `Future.wait`.
- **Rename** public API: `hasAccess(String doctype, {String permType = 'read'}) → bool?`.

Error handling in `_fetchPermission`:

| Condition | Result |
|---|---|
| 200, `has_permission: 1` | `true` |
| 200, `has_permission: 0` | `false` |
| 403 (session expired) | `false` |
| Network / 5xx error | `false` |

Fail-closed on all errors. The existing `true`-on-403 fallback is removed.

---

### `lib/app/modules/global_widgets/doctype_guard.dart`

Add one parameter:

```dart
final String permType; // default: 'read'
```

Thread through to `service.hasAccess(doctype, permType: permType)`.

---

### `lib/app/modules/global_widgets/app_nav_drawer.dart`

**`_ModuleGroup`:** Add `guardEntries: List<({String doctype, String permType})>` parameter. Wrap the existing `ExpansionTile` in an `Obx` that returns `SizedBox.shrink()` when `PermissionService.hasAccess` is `false` for every entry in `guardEntries`.

```dart
// Group is visible if at least one entry is accessible (true) or still loading (null).
final anyAccessible = guardEntries.any(
  (e) => service.hasAccess(e.doctype, permType: e.permType) != false,
);
if (!anyAccessible) return const SizedBox.shrink();
```

**Report links — add `DocTypeGuard` wrappers:**

```dart
DocTypeGuard(
  doctype: 'Batch',
  permType: 'report',
  child: _DrawerItem(title: 'Batch-Wise Balance', ...),
),
DocTypeGuard(
  doctype: 'Item',
  permType: 'report',
  child: _DrawerItem(title: 'Item Variant Details', ...),
),
DocTypeGuard(
  doctype: 'BOM',
  permType: 'report',
  child: _DrawerItem(title: 'BOM Search', ...),
),
DocTypeGuard(
  doctype: 'Job Card',
  permType: 'report',
  child: _DrawerItem(title: 'Job Card Summary', ...),
),
```

**`_ModuleGroup` instances — pass `guardEntries`:**

```dart
_ModuleGroup(
  title: 'Stock',
  guardEntries: kStockPermissions,
  ...
),
_ModuleGroup(
  title: 'Buying',
  guardEntries: kBuyingPermissions,
  ...
),
// etc.
```

---

### `lib/app/modules/auth/authentication_controller.dart`

**`fetchUserDetails`** — after `currentUser.value = user`:

```dart
if (Get.isRegistered<PermissionService>()) {
  await Get.find<PermissionService>().prefetchAll(kAppPermissions);
}
```

Navigation (`Get.offAllNamed`) only fires after this completes — permissions are warm before the home screen renders.

**`_clearSessionAndLocalData`** — add:

```dart
if (Get.isRegistered<PermissionService>()) {
  Get.find<PermissionService>().clearCache();
}
```

---

## Data Flow

```
fetchUserDetails()
  └─ fetch user + roles  (existing)
  └─ currentUser.value = user
  └─ prefetchAll(kAppPermissions)   ← NEW: parallel has_permission calls
       └─ Future.wait([...16 requests...])
       └─ _accessCache populated
  └─ return  →  Get.offAllNamed(HOME)

HomeScreen renders
  └─ AppNavDrawer builds
       └─ _ModuleGroup(guardEntries: kStockPermissions)
            └─ Obx: any accessible? → show / shrink
            └─ DocTypeGuard(doctype:'Item', permType:'read')     → sync cache read
            └─ DocTypeGuard(doctype:'Batch', permType:'report')  → sync cache read
            └─ ...
```

---

## Error / Edge Cases

- **Prefetch fails for one entry:** That entry defaults to `false` (fail-closed). Other entries are unaffected.
- **Cache miss at render time** (prefetch incomplete or entry not in `kAppPermissions`): `hasAccess` returns `null` → triggers lazy fetch; `DocTypeGuard` shows `loading ?? SizedBox.shrink()` until resolved. This is a bug-path, not normal flow.
- **Role change while app is open:** Permissions are only re-fetched on next `fetchUserDetails` call (login or app restart). Acceptable for a warehouse app — no need for live refresh.
- **`checkAuthenticationStatus` on app restart:** Also calls `fetchUserDetails`, so prefetch runs and permissions are fresh each cold start.

---

## Files Changed

| File | Change |
|---|---|
| `lib/app/data/constants/permission_entries.dart` | **New** — `kAppPermissions` and named sub-lists |
| `lib/app/data/providers/api_provider.dart` | Add `hasPermission` method |
| `lib/app/data/services/permission_service.dart` | Full rewrite |
| `lib/app/modules/global_widgets/doctype_guard.dart` | Add `permType` parameter |
| `lib/app/modules/global_widgets/app_nav_drawer.dart` | Add report guards; `_ModuleGroup` auto-hide |
| `lib/app/modules/auth/authentication_controller.dart` | Add prefetch + cache-clear calls |
