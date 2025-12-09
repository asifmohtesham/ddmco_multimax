import 'package:get/get.dart' hide Response;
import 'package:dio/dio.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

class UserProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getUsers() async {
    return await _apiProvider.getDocumentList(
      'User',
      filters: {'enabled': 1},
      fields: ['name', 'full_name', 'email'],
      limit: 0, // 0 = All records
    );
  }
}