// app/data/providers/batch_provider.dart
import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class BatchProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getBatches({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    String orderBy = 'modified desc',
  }) async {
    return _apiProvider.getDocumentList(
      'Batch',
      limit: limit,
      limitStart: limitStart,
      filters: filters,
      orderBy: orderBy,
      fields: ['name', 'item', 'description', 'manufacturing_date', 'expiry_date', 'custom_packaging_qty', 'modified', 'creation'],
    );
  }

  Future<Response> getBatch(String name) async {
    return _apiProvider.getDocument('Batch', name);
  }

  Future<Response> createBatch(Map<String, dynamic> data) async {
    return _apiProvider.createDocument('Batch', data);
  }

  Future<Response> updateBatch(String name, Map<String, dynamic> data) async {
    return _apiProvider.updateDocument('Batch', name, data);
  }
}