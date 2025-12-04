
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

  // This method likely needs a custom API endpoint (e.g., a whitelisted script)
  // to get stock levels, as it's often in a different doctype (Stock Ledger Entry or Bin).
  // For now, I'll create a placeholder that assumes a method exists in ApiProvider.
  Future<Response> getStockLevels(String itemCode) async {
    // Assuming a method like this exists or will be created in ApiProvider:
    // return _apiProvider.getReport('Stock Balance', filters: {'item_code': itemCode});
    
    // For now, returning a dummy response. I'll need to update ApiProvider for real data.
    return Future.value(Response(data: {
      'message': {
        'result': [
          {'warehouse': 'WH-DXB1 - KA', 'qty': 100.0},
          {'warehouse': 'WH-SHJ1 - SM', 'qty': 50.0},
        ]
      }
    }, statusCode: 200, requestOptions: RequestOptions(path: '')));
  }
}
