// test/unit/app_nav_drawer_workspace_source_test.dart
//
// Where the drawer gets the user's workspace pages from. Frappe 16.56 removed
// `get_workspace_sidebar_items` and stopped whitelisting `get_workspaces`;
// the pages then come from the boot data Desk embeds in its page.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';

import '../helpers/auth_fakes.dart';

/// A Desk page whose boot data lists one workspace and one sidebar, "Zeta",
/// that links Item — a group no default layout has.
String deskPage() => '<script>frappe.boot = ${jsonEncode({
      'workspaces': {
        'pages': [
          {'name': 'Zeta', 'title': 'Zeta', 'module': 'Zeta', 'public': 1},
        ],
      },
      'module_sidebars': {
        'Zeta': {
          'label': 'Zeta',
          'app': 'erpnext',
          'workspaces': ['Zeta'],
          'items': [
            {'type': 'Link', 'link_type': 'DocType', 'link_to': 'Item'},
          ],
        },
      },
    })};</script>';

void main() {
  late FakeApiProvider api;

  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  setUp(() {
    Get.testMode = true;
    api = FakeApiProvider();
    Get.put<ApiProvider>(api);
    Get.put<StorageService>(FakeStorageService());
    Get.put<PermissionService>(FakePermissionService());
  });

  tearDown(() => Get.deleteAll(force: true));

  List<String> groupTitles(AppNavDrawerController c) =>
      [for (final g in c.groups) g.title];

  /// Frappe 16.56: the v15 name is gone (417), the v16 name is refused (403).
  Future<Never> refuse(String method) async => throw httpError(
      method == AppNavDrawerController.workspaceMethods.first ? 417 : 403);

  test('16.56: both endpoints refuse → pages come from Desk boot data',
      () async {
    api.onCallMethod = refuse;
    api.onGetDeskHtml = () async => deskPage();
    final drawer = AppNavDrawerController();

    await drawer.loadFor(kTestEmail);

    expect(groupTitles(drawer), contains('Zeta'));
  });

  test('16.56: a later load skips the endpoints that refused', () async {
    api.onCallMethod = refuse;
    api.onGetDeskHtml = () async => deskPage();
    final drawer = AppNavDrawerController();
    await drawer.loadFor(kTestEmail);
    api.methodCalls.clear();

    await drawer.loadFor('someone.else@example.com');

    expect(
      api.methodCalls.where(AppNavDrawerController.workspaceMethods.contains),
      isEmpty,
    );
    expect(groupTitles(drawer), contains('Zeta'));
  });

  test('an endpoint that answers is used; boot pages are not needed',
      () async {
    api.onCallMethod = (method) async =>
        method == AppNavDrawerController.workspaceMethods.first
            ? jsonResponse({
                'message': {
                  'pages': [
                    {'name': 'Zeta', 'title': 'Zeta', 'module': 'Zeta'},
                  ],
                },
              })
            : throw httpError(403);
    api.onGetDeskHtml = () async => deskPage();
    final drawer = AppNavDrawerController();

    await drawer.loadFor(kTestEmail);

    expect(groupTitles(drawer), contains('Zeta'));
    expect(api.methodCalls,
        isNot(contains(AppNavDrawerController.workspaceMethods.last)));
  });

  test('a server that cannot be reached leaves the menu as it was', () async {
    // Default fake: every method call times out.
    api.onGetDeskHtml = () async => deskPage();
    final drawer = AppNavDrawerController();

    await drawer.loadFor(kTestEmail);

    expect(groupTitles(drawer), isNot(contains('Zeta')));
  });

  test('endpoints refuse and Desk has no pages → menu stays as it was',
      () async {
    api.onCallMethod = refuse;
    final drawer = AppNavDrawerController();

    await drawer.loadFor(kTestEmail);

    expect(groupTitles(drawer), isNot(contains('Zeta')));
    expect(groupTitles(drawer), isNotEmpty);
  });
}
