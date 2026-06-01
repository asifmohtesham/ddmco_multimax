# Role-Permission Access Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the broken DocType-definition permission fetch with `frappe.client.has_permission`, add `perm_type` support, guard the four unguarded report links, auto-hide empty `_ModuleGroup` headers, and prefetch all permissions at login so the drawer renders without skeletons.

**Architecture:** A static `ApiProvider.parseHasPermissionResponse` method handles response parsing (testable without DI). `PermissionService` is promoted to a permanent global service in `main.dart` (alongside `AuthenticationController`) so `fetchUserDetails` can call `prefetchAll` before navigating to Home. `DocTypeGuard` gains an optional `permType` parameter (default `'read'`); `_ModuleGroup` gains a `guardEntries` list and hides itself when none are accessible.

**Tech Stack:** Flutter/Dart, GetX, Dio, `frappe.client.has_permission` REST endpoint.

**Spec:** `docs/superpowers/specs/2026-06-02-role-permission-access-guard-design.md`

---

## File Map

| Action | Path |
|---|---|
| **Create** | `lib/app/data/constants/permission_entries.dart` |
| **Create** | `test/unit/has_permission_response_test.dart` |
| **Modify** | `lib/app/data/providers/api_provider.dart` |
| **Modify** | `lib/app/data/services/permission_service.dart` |
| **Modify** | `lib/app/modules/global_widgets/doctype_guard.dart` |
| **Modify** | `lib/app/modules/global_widgets/app_nav_drawer.dart` |
| **Modify** | `lib/app/modules/auth/authentication_controller.dart` |
| **Modify** | `lib/main.dart` |
| **Modify** | `lib/app/modules/home/home_binding.dart` |

---

## Task 1: Create `permission_entries.dart`

**Files:**
- Create: `lib/app/data/constants/permission_entries.dart`

This file is the single source of truth for every `(doctype, permType)` pair used by `DocTypeGuard`, `_ModuleGroup`, and `prefetchAll`. Both the nav drawer groups and the prefetch call reference these constants.

- [ ] **Step 1: Create the constants file**

```dart
// lib/app/data/constants/permission_entries.dart

typedef PermEntry = ({String doctype, String permType});

// Top-level drawer items (outside any _ModuleGroup)
const List<PermEntry> kTopLevelPermissions = [
  (doctype: 'ToDo', permType: 'read'),
];

const List<PermEntry> kStockPermissions = [
  (doctype: 'Item',             permType: 'read'),
  (doctype: 'Batch',            permType: 'read'),
  (doctype: 'Material Request', permType: 'read'),
  (doctype: 'Stock Entry',      permType: 'read'),
  (doctype: 'Delivery Note',    permType: 'read'),
  (doctype: 'Packing Slip',     permType: 'read'),
  (doctype: 'Batch',            permType: 'report'), // Batch-Wise Balance report
  (doctype: 'Item',             permType: 'report'), // Item Variant Details report
];

const List<PermEntry> kBuyingPermissions = [
  (doctype: 'Purchase Order',   permType: 'read'),
  (doctype: 'Purchase Receipt', permType: 'read'),
];

const List<PermEntry> kManufacturingPermissions = [
  (doctype: 'BOM',       permType: 'read'),
  (doctype: 'Work Order', permType: 'read'),
  (doctype: 'Job Card',  permType: 'read'),
  (doctype: 'BOM',       permType: 'report'), // BOM Search report
  (doctype: 'Job Card',  permType: 'report'), // Job Card Summary report
];

const List<PermEntry> kSellingPermissions = [
  (doctype: 'POS Upload', permType: 'read'),
];

const List<PermEntry> kAppPermissions = [
  ...kTopLevelPermissions,
  ...kStockPermissions,
  ...kBuyingPermissions,
  ...kManufacturingPermissions,
  ...kSellingPermissions,
];
```

- [ ] **Step 2: Verify it compiles**

```
flutter analyze lib/app/data/constants/permission_entries.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/app/data/constants/permission_entries.dart
git commit -m "feat(permissions): add kAppPermissions constants"
```

