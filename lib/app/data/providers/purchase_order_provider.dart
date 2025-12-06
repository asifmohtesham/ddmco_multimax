import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:ddmco_multimax/app/data/providers/api_provider.dart';

class PurchaseOrderProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getPurchaseOrders({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
  }) async {
    final effectiveFilters = filters ?? {};
    if (!effectiveFilters.containsKey('docstatus')) {
      effectiveFilters['docstatus'] = 1;
    }

    return _apiProvider.getDocumentList(
      'Purchase Order',
      limit: limit,
      limitStart: limitStart,
      filters: effectiveFilters,
      fields: ['name', 'supplier', 'transaction_date', 'grand_total', 'currency', 'status'],
      orderBy: 'modified desc',
    );
  }

  Future<Response> getPurchaseOrder(String name) async {
    return _apiProvider.getDocument('Purchase Order', name);
  }
}
