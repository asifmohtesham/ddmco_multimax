import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class PurchaseOrderProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getPurchaseOrders({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    String orderBy = 'modified desc',
  }) async {
    return _apiProvider.getDocumentList(
      'Purchase Order',
      limit: limit,
      limitStart: limitStart,
      filters: filters,
      fields: ['name', 'supplier', 'transaction_date', 'grand_total', 'currency', 'status', 'docstatus', 'modified', 'creation'],
      orderBy: orderBy,
    );
  }

  Future<Response> getPurchaseOrder(String name) async {
    return _apiProvider.getDocument('Purchase Order', name);
  }

  Future<Response> createPurchaseOrder(Map<String, dynamic> data) async {
    return _apiProvider.createDocument('Purchase Order', data);
  }

  Future<Response> updatePurchaseOrder(String name, Map<String, dynamic> data) async {
    return _apiProvider.updateDocument('Purchase Order', name, data);
  }
}