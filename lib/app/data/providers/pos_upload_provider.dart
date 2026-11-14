import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class PosUploadProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getPosUploads({
    int limit = 50,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    String orderBy = 'modified desc',
  }) async {
    // POS Upload specific logic to exclude cancelled/deleted if needed
    if (filters != null && filters.containsKey('docstatus')) {
      filters.remove('docstatus');
    }

    return _apiProvider.getDocumentList(
      'POS Upload',
      limit: limit,
      limitStart: limitStart,
      filters: filters,
      orderBy: orderBy,
      // Added 'total_qty'
      fields: ['name', 'customer', 'date', 'modified', 'status', 'total_qty'],
    );
  }

  Future<Response> getPosUpload(String name) async {
    return _apiProvider.getPosUpload(name);
  }

  Future<Response> updatePosUpload(String name, Map<String, dynamic> data) async {
    return _apiProvider.updateDocument('POS Upload', name, data);
  }

  /// Whether the current session user may write (update) the specific
  /// POS Upload [name]. Fail-closed: returns `false` on any network or
  /// permission error.
  Future<bool> canWrite(String name) async {
    try {
      final res =
          await _apiProvider.hasDocPermission('POS Upload', name, 'write');
      return ApiProvider.parseHasDocPermissionResponse(res.data);
    } catch (_) {
      return false;
    }
  }

  /// Whether a user holding [userRoles] may write the `status` field, which
  /// is permlevel-gated on the server (doc-level write alone is not enough —
  /// Frappe silently discards higher-permlevel changes from users without a
  /// write rule at that level). Complements [canWrite]; both must pass
  /// before the Status control is enabled. Fail-closed on any error.
  Future<bool> canWriteStatusField(Set<String> userRoles) async {
    try {
      final meta = await _apiProvider.getDocTypeMeta('POS Upload');
      return ApiProvider.fieldWriteGranted(
          meta.data, 'POS Upload', 'status', userRoles);
    } catch (_) {
      return false;
    }
  }
}