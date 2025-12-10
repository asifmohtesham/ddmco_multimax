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
      limit: 0,
    );
  }

  /// Fetches Employees who report to the given [employeeId].
  Future<Response> getDirectReports(String employeeId) async {
    return await _apiProvider.getDocumentList(
      'Employee',
      filters: {
        'reports_to': employeeId,
        'status': 'Active',
        'user_id': ['!=', '']
      },
      fields: ['name', 'employee_name', 'user_id'], // 'name' is Employee ID
      limit: 0,
    );
  }

  /// Helper to find Employee ID for a given User ID (Email)
  Future<Response> getEmployeeIdForUser(String userEmail) async {
    return await _apiProvider.getDocumentList(
      'Employee',
      filters: {'user_id': userEmail, 'status': 'Active'},
      fields: ['name'],
      limit: 1,
    );
  }

  /// Fetches roles using standard RPC method which is accessible to the user
  Future<Response> getUserRoles(String userId) async {
    return await _apiProvider.callMethod(
      'frappe.core.doctype.user.user.get_roles',
      params: {'uid': userId},
    );
  }
}