---

## Task 2: Add `ApiProvider.hasPermission` + static response parser

**Files:**
- Modify: `lib/app/data/providers/api_provider.dart`
- Create: `test/unit/has_permission_response_test.dart`

`hasPermission` makes the HTTP call. `parseHasPermissionResponse` is static so it can be unit-tested without GetX or Dio.

- [ ] **Step 1: Write the failing test**

Create `test/unit/has_permission_response_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

void main() {
  group('ApiProvider.parseHasPermissionResponse', () {
    test('T-1: returns true when has_permission is int 1', () {
      expect(
        ApiProvider.parseHasPermissionResponse(
            {'message': {'has_permission': 1}}),
        isTrue,
      );
    });

    test('T-2: returns false when has_permission is int 0', () {
      expect(
        ApiProvider.parseHasPermissionResponse(
            {'message': {'has_permission': 0}}),
        isFalse,
      );
    });

    test('T-3: returns true when has_permission is bool true', () {
      expect(
        ApiProvider.parseHasPermissionResponse(
            {'message': {'has_permission': true}}),
        isTrue,
      );
    });

    test('T-4: returns false when has_permission is bool false', () {
      expect(
        ApiProvider.parseHasPermissionResponse(
            {'message': {'has_permission': false}}),
        isFalse,
      );
    });

    test('T-5: returns false when data is null', () {
      expect(ApiProvider.parseHasPermissionResponse(null), isFalse);
    });

    test('T-6: returns false when data is not a Map', () {
      expect(ApiProvider.parseHasPermissionResponse('OK'), isFalse);
    });

    test('T-7: returns false when message key is absent', () {
      expect(
        ApiProvider.parseHasPermissionResponse({'other': 'data'}),
        isFalse,
      );
    });

    test('T-8: returns false when message is a String, not a Map', () {
      expect(
        ApiProvider.parseHasPermissionResponse(
            {'message': 'Insufficient Permission'}),
        isFalse,
      );
    });

    test('T-9: returns false when has_permission key is absent', () {
      expect(
        ApiProvider.parseHasPermissionResponse(
            {'message': {'other': 'data'}}),
        isFalse,
      );
    });
  });
}
```

- [ ] **Step 2: Run test — verify it fails**

```
flutter test test/unit/has_permission_response_test.dart --reporter=expanded
```

Expected: FAIL — `parseHasPermissionResponse` not defined.

- [ ] **Step 3: Add the method and static parser to `api_provider.dart`**

In `api_provider.dart`, add the following two methods. Place `hasPermission` in the **GENERIC METHODS** section (after `callMethodPost` around line 198). Place `parseHasPermissionResponse` directly below it.

```dart
/// Checks whether the current session user has [permType] access to [doctype].
/// Calls `frappe.client.has_permission` — the server enforces the check.
/// Returns the raw [Response]; parse it with [parseHasPermissionResponse].
Future<Response> hasPermission(String doctype, String permType) async {
  if (!_dioInitialised) await _initDio();
  return await _dio.get(
    '/api/method/frappe.client.has_permission',
    queryParameters: {'doctype': doctype, 'perm_type': permType},
  );
}

/// Parses a `frappe.client.has_permission` response into a [bool].
///
/// Expected shape: `{"message": {"has_permission": 1}}`.
/// Returns `false` for any malformed, null, or denied response.
/// Exposed as a public static method so unit tests can exercise this
/// logic without a live HTTP connection.
static bool parseHasPermissionResponse(dynamic data) {
  if (data is! Map) return false;
  final message = data['message'];
  if (message is! Map) return false;
  final hp = message['has_permission'];
  if (hp is bool) return hp;
  if (hp is int)  return hp == 1;
  return false;
}
```

- [ ] **Step 4: Run tests — verify they pass**

```
flutter test test/unit/has_permission_response_test.dart --reporter=expanded
```

