import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class SupplierProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getSuppliers({
    int limit = 0,
    String? searchTerm,
  }) async {
    return _apiProvider.getDocumentList(
      'Supplier',
      limit: limit,
      fields: ['name', 'supplier_name', 'supplier_group'],
      filters: {
        'disabled': 0,
        if (searchTerm != null && searchTerm.isNotEmpty)
          'supplier_name': ['like', '%$searchTerm%'],
      },
      orderBy: 'supplier_name asc',
    );
  }
}
