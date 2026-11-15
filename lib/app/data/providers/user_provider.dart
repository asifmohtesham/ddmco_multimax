import 'package:get/get.dart' hide Response;
import 'package:dio/dio.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/workspace_menu.dart';

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

  /// Fetches the roles of [userId].
  ///
  /// Frappe v15 only: the endpoint was removed in v16 and the call fails
  /// there. See [getRolesFromDesk].
  Future<Response> getUserRoles(String userId) async {
    return await _apiProvider.callMethod(
      'frappe.core.doctype.user.user.get_roles',
      params: {'uid': userId},
    );
  }

  /// The session user's roles, read from the boot data Desk embeds in its
  /// page (`frappe.boot.user.roles`).
  ///
  /// This is the only standard place a user who is not a System Manager can
  /// read their roles on Frappe v16: [getUserRoles] is gone there and the
  /// User document's `roles` table is permlevel 1. Empty when the page cannot
  /// be read, carries no boot data, or was rendered for someone other than
  /// [userId] — roles must never be taken from another session.
  Future<List<String>> getRolesFromDesk(String userId) async {
    final html = await _apiProvider.getDeskHtml();
    if (html == null) return const [];
    final desk = deskBootFromHtml(html);
    if (desk == null || desk.userId != userId) return const [];
    return desk.roles;
  }
}