Expected: all 9 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/app/data/providers/api_provider.dart test/unit/has_permission_response_test.dart
git commit -m "feat(permissions): add ApiProvider.hasPermission and response parser"
```

---

## Task 3: Rewrite `PermissionService`

**Files:**
- Modify: `lib/app/data/services/permission_service.dart`

Replace the broken DocType-definition fetch with `apiProvider.hasPermission`. Add `permType` support, `prefetchAll`, and a renamed public API.

- [ ] **Step 1: Replace the full contents of `permission_service.dart`**

```dart
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

class PermissionService extends GetxService {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  // Cache key: "$doctype:$permType"  e.g. "Stock Entry:read", "Batch:report"
  final Set<String> _pendingFetches = {};
  final RxMap<String, bool> _accessCache = <String, bool>{}.obs;

  /// Returns `null` while loading, `true` if permitted, `false` if denied.
  ///
  /// Triggers a lazy fetch if the result is not yet cached.
  bool? hasAccess(String doctype, {String permType = 'read'}) {
    final key = '$doctype:$permType';
    if (_accessCache.containsKey(key)) return _accessCache[key];
    if (!_pendingFetches.contains(key)) _fetchPermission(doctype, permType);
    return null;
  }

  /// Fires all [entries] in parallel and awaits completion.
  ///
  /// Call this after the user is confirmed logged in, before navigating
  /// to the home screen. After this returns every entry in [entries] is
  /// present in the cache — [hasAccess] will never return `null` for them.
  Future<void> prefetchAll(
    List<({String doctype, String permType})> entries,
  ) async {
    await Future.wait(
      entries.map((e) => _fetchPermission(e.doctype, e.permType)),
    );
  }

  /// Clears all cached results and any in-flight tracking.
  ///
  /// Call on logout or session change so stale permissions don't bleed
  /// into the next session.
  void clearCache() {
    _accessCache.clear();
    _pendingFetches.clear();
  }

  Future<void> _fetchPermission(String doctype, String permType) async {
    final key = '$doctype:$permType';
    if (_accessCache.containsKey(key)) return;
    if (_pendingFetches.contains(key)) return;
    _pendingFetches.add(key);
    try {
      final response = await _apiProvider.hasPermission(doctype, permType);
      _accessCache[key] =
          ApiProvider.parseHasPermissionResponse(response.data);
    } on DioException catch (e) {
      // 403 = session expired; all other errors = network/server failure.
      // Fail-closed in every case — never default to true.
      _accessCache[key] = false;
      if (e.response?.statusCode != 403) {
        print('PermissionService: check failed for $key — ${e.message}');
      }
    } catch (e) {
      _accessCache[key] = false;
      print('PermissionService: check failed for $key — $e');
    } finally {
      _pendingFetches.remove(key);
    }
  }
}
```

- [ ] **Step 2: Verify it compiles**

```
flutter analyze lib/app/data/services/permission_service.dart
```

Expected: no errors.

- [ ] **Step 3: Run the full test suite to catch any regressions**

```
flutter test --reporter=expanded
```

Expected: all tests pass. If any test imports `PermissionService` and calls `hasReadAccess` (the old method name), update those test files to call `hasAccess` instead.

- [ ] **Step 4: Commit**

```bash
git add lib/app/data/services/permission_service.dart
git commit -m "feat(permissions): rewrite PermissionService to use frappe.client.has_permission"
```

---

## Task 4: Add `permType` parameter to `DocTypeGuard`

**Files:**
- Modify: `lib/app/modules/global_widgets/doctype_guard.dart`

A single optional parameter with default `'read'` — all existing call sites are unchanged.

- [ ] **Step 1: Replace the full contents of `doctype_guard.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/services/permission_service.dart';

class DocTypeGuard extends StatelessWidget {
  final String doctype;

  /// The Frappe permission type to check. Defaults to `'read'`.
  /// Use `'report'` for report links (mirrors ERPNext's server enforcement).
  final String permType;

  final Widget child;
  final Widget? fallback;
  final Widget? loading;

