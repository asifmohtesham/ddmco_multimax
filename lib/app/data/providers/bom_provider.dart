import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:ddmco_multimax/app/data/providers/api_provider.dart';

class BomProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getBOMs({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
  }) async {
    return _apiProvider.getDocumentList(
      'BOM',
      limit: limit,
      limitStart: limitStart,
      filters: filters,
      fields: ['name', 'item', 'item_name', 'is_active', 'is_default', 'docstatus', 'currency', 'total_cost', 'modified'],
      orderBy: 'modified desc',
    );
  }
}