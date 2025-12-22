import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class MaterialRequestProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getMaterialRequests({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    String orderBy = 'modified desc',
  }) async {
    return _apiProvider.getDocumentList(
        'Material Request',
        limit: limit,
        limitStart: limitStart,
        filters: filters,
        orderBy: orderBy,
        fields: ['name', 'transaction_date', 'schedule_date', 'status', 'docstatus', 'material_request_type']
    );
  }

  Future<Response> getMaterialRequest(String name) async {
    return _apiProvider.getDocument('Material Request', name);
  }

  Future<Response> createMaterialRequest(Map<String, dynamic> data) async {
    return _apiProvider.createDocument('Material Request', data);
  }

  Future<Response> updateMaterialRequest(String name, Map<String, dynamic> data) async {
    return _apiProvider.updateDocument('Material Request', name, data);
  }

  Future<Response> deleteMaterialRequest(String name) async {
    return _apiProvider.deleteDocument('Material Request', name);
  }
}