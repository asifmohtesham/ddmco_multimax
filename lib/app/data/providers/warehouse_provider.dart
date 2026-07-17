import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class WarehouseProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  /// [isGroup] selects group-only (`true`) or leaf-only (`false`) warehouses,
  /// mirroring the reorder link filters in erpnext item.js:449-473
  /// ("Check in (group)" → `is_group: 1`, "Request for" → `is_group: 0`).
  /// When null, [includeGroups] keeps the historical behaviour: leaf-only
  /// unless groups are explicitly requested.
  Future<Response> getWarehouses({
    bool includeGroups = false,
    bool? isGroup,
  }) async {
    return _apiProvider.getDocumentList(
      'Warehouse',
      limit: 0, // fetch all — warehouse list is small
      fields: ['name', 'warehouse_name', 'is_group', 'disabled'],
      filters: {
        if (isGroup != null)
          'is_group': isGroup ? 1 : 0
        else if (!includeGroups)
          'is_group': 0,
        'disabled': 0,
      },
      orderBy: 'name asc',
    );
  }
}
