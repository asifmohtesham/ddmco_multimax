// test/unit/app_nav_drawer_workspace_source_test.dart
//
// Where the drawer gets the user's workspace pages from. Frappe 16.56 removed
// `get_workspace_sidebar_items` and stopped whitelisting `get_workspaces`;
// the pages then come from the boot data Desk embeds in its page.
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';

import '../helpers/auth_fakes.dart';

/// HR marks boot workspace order. The Zeta sidebar links Stock Balance under
/// an unrelated label that must not become a drawer group.
String deskPage([Map<String, dynamic> boot = const {}]) =>
    '<script>frappe.boot = ${jsonEncode({
      ...boot,
      'workspaces': {
        'pages': [
          {'name': 'HR', 'title': 'HR', 'module': 'HR', 'public': 1},
          {'name': 'Zeta', 'title': 'Zeta', 'module': 'Zeta', 'public': 1},
        ],
      },
      'module_sidebars': {
        'Zeta': {
          'label': 'Zeta',
          'app': 'erpnext',
          'workspaces': ['Zeta'],
          'items': [
            {'type': 'Link', 'link_type': 'Report', 'link_to': 'Stock Balance'},
          ],
        },
      },
    })};</script>';

const _reports = {
  'Batch-Wise Balance History': (module: 'Stock', refDoctype: 'Batch'),
  'Item Variant Details': (module: 'Stock', refDoctype: 'Item'),
  'Stock Balance': (module: 'Stock', refDoctype: 'Stock Entry'),
  'Stock Ageing - Custom': (module: 'Stock', refDoctype: 'Item'),
  'BOM Search': (module: 'Stock', refDoctype: 'BOM'),
  'Job Card Summary': (module: 'Manufacturing', refDoctype: 'Job Card'),
  'BOM Stock with Customer Code': (module: 'Manufacturing', refDoctype: 'BOM'),
  'POS and Delivery Note Item Rate': (
    module: 'Stock',
    refDoctype: 'POS Upload',
  ),
  'Monthly Attendance Sheet': (module: 'HR', refDoctype: 'Attendance'),
  'Shift Attendance': (module: 'HR', refDoctype: 'Attendance'),
  'Employee Hours Utilization Based On Timesheet': (
    module: 'HR',
    refDoctype: 'Timesheet',
  ),
};

String _itemDeskPage(User user, List<String> modules) =>
    '<script>frappe.boot = ${jsonEncode({
      'user': {'name': user.id, 'roles': user.roles},
      'workspaces': {
        'pages': [
          for (final module in modules) {'name': module, 'title': module, 'module': module, 'public': 1},
        ],
      },
      'module_app': {'stock': 'erpnext', 'buying': 'erpnext', 'selling': 'erpnext'},
      'module_sidebars': {
        for (final module in modules) module: {
            'label': module,
            'app': 'erpnext',
            'workspaces': [module],
            'items': [
              if (module != 'Stock') {'type': 'Section Break', 'label': 'Items'},
              {'type': 'Link', 'link_type': 'DocType', 'link_to': 'Item', 'child': module == 'Stock' ? 0 : 1},
            ],
          },
      },
    })};</script>';

String _reportDeskPage(
  User user, {
  bool blockedModules = false,
  bool v15 = false,
}) {
  final reportPermissions = {
    for (final report in _reports.entries)
      report.key: {
        'title': report.key,
        'ref_doctype': report.value.refDoctype,
        'report_type': 'Script Report',
      },
  };
  final json = jsonEncode({
    'user': {
      'name': user.id,
      'roles': user.roles,
      'blocked_modules': blockedModules ? ['Stock', 'Buying'] : <String>[],
      if (v15) 'all_reports': reportPermissions,
    },
    if (!v15) 'allowed_reports': reportPermissions,
    'workspaces': {
      'pages': [
        for (final module in [
          if (blockedModules) 'Shift & Attendance',
          'Selling',
          if (!blockedModules) ...['Stock', 'Buying'],
          'HR',
        ])
          {'name': module, 'title': module, 'module': module, 'public': 1},
      ],
    },
    if (!v15)
      'module_sidebars': {
        (blockedModules ? 'Shift & Attendance' : 'HR'): {
          'label': blockedModules ? 'Shift & Attendance' : 'HR',
          'app': 'hrms',
          'items': [
            {'type': 'Section Break', 'label': 'Desk attendance links'},
            {
              'type': 'Link',
              'link_type': 'Report',
              'link_to': 'Shift Attendance',
              'child': 1,
            },
          ],
        },
      },
  });
  return v15
      ? '<script>frappe.boot = JSON.parse(${jsonEncode(json)});</script>'
      : '<script>frappe.boot = $json;</script>';
}

