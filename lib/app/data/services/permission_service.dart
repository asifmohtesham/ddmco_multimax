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
    _roleFetches.clear();
  }

  Future<void> _fetchPermission(String doctype, String permType) async {
    final key = '$doctype:$permType';
    if (_accessCache.containsKey(key)) return;
    if (_pendingFetches.contains(key)) return;
    _pendingFetches.add(key);
    try {
      if (permType == 'create' || permType == 'write') {
        // create/write cannot be probed via get_list; resolve from the
        // doctype's DocPerm rows (getdoctype) intersected with the user's roles.
        await _resolveDocTypeRoles(doctype);
      } else {
        final response = await _apiProvider.hasPermission(doctype, permType);
        _accessCache[key] =
            ApiProvider.parseHasPermissionResponse(response.data);
      }
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

  /// Resolves and caches both `create` and `write` for [doctype] from a single
  /// getdoctype fetch, intersecting the DocPerm rows with the current user's
  /// roles. De-duped so concurrent create/write lookups share one network call.
  Future<void> _resolveDocTypeRoles(String doctype) {
    return _roleFetches.putIfAbsent(doctype, () async {
      try {
        final roles = await _apiProvider.fetchDocTypeRoles(doctype);
        final userRoles = _currentUserRoles();
        _accessCache['$doctype:create'] = roleGrants(userRoles, roles.create);
        _accessCache['$doctype:write'] = roleGrants(userRoles, roles.write);
      } catch (_) {
        // Fail-closed for operators (deny) but keep admins visible, and cache
        // the verdict so we don't refetch getdoctype on every rebuild.
        final userRoles = _currentUserRoles();
        _accessCache['$doctype:create'] = roleGrants(userRoles, const {});
        _accessCache['$doctype:write'] = roleGrants(userRoles, const {});
        rethrow;
      } finally {
        _roleFetches.remove(doctype);
      }
    });
  }

  Set<String> _currentUserRoles() {
    try {
      final user = Get.find<AuthenticationController>().currentUser.value;
      return user?.roles.toSet() ?? <String>{};
    } catch (_) {
      return <String>{};
    }
  }

  /// True when [userRoles] includes `System Manager` (admin bypass, mirroring
  /// [AuthenticationController.hasAnyRole]) or any role in [permittedRoles].
  /// Exposed as a public static method for unit testing.
  static bool roleGrants(Set<String> userRoles, Set<String> permittedRoles) {
    if (userRoles.contains('System Manager')) return true;
    return permittedRoles.any(userRoles.contains);
  }
}
