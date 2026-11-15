// test/unit/user_provider_desk_roles_test.dart
//
// Frappe v16 removed `get_roles`, and the User `roles` table is permlevel 1,
// so a user who is not a System Manager can only read their roles from the
// boot data Desk embeds in its page.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';

import '../helpers/auth_fakes.dart';

String deskPage(Map<String, dynamic> user) =>
    '<script>frappe.boot = ${jsonEncode({'user': user})};</script>';

void main() {
  late FakeApiProvider api;

  setUp(() {
    Get.testMode = true;
    api = FakeApiProvider();
    Get.put<ApiProvider>(api);
  });

  tearDown(() => Get.deleteAll(force: true));

  test('reads the session user\'s roles from Desk boot data', () async {
    api.onGetDeskHtml = () async => deskPage({
          'name': kTestEmail,
          'roles': ['Sales User', 'Stock User - Custom', 'All'],
        });

    expect(await UserProvider().getRolesFromDesk(kTestEmail),
        ['Sales User', 'Stock User - Custom', 'All']);
  });

  test('ignores a page rendered for someone else', () async {
    api.onGetDeskHtml = () async => deskPage({
          'name': 'someone.else@example.com',
          'roles': ['System Manager'],
        });

    expect(await UserProvider().getRolesFromDesk(kTestEmail), isEmpty);
  });

  test('no page, or a page without boot data, yields no roles', () async {
    expect(await UserProvider().getRolesFromDesk(kTestEmail), isEmpty);

    api.onGetDeskHtml = () async => '<html>Login</html>';
    expect(await UserProvider().getRolesFromDesk(kTestEmail), isEmpty);
  });
}