class _DrawerTestStorage extends FakeStorageService {
  @override
  String? getBaseUrl() => null;
}

class _DrawerServer {
  final workspaceRequests = <String>[];
  final desktopRequests = <String>[];
  final metadataRequests = <String>[];
  final reportModuleRequests = <RequestOptions>[];
  final reportModules = {
    for (final report in _reports.entries) report.key: report.value.module,
  };
  String? itemModule = 'Stock';
  bool refuseItemMetadata = false;
  bool v15 = false;
  late String deskHtml;

  void handleRequest(
    RequestOptions request,
    RequestInterceptorHandler handler,
  ) {
    final method = request.path.replaceFirst('/api/method/', '');
    final doctype = request.queryParameters['doctype'];
    if (AppNavDrawerController.workspaceMethods.contains(method)) {
      workspaceRequests.add(method);
      if (!v15) {
        handler.reject(
          httpError(
            method == AppNavDrawerController.workspaceMethods.first ? 417 : 403,
          ),
        );
        return;
      }
    }
    if (method == 'frappe.desk.desktop.get_desktop_page') {
      final page = jsonDecode(request.queryParameters['page'] as String);
      desktopRequests.add(page['name'] as String);
    }
    if (method == 'frappe.desk.form.load.getdoctype') {
      metadataRequests.add(doctype as String);
      if (doctype == 'Item' && refuseItemMetadata) {
        handler.reject(httpError(403));
        return;
      }
    }
    if (method == 'frappe.client.get_list' && doctype == 'Report') {
      reportModuleRequests.add(request);
    }
    final data = switch (method) {
      'frappe.desk.desktop.get_workspace_sidebar_items' => {
        'message': {
          'pages': [
            {'name': 'HR', 'title': 'HR', 'module': 'HR', 'public': 1},
          ],
        },
      },
      '/app' when v15 => deskHtml,
      '/desk' when !v15 => deskHtml,
      'frappe.desk.desktop.get_desktop_page' => {
        'message': <String, dynamic>{},
      },
      'frappe.client.get_list' when doctype == 'Report' => {
        'message': [
          for (final report in reportModules.entries)
            {'name': report.key, 'module': report.value},
        ],
      },
      'frappe.client.get_list' => {'message': <dynamic>[]},
      'frappe.desk.form.load.getdoctype' => {
        'docs': [
          {
            'doctype': 'DocType',
            'name': doctype,
            if (doctype == 'Item' && itemModule != null) 'module': itemModule,
            'permissions': [
              {'role': 'Sales User', 'permlevel': 0, 'write': 1},
            ],
          },
        ],
      },
      _ => null,
    };
    if (data == null) {
      handler.reject(
        DioException(
          requestOptions: request,
          error: 'Unexpected request ${request.path}',
        ),
      );
      return;
    }
    handler.resolve(
      Response(requestOptions: request, statusCode: 200, data: data),
    );
  }
}

