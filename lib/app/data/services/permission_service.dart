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