  const DocTypeGuard({
    super.key,
    required this.doctype,
    this.permType = 'read',
    required this.child,
    this.fallback,
    this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final PermissionService service = Get.find<PermissionService>();

    return Obx(() {
      final hasAccess = service.hasAccess(doctype, permType: permType);

      // Loading state — null only when the entry was not pre-fetched
      if (hasAccess == null) {
        return loading ?? const SizedBox.shrink();
      }

      if (hasAccess == true) return child;

      return fallback ?? const SizedBox.shrink();
    });
  }
}
```

- [ ] **Step 2: Verify it compiles**

```
flutter analyze lib/app/modules/global_widgets/doctype_guard.dart
```

Expected: no errors.

- [ ] **Step 3: Run the full test suite**

```
flutter test --reporter=expanded
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/app/modules/global_widgets/doctype_guard.dart
git commit -m "feat(permissions): add permType parameter to DocTypeGuard"
```

---

## Task 5: Update `AppNavDrawer` — report guards + `_ModuleGroup` auto-hide

**Files:**
- Modify: `lib/app/modules/global_widgets/app_nav_drawer.dart`

Three changes in this file:
1. Add imports for `permission_entries.dart` and `permission_service.dart`
2. Rewrite `_ModuleGroup` to add `guardEntries` + auto-hide `Obx`
3. Wrap the four unguarded report `_DrawerItem`s in `DocTypeGuard` with `permType: 'report'`
4. Pass `guardEntries:` to each `_ModuleGroup` instance

- [ ] **Step 1: Add imports at the top of `app_nav_drawer.dart`**

After the existing imports, add:

```dart
import 'package:multimax/app/data/constants/permission_entries.dart';
import 'package:multimax/app/data/services/permission_service.dart';
```

- [ ] **Step 2: Replace the `_ModuleGroup` class**

Find the `_ModuleGroup` class (starting at `class _ModuleGroup extends StatelessWidget`) and replace it entirely with:

```dart
class _ModuleGroup extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final String currentRoute;
  final AppNavDrawerController drawerController;

  /// Every `(doctype, permType)` guarded within this group.
  /// The group hides itself when none are accessible.
  final List<PermEntry> guardEntries;

  const _ModuleGroup({
    required this.title,
    required this.icon,
    required this.children,
    required this.currentRoute,
    required this.drawerController,
    required this.guardEntries,
  });