void main() {
  late FakeApiProvider api;

  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  setUp(() {
    Get.testMode = true;
    api = FakeApiProvider();
    Get.put<ApiProvider>(api);
    Get.put<StorageService>(_DrawerTestStorage());
    Get.put<PermissionService>(FakePermissionService());
  });

  tearDown(() => Get.deleteAll(force: true));

  List<String> groupTitles(AppNavDrawerController c) => [
    for (final g in c.groups) g.title,
  ];

  /// Frappe 16.56: the v15 name is gone (417), the v16 name is refused (403).
  Future<Never> refuse(String method) async => throw httpError(
    method == AppNavDrawerController.workspaceMethods.first ? 417 : 403,
  );

  test(
    '16.56: both endpoints refuse → pages come from Desk boot data',
    () async {
      api.onCallMethod = refuse;
      api.onGetDeskHtml = () async => deskPage();
      final drawer = AppNavDrawerController();

      await drawer.loadFor(kTestEmail);

      expect(groupTitles(drawer).first, 'HR');
      expect(groupTitles(drawer), isNot(contains('Zeta')));
      expect(
        api.methodCalls.where(AppNavDrawerController.workspaceMethods.contains),
        AppNavDrawerController.workspaceMethods,
      );
    },
  );

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
    expect(groupTitles(drawer).first, 'HR');
  });

  test('an endpoint that answers is used; boot pages are not needed', () async {
    api.onCallMethod = (method) async =>
        method == AppNavDrawerController.workspaceMethods.first
        ? jsonResponse({
            'message': {
              'pages': [
                {'name': 'Buying', 'title': 'Buying', 'module': 'Buying'},
              ],
            },
          })
        : throw httpError(403);
    api.onGetDeskHtml = () async => deskPage();
    final drawer = AppNavDrawerController();

    await drawer.loadFor(kTestEmail);

    expect(groupTitles(drawer).first, 'Buying');
    expect(
      api.methodCalls,
      isNot(contains(AppNavDrawerController.workspaceMethods.last)),
    );
  });

  test('a server that cannot be reached leaves the menu as it was', () async {
    // Default fake: every method call times out.
    api.onGetDeskHtml = () async => deskPage();
    final drawer = AppNavDrawerController();

    await drawer.loadFor(kTestEmail);

    expect(groupTitles(drawer).first, 'Stock');
  });

  test(
    'endpoints refuse and Desk has no pages → menu stays as it was',
    () async {
      api.onCallMethod = refuse;
      final drawer = AppNavDrawerController();

      await drawer.loadFor(kTestEmail);

      expect(groupTitles(drawer).first, 'Stock');
    },
  );

  group('Drawer placement from Frappe metadata', () {
    late _DrawerServer server;
    late AuthenticationController auth;
    late PermissionService permissions;

    setUp(() async {
      const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(pathProvider, (_) async => 'build');
      addTearDown(() => messenger.setMockMethodCallHandler(pathProvider, null));
      server = _DrawerServer();
      final realApi = ApiProvider();
      await realApi.initDio();
      realApi.dio.interceptors
        ..clear()
        ..add(InterceptorsWrapper(onRequest: server.handleRequest));
      Get.replace<ApiProvider>(realApi);
      await Get.delete<PermissionService>(force: true);
      permissions = Get.put(PermissionService());
      auth = Get.put(AuthenticationController());
    });

    User signIn(String user, List<String> roles, List<String> modules) {
      final account = User(id: user, name: user, email: user, roles: roles);
      auth.currentUser.value = account;
      auth.isAuthenticated.value = true;
      server.deskHtml = _itemDeskPage(account, modules);
      return account;
    }

    List<(String, String?)> itemPlacement(
      AppNavDrawerController drawer,
      User user,
    ) => [
      for (final group in drawer.visibleGroupsFor(user.id))
        for (final section in group.sections)
          for (final link in section.links)
            if (link.key == 'doctype:Item') (group.title, section.label),
    ];

    List<(String, String, String?)> reportPlacements(
      AppNavDrawerController drawer,
      User user,
    ) => [
      for (final group in drawer.visibleGroupsFor(user.id))
        for (final section in group.sections)
          for (final link in section.links)
            if (link.linkType == 'Report')
              (link.linkTo, group.title, section.label),
    ];

    void expectReportModuleRequest(RequestOptions request) {
      expect(request.method, 'GET');
      expect(request.path, '/api/method/frappe.client.get_list');
      expect(request.queryParameters['doctype'], 'Report');
      expect(jsonDecode(request.queryParameters['fields'] as String), [
        'name',
        'module',
      ]);
      expect(jsonDecode(request.queryParameters['filters'] as String), [
        ['name', 'in', unorderedEquals(_reports.keys)],
      ]);
      expect(request.queryParameters['limit_page_length'], 0);
    }

    const fixtures = [
      (
        name: 'Yunus-shaped user with Stock and Buying absent',
        roles: [
          'Sales User',
          'Employee',
          'System User',
          'Prepared Report User',
        ],
        modules: ['Selling'],
      ),
      (
        name: 'ordinary user with Buying, Selling and Stock',
        roles: ['Sales User', 'Stock User', 'System User'],
        modules: ['Buying', 'Selling', 'Stock'],
      ),
    ];

    for (final fixture in fixtures) {
      test(
        '${fixture.name} follows the module at login and on refresh',
        () async {
          final user = signIn(kTestEmail, fixture.roles, fixture.modules);
          final drawer = AppNavDrawerController();
          await permissions.prefetchAll([
            (doctype: 'Item', permType: 'read'),
            (doctype: 'Item', permType: 'write'),
          ]);

          await drawer.loadFor(user.id);

          expect(
            server.workspaceRequests,
            AppNavDrawerController.workspaceMethods,
          );
          expect(server.desktopRequests, isEmpty);
          expect(permissions.hasAccess('Item'), isTrue);
          expect(server.metadataRequests.where((name) => name == 'Item'), [
            'Item',
          ]);
          expect(itemPlacement(drawer, user), [('Stock', null)]);

          server.itemModule = 'Selling';
          await drawer.loadFor(user.id, refresh: true);

          expect(server.metadataRequests.where((name) => name == 'Item'), [
            'Item',
            'Item',
          ]);
          expect(itemPlacement(drawer, user), [('Selling', null)]);
        },
      );
    }

    test(
      'missing metadata and a failed refresh both use the catalog',
      () async {
        final user = signIn(kTestEmail, ['Sales User'], ['Selling']);
        final drawer = AppNavDrawerController();
        server.itemModule = null;

        await drawer.loadFor(user.id);

        expect(server.metadataRequests, contains('Item'));
        expect(itemPlacement(drawer, user), [('Stock', null)]);

        server.itemModule = 'Selling';
        await drawer.loadFor(user.id, refresh: true);
        expect(itemPlacement(drawer, user), [('Selling', null)]);
        expect(permissions.hasAccess('Item', permType: 'write'), isTrue);

        server.refuseItemMetadata = true;
        await drawer.loadFor(user.id, refresh: true);

        expect(itemPlacement(drawer, user), [('Stock', null)]);
        expect(permissions.hasAccess('Item', permType: 'write'), isTrue);
      },
    );

    test(
      'metadata still places a DocType when no workspace source answers',
      () async {
        final user = signIn(kTestEmail, ['Sales User'], ['Selling']);
        server.deskHtml = '<script>frappe.boot = {};</script>';
        server.itemModule = 'Selling';
        final drawer = AppNavDrawerController();

        await drawer.loadFor(user.id);

        expect(server.desktopRequests, isEmpty);
        expect(server.metadataRequests, contains('Item'));
        expect(itemPlacement(drawer, user), [('Selling', null)]);
      },
    );

    const posReport = 'POS and Delivery Note Item Rate';
    for (final blockedModules in [true, false]) {
      final shape = blockedModules ? 'Yunus-shaped' : 'ordinary';
      test(
        'v16 $shape Desk User places all Reports by module on load and refresh',
        () async {
          final user = signIn(kTestEmail, [
            'Desk User',
            'Employee',
            'Sales User',
            'System User',
            if (blockedModules) 'Prepared Report User' else 'Stock User',
          ], const []);
          server.deskHtml = _reportDeskPage(
            user,
            blockedModules: blockedModules,
          );
          final drawer = AppNavDrawerController();

          await drawer.loadFor(user.id);

          expect(
            server.workspaceRequests,
            AppNavDrawerController.workspaceMethods,
          );
          expect(server.desktopRequests, isEmpty);
          expectReportModuleRequest(server.reportModuleRequests.single);
          expect(groupTitles(drawer), isNot(contains('Shift & Attendance')));
          expect(
            reportPlacements(drawer, user),
            unorderedEquals([
              for (final report in _reports.entries)
                (report.key, report.value.module, 'Reports'),
            ]),
          );

          server.reportModules[posReport] = 'Selling';
          await drawer.loadFor(user.id, refresh: true);

          expect(server.reportModuleRequests, hasLength(2));
          expectReportModuleRequest(server.reportModuleRequests.last);
          expect(
            reportPlacements(drawer, user),
            unorderedEquals([
              for (final report in _reports.entries)
                (
                  report.key,
                  report.key == posReport ? 'Selling' : report.value.module,
                  'Reports',
                ),
            ]),
          );
        },
      );
    }

    test(
      'v15 Desk User applies returned Report modules and falls back for unknown ones',
      () async {
        final user = signIn(kTestEmail, ['Desk User', 'Sales User'], const []);
        server.v15 = true;
        server.deskHtml = _reportDeskPage(user, v15: true);
        server.reportModules[posReport] = 'Selling';
        server.reportModules.remove('BOM Search');
        server.reportModules['Shift Attendance'] = '  ';
        final drawer = AppNavDrawerController();

        await drawer.loadFor(user.id);

        expect(server.workspaceRequests, [
          AppNavDrawerController.workspaceMethods.first,
        ]);
        expectReportModuleRequest(server.reportModuleRequests.single);
        expect(
          reportPlacements(drawer, user),
          unorderedEquals([
            for (final report in _reports.entries)
              (
                report.key,
                report.key == posReport ? 'Selling' : report.value.module,
                'Reports',
              ),
          ]),
        );
      },
    );

    test(
      'Report metadata still applies when no workspace source answers',
      () async {
        final user = signIn(kTestEmail, ['Desk User', 'Sales User'], const []);
        server.deskHtml = '<script>frappe.boot = {};</script>';
        server.reportModules[posReport] = 'Selling';
        final drawer = AppNavDrawerController();

        await drawer.loadFor(user.id);

        expectReportModuleRequest(server.reportModuleRequests.single);
        expect(
          reportPlacements(drawer, user),
          contains((posReport, 'Selling', 'Reports')),
        );
      },
    );
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
      expect(groupTitles(drawer), isNot(contains('Zeta')));
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
