import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class JobCardProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getJobCards({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
  }) async {
    return _apiProvider.getDocumentList(
      'Job Card',
      limit: limit,
      limitStart: limitStart,
      filters: filters,
      fields: ['name', 'work_order', 'operation', 'workstation', 'status', 'for_quantity', 'total_completed_qty', 'docstatus', 'modified', 'posting_date'],
      orderBy: 'modified desc',
    );
  }
}