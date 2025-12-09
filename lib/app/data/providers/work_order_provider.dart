import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class WorkOrderProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getWorkOrders({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
  }) async {
    return _apiProvider.getDocumentList(
      'Work Order',
      limit: limit,
      limitStart: limitStart,
      filters: filters,
      fields: ['name', 'production_item', 'item_name', 'bom_no', 'qty', 'produced_qty', 'status', 'planned_start_date', 'docstatus', 'modified'],
      orderBy: 'modified desc',
    );
  }
}