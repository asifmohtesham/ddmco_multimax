import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';

class PermissionService extends GetxService {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final AuthenticationController _authController = Get.find<AuthenticationController>();

  // Cache: DocType -> List of Roles allowed to read
  final Map<String, List<String>> _readPermissionsCache = {};

  // Observable map to trigger UI updates when permissions are loaded
  final RxMap<String, bool> _accessCache = <String, bool>{}.obs;

  /// Checks if the current user has read access to the given [doctype].
  /// Returns null if loading, true/false otherwise.
  bool? hasReadAccess(String doctype) {
    if (_accessCache.containsKey(doctype)) {
      return _accessCache[doctype];
    }

    // Trigger fetch if not already cached/loading
    _fetchDocTypePermissions(doctype);
    return null; // Loading state
  }

  Future<void> _fetchDocTypePermissions(String doctype) async {
    // Prevent duplicate fetches
    if (_readPermissionsCache.containsKey(doctype)) return;

    try {
      final response = await _apiProvider.getDocument('DocType', doctype);

      if (response.statusCode == 200 && response.data['data'] != null) {
        final data = response.data['data'];
        final List<dynamic> permissions = data['permissions'] ?? [];

        final allowedRoles = <String>{};

        // System Manager always has access
        allowedRoles.add('System Manager');

        for (var p in permissions) {
          // Check for Read (1) or Write (1) access.
          // Usually 'read' is enough for menu visibility.
          // 'permlevel' 0 is the base level for the document.
          if ((p['read'] == 1) && (p['permlevel'] == 0)) {
            allowedRoles.add(p['role']);
          }
        }

        _readPermissionsCache[doctype] = allowedRoles.toList();

        // Determine access for current user immediately
        final hasAccess = _authController.hasAnyRole(allowedRoles.toList());
        _accessCache[doctype] = hasAccess;
      } else {
        // Fail safe: deny access if fetch fails without exception
        _accessCache[doctype] = false;
      }
    } on DioException catch (e) {
      // HANDLE 403 FORBIDDEN
      // If the user cannot read the DocType definition (metadata), we assume they
      // are a standard user. We grant access to avoid locking them out of the UI.
      // This covers: Item, Purchase Order, Purchase Receipt, Stock Entry, Delivery Note,
      // Packing Slip, BOM, Work Order, Job Card, POS Upload.
      if (e.response?.statusCode == 403) {
        print('Permission Warning: 403 Forbidden reading DocType "$doctype". Defaulting to ALLOW.');
        _accessCache[doctype] = true;
      } else {
        print('Error fetching permissions for $doctype: $e');
        _accessCache[doctype] = false;
      }
    } catch (e) {
      print('Error fetching permissions for $doctype: $e');
      _accessCache[doctype] = false;
    }
  }
}