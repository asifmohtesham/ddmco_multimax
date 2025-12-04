
import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:ddmco_multimax/app/data/providers/api_provider.dart';

class ItemProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getItems({
    int limit = 20, 
    int limitStart = 0, 
    Map<String, dynamic>? filters,
    String orderBy = 'modified desc',
  }) async {
    return _apiProvider.getDocumentList(
      'Item', 
      limit: limit, 
      limitStart: limitStart, 
      filters: filters,
      orderBy: orderBy,
      fields: ['name', 'item_name', 'item_code', 'item_group', 'image', 'variant_of', 'country_of_origin', 'description'],
    );
  }

  Future<Response> getStockLevels(String itemCode) async {
    return _apiProvider.getReport('Stock Balance', filters: {'item_code': itemCode});
  }
}
