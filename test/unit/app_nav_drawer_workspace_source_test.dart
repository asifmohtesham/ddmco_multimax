// test/unit/app_nav_drawer_workspace_source_test.dart
//
// Where the drawer gets the user's workspace pages from. Frappe 16.56 removed
// `get_workspace_sidebar_items` and stopped whitelisting `get_workspaces`;
// the pages then come from the boot data Desk embeds in its page.
import 'dart:async';
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
String deskPage([Map<String, dynamic> boot = const {}]) =>
    '<script>frappe.boot = ${jsonEncode({
      ...boot,
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

  group('Desk report permissions', () {
    const floor = 'floor@example.com';
    const manager = 'manager@example.com';
    const refused = {
      'Monthly Attendance Sheet': 'Attendance',
      'Employee Hours Utilization Based On Timesheet': 'Timesheet',
      'BOM Search': 'BOM',
      'BOM Stock with Customer Code': 'BOM',
    };
    const floorReports = {
      'Stock Balance': {
        'title': 'Stock Balance',
        'ref_doctype': 'Stock Ledger Entry',
        'report_type': 'Script Report',
      },
    };

    List<String> reportsFor(AppNavDrawerController drawer, String user) =>
        drawer
            .visibleGroupsFor(user)
            .expand((group) => group.links)
            .where((link) => link.linkType == 'Report')
            .map((link) => link.linkTo)
            .toList();

    test('v15 floor boot hides denied reports even if workspace requests fail',
        () async {
      final json = jsonEncode({
        'user': {
          'name': floor,
          'roles': [
            'All', 'Delivery User', 'Desk User', 'Employee', 'Guest',
            'Sales User', 'Stock User', 'Stock User - Custom', 'System User',
          ],
          'can_get_report': [
            'Attendance', 'BOM', 'Timesheet', 'Stock Ledger Entry',
          ],
          'all_reports': floorReports,
        },
      });
      api.onGetDeskHtml = () async =>
          '<script>frappe.boot = JSON.parse(${jsonEncode(json)});</script>';
      final drawer = AppNavDrawerController();

      await drawer.loadFor(floor);

      expect(reportsFor(drawer, floor), ['Stock Balance']);
      final visible = drawer.visibleGroupsFor(floor);
      expect(visible.expand((g) => g.links).map((l) => l.linkTo),
          containsAll(['Delivery Note', 'BOM']));
      expect(visible.expand((g) => g.sections).every((s) => s.links.isNotEmpty),
          isTrue);
    });

    test('v16 System Manager boot keeps reports in the permission map',
        () async {
      api.onGetDeskHtml = () async => deskPage({
        'user': {
          'name': manager,
          'roles': ['System Manager'],
        },
        'allowed_reports': {
          ...floorReports,
          for (final report in refused.entries)
            report.key: {
              'title': report.key,
              'ref_doctype': report.value,
              'report_type': 'Script Report',
            },
        },
      });
      api.onCallMethod = refuse;
      final drawer = AppNavDrawerController();

      await drawer.loadFor(manager);

      expect(reportsFor(drawer, manager),
          unorderedEquals(['Stock Balance', ...refused.keys]));
      expect(groupTitles(drawer), contains('Zeta'));
    });

    test('missing, malformed, or another user’s boot permission data is unknown',
        () async {
      final drawer = AppNavDrawerController();
      api.onCallMethod = refuse;
      api.onGetDeskHtml = () async => deskPage({
        'user': {'name': floor},
        'allowed_reports': floorReports,
      });

      await drawer.loadFor(floor);
      expect(reportsFor(drawer, floor), ['Stock Balance']);
      expect(reportsFor(drawer, manager), containsAll(refused.keys));

      await drawer.loadFor(manager);
      expect(reportsFor(drawer, manager), containsAll(refused.keys));

      api.onGetDeskHtml = () async => deskPage({
        'user': {'name': floor},
        'allowed_reports': {'Stock Balance': false},
      });
      await drawer.loadFor(floor);
      expect(reportsFor(drawer, floor), containsAll(refused.keys));

      api.onGetDeskHtml = () async => deskPage({'user': {'name': manager}});
      await drawer.loadFor(manager);
      expect(reportsFor(drawer, manager), containsAll(refused.keys));
    });

    test('a valid empty report map hides report entries only', () async {
      api.onGetDeskHtml = () async => deskPage({
        'user': {'name': floor},
        'allowed_reports': <String, dynamic>{},
      });
      api.onCallMethod = refuse;
      final drawer = AppNavDrawerController();

      await drawer.loadFor(floor);

      expect(reportsFor(drawer, floor), isEmpty);
      expect(drawer.visibleGroupsFor(floor).expand((g) => g.links), isNotEmpty);
    });

    test('a previous session cannot hide reports after the same user signs in',
        () async {
      final previousBoot = Completer<String?>();
      api.onGetDeskHtml = () => previousBoot.future;
      api.onCallMethod = refuse;
      final drawer = AppNavDrawerController();
      final previousLoad = drawer.loadFor(floor);

      drawer.clearSession();
      api.onGetDeskHtml = () async => deskPage({'user': {'name': floor}});
      await drawer.loadFor(floor);
      previousBoot.complete(deskPage({
        'user': {'name': floor},
        'allowed_reports': floorReports,
      }));
      await previousLoad;

      expect(api.deskHtmlCalls, 2);
      expect(reportsFor(drawer, floor), containsAll(refused.keys));
    });
  });
}
