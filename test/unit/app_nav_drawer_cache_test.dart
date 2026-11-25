import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' show Response;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/workspace_menu.dart';

import '../helpers/auth_fakes.dart';

const _legacyMenu = [
  {
    't': 'Selling',
    's': [
      {
        'l': 'Items',
        'k': ['doctype:Item'],
      },
      {
        'l': null,
        'k': ['doctype:Sales Order'],
      },
      {
        'l': 'Cached reports',
        'k': ['report:Stock Balance', 'report:POS and Delivery Note Item Rate'],
      },
    ],
  },
  {
    't': 'Buying',
    's': [
      {
        'l': 'Items',
        'k': ['doctype:Item'],
      },
      {
        'l': null,
        'k': ['report:Stock Balance'],
      },
    ],
  },
  {
    't': 'Shift & Attendance',
    's': [
      {
        'l': 'Cached attendance',
        'k': ['report:Shift Attendance'],
      },
    ],
  },
];

class _MenuStorage extends FakeStorageService {
  final menus = <String, List<dynamic>>{};
  int writes = 0;

  @override
  List<dynamic>? getNavMenu(String user) => menus[user];

  @override
  Future<void> saveNavMenu(String user, List<Map<String, dynamic>> menu) async {
    writes++;
    menus[user] = menu;
  }
}

class _DrawerApi extends FakeApiProvider {
  bool canReadItem = true;
  bool _online = false;
  final modules = {'Item': 'Stock'};
  final metadataRequests = <String>[];
  Future<void> Function()? beforeMetadata;

  @override
  Future<Response> hasPermission(String doctype, String permType) async {
    final allowed = switch ((doctype, permType)) {
      ('Item', 'read') => canReadItem,
      ('Sales Order', 'read') ||
      ('Stock Entry' || 'POS Upload' || 'Attendance', 'report') => true,
      (_, 'read') => modules.containsKey(doctype),
      _ => false,
    };
    if (!allowed) throw httpError(403);
    return super.hasPermission(doctype, permType);
  }

  @override
  Future<({Set<String> create, Set<String> write, String? module})>
  fetchDocTypeRoles(String doctype) async {
    metadataRequests.add(doctype);
    if (!_online) throw networkError();
    await beforeMetadata?.call();
    return (create: <String>{}, write: <String>{}, module: modules[doctype]);
  }

  void connect() {
    _online = true;
    onGetDeskHtml = () async =>
        '<script>frappe.boot = ${jsonEncode({
          'user': {'name': kTestEmail},
          'workspaces': {
            'pages': [
              {'name': 'Selling', 'title': 'Selling', 'module': 'Selling', 'public': 1},
            ],
          },
          'module_sidebars': {
            'Selling': {
              'label': 'Selling',
              'app': 'erpnext',
              'workspaces': ['Selling'],
              'items': [
                {'type': 'Section Break', 'label': 'Items'},
                {'type': 'Link', 'link_type': 'DocType', 'link_to': 'Item', 'child': 1},
              ],
            },
          },
        })};</script>';
    onCallMethod = (method) async => switch (method) {
      'frappe.desk.desktop.get_workspace_sidebar_items' => throw httpError(417),
      'frappe.desk.desktop.get_workspaces' => throw httpError(403),
      'frappe.desk.desktop.get_desktop_page' => jsonResponse({'message': {}}),
      'frappe.client.get_list' => jsonResponse({'message': []}),
      _ => throw StateError('Unexpected method $method'),
    };
  }
}

Finder _group(String title) => find.byWidgetPredicate(
  (widget) =>
      widget is ExpansionTile &&
      widget.title is Text &&
      (widget.title as Text).data == title,
);

List<(String, String?)> _placements(
  AppNavDrawerController drawer,
  String key,
) => [
  for (final group in drawer.groups)
    for (final section in group.sections)
      for (final link in section.links)
        if (link.key == key) (group.title, section.label),
];

void _expectItemUnderStock(AppNavDrawerController drawer) {
  expect(_placements(drawer, 'doctype:Item'), [('Stock', null)]);
  expect(find.text('Item'), findsOneWidget);
  expect(
    find.descendant(of: _group('Stock'), matching: find.text('Item')),
    findsOneWidget,
  );
  expect(find.text('Items'), findsNothing);
}

