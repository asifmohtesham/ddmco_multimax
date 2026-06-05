import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class CustomerProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getCustomers({
    int limit = 0,
    String? searchTerm,
  }) async {
    return _apiProvider.getDocumentList(
      'Customer',
      limit: limit,
      fields: ['name', 'customer_name', 'customer_group', 'territory'],
      filters: {
        'disabled': 0,
        if (searchTerm != null && searchTerm.isNotEmpty)
          'customer_name': ['like', '%$searchTerm%'],
      },
      orderBy: 'customer_name asc',
    );
  }
}