  bool get _hasActiveChild {
    final routes = _extractRoutes(children);
    return routes.any(
      (r) => r.isNotEmpty && currentRoute.startsWith(r),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = Get.find<PermissionService>();

    return Obx(() {
      // Visible when at least one entry is accessible (true) or still
      // loading (null). Hides only when every entry is confirmed false.
      final anyAccessible = guardEntries.any(
        (e) => service.hasAccess(e.doctype, permType: e.permType) != false,
      );
      if (!anyAccessible) return const SizedBox.shrink();

      final initialExpanded =
          drawerController.isGroupExpanded(title, defaultValue: _hasActiveChild);

      return Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initialExpanded,
          onExpansionChanged: (v) =>
              drawerController.setGroupExpanded(title, v),
          leading: Icon(icon, color: Colors.grey.shade700, size: 22),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          iconColor:  Theme.of(context).primaryColor,
          textColor:  Theme.of(context).primaryColor,
          children: children,
        ),
      );
    });
  }
}
```

- [ ] **Step 3: Add report guards — Stock section**

In the Stock `_ModuleGroup`'s `children` list, find the two unguarded report `_DrawerItem`s and wrap each:

Replace:
```dart
_DrawerItem(
  title: 'Batch-Wise Balance',
  icon: Icons.history_toggle_off_rounded,
  route: AppRoutes.BATCH_WISE_BALANCE,
  currentRoute: currentRoute,
),
_DrawerItem(
  title:        'Item Variant Details',
  icon:         Icons.style_outlined,
  route:        AppRoutes.ITEM_VARIANT_DETAILS,
  currentRoute: currentRoute,
),
```

With:
```dart
DocTypeGuard(
  doctype: 'Batch',
  permType: 'report',
  child: _DrawerItem(
    title: 'Batch-Wise Balance',
    icon: Icons.history_toggle_off_rounded,
    route: AppRoutes.BATCH_WISE_BALANCE,
    currentRoute: currentRoute,
  ),
),
DocTypeGuard(
  doctype: 'Item',
  permType: 'report',
  child: _DrawerItem(
    title:        'Item Variant Details',
    icon:         Icons.style_outlined,
    route:        AppRoutes.ITEM_VARIANT_DETAILS,
    currentRoute: currentRoute,
  ),
),
```

- [ ] **Step 4: Add report guards — Manufacturing section**

In the Manufacturing `_ModuleGroup`'s `children` list, find the two unguarded report `_DrawerItem`s and wrap each:

Replace:
```dart
_DrawerItem(
  title: 'BOM Search',
  icon: Icons.manage_search_rounded,
  route: AppRoutes.BOM_SEARCH,
  currentRoute: currentRoute,
),
_DrawerItem(                                   // ← NEW
  title: 'Job Card Summary',
  icon: Icons.summarize_outlined,
  route: AppRoutes.JOB_CARD_SUMMARY,
  currentRoute: currentRoute,
),
```

With:
```dart
DocTypeGuard(
  doctype: 'BOM',
  permType: 'report',
  child: _DrawerItem(
    title: 'BOM Search',
    icon: Icons.manage_search_rounded,
    route: AppRoutes.BOM_SEARCH,
    currentRoute: currentRoute,
  ),
),
DocTypeGuard(
  doctype: 'Job Card',
  permType: 'report',
  child: _DrawerItem(
    title: 'Job Card Summary',
    icon: Icons.summarize_outlined,
    route: AppRoutes.JOB_CARD_SUMMARY,
    currentRoute: currentRoute,
  ),
),
```

- [ ] **Step 5: Pass `guardEntries` to each `_ModuleGroup` instance**

Find each `_ModuleGroup(` call in the main menu `ListView` and add the `guardEntries:` argument:

**Stock group** — add `guardEntries: kStockPermissions,`:
```dart
_ModuleGroup(
  title: 'Stock',
  icon: Icons.inventory_2_rounded,
  currentRoute: currentRoute,
  drawerController: drawerController,
  guardEntries: kStockPermissions,
  children: [ ... ],
),
```

**Buying group** — add `guardEntries: kBuyingPermissions,`:
```dart
_ModuleGroup(
  title: 'Buying',
  icon: Icons.shopping_bag_rounded,
  currentRoute: currentRoute,
  drawerController: drawerController,
  guardEntries: kBuyingPermissions,
  children: [ ... ],
),
```

**Manufacturing group** — add `guardEntries: kManufacturingPermissions,`:
```dart
_ModuleGroup(
  title: 'Manufacturing',
  icon: Icons.precision_manufacturing_rounded,
  currentRoute: currentRoute,
  drawerController: drawerController,
  guardEntries: kManufacturingPermissions,
  children: [ ... ],
),
```

**Selling group** — add `guardEntries: kSellingPermissions,`:
```dart
_ModuleGroup(
  title: 'Selling',
  icon: Icons.storefront_rounded,
  currentRoute: currentRoute,
  drawerController: drawerController,
  guardEntries: kSellingPermissions,
  children: [ ... ],
),
```

- [ ] **Step 6: Verify it compiles**

```
flutter analyze lib/app/modules/global_widgets/app_nav_drawer.dart
```

Expected: no errors.

- [ ] **Step 7: Run the full test suite**

```
flutter test --reporter=expanded
```

Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add lib/app/modules/global_widgets/app_nav_drawer.dart
git commit -m "feat(permissions): add report guards and auto-hide ModuleGroup in AppNavDrawer"
```

---

## Task 6: Wire up prefetch — `main.dart`, `HomeBinding`, `AuthenticationController`

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/app/modules/home/home_binding.dart`
- Modify: `lib/app/modules/auth/authentication_controller.dart`

`PermissionService` must be a permanent global service so `fetchUserDetails` (called from `main.dart`) can call `prefetchAll`. Remove it from `HomeBinding` and add it to `main.dart` instead.

- [ ] **Step 1: Register `PermissionService` in `main.dart`**

In `main.dart`, add the import:
```dart
import 'package:multimax/app/data/services/permission_service.dart';
```

Then add the registration after `ApiProvider` and before `AuthenticationController`:
```dart
await Get.putAsync<ApiProvider>(() async => ApiProvider(), permanent: true);

// Permission service must be registered before AuthenticationController so
// fetchUserDetails can call prefetchAll on login / app restart.
Get.put<PermissionService>(PermissionService(), permanent: true);

Get.put<DataWedgeService>(DataWedgeService(), permanent: true);
```

- [ ] **Step 2: Remove `PermissionService` from `HomeBinding`**

In `lib/app/modules/home/home_binding.dart`:

Remove the import line:
```dart
import 'package:multimax/app/data/services/permission_service.dart';
```

Remove the registration line:
```dart
Get.put(PermissionService());
```

- [ ] **Step 3: Update `AuthenticationController.fetchUserDetails`**

Add the following two imports at the top of `authentication_controller.dart`:

```dart
import 'package:multimax/app/data/constants/permission_entries.dart';
import 'package:multimax/app/data/services/permission_service.dart';
```

In `fetchUserDetails`, find the block that ends with:
```dart
currentUser.value = user;
isAuthenticated.value = true;

if (Get.isRegistered<StorageService>()) {
  await Get.find<StorageService>().saveUser(user);
}
```

Add the prefetch call immediately after the `saveUser` block:
```dart
currentUser.value = user;
isAuthenticated.value = true;

if (Get.isRegistered<StorageService>()) {
  await Get.find<StorageService>().saveUser(user);
}

if (Get.isRegistered<PermissionService>()) {
  await Get.find<PermissionService>().prefetchAll(kAppPermissions);
}
```

- [ ] **Step 4: Update `_clearSessionAndLocalData`**

In `authentication_controller.dart`, find `_clearSessionAndLocalData` and add the `clearCache` call:

Replace:
```dart
Future<void> _clearSessionAndLocalData() async {
  await _apiProvider.clearSessionCookies();
  if (Get.isRegistered<StorageService>()) {
    await Get.find<StorageService>().clearUserData();
  }
  currentUser.value = null;
  isAuthenticated.value = false;
}
```

With:
```dart
Future<void> _clearSessionAndLocalData() async {
  await _apiProvider.clearSessionCookies();
  if (Get.isRegistered<StorageService>()) {
    await Get.find<StorageService>().clearUserData();
  }
  if (Get.isRegistered<PermissionService>()) {
    Get.find<PermissionService>().clearCache();
  }
  currentUser.value = null;
  isAuthenticated.value = false;
}
```

- [ ] **Step 5: Verify everything compiles**

```
flutter analyze lib/
```

Expected: no errors.

- [ ] **Step 6: Run the full test suite**

```
flutter test --reporter=expanded
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/main.dart lib/app/modules/home/home_binding.dart lib/app/modules/auth/authentication_controller.dart
git commit -m "feat(permissions): wire prefetchAll at login; promote PermissionService to permanent global service"
```

---

## Manual Smoke Test

After all tasks are committed, verify the feature works end-to-end on a device:

1. Log in as a **System Manager** — all drawer items and dashboard tiles should appear (same as before).
2. Log in as a **restricted user** (e.g., one with only `Stock User` role, no manufacturing access):
   - Manufacturing `_ModuleGroup` should be hidden entirely.
   - Selling `_ModuleGroup` should be hidden if the user lacks `POS Upload:read`.
   - Report links (Batch-Wise Balance, etc.) should be hidden if the user lacks `report` permission on the ref doctype.
3. Open the drawer immediately after login — no shimmer skeletons should appear (permissions are pre-fetched).
4. Log out — permissions cache clears. Log back in as a different user — drawer reflects the new user's access.
