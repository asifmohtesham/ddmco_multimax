import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';

class PermissionService extends GetxService {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  // Cache key: "$doctype:$permType"  e.g. "Stock Entry:read", "Batch:report"
  final Set<String> _pendingFetches = {};
  final RxMap<String, bool> _accessCache = <String, bool>{}.obs;

  // De-dupes concurrent role resolutions per doctype: a single getdoctype call
  // yields both the `create` and `write` results.
  final Map<String, Future<void>> _roleFetches = {};

  // Frappe module per doctype, captured from the same getdoctype response.
  final Map<String, String> _modules = {};

  // Bumped by every clearCache(). A fetch records the value it started under
  // and drops its result if the session has changed by the time it lands.
  int _session = 0;

  /// Returns `null` while loading, `true` if permitted, `false` if denied.
  ///
  /// Triggers a lazy fetch if the result is not yet cached. Signed out, it
  /// is `false` and nothing is fetched: clearing the cache on logout rebuilds
  /// every mounted [DocTypeGuard], and those must not probe a dead session.
  bool? hasAccess(String doctype, {String permType = 'read'}) {
    final key = '$doctype:$permType';
    // Read the cache before the session check so an enclosing Obx always
    // subscribes to it.
    final cached = _accessCache[key];
    if (!_hasSession) return false;
    if (cached != null) return cached;
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
  /// into the next session. Fetches still in flight are orphaned — their
  /// results are discarded when they land.
  void clearCache() {
    _session++;
    _accessCache.clear();
    _pendingFetches.clear();
    _roleFetches.clear();
    _modules.clear();
  }

  /// [doctype]'s Frappe module (e.g. Item → Stock), or `null` if it can't be
  /// resolved. Reuses the getdoctype fetch behind create/write checks, so
  /// doctypes prefetched at login cost no extra request.
  Future<String?> moduleOf(String doctype) async {
    if (!_hasSession) return null;
    if (!_modules.containsKey(doctype)) {
      try {
        await _resolveDocTypeRoles(doctype);
      } catch (_) {}
    }
    return _modules[doctype];
  }

  Future<void> _fetchPermission(String doctype, String permType) async {
    final key = '$doctype:$permType';
    if (!_hasSession) return;
    if (_accessCache.containsKey(key)) return;
    if (_pendingFetches.contains(key)) return;
    _pendingFetches.add(key);
    final session = _session;
    try {
      if (permType == 'create' || permType == 'write') {
        // create/write cannot be probed via get_list; resolve from the
        // doctype's DocPerm rows (getdoctype) intersected with the user's roles.
        await _resolveDocTypeRoles(doctype);
      } else {
        final response = await _apiProvider.hasPermission(doctype, permType);
        if (session != _session) return;
        _accessCache[key] =
            ApiProvider.parseHasPermissionResponse(response.data);
      }
    } on DioException catch (e) {
      if (session != _session) return;
      // 403 = session expired; all other errors = network/server failure.
      // Fail-closed in every case — never default to true.
      _accessCache[key] = false;
      if (e.response?.statusCode != 403) {
        print('PermissionService: check failed for $key — ${e.message}');
      }
    } catch (e) {
      if (session != _session) return;
      _accessCache[key] = false;
      print('PermissionService: check failed for $key — $e');
    } finally {
      // An orphaned fetch must not release the key a newer session holds.
      if (session == _session) _pendingFetches.remove(key);
    }
  }

  /// Resolves and caches both `create` and `write` for [doctype] from a single
  /// getdoctype fetch, intersecting the DocPerm rows with the current user's
  /// roles. When the roles are not known (see [rolesKnown]) the server is
  /// asked instead. De-duped so concurrent create/write lookups share one
  /// resolution.
  Future<void> _resolveDocTypeRoles(String doctype) {
    final session = _session;
    return _roleFetches.putIfAbsent(doctype, () async {
      try {
        final roles = await _apiProvider.fetchDocTypeRoles(doctype);
        if (session != _session) return;
        if (roles.module != null) _modules[doctype] = roles.module!;
        final userRoles = _currentUserRoles();
        if (rolesKnown(userRoles)) {
          _accessCache['$doctype:create'] = roleGrants(userRoles, roles.create);
          _accessCache['$doctype:write'] = roleGrants(userRoles, roles.write);
        } else {
          // Nothing to intersect the DocPerm rows with, so the server
          // evaluates the permission itself. A user who is signing out has
          // no roles either, and must not be probed.
          if (!_hasSession) return;
          final granted = await Future.wait([
            _serverGrants(doctype, 'create'),
            _serverGrants(doctype, 'write'),
          ]);
          if (session != _session) return;
          _accessCache['$doctype:create'] = granted[0];
          _accessCache['$doctype:write'] = granted[1];
        }
      } catch (_) {
        if (session != _session) return;
        // Fail-closed for operators (deny) but keep admins visible, and cache
        // the verdict so we don't refetch getdoctype on every rebuild.
        final userRoles = _currentUserRoles();
        _accessCache['$doctype:create'] = roleGrants(userRoles, const {});
        _accessCache['$doctype:write'] = roleGrants(userRoles, const {});
        rethrow;
      } finally {
        if (session == _session) _roleFetches.remove(doctype);
      }
    });
  }

  Future<bool> _serverGrants(String doctype, String permType) async {
    final response = await _apiProvider.hasDocTypePermission(doctype, permType);
    return ApiProvider.parseHasDocPermissionResponse(response.data);
  }

  /// Whether the session user's roles could be read.
  ///
  /// Every Frappe user holds at least the automatic roles (`All`, …), so an
  /// empty set means the lookup failed rather than "no roles". That is the
  /// normal case on Frappe v16 for users who are not System Managers: the
  /// `roles` table on User is permlevel 1 and the v15 `get_roles` endpoint
  /// was removed. Exposed as a public static method for unit testing.
  static bool rolesKnown(Set<String> userRoles) => userRoles.isNotEmpty;

  /// Whether a user is signed in, i.e. whether a probe could be answered.
  bool get _hasSession {
    try {
      return Get.find<AuthenticationController>().isAuthenticated.value;
    } catch (_) {
      return false;
    }
  }

  Set<String> _currentUserRoles() {
    try {
      final user = Get.find<AuthenticationController>().currentUser.value;
      return user?.roles.toSet() ?? <String>{};
    } catch (_) {
      return <String>{};
    }
  }

  /// True when [userRoles] includes `System Manager` (admin bypass) or any
  /// role in [permittedRoles].
  /// Exposed as a public static method for unit testing.
  static bool roleGrants(Set<String> userRoles, Set<String> permittedRoles) {
    if (userRoles.contains('System Manager')) return true;
    return permittedRoles.any(userRoles.contains);
  }
}
