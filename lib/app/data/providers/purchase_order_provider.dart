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
    // Default filter: Submitted (docstatus=1)
    final effectiveFilters = filters ?? {};
    if (!effectiveFilters.containsKey('docstatus')) {
      effectiveFilters['docstatus'] = 1;
    }
    // Exclude closed/cancelled? Usually status != 'Closed' etc. 
    // Let's stick to docstatus=1 for now as "Submit state" was requested.

    return _apiProvider.getDocumentList(
      'Purchase Order',
      limit: limit,
      limitStart: limitStart,
      filters: effectiveFilters,
      fields: ['name', 'supplier', 'transaction_date', 'grand_total', 'currency', 'status'],
      orderBy: 'modified desc',
    );
  }
}
