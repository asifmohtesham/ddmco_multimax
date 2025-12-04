
import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:ddmco_multimax/app/data/providers/api_provider.dart';
import 'package:intl/intl.dart';

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
    var filters = {
      'company': 'Multimax',
      'from_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'to_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'item_code': itemCode,
      'warehouse': 'WH-DXB1 - KA',
      "valuation_field_type": "Currency",
      "rack": [],
      "show_variant_attributes": 1,
      "show_dimension_wise_stock": 1,
    };
    return _apiProvider.getReport('Stock Balance', filters: filters);
  }
}
