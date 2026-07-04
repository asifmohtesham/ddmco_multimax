import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class WarehouseProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getWarehouses({bool includeGroups = false}) async {
    return _apiProvider.getDocumentList(
      'Warehouse',
      limit: 0, // fetch all — warehouse list is small
      fields: ['name', 'warehouse_name', 'is_group', 'disabled'],
      filters: {
        if (!includeGroups) 'is_group': 0,
        'disabled': 0,
      },
      orderBy: 'name asc',
    );
  }
}
