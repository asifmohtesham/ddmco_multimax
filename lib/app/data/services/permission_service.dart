import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';

class PermissionService extends GetxService {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final AuthenticationController _authController = Get.find<AuthenticationController>();

  // Cache: DocType -> List of Roles allowed to read
  final Map<String, List<String>> _readPermissionsCache = {};

  // Track in-flight requests to prevent duplicate API calls
  final Set<String> _pendingFetches = {};

  // Observable map to trigger UI updates when permissions are loaded
  final RxMap<String, bool> _accessCache = <String, bool>{}.obs;

  /// Checks if the current user has read access to the given [doctype].
  /// Returns null if loading, true/false otherwise.
  bool? hasReadAccess(String doctype) {
    if (_accessCache.containsKey(doctype)) {
      return _accessCache[doctype];
    }

    // Trigger fetch if not already cached and not currently fetching
    if (!_pendingFetches.contains(doctype)) {
      _fetchDocTypePermissions(doctype);
    }

    return null; // Loading state
  }

  /// Clears all cached permission data, forcing re-verification on next access.
  void clearCache() {
    _readPermissionsCache.clear();
    _accessCache.clear();
    _pendingFetches.clear();
    print('Permissions cache cleared.');
  }

  Future<void> _fetchDocTypePermissions(String doctype) async {
    if (_readPermissionsCache.containsKey(doctype)) return;

    _pendingFetches.add(doctype);

    try {
      final response = await _apiProvider.getDocument('DocType', doctype);

      if (response.statusCode == 200 && response.data['data'] != null) {
        final data = response.data['data'];
        final List<dynamic> permissions = data['permissions'] ?? [];

        final allowedRoles = <String>{};

        // System Manager always has access
        allowedRoles.add('System Manager');

        for (var p in permissions) {
          if ((p['read'] == 1) && (p['permlevel'] == 0)) {
            allowedRoles.add(p['role']);
          }
        }

        _readPermissionsCache[doctype] = allowedRoles.toList();

        // Determine access for current user immediately
        final hasAccess = _authController.hasAnyRole(allowedRoles.toList());
        _accessCache[doctype] = hasAccess;
      } else {
        _accessCache[doctype] = false;
      }
    } on DioException catch (e) {
      // Handle 403: If user can't read DocType definition, assume they are standard user and Allow Access
      if (e.response?.statusCode == 403) {
        // print('Permission Warning: 403 Forbidden reading DocType "$doctype". Defaulting to ALLOW.');
        _accessCache[doctype] = true;
      } else {
        print('Error fetching permissions for $doctype: $e');
        _accessCache[doctype] = false;
      }
    } catch (e) {
      print('Error fetching permissions for $doctype: $e');
      _accessCache[doctype] = false;
    } finally {
      _pendingFetches.remove(doctype);
    }
  }
}