import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class PosUploadProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getPosUploads({
    int limit = 20, 
    int limitStart = 0, 
    Map<String, dynamic>? filters,
    String orderBy = 'modified desc',
  }) async {
    // POS Upload specific logic to exclude cancelled/deleted if needed, but standard filters handle it.
    if (filters != null && filters.containsKey('docstatus')) {
      filters.remove('docstatus'); 
    }
    
    return _apiProvider.getDocumentList(
      'POS Upload', 
      limit: limit, 
      limitStart: limitStart, 
      filters: filters,
      orderBy: orderBy,
      fields: ['name', 'customer', 'date', 'modified', 'status'],
    );
  }

  Future<Response> getPosUpload(String name) async {
    return _apiProvider.getPosUpload(name);
  }

  Future<Response> updatePosUpload(String name, Map<String, dynamic> data) async {
    return _apiProvider.updateDocument('POS Upload', name, data);
  }
}
