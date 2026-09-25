import 'package:get/get.dart' hide Response;
import 'package:dio/dio.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

class SearchProvider {
  ApiProvider get _apiProvider => Get.find<ApiProvider>();

  Future<Response> globalSearch(String query, {int limit = 20, int start = 0}) async {
    return await _apiProvider.callMethod(
      'frappe.utils.global_search.search',
      params: {
        'text': query,
        'limit': limit,
        'start': start,
      },
    );
  }

  Future<Response> awesomeBarSearch(String query) async {
    return await _apiProvider.callMethod(
      'frappe.desk.search.awesomebar_search',
      params: {
        'txt': query,
      },
    );
  }

  Future<Response> getBootData() async {
    return await _apiProvider.callMethod('frappe.boot');
  }
}