void main() {
  late _DrawerApi api;
  late _MenuStorage storage;
  late PermissionService permissions;

  setUp(() {
    Get.testMode = true;
    api = _DrawerApi();
    storage = _MenuStorage();
    Get.put<ApiProvider>(api);
    Get.put<StorageService>(storage);
    permissions = Get.put(PermissionService());
    final auth = Get.put(AuthenticationController());
    auth.currentUser.value = cachedUser();
    auth.isAuthenticated.value = true;
  });

  tearDown(() => Get.deleteAll(force: true));

  Future<void> prefetchDrawerPermissions() => permissions.prefetchAll([
    for (final link in kNavCatalog.where((link) => link.showInDrawer))
      link.guard,
    (doctype: 'ToDo', permType: 'read'),
  ]);

  AppNavDrawerController drawerWithExpandedGroups() =>
      AppNavDrawerController.instance
        ..setGroupExpanded('Stock', true)
        ..setGroupExpanded('Selling', true);

  Future<void> pumpDrawer(WidgetTester tester) => tester.pumpWidget(
    GetMaterialApp(
      // Flutter's test font is wider than the app font in the account header.
      theme: ThemeData(drawerTheme: const DrawerThemeData(width: 400)),
      home: const Scaffold(body: AppNavDrawer()),
    ),
  );

  testWidgets('legacy cache re-places Item and Reports before refresh', (
    tester,
  ) async {
    // Keep existing permission verdicts while the workspace connection fails.
    await prefetchDrawerPermissions();
    storage.menus[kTestEmail] = _legacyMenu;
    final offline = Completer<void>();
    api.onGetDeskHtml = () async {
      await offline.future;
      throw networkError();
    };
    api.onCallMethod = (_) async {
      await offline.future;
      throw networkError();
    };

    await tester.binding.setSurfaceSize(const Size(800, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final drawer = drawerWithExpandedGroups()..setGroupExpanded('HR', true);

    void expectPlacement() {
      _expectItemUnderStock(drawer);
      const reports = [
        (name: 'Stock Balance', title: 'Stock Balance', group: 'Stock'),
        (
          name: 'POS and Delivery Note Item Rate',
          title: 'POS & DN Item Rate',
          group: 'Stock',
        ),
        (name: 'Shift Attendance', title: 'Shift Attendance', group: 'HR'),
      ];
      for (final report in reports) {
        expect(_placements(drawer, 'report:${report.name}'), [
          (report.group, 'Reports'),
        ]);
        expect(find.text(report.title), findsOneWidget);
        expect(
          find.descendant(
            of: _group(report.group),
            matching: find.text(report.title),
          ),
          findsOneWidget,
        );
      }
      expect(find.text('Reports'), findsNWidgets(2));
      expect(find.text('Cached reports'), findsNothing);
      expect(find.text('Cached attendance'), findsNothing);
      expect(_group('Shift & Attendance'), findsNothing);
    }

    final pendingLoad = drawer.loadFor(kTestEmail);
    await pumpDrawer(tester);
    expectPlacement();
    expect(storage.writes, 0);

    offline.complete();
    await pendingLoad;
    await tester.pumpAndSettle();
    expectPlacement();
    expect(storage.writes, 0);

    api.connect();
    await drawer.loadFor(kTestEmail);
    await tester.pumpAndSettle();
    expectPlacement();
    expect(storage.writes, 1);
  });

  testWidgets('aligned drawer placements survive legacy cache and refresh', (
    tester,
  ) async {
    const placements = <String, (String, String?)>{
      'Purchase Receipt': ('Stock', null),
      'Item Price': ('Stock', 'Pricing'),
      'Pricing Rule': ('Accounts', 'Pricing'),
    };
    api.modules.addAll({
      for (final entry in placements.entries) entry.key: entry.value.$1,
      'ToDo': 'Desk',
    });
    await prefetchDrawerPermissions();
    storage.menus[kTestEmail] = const [
      {
        't': 'Buying',
        's': [
          {
            'l': null,
            'k': ['doctype:Purchase Receipt'],
          },
        ],
      },
      {
        't': 'Selling',
        's': [
          {
            'l': 'Pricing',
            'k': ['doctype:Item Price', 'doctype:Pricing Rule'],
          },
        ],
      },
      {
        't': 'Tools',
        's': [
          {
            'l': null,
            'k': ['doctype:ToDo'],
          },
        ],
      },
    ];
    // Keep the expanded groups in the viewport for the placement assertions.
    await tester.binding.setSurfaceSize(const Size(800, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final metadata = Completer<void>();
    api.connect();
    api.beforeMetadata = () async {
      await metadata.future;
      throw httpError(403);
    };
    final drawer = drawerWithExpandedGroups()
      ..setGroupExpanded('Accounts', true);

    void expectPlacement() {
      for (final entry in placements.entries) {
        expect(_placements(drawer, 'doctype:${entry.key}'), [entry.value]);
        expect(
          find.descendant(
            of: _group(entry.value.$1),
            matching: find.text(entry.key),
          ),
          findsOneWidget,
        );
      }
      // The catalog's ToDo entry is search-only. Its drawer shortcut is always
      // above the module groups, even when a legacy cache contains its key.
      expect(_placements(drawer, 'doctype:ToDo'), isEmpty);
      expect(find.text('To Do'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('To Do'),
          matching: find.byType(ExpansionTile),
        ),
        findsNothing,
      );
    }

    final pendingLoad = drawer.loadFor(kTestEmail);
    await pumpDrawer(tester);
    expectPlacement();
    expect(storage.writes, 0);

    metadata.complete();
    await pendingLoad;
    await tester.pumpAndSettle();
    expectPlacement();
    expect(api.metadataRequests, containsAll(placements.keys));
    expect(storage.writes, 1);

    api.beforeMetadata = null;
    api.metadataRequests.clear();
    await drawer.loadFor(kTestEmail, refresh: true);
    await tester.pumpAndSettle();
    expectPlacement();
    expect(api.metadataRequests, containsAll(placements.keys));
    expect(api.metadataRequests, isNot(contains('ToDo')));
    expect(storage.writes, 2);
  });

  testWidgets(
    'drawer hides Item when the Selling sidebar links a denied DocType',
    (tester) async {
      api.canReadItem = false;
      api.connect();
      await prefetchDrawerPermissions();
      final drawer = drawerWithExpandedGroups();
      await drawer.loadFor(kTestEmail);

      await pumpDrawer(tester);
      await tester.pumpAndSettle();

      expect(permissions.hasAccess('Item'), isFalse);
      expect(find.text('Item'), findsNothing);
      expect(find.text('Sales Order'), findsOneWidget);
      expect(find.text('Stock Balance'), findsOneWidget);
    },
  );
}
