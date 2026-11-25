import 'dart:async';
import 'dart:ui' show CheckedState, SemanticsAction, Tristate;

// Keep the shared Flutter Material API until the app migrates to material_ui.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/models/suppliers_by_item_report.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/item_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/database_service.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/add_filter_chip.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/count_badge.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'package:multimax/app/modules/item/form/item_form_controller.dart';
import 'package:multimax/app/modules/item/form/widgets/item_suppliers_card.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_binding.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_controller.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_fields.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_layout.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_screen.dart';

import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_rows.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/main.dart' show buildAppTheme;

import '../helpers/auth_fakes.dart';

const reportFont = 'SuppliersReportTestInter';

// Deployed Desk schema from docs/suppliers_by_item_report.md.
List<DeskColumn> _localizedColumns({bool expandBom = false}) => [
  for (final (fieldname, label) in [
    ('tree_label', 'Item / Supplier'),
    ('item_name', 'Item Name'),
    if (expandBom) ('bom_qty_per_unit', 'Stücklistenmenge'),
    ('balance_qty', 'Available Stock'),
    ('projected_qty', 'Projected Qty'),
    ('reorder_level', 'Reorder Level'),
    ('reorder_qty', 'Reorder Qty'),
    ('supplier_name', 'Supplier Name'),
    ('supplier_status', 'Supplier Status'),
    ('supplier_part_number', 'Supplier Part Number'),
    ('sources', 'Sources'),
    ('open_order_qty', 'Open Order Qty'),
    ('draft_order_qty', 'Draft Order Qty'),
    ('lead_time_days', 'Lead Time (Days)'),
    ('lead_time_receipts', 'Lead Time Receipts'),
    ('po_count', 'PO Count'),
    ('receipt_count', 'Receipt Count'),
    ('last_purchase_date', 'Letzter Einkauf'),
    ('last_purchase_receipt', 'Last Purchase Receipt'),
    ('last_rate', 'Last Rate'),
    ('rate_source', 'Rate Source'),
    ('rate_date', 'Rate Date'),
    ('rate_document', 'Rate Document'),
    ('currency', 'Currency'),
    ('rate_uom', 'Rate UOM'),
    ('total_qty_received', 'Total Qty Received'),
    ('stock_uom', 'Stock UOM'),
    ('last_po_date', 'Last PO Date'),
    ('supplier_count', 'Supplier Count'),
  ])
    (fieldname: fieldname, label: label),
];

class _FieldPreferenceBox extends Fake implements GetStorage {
  final _values = <String, Object?>{};
  final _listeners = <void Function()>{};

  @override
  Map<String, dynamic> changes = {};

  @override
  T? read<T>(String key) => _values[key] as T?;

  @override
  Future<void> write(String key, Object? value) async {
    _values[key] = value;
    changes = {key: value};
    for (final listener in _listeners) {
      listener();
    }
  }

  @override
  void Function() listen(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

User _fieldUser(String id) =>
    User(id: id, name: id, email: id, roles: const ['Purchase User']);

class _FieldsDatabase extends Fake implements DatabaseService {
  final records = <String, String>{
    DatabaseService.serverUrlKey: 'https://erp.example',
  };
  Future<void> Function()? onSave;
  Future<String?> Function()? readSite;

  @override
  Future<String?> getConfig(String key) async {
    if (key == DatabaseService.serverUrlKey && readSite != null) {
      return readSite!();
    }
    return records[key];
  }

  @override
  Future<void> saveConfig(String key, String value) async {
    await onSave?.call();
    records[key] = value;
  }
}

_FieldsDatabase _useFieldPreferences(String owner) {
  final auth = Get.find<AuthenticationController>();
  auth.isAuthenticated.value = true;
  auth.currentUser.value = _fieldUser(owner);
  final database = _FieldsDatabase();
  Get.put(
    StorageService.withStorage(_FieldPreferenceBox(), database: database),
  );
  return database;
}

Finder reportRow(String id) => find.byKey(ValueKey((nodeId: id)));

Finder rowWith(String text) => find.ancestor(
  of: find.text(text),
  matching: find.byType(SuppliersByItemDisplayTile),
);

Finder within(Finder row, String text) =>
    find.descendant(of: row, matching: find.text(text));

Iterable<CheckboxListTile> _configuredFieldsTiles(
  WidgetTester tester,
  Finder sheet,
) {
  final list = tester.widget<ListView>(
    find.descendant(of: sheet, matching: find.byType(ListView)),
  );
  return (list.childrenDelegate as SliverChildListDelegate).children
      .whereType<CheckboxListTile>();
}

SuppliersByItemController currentReport() =>
    Get.find<SuppliersByItemController>(
      tag: SuppliersByItemBinding.tagForRoute(Get.routing.route),
    );

double pinnedBottom(
  WidgetTester tester, {
  bool includesSearch = true,
  bool includesSupplier = true,
}) {
  var supplierExtent = 0.0;
  if (includesSearch) {
    final viewport = tester.renderObject<RenderViewport>(
      find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Viewport),
      ),
    );
    final search = viewport.childAfter(viewport.firstChild!);
    if (search is RenderSliverToBoxAdapter) {
      final sticky = viewport.childAfter(search)!;
      supplierExtent = includesSupplier
          ? sticky.geometry!.maxScrollObstructionExtent
          : 0.0;
      if (search.geometry!.maxScrollObstructionExtent > 0) {
        final box = search.child!;
        return box.localToGlobal(Offset(0, box.size.height)).dy +
            supplierExtent;
      }
    }
  }
  final toolbar = find
      .descendant(
        of: find.byType(DocTypeListHeader),
        matching: find.byType(Material),
      )
      .first;
  return tester.getBottomLeft(toolbar).dy + supplierExtent;
}

class _FakeApi extends FakeApiProvider {
  final requests = <SuppliersByItemFilters>[];
  Future<List<SuppliersByItemNode>> Function() load = () async => [];
  List<DeskColumn>? columns;

  @override
  Future<SuppliersByItemReport> runSuppliersByItemReport(
    SuppliersByItemFilters filters,
  ) async {
    requests.add(filters);
    return SuppliersByItemReport(nodes: await load(), columns: columns);
  }

  @override
  Future<List<String>> searchLinkOptions(
    String doctype, {
    String query = '',
    int limit = 20,
    Map<String, dynamic>? filters,
  }) async {
    expect(doctype, 'Item');
    expect(filters, {'has_variants': 1});
    return ['SHIRT', 'JACKET'];
  }
}

class _DrawerPermissions extends FakePermissionService {
  final _allowed = true.obs;

  @override
  bool hasAccess(String doctype, {String permType = 'read'}) => _allowed.value;
}

const _acp25Rows = [
  {
    'node_id': 'template:ACP-25',
    'row_type': 'template',
    'template': 'ACP-25',
    'tree_label': 'ACP-25',
    'indent': 0,
    'supplier_count': 1,
    'total_qty_received': 0,
    'balance_qty': 12.5,
    'stock_uom': 'Nos',
  },
  {
    'node_id': 'item:2002492',
    'parent_id': 'template:ACP-25',
    'row_type': 'item',
    'item_code': '2002492',
    'tree_label': '2002492',
    'indent': 1,
    'supplier_count': 0,
    'total_qty_received': 0,
    'balance_qty': 0,
    'stock_uom': 'Nos',
  },
  {
    'node_id': 'none:7:2002492',
    'parent_id': 'item:2002492',
    'row_type': 'placeholder',
    'item_code': '2002492',
    'tree_label': 'No supplier recorded',
    'indent': 2,
    'is_placeholder': 1,
    'supplier': null,
    'last_rate': null,
    'total_qty_received': null,
  },
  {
    'node_id': 'item:2002506',
    'parent_id': 'template:ACP-25',
    'row_type': 'item',
    'item_code': '2002506',
    'tree_label': '2002506',
    'indent': 1,
    'supplier_count': 1,
    'total_qty_received': 0,
    'balance_qty': 12.5,
    'stock_uom': 'Nos',
  },
  {
    'node_id': 'supplier:7:2002506:KANG KAI',
    'parent_id': 'item:2002506',
    'row_type': 'supplier',
    'item_code': '2002506',
    'tree_label': 'KANG KAI',
    'indent': 2,
    'is_placeholder': 0,
    'supplier': 'KANG KAI',
    'supplier_name': 'KANG KAI',
    'supplier_part_number': '1234-B',
    'sources': 'Purchase Order, Batch',
    'total_qty_received': 0,
    'stock_uom': 'Nos',
    'last_po_date': '2026-11-05',
    'last_rate': 0,
    'currency': 'AED',
    'rate_source': 'Purchase Order',
    'rate_date': '2026-11-05',
    'rate_document': 'PO-123',
  },
];

const _supplierViewRows = [
  {
    'node_id': 'item:KIT',
    'item_code': 'KIT',
    'balance_qty': -2,
    'stock_uom': 'Nos',
  },
  {
    'node_id': 'supplier:KIT:EDGE',
    'parent_id': 'item:KIT',
    'supplier': 'EDGE',
    'last_purchase_date': '2025-10-01',
    'sources': 'Purchase Receipt',
    'open_order_qty': 4,
    'stock_uom': 'Nos',
    'matched_supplier': 1,
  },
  {
    'node_id': 'supplier:KIT:LOCKAL',
    'parent_id': 'item:KIT',
    'supplier': 'LOCKAL',
    'last_purchase_date': '2026-11-10',
    'sources': 'Purchase Order',
  },
  {'node_id': 'bom:KIT', 'parent_id': 'item:KIT', 'bom_no': 'BOM-KIT-001'},
  {
    'node_id': 'component:FRAME',
    'parent_id': 'bom:KIT',
    'item_code': 'FRAME',
    'balance_qty': 100,
    'stock_uom': 'Nos',
  },
  {
    'node_id': 'supplier:FRAME:EDGE',
    'parent_id': 'component:FRAME',
    'supplier': 'EDGE',
    'last_purchase_date': '2026-07-10',
  },
  {
    'node_id': 'bom:FRAME',
    'parent_id': 'component:FRAME',
    'bom_no': 'BOM-FRAME-001',
  },
  {'node_id': 'component:PIN', 'parent_id': 'bom:FRAME', 'item_code': 'PIN'},
  {
    'node_id': 'supplier:PIN:NEST-ONLY',
    'parent_id': 'component:PIN',
    'supplier': 'NEST-ONLY',
  },
  {
    'node_id': 'item:SPARE',
    'item_code': 'SPARE',
    'balance_qty': 5,
    'stock_uom': 'Nos',
  },
  {
    'node_id': 'none:SPARE',
    'parent_id': 'item:SPARE',
    'row_type': 'placeholder',
  },
];

void registerSuppliersByItemFieldsContract() {
  testWidgets(
    'Suppliers Fields protects legacy identities and resets by surface',
    (tester) async {
      Get.testMode = true;
      addTearDown(Get.reset);
      final api = Get.put<ApiProvider>(_FakeApi()) as _FakeApi;
      Get.put(AuthenticationController());
      final database = _useFieldPreferences('reader@example.com');
      const key =
          'suppliers_by_item_fields::https%3A%2F%2Ferp.example'
          '::reader%40example.com';
      const saved =
          '{"itemName":false,"supplierStatus":false,'
          '"itemBalance":false,"summaryItemCount":false}';
      database.records[key] = saved;
      api.columns = _localizedColumns();
      api.load = () async => SuppliersByItemNode.parseRows([
        {
          'node_id': 'item:KIT',
          'item_code': 'KIT',
          'item_name': 'Travel Kit',
          'balance_qty': 4,
          'stock_uom': 'Nos',
        },
        {
          'node_id': 'supplier:KIT:VENDOR',
          'parent_id': 'item:KIT',
          'supplier': 'VENDOR',
          'supplier_status': 'Disabled',
          'last_purchase_date': '2025-10-01',
        },
      ]);
      await tester.binding.setSurfaceSize(const Size(500, 940));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        GetMaterialApp(
          home: const Scaffold(),
          getPages: [
            GetPage(
              name: AppRoutes.SUPPLIERS_BY_ITEM,
              page: () => const SuppliersByItemScreen(),
              binding: SuppliersByItemBinding(),
              transition: Transition.noTransition,
            ),
          ],
        ),
      );
      Get.toNamed(AppRoutes.SUPPLIERS_BY_ITEM);
      await tester.pumpAndSettle();
      final semantics = tester.ensureSemantics();
      final item = reportRow('item:KIT');
      final supplier = reportRow('supplier:KIT:VENDOR');
      final footer = find.byType(SuppliersByItemFooter);
      void expectBalance(bool visible) {
        expect(
          within(item, 'Available Stock 4 Nos'),
          visible ? findsOneWidget : findsNothing,
        );
        expect(
          find.bySemanticsLabel(RegExp(r'^Item KIT,.*Available Stock 4 Nos')),
          visible ? findsOneWidget : findsNothing,
        );
        final metric = find
            .ancestor(
              of: within(footer, 'Available Stock'),
              matching: find.byType(Padding),
            )
            .first;
        expect(within(metric, '4 Nos'), findsOneWidget);
        expect(within(footer, 'Balance Qty'), findsNothing);
      }

      expectBalance(false);
      expect(within(supplier, 'Letzter Einkauf 1 Oct 25'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp(r'^Item / Supplier VENDOR,.*Letzter Einkauf 1 October 2025'),
        ),
        findsOneWidget,
      );
      expect(database.records[key], saved);
      expect(find.text('Travel Kit'), findsOneWidget);
      expect(find.text('Disabled'), findsOneWidget);

      final fields = find.byTooltip('Fields');
      final sheet = find.byType(DraggableScrollableSheet);
      final balance = find.byKey(
        const ValueKey(SuppliersByItemField.itemBalance),
      );
      await tester.tap(fields);
      await tester.pumpAndSettle();
      final tiles = _configuredFieldsTiles(tester, sheet);
      for (final field in [
        SuppliersByItemField.itemName,
        SuppliersByItemField.supplierStatus,
      ]) {
        final locked = tiles.singleWhere((tile) => tile.key == ValueKey(field));
        expect(locked.value, isTrue);
        expect(locked.onChanged, isNull);
      }
      expect(within(balance, 'Available Stock'), findsOneWidget);
      expect(tester.widget<CheckboxListTile>(balance).value, isFalse);
      expect(
        tiles.map((tile) => tile.key),
        isNot(contains(const ValueKey(SuppliersByItemField.summaryItemCount))),
      );
      await tester.tap(find.text('Reset to defaults'));
      await tester.pumpAndSettle();
      expect(database.records[key], '{"summaryItemCount":false}');
      expect(tester.widget<CheckboxListTile>(balance).value, isTrue);
      Navigator.of(tester.element(sheet)).pop();
      await tester.pumpAndSettle();
      expectBalance(true);
      await tester.tap(fields);
      await tester.pumpAndSettle();
      await tester.tap(balance);
      await tester.pumpAndSettle();
      Navigator.of(tester.element(sheet)).pop();
      await tester.pumpAndSettle();
      expectBalance(false);
      semantics.dispose();

      await tester.tap(find.byKey(const ValueKey('suppliers-by-item-view')));
      await tester.pumpAndSettle();
      final moved = find.byKey(
        const ValueKey(SuppliersByItemField.summaryItemCount),
      );
      expect(tester.widget<CheckboxListTile>(moved).value, isFalse);
      final resetView = find.text('Reset display options');
      await tester.ensureVisible(resetView);
      await tester.tap(resetView);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(moved).value, isTrue);
      expect(database.records[key], '{"itemBalance":false}');
      await tester.tap(find.widgetWithText(TextButton, 'Done'));
      await tester.pumpAndSettle();
      expect(find.text('Travel Kit'), findsOneWidget);
      expect(find.text('Disabled'), findsOneWidget);
      expect(
        find.text('End of list · Totals for all loaded items'),
        findsOneWidget,
      );
      expect(api.requests, hasLength(1));
    },
  );
}

void main() {
  late _FakeApi api;

  setUp(() {
    Get.testMode = true;
    api = _FakeApi();
    Get.put<ApiProvider>(api, permanent: true);
    Get.put(AuthenticationController(), permanent: true);
  });
  tearDown(Get.reset);

  Future<void> openReport(
    WidgetTester tester, {
    SuppliersByItemFilters? filters,
    ThemeMode themeMode = ThemeMode.light,
    Size size = const Size(390, 780),
    List<SuppliersByItemField> showFields = const [],
    Iterable<SuppliersByItemField> hideFields = const [],
    Widget home = const Scaffold(),
    Future<void> Function()? enterFromHome,
    String? fontFamily,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ThemeData theme(AppScheme scheme, Brightness brightness) {
      final appTheme = buildAppTheme(scheme, brightness);
      return fontFamily == null
          ? appTheme
          : appTheme.copyWith(
              textTheme: appTheme.textTheme.apply(fontFamily: fontFamily),
            );
    }

    await tester.pumpWidget(
      GetMaterialApp(
        theme: theme(AppScheme.light, Brightness.light),
        darkTheme: theme(AppScheme.dark, Brightness.dark),
        themeMode: themeMode,
        home: home,
        getPages: [
          GetPage(
            name: AppRoutes.SUPPLIERS_BY_ITEM,
            page: () => const SuppliersByItemScreen(),
            binding: SuppliersByItemBinding(),
            transition: Transition.noTransition,
          ),
        ],
      ),
    );
    if (enterFromHome != null) {
      await enterFromHome();
    } else {
      Get.toNamed(AppRoutes.SUPPLIERS_BY_ITEM, arguments: filters);
    }
    await tester.pump();
    if (showFields.isNotEmpty || hideFields.isNotEmpty) {
      final controller = Get.find<SuppliersByItemController>(
        tag: SuppliersByItemBinding.tagForRoute(Get.routing.route),
      );
      for (final field in showFields) {
        await controller.setFieldVisible(field, true);
      }
      for (final field in hideFields) {
        await controller.setFieldVisible(field, false);
      }
    }
  }

  final viewButton = find.byKey(const ValueKey('suppliers-by-item-view'));

  Future<void> openView(WidgetTester tester) async {
    if (viewButton.hitTestable().evaluate().isEmpty) {
      await tester.ensureVisible(viewButton);
      await tester.pumpAndSettle();
    }
    await tester.tap(viewButton);
    await tester.pumpAndSettle();
  }

  Future<void> selectView<T extends Enum>(WidgetTester tester, T value) async {
    final tile = find.byKey(ValueKey(value));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }

  Future<void> viewCommand(WidgetTester tester, String label) async {
    await openView(tester);
    final command = find.widgetWithText(ListTile, label);
    await tester.ensureVisible(command);
    await tester.tap(command);
    await tester.pumpAndSettle();
  }

  Future<void> doneWithView(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Done'));
    await tester.pumpAndSettle();
  }

  ScrollController reportScroll(WidgetTester tester) => tester
      .widget<CustomScrollView>(find.byType(CustomScrollView))
      .controller!;

  Finder pairOccurrence(String sourceId) {
    final occurrence = currentReport().visibleRows.rows.firstWhere(
      (row) => row.isPairOccurrence && row.pairNode?.row.nodeId == sourceId,
    );
    return find.byKey(ValueKey<SuppliersByItemRowKey>(occurrence.key));
  }

  testWidgets('View radios update in place and announce the current sort', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    api.load = () async => SuppliersByItemNode.parseRows(_supplierViewRows);
    await openReport(
      tester,
      filters: const SuppliersByItemFilters(expandBom: true),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<ActionChip>(viewButton).visualDensity,
      VisualDensity.compact,
    );

    void expectChecked<T extends Enum>(T value, bool expected) {
      final tile = find.byKey(ValueKey(value));
      final data = tester.getSemantics(tile).getSemanticsData();
      expect(
        data.flagsCollection.isChecked,
        expected ? CheckedState.isTrue : CheckedState.isFalse,
      );
      expect(tester.getSize(tile).height, greaterThanOrEqualTo(48));
    }

    await openView(tester);
    expectChecked(SuppliersByItemGroup.template, true);
    expectChecked(SuppliersByItemSortField.stock, true);
    expectChecked(SuppliersByItemSortDirection.desc, true);
    await selectView(tester, SuppliersByItemGroup.supplier);
    await selectView(tester, SuppliersByItemSortDirection.asc);
    await selectView(tester, SuppliersByItemSortField.lastPurchase);
    expectChecked(SuppliersByItemGroup.template, false);
    expectChecked(SuppliersByItemGroup.supplier, true);
    expectChecked(SuppliersByItemSortField.lastPurchase, true);
    expectChecked(SuppliersByItemSortDirection.desc, true);
    expect(find.text('Newest first'), findsOneWidget);
    await selectView(tester, SuppliersByItemSortDirection.asc);
    expectChecked(SuppliersByItemSortDirection.asc, true);
    await doneWithView(tester);
    await tester.ensureVisible(viewButton);
    await tester.pumpAndSettle();
    expect(
      within(viewButton, 'Supplier · Last Purchase Date ↑').hitTestable(),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(viewButton).getSemanticsData().value,
      'Supplier, Last Purchase Date, Oldest first',
    );
    expect(find.byTooltip('Fields').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Refresh report').hitTestable(), findsOneWidget);
    expect(find.byIcon(Icons.filter_alt).hitTestable(), findsOneWidget);
    expect(find.text('EDGE').hitTestable(), findsOneWidget);
    expect(pairOccurrence('supplier:KIT:EDGE'), findsOneWidget);
    expect(viewButton.hitTestable(), findsOneWidget);
    expect(api.requests, hasLength(1));
    semantics.dispose();
  });

  testWidgets(
    'View shows the saved order in the scrolling chip row at 320 dp and 2x',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 780);
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      _useFieldPreferences('buyer');
      final storage = Get.find<StorageService>();
      const scope = (site: 'https://erp.example', user: 'buyer');
      await storage.loadSuppliersByItemView(scope);
      await storage.saveSuppliersByItemView(
        scope,
        const SuppliersByItemView(
          group: SuppliersByItemGroup.supplier,
          sortField: SuppliersByItemSortField.lastPurchase,
          sortDirection: SuppliersByItemSortDirection.asc,
        ),
      );
      await openReport(
        tester,
        size: const Size(320, 780),
        fontFamily: reportFont,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(viewButton);
      await tester.pumpAndSettle();

      final caption = within(viewButton, 'Supplier · Last Purchase Date ↑');
      expect(caption.hitTestable(), findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(caption).didExceedMaxLines,
        isFalse,
      );
      final chipRow = find
          .ancestor(
            of: viewButton,
            matching: find.byType(SingleChildScrollView),
          )
          .first;
      expect(
        tester.widget<SingleChildScrollView>(chipRow).scrollDirection,
        Axis.horizontal,
      );
      expect(find.byTooltip('Fields').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await openView(tester);
      expect(
        find.byKey(const ValueKey(SuppliersByItemSortField.lastPurchase)),
        findsOneWidget,
      );
    },
  );

  testWidgets('a shared settings load failure shows one guarded Retry', (
    tester,
  ) async {
    final database = _useFieldPreferences('buyer');
    final site = Completer<String?>();
    var attempts = 0;
    database.readSite = () async {
      if (++attempts == 1) throw StateError('Config unavailable');
      return site.future;
    };
    await openReport(tester);
    await tester.pumpAndSettle();

    final message = find.text("Couldn't load settings");
    final retry = find.widgetWithText(TextButton, 'Retry');
    expect(message, findsOneWidget);
    expect(retry, findsOneWidget);
    await tester.tap(retry);
    await tester.pump();
    expect(tester.widget<TextButton>(retry).onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(attempts, 2);

    site.complete('https://erp.example');
    await tester.pumpAndSettle();
    expect(message, findsNothing);
    expect(retry, findsNothing);
  });

  testWidgets('Supplier rows retain memberships and totals with Fields off', (
    tester,
  ) async {
    api.load = () async => SuppliersByItemNode.parseRows(_supplierViewRows);
    await openReport(
      tester,
      size: const Size(411, 1150),
      filters: const SuppliersByItemFilters(expandBom: true),
    );
    await tester.pumpAndSettle();
    final controller = currentReport();
    await controller.setGroup(SuppliersByItemGroup.supplier);
    await tester.pumpAndSettle();
    await viewCommand(tester, 'Expand all');
    final edge = pairOccurrence('supplier:KIT:EDGE');
    final lockal = pairOccurrence('supplier:KIT:LOCKAL');
    final frame = pairOccurrence('supplier:FRAME:EDGE');
    expect(within(edge, 'Last Purchase Date 1 Oct 25'), findsOneWidget);
    expect(within(edge, 'Open Order Qty 4 Nos'), findsOneWidget);
    expect(within(frame, 'KIT › BOM-KIT-001 › FRAME'), findsOneWidget);
    expect(within(rowWith('EDGE'), 'Items 1'), findsOneWidget);
    expect(within(rowWith('EDGE'), 'BOM components 1'), findsOneWidget);

    final scroll = reportScroll(tester);
    final scrollable = find.byWidgetPredicate(
      (widget) => widget is Scrollable && widget.controller == scroll,
    );
    await tester.scrollUntilVisible(lockal, 160, scrollable: scrollable);
    expect(within(lockal, 'Last Purchase Date 10 Nov 26'), findsOneWidget);
    expect(within(lockal, 'Open Order Qty'), findsNothing);

    for (final field in [
      SuppliersByItemField.supplierGroupItemCount,
      SuppliersByItemField.supplierGroupComponentCount,
      SuppliersByItemField.componentMatchPath,
    ]) {
      await controller.setFieldVisible(field, false);
    }
    await tester.pumpAndSettle();
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('Items 1'), findsNothing);
    expect(find.text('BOM components 1'), findsNothing);
    expect(within(frame, 'KIT › BOM-KIT-001 › FRAME'), findsOneWidget);
    expect(within(frame, 'Component FRAME for KIT'), findsOneWidget);

    for (final field in SuppliersByItemField.values) {
      await controller.setFieldVisible(field, false);
    }
    await tester.pumpAndSettle();
    expect(within(edge, 'KIT'), findsOneWidget);
    expect(within(edge, 'Last Purchase Date 1 Oct 25'), findsNothing);
    await tester.scrollUntilVisible(lockal, 150, scrollable: scrollable);
    expect(within(lockal, 'KIT'), findsOneWidget);
    final footer = find.byType(SuppliersByItemFooter);
    await tester.scrollUntilVisible(footer, 150, scrollable: scrollable);
    final noSupplierGroup = find.byWidgetPredicate(
      (widget) =>
          widget is SuppliersByItemDisplayTile &&
          widget.entry.group?.label == 'No supplier recorded',
    );
    expect(within(noSupplierGroup, 'No supplier recorded'), findsOneWidget);
    expect(find.text('No supplier recorded'), findsWidgets);
    expect(
      within(footer, 'End of list · Totals for all loaded items'),
      findsOneWidget,
    );
    expect(within(footer, '3 Nos'), findsOneWidget);
    expect(within(footer, '103 Nos'), findsNothing);
    expect(
      tester.widget<Scrollbar>(find.byType(Scrollbar)).controller,
      same(scroll),
    );
    expect(api.requests, hasLength(1));
  });

  testWidgets(
    'nested Supplier search keeps other pairs and restores each mode',
    (tester) async {
      api.load = () async => SuppliersByItemNode.parseRows(_supplierViewRows);
      await openReport(
        tester,
        size: const Size(411, 1150),
        filters: const SuppliersByItemFilters(expandBom: true),
        showFields: [SuppliersByItemField.supplierSources],
      );
      await tester.pumpAndSettle();
      final controller = currentReport();
      await controller.setGroup(SuppliersByItemGroup.supplier);
      await tester.pumpAndSettle();
      await tester.tap(within(rowWith('LOCKAL'), 'LOCKAL'));
      await tester.pumpAndSettle();
      final lockal = pairOccurrence('supplier:KIT:LOCKAL');
      await tester.tap(
        find.descendant(
          of: lockal,
          matching: find.widgetWithText(TextButton, 'Show supplier details'),
        ),
      );
      await tester.pumpAndSettle();
      expect(within(lockal, 'Purchase Order'), findsOneWidget);

      final scroll = reportScroll(tester);
      final scrollable = find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.controller == scroll,
      );
      Future<void> reveal(Finder row) async {
        if (row.hitTestable().evaluate().isEmpty) {
          await tester.scrollUntilVisible(row, 160, scrollable: scrollable);
          await tester.pumpAndSettle();
        }
      }

      final input = find.byType(TextField);
      await tester.enterText(input, 'kit nest-only');
      await tester.pumpAndSettle();
      final lockalHeading = find.byWidgetPredicate(
        (widget) =>
            widget is SuppliersByItemDisplayTile &&
            widget.entry.group?.label == 'LOCKAL',
      );
      expect(find.text('Items 1'), findsOneWidget);
      expect(find.text('EDGE'), findsOneWidget);
      expect(within(lockalHeading, 'LOCKAL'), findsOneWidget);
      final nestedPair = pairOccurrence('supplier:PIN:NEST-ONLY');
      await reveal(nestedPair);
      expect(
        within(nestedPair, 'KIT › BOM-KIT-001 › FRAME › BOM-FRAME-001 › PIN'),
        findsOneWidget,
      );
      await viewCommand(tester, 'Collapse all');
      await reveal(nestedPair);
      expect(within(nestedPair, 'Component PIN for KIT'), findsOneWidget);
      expect(find.text('Purchase Order'), findsNothing);
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(within(lockalHeading, 'LOCKAL'));
      await tester.pumpAndSettle();
      expect(lockal, findsOneWidget);
      await viewCommand(tester, 'Expand all');
      expect(controller.canExpandAll, isFalse);

      await openView(tester);
      await selectView(tester, SuppliersByItemGroup.template);
      await doneWithView(tester);
      expect(find.text('Items 1'), findsOneWidget);
      final itemTreePair = reportRow('supplier:PIN:NEST-ONLY');
      await reveal(itemTreePair);
      expect(itemTreePair, findsOneWidget);
      expect(tester.widget<TextField>(input).controller!.text, 'kit nest-only');
      await openView(tester);
      await selectView(tester, SuppliersByItemGroup.supplier);
      await doneWithView(tester);
      expect(controller.canExpandAll, isFalse);
      await reveal(nestedPair);
      expect(within(nestedPair, 'Component PIN for KIT'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear search query'));
      await tester.pumpAndSettle();
      expect(find.text('Component PIN for KIT'), findsNothing);
      expect(within(lockal, 'Purchase Order'), findsOneWidget);
      expect(find.text('No supplier recorded'), findsWidgets);
      expect(api.requests, hasLength(1));
    },
  );

  testWidgets(
    'View failure retries in the sheet and report and saves by site',
    (tester) async {
      final database = _useFieldPreferences('view@example.com');
      api.load = () async => SuppliersByItemNode.parseRows(_supplierViewRows);
      await openReport(tester);
      await tester.pumpAndSettle();

      final controller = currentReport();
      final pending = Completer<void>();
      database.onSave = () => pending.future;
      await openView(tester);
      final supplier = find.byKey(
        const ValueKey(SuppliersByItemGroup.supplier),
      );
      await tester.tap(supplier);
      await tester.pump();
      expect(find.text('Saving View…'), findsOneWidget);
      expect(controller.view.value.group, SuppliersByItemGroup.supplier);
      pending.completeError(StateError('disk unavailable'));
      await tester.pumpAndSettle();
      final sheet = find.byType(BottomSheet);
      const message = "Couldn't save View. Your choices apply to this session.";
      expect(within(sheet, message), findsOneWidget);
      expect(within(sheet, 'Retry'), findsOneWidget);
      await doneWithView(tester);
      expect(find.text(message).hitTestable(), findsOneWidget);

      final retry = Completer<void>();
      database.onSave = () => retry.future;
      await openView(tester);
      await tester.tap(within(sheet, 'Retry'));
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(
              find.descendant(
                of: sheet,
                matching: find.widgetWithText(TextButton, 'Retry'),
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Done'));
      await tester.pump();
      expect(
        controller.viewSaving.value || controller.viewRetrying.value,
        isTrue,
      );
      retry.completeError(StateError('disk still unavailable'));
      await tester.pumpAndSettle();
      expect(find.text(message).hitTestable(), findsOneWidget);
      database.onSave = null;
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pumpAndSettle();
      expect(find.text(message), findsNothing);
      expect(api.requests, hasLength(1));
      await currentReport().setSortField(
        SuppliersByItemSortField.supplierCount,
      );
      await currentReport().setSortDirection(SuppliersByItemSortDirection.asc);
      await tester.pumpAndSettle();

      Get.back<void>();
      await tester.pumpAndSettle();
      Get.toNamed(AppRoutes.SUPPLIERS_BY_ITEM);
      await tester.pumpAndSettle();
      expect(
        currentReport().view.value,
        const SuppliersByItemView(
          group: SuppliersByItemGroup.supplier,
          sortField: SuppliersByItemSortField.supplierCount,
          sortDirection: SuppliersByItemSortDirection.asc,
        ),
      );
      expect(find.text('EDGE'), findsOneWidget);

      final store = Get.find<StorageService>();
      await store.saveBaseUrl('https://other.example');
      await tester.pumpAndSettle();
      expect(currentReport().view.value, const SuppliersByItemView());
      Get.back<void>();
      await tester.pumpAndSettle();
      Get.toNamed(AppRoutes.SUPPLIERS_BY_ITEM);
      await tester.pumpAndSettle();
      expect(currentReport().view.value, const SuppliersByItemView());
      expect(api.requests, hasLength(3));
    },
  );

  testWidgets(
    'regroup and sort restore the same pair below the painted header',
    (tester) async {
      api.load = () async => SuppliersByItemNode.parseRows([
        for (var index = 0; index < 40; index++) ...[
          {
            'node_id': 'item:PAIR-$index',
            'balance_qty': 40 - index,
            'stock_uom': 'Nos',
            'item_name': 'Item $index with a longer name for narrow screens',
          },
          {
            'node_id': 'supplier:PAIR-$index:${index == 0 ? 'EDGE' : 'LOCKAL'}',
            'parent_id': 'item:PAIR-$index',
            'supplier': index == 0 ? 'EDGE' : 'LOCKAL',
          },
        ],
      ]);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openReport(tester, size: const Size(390, 720));
      await tester.pumpAndSettle();
      final controller = currentReport();
      controller.toggleBranch('item:PAIR-11');
      await tester.pumpAndSettle();
      const key = 'supplier:PAIR-11:LOCKAL';
      final source = reportRow(key);
      final scroll = reportScroll(tester);
      await tester.scrollUntilVisible(
        source,
        200,
        scrollable: find.byWidgetPredicate(
          (widget) => widget is Scrollable && widget.controller == scroll,
        ),
      );
      await tester.pumpAndSettle();
      scroll.jumpTo(
        scroll.offset + tester.getTopLeft(source).dy - pinnedBottom(tester) + 8,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(source).dy,
        closeTo(pinnedBottom(tester) - 8, 0.5),
      );

      await openView(tester);
      await selectView(tester, SuppliersByItemGroup.supplier);
      await doneWithView(tester);
      final occurrence = pairOccurrence(key);
      await tester.pump();
      expect(
        tester.getTopLeft(occurrence).dy,
        closeTo(pinnedBottom(tester), 0.5),
      );

      await openView(tester);
      await selectView(tester, SuppliersByItemSortDirection.asc);
      await doneWithView(tester);
      await tester.pump();
      expect(
        tester.getTopLeft(occurrence).dy,
        closeTo(pinnedBottom(tester), 0.5),
      );

      await controller.setFieldVisible(
        SuppliersByItemField.supplierLastBuyColumn,
        false,
      );
      await tester.pumpAndSettle();
      await tester.pump();
      expect(
        tester.getTopLeft(occurrence).dy,
        closeTo(pinnedBottom(tester), 0.5),
      );
      await openView(tester);
      await selectView(tester, SuppliersByItemGroup.template);
      await doneWithView(tester);
      await tester.pump();
      expect(tester.getTopLeft(source).dy, closeTo(pinnedBottom(tester), 0.5));

      await tester.enterText(find.byType(TextField), 'EDGE');
      await tester.pumpAndSettle();
      await openView(tester);
      await selectView(tester, SuppliersByItemGroup.supplier);
      await doneWithView(tester);
      expect(find.text('Items 1'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search query'));
      await tester.pumpAndSettle();
      await tester.pump();
      expect(
        tester.getTopLeft(occurrence).dy,
        closeTo(pinnedBottom(tester), 0.5),
      );
      expect(api.requests, hasLength(1));
    },
  );

  testWidgets(
    'supplier headings pin, then hand off in a lazy 10,000-row list',
    (tester) async {
      api.load = () async => SuppliersByItemNode.parseRows([
        for (var index = 0; index < 10000; index++) ...[
          {
            'node_id': 'item:ROW-$index',
            'balance_qty': 10000 - index,
            'stock_uom': 'Nos',
          },
          {
            'node_id': 'supplier:ROW-$index:${index < 24 ? 'A' : 'B'}',
            'parent_id': 'item:ROW-$index',
            'supplier': index < 24 ? 'A' : 'B',
            'supplier_name': 'Shared',
          },
        ],
      ]);
      await openReport(tester);
      await tester.pumpAndSettle();
      final controller = currentReport();
      await controller.setGroup(SuppliersByItemGroup.supplier);
      controller.expandAll();
      await tester.pumpAndSettle();
      final scroll = reportScroll(tester);
      scroll.jumpTo(600);
      await tester.pumpAndSettle();
      final baseline = pinnedBottom(tester, includesSupplier: false);
      final second = controller.visibleRows.rows.firstWhere(
        (row) => row.group?.label == 'Shared (B)',
      );
      final inFlow = find.byKey(ValueKey<SuppliersByItemRowKey>(second.key));
      final firstPinned = find.text('Shared (A)').hitTestable();
      final secondPinned = find.text('Shared (B)').hitTestable();

      for (final offset in [600.0, 900.0]) {
        scroll.jumpTo(offset);
        await tester.pumpAndSettle();
        expect(firstPinned, findsOneWidget);
        expect(
          tester.getTopLeft(firstPinned).dy,
          inInclusiveRange(baseline, baseline + 24),
        );
        expect(
          find.byType(SuppliersByItemDisplayTile).evaluate().length,
          lessThan(60),
        );
      }
      await tester.scrollUntilVisible(
        inFlow,
        360,
        scrollable: find.byWidgetPredicate(
          (widget) => widget is Scrollable && widget.controller == scroll,
        ),
      );
      await tester.pumpAndSettle();
      scroll.jumpTo(
        scroll.offset + tester.getTopLeft(inFlow).dy - baseline - 20,
      );
      await tester.pumpAndSettle();
      expect(pinnedBottom(tester), closeTo(baseline + 20, 0.5));
      scroll.jumpTo(
        scroll.offset + tester.getTopLeft(inFlow).dy - baseline + 450,
      );
      await tester.pumpAndSettle();
      expect(firstPinned, findsNothing);
      expect(secondPinned, findsOneWidget);
      expect(
        tester.getTopLeft(secondPinned).dy,
        inInclusiveRange(baseline, baseline + 24),
      );
      expect(
        find.byType(SuppliersByItemDisplayTile).evaluate().length,
        lessThan(60),
      );
      expect(tester.takeException(), isNull);
    },
  );

  void loadStickySupplierRows() {
    api.load = () async => SuppliersByItemNode.parseRows([
      for (var index = 0; index < 16; index++) ...[
        {
          'node_id': 'item:STICKY-$index',
          'balance_qty': 16 - index,
          'stock_uom': 'Nos',
        },
        {
          'node_id': 'supplier:STICKY-$index:SUP',
          'parent_id': 'item:STICKY-$index',
          'supplier': 'SUP',
          'supplier_name': 'Sticky Supplier',
        },
      ],
    ]);
  }

  Finder stickySupplierGroup() {
    final group = currentReport().visibleRows.rows.firstWhere(
      (row) => row.group?.label == 'Sticky Supplier',
    );
    return find.byKey(ValueKey<SuppliersByItemRowKey>(group.key));
  }

  testWidgets('a child at the header boundary keeps its supplier heading', (
    tester,
  ) async {
    loadStickySupplierRows();
    await openReport(tester);
    await tester.pumpAndSettle();
    final controller = currentReport();
    await controller.setGroup(SuppliersByItemGroup.supplier);
    controller.expandAll();
    await tester.pumpAndSettle();
    final heading = stickySupplierGroup();
    final child = pairOccurrence('supplier:STICKY-0:SUP');
    final initialBase = pinnedBottom(tester, includesSupplier: false);
    expect(tester.getTopLeft(heading).dy, closeTo(initialBase, 0.5));
    expect(pinnedBottom(tester), closeTo(initialBase, 0.5));

    final scroll = reportScroll(tester);
    scroll.jumpTo(120);
    await tester.pumpAndSettle();
    final base = pinnedBottom(tester, includesSupplier: false);
    scroll.jumpTo(scroll.offset + tester.getTopLeft(child).dy - base);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(child).dy, closeTo(base, 0.001));
    expect(pinnedBottom(tester), greaterThan(base));
    expect(find.text('Sticky Supplier').hitTestable(), findsOneWidget);
  });

  testWidgets(
    'supplier heading remains accessible as its overlay gains and loses space',
    (tester) async {
      final semantics = tester.ensureSemantics();
      loadStickySupplierRows();
      await openReport(tester, size: const Size(390, 240));
      await tester.pumpAndSettle();
      final controller = currentReport();
      await controller.setGroup(SuppliersByItemGroup.supplier);
      controller.expandAll();
      await tester.pumpAndSettle();
      final scroll = reportScroll(tester);
      scroll.jumpTo(200);
      await tester.pumpAndSettle();
      final group = stickySupplierGroup();
      final base = pinnedBottom(tester, includesSupplier: false);
      scroll.jumpTo(scroll.offset + tester.getTopLeft(group).dy - base + 2);
      await tester.pumpAndSettle();
      final heading = find.semantics.byLabel(
        RegExp(r'^Supplier Name Sticky Supplier\b'),
      );

      for (final space in [132.0, 72.0, 132.0]) {
        await tester.binding.setSurfaceSize(Size(390, base + space));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(group).dy, closeTo(base - 2, 0.5));
        expect(
          pinnedBottom(tester),
          space == 72 ? closeTo(base, 0.5) : greaterThan(base),
        );
        expect(heading, findsOne);
        final data = heading.evaluate().single.getSemanticsData();
        expect(data.flagsCollection.isExpanded, Tristate.isTrue);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
      }
      semantics.dispose();
    },
  );

  testWidgets('a long sort reversal restores the same row within 16 frames', (
    tester,
  ) async {
    const count = 2000;
    api.load = () async => SuppliersByItemNode.parseRows([
      for (var index = 0; index < count; index++)
        {
          'node_id': 'item:ROW-$index',
          'balance_qty': count - index,
          'stock_uom': 'Nos',
        },
    ]);
    await openReport(tester, size: const Size(390, 660));
    await tester.pumpAndSettle();
    final scroll = reportScroll(tester);
    final row = reportRow('item:ROW-20');
    await tester.scrollUntilVisible(
      row,
      300,
      scrollable: find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.controller == scroll,
      ),
    );
    await tester.pumpAndSettle();
    scroll.jumpTo(
      scroll.offset + tester.getTopLeft(row).dy - pinnedBottom(tester) + 8,
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(row).dy, closeTo(pinnedBottom(tester) - 8, 0.5));

    await currentReport().setSortDirection(SuppliersByItemSortDirection.asc);
    for (var frame = 0; frame < 16; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(row.hitTestable(), findsOneWidget);
    expect(tester.getTopLeft(row).dy, closeTo(pinnedBottom(tester), 0.5));
    final restored = scroll.offset;
    await tester.pump();
    expect(scroll.offset, closeTo(restored, 0.5));
  });

  testWidgets('Suppliers clears the tree and Fields schema on owner change', (
    tester,
  ) async {
    const firstId = 'buyer-a@example.com';
    const secondId = 'buyer-b@example.com';
    final auth = Get.find<AuthenticationController>();
    final database = _useFieldPreferences(firstId);
    const prefix = 'suppliers_by_item_fields::https%3A%2F%2Ferp.example::';
    database.records['$prefix${Uri.encodeComponent(firstId)}'] =
        '{"itemBalance":false}';
    database.records['$prefix${Uri.encodeComponent(secondId)}'] =
        '{"itemProjected":true}';
    api.columns = const [
      (fieldname: 'balance_qty', label: 'Site A balance'),
      (fieldname: 'projected_qty', label: 'Site A projected'),
    ];
    api.load = () async => SuppliersByItemNode.parseRows([
      {
        'node_id': 'item:KIT',
        'balance_qty': 4,
        'projected_qty': 7,
        'stock_uom': 'Nos',
      },
    ]);
    final balanceField = find.byKey(
      const ValueKey(SuppliersByItemField.itemBalance),
    );
    final projectedField = find.byKey(
      const ValueKey(SuppliersByItemField.itemProjected),
    );
    final oldBalanceCaption = within(balanceField, 'Site A balance');

    await openReport(tester);
    await tester.pumpAndSettle();
    expect(reportRow('item:KIT'), findsOneWidget);

    await tester.tap(find.byTooltip('Fields'));
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(balanceField).value, isFalse);
    expect(tester.widget<CheckboxListTile>(projectedField).value, isFalse);
    expect(oldBalanceCaption, findsOneWidget);

    auth.currentUser.value = _fieldUser(secondId);
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(balanceField).value, isTrue);
    expect(tester.widget<CheckboxListTile>(projectedField).value, isTrue);
    expect(oldBalanceCaption, findsNothing);

    Navigator.of(tester.element(balanceField)).pop();
    await tester.pumpAndSettle();
    expect(reportRow('item:KIT'), findsNothing);
    expect(currentReport().summary.itemCount, 0);
    expect(api.requests, hasLength(1));

    api.columns = null;
    await tester.tap(find.byTooltip('Refresh report'));
    await tester.pumpAndSettle();
    expect(within(reportRow('item:KIT'), 'Balance Qty 4 Nos'), findsOneWidget);
    expect(
      within(reportRow('item:KIT'), 'Projected Qty 7 Nos'),
      findsOneWidget,
    );
    auth.currentUser.value = _fieldUser('buyer-c@example.com');
    await tester.pumpAndSettle();
    expect(reportRow('item:KIT'), findsNothing);
    expect(api.requests, hasLength(2));
  });

  testWidgets('Suppliers ignores a run from before an owner round trip', (
    tester,
  ) async {
    final auth = Get.find<AuthenticationController>();
    _useFieldPreferences('Alice');
    await openReport(tester);
    await tester.pumpAndSettle();
    final report = currentReport();
    final oldRows = Completer<List<SuppliersByItemNode>>();
    api.load = () => oldRows.future;
    final stale = report.run();
    expect(report.isLoading.value, isTrue);

    auth.currentUser.value = _fieldUser('Bob');
    auth.currentUser.value = _fieldUser('Alice');
    final newRows = Completer<List<SuppliersByItemNode>>();
    api.load = () => newRows.future;
    final fresh = report.run();
    oldRows.complete(
      SuppliersByItemNode.parseRows([
        {'node_id': 'item:OLD'},
      ]),
    );
    await stale;
    expect(report.isLoading.value, isTrue);
    expect(report.nodes, isEmpty);

    newRows.complete(
      SuppliersByItemNode.parseRows([
        {'node_id': 'item:NEW'},
      ]),
    );
    await fresh;
    await tester.pumpAndSettle();
    expect(reportRow('item:NEW'), findsOneWidget);
    expect(reportRow('item:OLD'), findsNothing);
  });

  testWidgets('Suppliers keeps Guest and stale-cache display choices local', (
    tester,
  ) async {
    final database = _useFieldPreferences('Guest');
    final auth = Get.find<AuthenticationController>();
    final storage = Get.find<StorageService>();
    await storage.saveUser(_fieldUser('Guest'));
    await openReport(tester);
    await tester.pumpAndSettle();
    final report = currentReport();
    const moved = SuppliersByItemField.summaryItemCount;
    expect(report.fieldsSessionOnly.value, isTrue);
    await report.setFieldVisible(moved, false);
    expect(report.fieldVisibility.shows(moved), isFalse);
    expect(database.records.keys, [DatabaseService.serverUrlKey]);

    final alice = _fieldUser('Alice');
    await storage.saveUser(alice);
    auth.currentUser.value = alice;
    await tester.pumpAndSettle();
    expect(report.fieldsSessionOnly.value, isFalse);
    expect(report.fieldVisibility.shows(moved), isTrue);

    auth.currentUser.value = null;
    await tester.pumpAndSettle();
    expect(report.fieldsSessionOnly.value, isTrue);
    await report.setFieldVisible(moved, false);
    expect(report.fieldVisibility.shows(moved), isFalse);
    expect(database.records.keys, [DatabaseService.serverUrlKey]);

    auth.currentUser.value = alice;
    await tester.pumpAndSettle();
    expect(report.fieldsSessionOnly.value, isFalse);
    expect(report.fieldVisibility.shows(moved), isTrue);
  });

  testWidgets(
    'Fields changes row details without reloading or closing groups',
    (tester) async {
      api.load = () async => SuppliersByItemNode.parseRows([
        {
          'node_id': 'item:KIT',
          'item_name': 'Travel kit',
          'supplier_count': 1,
          'balance_qty': 4,
          'projected_qty': 7,
          'stock_uom': 'Nos',
        },
        {
          'node_id': 'supplier:KIT:VENDOR',
          'parent_id': 'item:KIT',
          'supplier_name': 'Supply Co',
          'supplier_status': 'Disabled',
          'sources': 'Purchase Order, Batch',
        },
        {'node_id': 'bom:KIT', 'parent_id': 'item:KIT', 'bom_no': 'BOM-KIT'},
        {
          'node_id': 'component:KIT:PART',
          'parent_id': 'bom:KIT',
          'item_code': 'PART',
          'item_name': 'Kit component',
          'bom_qty_per_unit': 2,
          'stock_uom': 'Nos',
        },
      ]);
      await openReport(
        tester,
        filters: const SuppliersByItemFilters(expandBom: true),
        themeMode: ThemeMode.dark,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('BOM-KIT'));
      await tester.pumpAndSettle();

      final fields = find.widgetWithIcon(
        IconButton,
        Icons.view_agenda_outlined,
      );
      expect(tester.widget<IconButton>(fields).tooltip, 'Fields');
      expect(find.text('Travel kit'), findsOneWidget);
      expect(
        within(reportRow('item:KIT'), 'Balance Qty 4 Nos'),
        findsOneWidget,
      );
      expect(find.text('Projected Qty 7 Nos'), findsNothing);
      expect(find.text('Supply Co'), findsOneWidget);
      expect(find.text('Disabled'), findsOneWidget);
      expect(find.text('Purchase Order, Batch'), findsNothing);
      expect(find.text('BOM Qty per Unit 2 Nos per Nos'), findsOneWidget);

      await tester.tap(fields);
      await tester.pumpAndSettle();
      expect(find.text('Item rows'), findsOneWidget);
      expect(find.bySemanticsLabel('Item rows, Item Name'), findsOneWidget);
      final sheetScroll = find.descendant(
        of: find.byType(DraggableScrollableSheet),
        matching: find.byType(Scrollable),
      );

      Future<void> toggle(
        SuppliersByItemField field, {
        required bool was,
        bool locked = false,
      }) async {
        final tile = find.byKey(ValueKey(field));
        await tester.scrollUntilVisible(tile, 140, scrollable: sheetScroll);
        expect(tester.widget<CheckboxListTile>(tile).value, was);
        if (locked) {
          expect(tester.widget<CheckboxListTile>(tile).onChanged, isNull);
          return;
        }
        await tester.tap(tile);
        await tester.pumpAndSettle();
        expect(tester.widget<CheckboxListTile>(tile).value, !was);
      }

      await toggle(SuppliersByItemField.itemName, was: true, locked: true);
      await toggle(SuppliersByItemField.itemBalance, was: true);
      await toggle(SuppliersByItemField.itemProjected, was: false);
      await toggle(
        SuppliersByItemField.supplierStatus,
        was: true,
        locked: true,
      );
      await toggle(SuppliersByItemField.supplierSources, was: false);
      await toggle(SuppliersByItemField.componentQtyPerUnit, was: true);

      Navigator.of(tester.element(sheetScroll)).pop();
      await tester.pumpAndSettle();
      expect(find.text('KIT'), findsOneWidget);
      expect(find.text('Travel kit'), findsOneWidget);
      expect(within(reportRow('item:KIT'), 'Balance Qty 4 Nos'), findsNothing);
      expect(find.text('Projected Qty 7 Nos'), findsOneWidget);
      expect(find.text('Supply Co'), findsOneWidget);
      expect(find.text('Disabled'), findsOneWidget);
      expect(find.text('Purchase Order, Batch'), findsNothing);
      await tester.tap(find.text('Supply Co'));
      await tester.pumpAndSettle();
      expect(find.text('Purchase Order, Batch'), findsOneWidget);
      expect(find.text('PART'), findsOneWidget);
      expect(find.text('Kit component'), findsOneWidget);
      expect(find.text('BOM Qty per Unit 2 Nos per Nos'), findsNothing);
      expect(api.requests, hasLength(1));

      await tester.tap(fields);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset to defaults'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey(SuppliersByItemField.itemName)),
            )
            .value,
        isTrue,
      );
      Navigator.of(tester.element(sheetScroll)).pop();
      await tester.pumpAndSettle();
      expect(find.text('Travel kit'), findsOneWidget);
      expect(
        within(reportRow('item:KIT'), 'Balance Qty 4 Nos'),
        findsOneWidget,
      );
      expect(find.text('Projected Qty 7 Nos'), findsNothing);
      expect(find.text('Supply Co'), findsOneWidget);
      expect(find.text('Disabled'), findsOneWidget);
      expect(find.text('Purchase Order, Batch'), findsNothing);
      expect(find.text('BOM Qty per Unit 2 Nos per Nos'), findsOneWidget);
      expect(api.requests, hasLength(1));
    },
  );

  void loadAnchorRows(
    String Function(int) nameFor, {
    bool balanceUnits = false,
  }) {
    api.load = () async => SuppliersByItemNode.parseRows([
      for (var index = 0; index < 40; index++) ...[
        {
          'node_id': 'item:ROW-$index',
          'item_name': balanceUnits ? 'Item $index' : nameFor(index),
          'balance_qty': 39 - index,
          'stock_uom': balanceUnits && nameFor(index) != 'Item $index'
              ? nameFor(index)
              : 'Nos',
        },
        {
          'node_id': 'supplier:ROW-$index:SUP',
          'parent_id': 'item:ROW-$index',
          'supplier': 'SUP',
        },
      ],
    ]);
  }

  Finder anchorRow(int index) => reportRow('item:ROW-$index');

  double toolbarBottom(WidgetTester tester) => pinnedBottom(tester);

  Future<ScrollController> scrollIntoRow(
    WidgetTester tester,
    int index,
    double offset,
  ) async {
    final scroll = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!;
    if (anchorRow(index).evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        anchorRow(index),
        120,
        scrollable: find.byWidgetPredicate(
          (widget) => widget is Scrollable && widget.controller == scroll,
        ),
      );
      await tester.pumpAndSettle();
    }
    scroll.jumpTo(
      scroll.offset +
          tester.getTopLeft(anchorRow(index)).dy -
          toolbarBottom(tester) +
          offset,
    );
    await tester.pumpAndSettle();
    return scroll;
  }

  testWidgets('changing and resetting fields preserves the visible row', (
    tester,
  ) async {
    api.load = () async => SuppliersByItemNode.parseRows([
      for (var index = 0; index < 40; index++) ...[
        {
          'node_id': 'item:ROW-$index',
          'row_type': 'item',
          'item_code': 'ROW-$index',
          'item_name': 'Item $index',
          'balance_qty': 39 - index,
          'stock_uom': 'Nos',
          'reorder_level': 7,
        },
        {
          'node_id': 'supplier:ROW-$index:SUP',
          'parent_id': 'item:ROW-$index',
          'supplier': 'SUP',
        },
      ],
    ]);
    await openReport(tester);
    await tester.pumpAndSettle();

    final scroll = await scrollIntoRow(tester, 4, 8);
    final anchor = reportRow('item:ROW-4');
    final toolbarBottom = pinnedBottom(tester);
    final originalOffset = tester.getTopLeft(anchor).dy;
    final originalPixels = scroll.offset;

    final fields = find.byTooltip('Fields');
    final sheet = find.byType(DraggableScrollableSheet);
    Future<void> changeFields(Finder control) async {
      await tester.tap(fields);
      await tester.pumpAndSettle();
      if (control.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          control,
          140,
          scrollable: find.descendant(
            of: sheet,
            matching: find.byType(Scrollable),
          ),
        );
      } else {
        await tester.ensureVisible(control);
      }
      await tester.tap(control);
      await tester.pumpAndSettle();
      Navigator.of(tester.element(sheet)).pop();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(anchor).dy, closeTo(originalOffset, 0.5));
      expect(tester.getBottomLeft(anchor).dy, greaterThan(toolbarBottom));
    }

    await changeFields(
      find.byKey(const ValueKey(SuppliersByItemField.itemReorderLevel)),
    );
    final expandedPixels = scroll.offset;
    expect(expandedPixels, greaterThan(originalPixels));
    expect(find.text('Item 4'), findsOneWidget);
    expect(within(anchor, 'Reorder Level 7 Nos'), findsOneWidget);

    await changeFields(find.text('Reset to defaults'));
    expect(scroll.offset, lessThan(expandedPixels));
    expect(within(anchor, 'Reorder Level 7 Nos'), findsNothing);
  });

  setUpAll(() async {
    final loader = FontLoader(reportFont)
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-Regular.ttf'));
    await loader.load();
  });

  testWidgets('View chip fits at rest with Variant Of ALS at 411 dp', (
    tester,
  ) async {
    const size = Size(411, 780);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openReport(
      tester,
      filters: const SuppliersByItemFilters(variantOf: ['ALS']),
      size: size,
      fontFamily: reportFont,
    );
    await tester.pumpAndSettle();

    final chipRow = find
        .ancestor(of: viewButton, matching: find.byType(SingleChildScrollView))
        .first;
    expect(find.byType(FilterChipWidget), findsOneWidget);
    expect(find.text('Variant Of: ALS').hitTestable(), findsOneWidget);
    expect(find.byType(AddFilterChip).hitTestable(), findsOneWidget);
    expect(
      tester.getRect(viewButton).right,
      lessThanOrEqualTo(tester.getRect(chipRow).right),
    );
    expect(viewButton.hitTestable(), findsOneWidget);
    expect(within(viewButton, 'Balance Qty ↓').hitTestable(), findsOneWidget);
    expect(
      tester.getSemantics(viewButton).getSemanticsData().value,
      'Item, Balance Qty, High to low',
    );
  });

  testWidgets('standard filter row scrolls at 411 dp and hides while busy', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 780);
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openReport(
      tester,
      filters: const SuppliersByItemFilters(
        items: ['ITEM-WITH-A-LONG-CODE-4217845'],
      ),
      size: const Size(411, 780),
      fontFamily: reportFont,
    );
    await currentReport().setGroup(SuppliersByItemGroup.supplier);
    await tester.pumpAndSettle();

    final header = find.byType(DocTypeListHeader);
    final addFilter = find.descendant(
      of: header,
      matching: find.byType(AddFilterChip),
    );
    expect(within(addFilter, 'Filter'), findsOneWidget);
    expect(
      find.descendant(of: addFilter, matching: find.byIcon(Icons.add)),
      findsOneWidget,
    );
    final chipRow = find
        .ancestor(of: addFilter, matching: find.byType(SingleChildScrollView))
        .first;
    await tester.ensureVisible(addFilter);
    await tester.pumpAndSettle();
    final filterBounds = tester.getRect(addFilter);
    final chipRowBounds = tester.getRect(chipRow);
    expect(filterBounds.left, greaterThanOrEqualTo(chipRowBounds.left));
    expect(filterBounds.right, lessThanOrEqualTo(chipRowBounds.right));
    expect(addFilter.hitTestable(), findsOneWidget);
    final viewChip = find.descendant(of: chipRow, matching: viewButton);
    expect(within(viewChip, 'Supplier · Balance Qty ↓'), findsOneWidget);
    expect(
      tester.widget<ActionChip>(viewChip).visualDensity,
      VisualDensity.compact,
    );
    expect(
      find.widgetWithIcon(IconButton, Icons.view_agenda_outlined),
      findsOneWidget,
    );

    final toolbarFilter = find.widgetWithIcon(IconButton, Icons.filter_alt);
    final activeChip = find.widgetWithText(
      FilterChipWidget,
      'Items: ITEM-WITH-A-LONG-CODE-4217845',
    );
    expect(tester.widget<FilterChipWidget>(activeChip).maxLabelWidth, isNull);
    final badge = find.byType(CountBadge);
    expect(tester.widget<CountBadge>(badge).count, 1);
    expect(tester.widget<CountBadge>(badge).muted, isFalse);
    expect(
      tester.widget<IconButton>(toolbarFilter).tooltip,
      '1 filter active — tap to edit',
    );
    expect(tester.widget<IconButton>(toolbarFilter).onPressed, isNotNull);
    expect(tester.widget<AddFilterChip>(addFilter).onTap, isNotNull);

    final pending = Completer<List<SuppliersByItemNode>>();
    api.load = () => pending.future;
    await tester.tap(find.byTooltip('Refresh report'));
    await tester.pump();
    expect(toolbarFilter, findsNothing);
    expect(badge, findsNothing);
    expect(activeChip, findsNothing);
    expect(addFilter, findsNothing);
    expect(viewButton.hitTestable(), findsOneWidget);

    pending.complete([]);
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(toolbarFilter).onPressed, isNotNull);
    expect(activeChip, findsOneWidget);
    await tester.ensureVisible(addFilter);
    await tester.pumpAndSettle();
    await tester.tap(addFilter);
    await tester.pumpAndSettle();
    expect(find.text('Run Report'), findsOneWidget);
  });

  for (final width in [320.0, 411.0]) {
    testWidgets('check filter values stay visible when scrolled at $width dp', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 780);
      addTearDown(tester.view.reset);
      await openReport(
        tester,
        filters: const SuppliersByItemFilters(
          includeDrafts: false,
          expandBom: true,
        ),
        size: Size(width, 780),
        fontFamily: reportFont,
      );
      await tester.pumpAndSettle();
      for (final label in [
        'Include Draft Purchase Orders: Off',
        'Expand BOM components: On',
      ]) {
        final caption = find.text(label);
        final chip = find.widgetWithText(FilterChipWidget, label);
        expect(tester.widget<FilterChipWidget>(chip).maxLabelWidth, isNull);
        await tester.ensureVisible(caption);
        await tester.pumpAndSettle();
        expect(caption.hitTestable(), findsOneWidget);
        final bounds = tester.getRect(caption);
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(width));
        expect(
          tester.renderObject<RenderParagraph>(caption).didExceedMaxLines,
          isFalse,
        );
      }
      final addFilter = find.byType(AddFilterChip);
      await tester.ensureVisible(addFilter);
      await tester.pumpAndSettle();
      expect(addFilter.hitTestable(), findsOneWidget);
      expect(tester.widget<ActionChip>(viewButton).padding, isNull);
    });
  }

  testWidgets('Suppliers summary shows zero suppliers for a BOM-only match', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    api.load = () async => SuppliersByItemNode.parseRows([
      {'node_id': 'item:KIT', 'item_code': 'KIT', 'supplier_count': 0},
      {'node_id': 'bom:KIT', 'parent_id': 'item:KIT'},
      {
        'node_id': 'component:PART',
        'parent_id': 'bom:KIT',
        'item_code': 'PART',
      },
      {
        'node_id': 'supplier:PART:JOAP',
        'parent_id': 'component:PART',
        'supplier': 'JOAP',
      },
    ]);
    await openReport(
      tester,
      filters: const SuppliersByItemFilters(
        suppliers: ['JOAP'],
        expandBom: true,
      ),
    );
    await currentReport().setGroup(SuppliersByItemGroup.supplier);
    await tester.pumpAndSettle();
    expect(find.text('Suppliers'), findsOneWidget);
    expect(find.bySemanticsLabel('Suppliers 0'), findsOneWidget);
    expect(find.text('JOAP'), findsOneWidget);
    semantics.dispose();
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('drawer and Item Overview use the standard header at $scale', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 2.625;
      tester.view.physicalSize = const Size(1080, 2400);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      Get.put<PermissionService>(_DrawerPermissions());
      Get.put(ItemProvider());
      final itemController = ItemFormController();
      final item = Item.fromJson({'name': 'ITEM', 'item_code': 'ITEM'});
      loadAnchorRows((index) => 'Item $index');
      await openReport(
        tester,
        size: const Size(1080 / 2.625, 2400 / 2.625),
        fontFamily: reportFont,
        home: AppShellScaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  child: const Text('Open reports drawer'),
                ),
                ItemSuppliersCard(
                  itemCode: item.itemCode,
                  isTemplate: false,
                  loadReport: () async => SuppliersByItemNode.parseRows([
                    {'node_id': 'item:ITEM'},
                    {
                      'node_id': 'supplier:ITEM:SUP',
                      'parent_id': 'item:ITEM',
                      'supplier': 'SUP',
                    },
                  ]),
                  onViewReport: (expandBom) => itemController
                      .openSuppliersReport(item, expandBom: expandBom),
                ),
              ],
            ),
          ),
        ),
        enterFromHome: () async {
          await tester.pumpAndSettle();
          await tester.tap(find.text('Open reports drawer'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Buying'));
          await tester.tap(find.text('Buying'));
          await tester.pumpAndSettle();
          final entry = find.descendant(
            of: find.byType(Drawer),
            matching: find.text('Suppliers by Item'),
          );
          await tester.ensureVisible(entry);
          await tester.tap(entry);
        },
      );
      await tester.pumpAndSettle();

      void checkHeader(IconData leading) {
        final title = within(
          find.byType(DocTypeListHeader),
          'Suppliers by Item',
        );
        expect(title.hitTestable(), findsOneWidget);
        expect(find.byIcon(leading).hitTestable(), findsOneWidget);
        expect(find.byTooltip('Fields').hitTestable(), findsOneWidget);
        expect(find.byTooltip('Refresh report').hitTestable(), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is IconButton &&
                (widget.tooltip == 'Filter' ||
                    (widget.tooltip?.contains('filter active') ?? false)),
          ),
          findsOneWidget,
        );
        expect(find.byType(AddFilterChip).hitTestable(), findsOneWidget);
        expect(viewButton.hitTestable(), findsOneWidget);
      }

      checkHeader(Icons.menu);
      final title = find.text('Suppliers by Item').hitTestable();
      final expandedY = tester.getTopLeft(title).dy;
      await scrollIntoRow(tester, 25, 0);
      checkHeader(Icons.menu);
      expect(tester.getTopLeft(title).dy, lessThan(expandedY));
      Get.back<void>();
      await tester.pumpAndSettle();
      await tester.tap(find.text('View full report'));
      await tester.pumpAndSettle();
      checkHeader(Icons.arrow_back);
      expect(api.requests.last.items, ['ITEM']);
      await scrollIntoRow(tester, 25, 0);
      checkHeader(Icons.arrow_back);
    });
  }

  testWidgets('View and summary use the same returned balance caption', (
    tester,
  ) async {
    api.columns = const [(fieldname: 'balance_qty', label: 'Bilanzmenge')];
    api.load = () async => SuppliersByItemNode.parseRows([
      {'node_id': 'item:SKU', 'balance_qty': 12, 'stock_uom': 'Nos'},
      {'node_id': 'item:BOX', 'balance_qty': 3, 'stock_uom': 'Box'},
    ]);
    await openReport(tester, hideFields: [SuppliersByItemField.itemBalance]);
    await tester.pumpAndSettle();

    final summary = find.widgetWithText(TextButton, 'Bilanzmenge by Stock UOM');
    expect(summary.hitTestable(), findsOneWidget);
    await openView(tester);
    const field = SuppliersByItemField.summaryStockByUom;
    expect(
      within(find.byKey(const ValueKey(field)), 'Bilanzmenge'),
      findsOneWidget,
    );
    await selectView(tester, field);
    await doneWithView(tester);
    expect(summary.hitTestable(), findsNothing);
  });

  testWidgets(
    'Balance Qty by Stock UOM requires two known units with a Balance Qty',
    (tester) async {
      var includeBoxBalance = false;
      api.load = () async => SuppliersByItemNode.parseRows([
        {'node_id': 'item:A', 'balance_qty': 12, 'stock_uom': 'Nos'},
        {
          'node_id': 'item:B',
          'total_qty_received': 1,
          if (includeBoxBalance) 'balance_qty': 0,
          'stock_uom': 'Box',
        },
        {'node_id': 'item:C', 'balance_qty': 5},
        {'node_id': 'bom:A', 'parent_id': 'item:A'},
        {
          'node_id': 'component:A:C',
          'parent_id': 'bom:A',
          'balance_qty': 3,
          'stock_uom': 'Kg',
        },
      ]);
      await openReport(tester);
      await tester.pumpAndSettle();

      final stock = find.widgetWithText(TextButton, 'Balance Qty by Stock UOM');
      expect(stock, findsNothing);
      includeBoxBalance = true;
      await tester.tap(find.byTooltip('Refresh report'));
      await tester.pumpAndSettle();
      await tester.tap(stock);
      await tester.pumpAndSettle();
      expect(find.text('12 Nos').hitTestable(), findsOneWidget);
      expect(find.text('0 Box').hitTestable(), findsOneWidget);
      expect(find.text('3 Kg').hitTestable(), findsNothing);
    },
  );

  testWidgets(
    'mixed stock summary, View and local search preserve browse state',
    (tester) async {
      api.load = () async => SuppliersByItemNode.parseRows([
        ..._acp25Rows,
        {'node_id': 'item:CAFÉ', 'balance_qty': 1, 'stock_uom': 'Kg'},
        {
          'node_id': 'supplier:CAFÉ:OTHER',
          'parent_id': 'item:CAFÉ',
          'supplier': 'OTHER',
        },
      ]);
      await openReport(tester);
      await tester.pumpAndSettle();
      final summary = find
          .ancestor(of: find.text('Suppliers'), matching: find.byType(Wrap))
          .first;
      expect(within(summary, 'No supplier recorded'), findsOneWidget);
      final stock = find.widgetWithText(TextButton, 'Balance Qty by Stock UOM');
      expect(tester.getSize(stock).height, greaterThanOrEqualTo(48));
      await tester.tap(stock);
      await tester.pumpAndSettle();
      expect(find.text('1 Kg').hitTestable(), findsOneWidget);
      expect(find.text('12.5 Nos').hitTestable(), findsOneWidget);
      Get.back<void>();
      await tester.pumpAndSettle();

      final input = find.byType(TextField);
      await tester.enterText(input, 'cafe other');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
      expect(find.text('Items 1'), findsOneWidget);
      expect(find.text('OTHER'), findsOneWidget);
      expect(find.text('ACP-25'), findsNothing);
      await openView(tester);
      await selectView(tester, SuppliersByItemField.searchMatchCount);
      await doneWithView(tester);
      expect(find.text('Items 1'), findsNothing);
      expect(find.text('OTHER'), findsOneWidget);

      await tester.enterText(input, 'missing:code');
      await tester.pumpAndSettle();
      expect(find.text('No matches for “missing:code”'), findsOneWidget);
      expect(
        find.text('End of list · Totals for all loaded items'),
        findsOneWidget,
      );
      expect(find.text('No items found for these filters'), findsNothing);
      await tester.tap(find.byTooltip('Clear search query'));
      await tester.pumpAndSettle();
      expect(find.text('ACP-25'), findsOneWidget);
      expect(find.text('OTHER'), findsNothing);

      await openView(tester);
      expect(
        find.byKey(const ValueKey(SuppliersByItemGroup.template)),
        findsOneWidget,
      );
      await tester.tap(find.text('Expand all'));
      await tester.pumpAndSettle();
      expect(find.text('OTHER'), findsOneWidget);
      expect(find.text('KANG KAI'), findsOneWidget);
      await openView(tester);
      await tester.tap(find.text('Collapse all'));
      await tester.pumpAndSettle();
      expect(find.text('OTHER'), findsNothing);
      expect(find.text('2002492'), findsNothing);
      expect(api.requests, hasLength(1));
    },
  );

  testWidgets(
    'short keyboard viewport scrolls summary away and reaches footer',
    (tester) async {
      loadAnchorRows((index) => 'Item $index');
      await openReport(tester, size: const Size(680, 340));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 126);
      addTearDown(tester.view.reset);
      await tester.pumpAndSettle();
      final view = find.byType(CustomScrollView);
      final scroll = tester.widget<CustomScrollView>(view).controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('Suppliers').hitTestable(), findsNothing);
      expect(viewButton.hitTestable(), findsOneWidget);
      expect(find.text('780 Nos').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  void expectFirstVisibleRow(WidgetTester tester, int index) {
    final header = toolbarBottom(tester);
    final viewportBottom = tester
        .getBottomLeft(find.byType(CustomScrollView))
        .dy;
    for (var i = 0; i < 40; i++) {
      final row = anchorRow(i);
      if (row.evaluate().isEmpty) continue;
      final rect = tester.getRect(row);
      if (rect.bottom <= header + 4 || rect.top >= viewportBottom) continue;
      expect(i, index);
      return;
    }
    fail('No report row is visible below the toolbar');
  }

  void loadTallReorderRows(bool Function(int) tall) {
    api.columns = [
      (
        fieldname: 'reorder_level',
        label: List.filled(75, 'Reorder level').join(' '),
      ),
    ];
    api.load = () async => SuppliersByItemNode.parseRows([
      for (var i = 0; i < 40; i++) ...[
        {
          'node_id': 'item:ROW-$i',
          'item_name': 'Item $i',
          'balance_qty': 39 - i,
          'stock_uom': 'Nos',
          if (tall(i)) 'reorder_level': 7,
        },
        {
          'node_id': 'supplier:ROW-$i:SUP',
          'parent_id': 'item:ROW-$i',
          'supplier': 'SUP',
        },
      ],
    ]);
  }

  Future<void> toggleAnchorField(
    WidgetTester tester,
    SuppliersByItemField key,
  ) async {
    await tester.tap(find.byTooltip('Fields'));
    await tester.pumpAndSettle();
    final field = find.byKey(ValueKey(key));
    final sheetScroll = find.descendant(
      of: find.byType(DraggableScrollableSheet),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      field.hitTestable(),
      100,
      scrollable: sheetScroll,
    );
    await tester.tap(field);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(DraggableScrollableSheet))).pop();
    await tester.pumpAndSettle();
  }

  testWidgets('anchors a shrinking row with its top below the toolbar', (
    tester,
  ) async {
    loadAnchorRows(
      (index) => index == 2
          ? List.filled(60, 'Wrapping description').join(' ')
          : 'Item $index',
      balanceUnits: true,
    );
    await openReport(tester, size: const Size(320, 500));
    await tester.pumpAndSettle();
    await scrollIntoRow(tester, 2, 100);
    expectFirstVisibleRow(tester, 2);
    expect(
      tester.getTopLeft(anchorRow(2)).dy,
      closeTo(toolbarBottom(tester) - 100, 0.01),
    );

    await toggleAnchorField(tester, SuppliersByItemField.itemBalance);
    await tester.pump();

    expectFirstVisibleRow(tester, 2);
    expect(
      tester.getTopLeft(anchorRow(2)).dy,
      closeTo(toolbarBottom(tester), 0.01),
    );
  });

  testWidgets('finds the anchor again after growing rows evict it', (
    tester,
  ) async {
    loadTallReorderRows((index) => index < 4);
    await openReport(tester, size: const Size(320, 480));
    await tester.pumpAndSettle();
    await scrollIntoRow(tester, 4, 8);
    expectFirstVisibleRow(tester, 4);
    final before = tester.renderObject(anchorRow(4));

    await toggleAnchorField(tester, SuppliersByItemField.itemReorderLevel);
    await tester.pump();

    expectFirstVisibleRow(tester, 4);
    expect(before.attached, isFalse);
    expect(tester.renderObject(anchorRow(4)), isNot(same(before)));
    expect(
      tester.getTopLeft(anchorRow(4)).dy,
      closeTo(toolbarBottom(tester), 0.5),
    );
  });

  testWidgets('field changes preserve the anchor in a stacked report', (
    tester,
  ) async {
    _useFieldPreferences('stacked@example.com');
    loadAnchorRows(
      (index) => index < 5
          ? 'Item $index with a wrapped description that takes another line'
          : 'Item $index',
      balanceUnits: true,
    );
    await openReport(tester, size: const Size(360, 560));
    await tester.pumpAndSettle();
    final underlying = await scrollIntoRow(tester, 5, 8);
    expectFirstVisibleRow(tester, 5);
    final before = underlying.offset;

    Get.toNamed(AppRoutes.SUPPLIERS_BY_ITEM, preventDuplicates: false);
    await tester.pumpAndSettle();
    expect(find.textContaining('Item 0 with'), findsOneWidget);
    await toggleAnchorField(tester, SuppliersByItemField.itemBalance);
    expect(find.textContaining('Item 0 with'), findsNothing);
    Get.back<void>();
    await tester.pumpAndSettle();

    expect(find.text('Item 5'), findsOneWidget);
    expectFirstVisibleRow(tester, 5);
    expect(
      tester.getTopLeft(anchorRow(5)).dy,
      closeTo(toolbarBottom(tester) - 8, 0.5),
    );
    expect(underlying.offset, lessThan(before));
  });

  testWidgets(
    'keeps the reading anchor as scaled summary cells wrap and disappear',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      loadAnchorRows((index) => 'Item $index');
      await openReport(tester, size: const Size(320, 950));
      await tester.pumpAndSettle();
      await scrollIntoRow(tester, 8, 8);
      expectFirstVisibleRow(tester, 8);
      final originalBottom = toolbarBottom(tester);
      expect(
        tester.getTopLeft(anchorRow(8)).dy,
        closeTo(originalBottom - 8, 0.5),
      );

      for (final field in [
        SuppliersByItemField.summaryItemCount,
        SuppliersByItemField.summarySupplierCount,
        SuppliersByItemField.summaryNoDirectCount,
        SuppliersByItemField.summaryStockByUom,
      ]) {
        await currentReport().setFieldVisible(field, false);
      }
      await tester.pumpAndSettle();
      await tester.pump();
      final smallerBottom = toolbarBottom(tester);
      expect(smallerBottom, lessThan(originalBottom));
      expect(find.text('Suppliers'), findsNothing);
      expect(find.byType(TextField).hitTestable(), findsOneWidget);
      expectFirstVisibleRow(tester, 8);
      expect(
        tester.getTopLeft(anchorRow(8)).dy,
        closeTo(smallerBottom - 8, 0.5),
      );

      await currentReport().resetViewDisplayOptions();
      await tester.pumpAndSettle();
      await tester.pump();
      expect(toolbarBottom(tester), closeTo(originalBottom, 0.5));
      expect(
        tester.getTopLeft(anchorRow(8)).dy,
        closeTo(originalBottom - 8, 0.5),
      );
    },
  );

  testWidgets('a user drag cancels pending restoration of an evicted row', (
    tester,
  ) async {
    loadTallReorderRows((index) => index < 8);
    await openReport(tester, size: const Size(320, 590));
    await tester.pumpAndSettle();
    final scroll = await scrollIntoRow(tester, 8, 8);
    final original = tester.renderObject(anchorRow(8));
    await currentReport().setFieldVisible(
      SuppliersByItemField.itemReorderLevel,
      true,
    );
    await tester.pump();
    expect(original.attached, isFalse);
    final firstCorrection = scroll.offset;
    expect(firstCorrection, greaterThan(0));

    final gesture = await tester.startGesture(
      Offset(155, toolbarBottom(tester) + 24),
    );
    await gesture.moveBy(const Offset(0, 85));
    await gesture.moveBy(const Offset(0, 45));
    final userPosition = scroll.offset;
    expect(userPosition, lessThan(firstCorrection));
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.pump();

    expect(scroll.offset, closeTo(userPosition, 0.5));
    final anchor = anchorRow(8);
    expect(anchor.hitTestable(), findsNothing);
  });

  testWidgets(
    'restoring near the shortened list end uses the visible scroll limit',
    (tester) async {
      loadTallReorderRows((index) => index >= 36);
      await openReport(
        tester,
        size: const Size(370, 720),
        showFields: [SuppliersByItemField.itemReorderLevel],
      );
      await tester.pumpAndSettle();
      final scroll = await scrollIntoRow(tester, 37, 8);
      expectFirstVisibleRow(tester, 37);
      final top = tester.getTopLeft(anchorRow(37)).dy;
      expect(top, closeTo(toolbarBottom(tester) - 8, 0.5));

      await currentReport().setFieldVisible(
        SuppliersByItemField.itemReorderLevel,
        false,
      );
      await tester.pumpAndSettle();
      await tester.pump();

      expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, 0.5));
      expect(anchorRow(37).hitTestable(), findsOneWidget);
      expect(
        tester.getTopLeft(anchorRow(37)).dy,
        greaterThanOrEqualTo(toolbarBottom(tester) - 0.5),
      );
    },
  );

  testWidgets('clearing local search restores a partially visible browse row', (
    tester,
  ) async {
    loadAnchorRows((index) => 'Item $index');
    await openReport(tester);
    await tester.pumpAndSettle();
    currentReport().toggleBranch('item:ROW-15');
    await tester.pumpAndSettle();
    final scroll = await scrollIntoRow(tester, 15, 8);
    expectFirstVisibleRow(tester, 15);
    final before = scroll.offset;
    final signedOffset =
        tester.getTopLeft(anchorRow(15)).dy - toolbarBottom(tester);
    expect(signedOffset, closeTo(-8, 0.5));

    await tester.enterText(find.byType(TextField), 'ROW-30 SUP');
    await tester.pumpAndSettle();
    expect(find.text('Items 1'), findsOneWidget);
    expect(reportRow('supplier:ROW-30:SUP').hitTestable(), findsOneWidget);
    expect(scroll.offset, lessThan(before));

    await tester.tap(find.byTooltip('Clear search query'));
    await tester.pumpAndSettle();
    await tester.pump();
    expectFirstVisibleRow(tester, 15);
    expect(
      tester.getTopLeft(anchorRow(15)).dy - toolbarBottom(tester),
      closeTo(signedOffset, 0.5),
    );
    expect(reportRow('supplier:ROW-15:SUP').hitTestable(), findsOneWidget);
    expect(currentReport().isExpanded('item:ROW-30'), isFalse);
    expect(api.requests, hasLength(1));
  });

  testWidgets('clearing search preserves a nearly hidden template heading', (
    tester,
  ) async {
    api.load = () async => SuppliersByItemNode.parseRows([
      for (var index = 0; index < 40; index++)
        {
          'node_id': 'item:ROW-$index',
          'balance_qty': 100 - 3 * index,
          'stock_uom': 'Nos',
        },
      {
        'node_id': 'supplier:ROW-30:EDGE',
        'parent_id': 'item:ROW-30',
        'supplier': 'EDGE',
      },
      {'node_id': 'template:402--WAL', 'balance_qty': 50, 'stock_uom': 'Nos'},
      for (final code in ['1000052', '1000053'])
        {
          'node_id': 'item:$code',
          'parent_id': 'template:402--WAL',
          'balance_qty': code == '1000052' ? 28 : 22,
          'stock_uom': 'Nos',
        },
    ]);
    await openReport(tester);
    await tester.pumpAndSettle();
    final controller = currentReport();
    if (!controller.isExpanded('template:402--WAL')) {
      controller.toggleBranch('template:402--WAL');
    }
    await tester.pumpAndSettle();
    final scroll = reportScroll(tester);
    final heading = reportRow('template:402--WAL');
    final variant = reportRow('item:1000052');
    await tester.scrollUntilVisible(
      heading,
      200,
      scrollable: find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.controller == scroll,
      ),
    );
    await tester.pumpAndSettle();
    // The padded row ends 5 dp below the header, leaving 1 dp of its tile.
    scroll.jumpTo(
      scroll.offset +
          tester.getBottomLeft(heading).dy -
          toolbarBottom(tester) -
          5,
    );
    await tester.pumpAndSettle();
    final signedOffset = tester.getTopLeft(heading).dy - toolbarBottom(tester);
    final variantTop = tester.getTopLeft(variant).dy;
    expect(variantTop, closeTo(toolbarBottom(tester) + 5, 0.5));
    expect(
      tester.getBottomLeft(heading).dy,
      closeTo(toolbarBottom(tester) + 5, 0.5),
    );
    final originalHeading = tester.renderObject(heading);

    await tester.enterText(find.byType(TextField), 'EDGE');
    await tester.pumpAndSettle();
    expect(heading, findsNothing);
    await tester.tap(find.byTooltip('Clear search query'));
    await tester.pumpAndSettle();

    expect(controller.isExpanded('template:402--WAL'), isTrue);
    expect(tester.renderObject(heading), isNot(same(originalHeading)));
    expect(
      tester.getTopLeft(heading).dy - toolbarBottom(tester),
      closeTo(signedOffset, 0.5),
    );
    expect(tester.getTopLeft(variant).dy, closeTo(variantTop, 0.5));
  });

  testWidgets('clearing search restores a partly collapsed large title', (
    tester,
  ) async {
    loadAnchorRows((index) => 'Item $index');
    await openReport(tester);
    await tester.pumpAndSettle();
    final scroll = reportScroll(tester);
    final first = anchorRow(0);
    final expandedTop = tester.getTopLeft(first).dy;
    scroll.jumpTo(48);
    await tester.pumpAndSettle();
    final rowTop = tester.getTopLeft(first).dy;
    expect(rowTop, closeTo(expandedTop - 48, 0.5));
    expect(rowTop, closeTo(toolbarBottom(tester), 0.5));

    await tester.enterText(find.byType(TextField), 'ROW-30 SUP');
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    await tester.tap(find.byTooltip('Clear search query'));
    await tester.pumpAndSettle();

    expect(scroll.offset, closeTo(48, 0.5));
    expect(tester.getTopLeft(first).dy, closeTo(rowTop, 0.5));
  });

  testWidgets('reversing tied Balance Qty keeps a partially visible row', (
    tester,
  ) async {
    api.load = () async => SuppliersByItemNode.parseRows([
      for (var index = 0; index < 40; index++)
        {'node_id': 'item:ROW-$index', 'balance_qty': 10, 'stock_uom': 'Nos'},
    ]);
    await openReport(tester);
    await tester.pumpAndSettle();
    final row = anchorRow(20);
    final scroll = await scrollIntoRow(tester, 20, 8);
    final pixels = scroll.offset;
    final signedOffset = tester.getTopLeft(row).dy - toolbarBottom(tester);
    expect(signedOffset, closeTo(-8, 0.5));
    final keys = currentReport().visibleRows.rows
        .map((row) => row.key)
        .toList();

    await currentReport().setSortDirection(SuppliersByItemSortDirection.asc);
    await tester.pumpAndSettle();

    expect(currentReport().visibleRows.rows.map((row) => row.key), keys);
    expect(scroll.offset, closeTo(pixels, 0.5));
    expect(
      tester.getTopLeft(row).dy - toolbarBottom(tester),
      closeTo(signedOffset, 0.5),
    );
  });

  testWidgets('clearing local search restores a footer-only viewport', (
    tester,
  ) async {
    api.load = () async => SuppliersByItemNode.parseRows([
      for (var index = 0; index < 20; index++)
        {
          'node_id': 'item:ROW-$index',
          'balance_qty': index + 1,
          'projected_qty': index + 1,
          'open_order_qty': 1,
          'reorder_qty': 1,
          'draft_order_qty': 1,
          'total_qty_received': 1,
          'stock_uom': index.isEven ? 'Kg' : 'Nos',
        },
    ]);
    await openReport(
      tester,
      size: const Size(390, 390),
      hideFields: [
        SuppliersByItemField.summaryItemCount,
        SuppliersByItemField.summarySupplierCount,
        SuppliersByItemField.summaryNoDirectCount,
        SuppliersByItemField.summaryStockByUom,
      ],
    );
    await tester.pumpAndSettle();
    final scroll = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!;
    for (var attempt = 0; attempt < 5; attempt++) {
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
    }
    final offset = scroll.offset;
    if (anchorRow(19).evaluate().isNotEmpty) {
      expect(
        tester.getBottomLeft(anchorRow(19)).dy,
        lessThanOrEqualTo(pinnedBottom(tester)),
      );
    }
    final footer = find.text('Total Qty Received');
    expect(footer.hitTestable(), findsOneWidget);
    final input = find.byType(TextField);
    expect(input.hitTestable(), findsOneWidget);
    await tester.enterText(input, 'ROW-2');
    await tester.pumpAndSettle();
    expect(scroll.offset, lessThan(offset));

    await tester.tap(find.byTooltip('Clear search query'));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(scroll.offset, closeTo(offset, 0.5));
    expect(footer.hitTestable(), findsOneWidget);
    expect(anchorRow(0).hitTestable(), findsNothing);
  });

  testWidgets(
    'expanding a near-bottom item reveals its suppliers listed under the item',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 24);
      addTearDown(tester.view.reset);
      api.load = () async => SuppliersByItemNode.parseRows([
        for (var index = 0; index < 30; index++) ...[
          {'node_id': 'item:ROW-$index', 'stock_uom': 'Nos'},
          if (index == 15)
            for (var supplier = 1; supplier <= 3; supplier++)
              {
                'node_id': 'supplier:S$supplier',
                'parent_id': 'item:ROW-15',
                'supplier': 'Supplier $supplier',
              },
        ],
      ]);
      const height = 640.0;
      await openReport(tester, size: const Size(390, height));
      await tester.pumpAndSettle();
      final scroll = await scrollIntoRow(tester, 15, 0);
      final branch = anchorRow(15);
      scroll.jumpTo(
        scroll.offset + tester.getBottomLeft(branch).dy - height + 26,
      );
      await tester.pumpAndSettle();
      final before = scroll.offset;
      final itemTop = tester.getTopLeft(branch).dy;

      await tester.tap(find.text('ROW-15'));
      await tester.pumpAndSettle();
      await tester.pump();

      final lastSupplier = rowWith('Supplier 3');
      final usableBottom = height - 24;
      expect(scroll.offset, greaterThan(before));
      expect(
        tester.getTopLeft(branch).dy,
        greaterThanOrEqualTo(pinnedBottom(tester) - 0.5),
      );
      expect(tester.getTopLeft(branch).dy, lessThan(itemTop));
      for (var supplier = 1; supplier <= 3; supplier++) {
        expect(find.text('Supplier $supplier').hitTestable(), findsOneWidget);
      }
      expect(tester.getBottomLeft(lastSupplier).dy, closeTo(usableBottom, 0.5));
    },
  );

  testWidgets(
    'promoted variant retains its supplier and protected template context',
    (tester) async {
      final database = _useFieldPreferences('buyer');
      const key = 'suppliers_by_item_fields::https%3A%2F%2Ferp.example::buyer';
      const saved = '{"itemTemplateContext":false}';
      database.records[key] = saved;
      api.load = () async => SuppliersByItemNode.parseRows([
        {'node_id': 'template:MIX', 'template': 'MIX'},
        {
          'node_id': 'item:2002506',
          'parent_id': 'template:MIX',
          'item_code': '2002506',
        },
        {
          'node_id': 'supplier:2002506:EDGE',
          'parent_id': 'item:2002506',
          'supplier': 'EDGE',
        },
      ]);
      await openReport(tester);
      await tester.pumpAndSettle();
      expect(reportRow('template:MIX'), findsNothing);
      final item = reportRow('item:2002506');
      final supplier = reportRow('supplier:2002506:EDGE');
      expect(item.hitTestable(), findsOneWidget);
      expect(supplier.hitTestable(), findsOneWidget);
      expect(within(item, 'Variant Of MIX'), findsOneWidget);

      await tester.tap(find.byTooltip('Fields'));
      await tester.pumpAndSettle();
      final sheet = find.byType(DraggableScrollableSheet);
      final tiles = _configuredFieldsTiles(
        tester,
        sheet,
      ).map((tile) => tile.key);
      expect(tiles, contains(const ValueKey(SuppliersByItemField.itemBalance)));
      expect(
        tiles,
        isNot(
          contains(const ValueKey(SuppliersByItemField.itemTemplateContext)),
        ),
      );
      Navigator.of(tester.element(sheet)).pop();
      await tester.pumpAndSettle();
      expect(database.records[key], saved);
      expect(within(item, 'Variant Of MIX'), findsOneWidget);
      expect(item, findsOneWidget);
      expect(supplier, findsOneWidget);
    },
  );

  testWidgets('ACP-25 tree omits supplier placeholders in dark mode', (
    tester,
  ) async {
    api.load = () async => SuppliersByItemNode.parseRows([
      ..._acp25Rows,
      {'node_id': 'item:GLOVES', 'item_name': 'Gloves', 'supplier_count': 1},
      {
        'node_id': 'supplier:GLOVES:LEATHER',
        'parent_id': 'item:GLOVES',
        'is_placeholder': 0,
        'supplier_name': 'Leather Shop',
        'last_rate': '',
        'currency': 'USD',
        'rate_source': 'Purchase Order',
        'rate_date': '2026-11-01',
      },
    ]);
    await openReport(
      tester,
      size: const Size(540, 800),
      themeMode: ThemeMode.dark,
      showFields: [
        SuppliersByItemField.supplierPartNumber,
        SuppliersByItemField.supplierSources,
        SuppliersByItemField.supplierQtyReceived,
        SuppliersByItemField.supplierLastPo,
        SuppliersByItemField.supplierRate,
        SuppliersByItemField.supplierRateSource,
        SuppliersByItemField.supplierRateDate,
      ],
    );
    await tester.pumpAndSettle();

    expect(within(rowWith('ACP-25'), 'Supplier Count 1'), findsOneWidget);
    expect(within(rowWith('ACP-25'), 'Balance Qty 12.5 Nos'), findsOneWidget);

    final itemWithoutSupplier = rowWith('2002492');
    final noSupplier = find.descendant(
      of: itemWithoutSupplier,
      matching: find.text('No supplier recorded'),
    );
    expect(noSupplier, findsOneWidget);
    expect(within(itemWithoutSupplier, '0 Nos'), findsOneWidget);
    expect(
      find.descendant(of: itemWithoutSupplier, matching: find.byType(InkWell)),
      findsNothing,
    );
    expect(reportRow('none:7:2002492'), findsNothing);
    expect(find.text('KANG KAI'), findsNothing);
    expect(within(rowWith('2002506'), '12.5 Nos'), findsOneWidget);

    final (background, expectedInk) = StatusPill.colourForStatus(
      'Disabled',
      brightness: Brightness.dark,
    );
    final ink = tester.widget<Text>(noSupplier).style!.color!;
    expect(ink, expectedInk);
    final foreground = Color.alphaBlend(ink, background);
    final lighter = foreground.computeLuminance();
    final darker = background.computeLuminance();
    expect((lighter + 0.05) / (darker + 0.05), greaterThanOrEqualTo(4.5));

    await tester.tap(find.text('2002506'));
    await tester.pumpAndSettle();
    final supplier = rowWith('KANG KAI');
    expect(supplier, findsOneWidget);
    expect(within(supplier, 'Sources'), findsNothing);
    await tester.tap(find.text('KANG KAI'));
    await tester.pumpAndSettle();
    for (final detail in [
      '1234-B',
      'Purchase Order, Batch',
      '0\u00a0Nos',
      'AED 0.00',
      'Purchase Order',
    ]) {
      expect(
        find.descendant(of: supplier, matching: find.text(detail)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(of: supplier, matching: find.text('2026-11-05')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(
        of: supplier,
        matching: find.textContaining('Balance Qty'),
      ),
      findsNothing,
    );

    await tester.tap(find.text('ACP-25'));
    await tester.pumpAndSettle();
    expect(find.text('KANG KAI'), findsNothing);
    expect(find.text('2002506'), findsNothing);

    await tester.tap(find.text('GLOVES'));
    await tester.pumpAndSettle();
    expect(find.text('Leather Shop'), findsOneWidget);
    expect(find.text('Rate'), findsNothing);
    expect(find.textContaining('Purchase Order'), findsNothing);
    expect(find.textContaining('USD'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'aligns Balance Qty and Supplier Count columns beside variant codes',
    (tester) async {
      api.load = () async => SuppliersByItemNode.parseRows([
        {
          'node_id': 'template:ALS',
          'item_name': 'Automatic watches',
          'tree_label': 'Automatic watches',
        },
        for (final (code, name) in [
          ('2002906', 'AUTO'),
          ('2002907', 'AUTO'),
          ('SAME', 'SAME'),
          ('BLANK', '  '),
          ('DASH', '-'),
        ])
          {
            'node_id': 'item:$code',
            'parent_id': 'template:ALS',
            'item_name': name,
            'tree_label': name,
            'balance_qty': code == '2002906' ? 2186 : 256,
            'stock_uom': 'Nos',
          },
      ]);
      await openReport(
        tester,
        filters: const SuppliersByItemFilters(variantOf: ['ALS']),
        size: const Size(540, 880),
      );
      await tester.pumpAndSettle();

      final template = rowWith('ALS');
      final templateName = find.descendant(
        of: template,
        matching: find.text('Automatic watches'),
      );
      expect(templateName, findsOneWidget);
      expect(
        tester.getTopLeft(templateName).dy,
        greaterThan(tester.getTopLeft(find.text('ALS')).dy),
      );
      final first = rowWith('2002906');
      final second = rowWith('2002907');
      final onHandCaption = within(first, 'Balance Qty');
      final supplierCaption = within(first, 'Supplier Count');
      expect(onHandCaption, findsOneWidget);
      expect(supplierCaption, findsOneWidget);
      expect(within(second, 'Balance Qty'), findsNothing);
      final firstStock = within(first, '2,186 Nos');
      final secondStock = within(second, '256 Nos');
      expect(
        tester.getTopLeft(firstStock).dy,
        closeTo(tester.getTopLeft(find.text('2002906')).dy, 3),
      );
      expect(
        tester.getTopRight(firstStock).dx,
        tester.getTopRight(secondStock).dx,
      );
      expect(
        tester.getTopRight(firstStock).dx,
        tester.getTopRight(onHandCaption).dx,
      );
      expect(
        tester.getTopRight(within(first, '0')).dx,
        tester.getTopRight(supplierCaption).dx,
      );
      expect(tester.widget<Text>(firstStock).style?.fontFeatures, isNotEmpty);

      for (final code in ['2002906', '2002907']) {
        final tile = rowWith(code);
        final name = find.descendant(of: tile, matching: find.text('AUTO'));
        expect(name, findsOneWidget);
        expect(
          tester.getTopLeft(name).dy,
          greaterThan(tester.getTopLeft(find.text(code)).dy),
        );
      }
      for (final code in ['SAME', 'BLANK', 'DASH']) {
        final tile = rowWith(code);
        expect(within(tile, code), findsOneWidget);
        expect(within(tile, 'No supplier recorded'), findsOneWidget);
        expect(
          find.descendant(of: tile, matching: find.text(' ')),
          findsNothing,
        );
      }
    },
  );

  testWidgets('standalone siblings share exact columns and reflow together', (
    tester,
  ) async {
    const quantity = '1,234,567 Pallets of 24 Items';
    api.load = () async => SuppliersByItemNode.parseRows([
      {'node_id': 'item:SMALL', 'balance_qty': -2, 'stock_uom': 'Nos'},
      {'node_id': 'item:MISSING', 'stock_uom': 'Nos'},
      {
        'node_id': 'item:LARGE',
        'balance_qty': 1234567,
        'stock_uom': 'Pallets of 24 Items',
      },
    ]);
    await openReport(tester, size: const Size(880, 910));
    await tester.pumpAndSettle();
    final small = rowWith('SMALL');
    final missing = rowWith('MISSING');
    final large = rowWith('LARGE');
    final caption = within(small, 'Balance Qty');
    expect(caption, findsOneWidget);
    final trailing = tester.getTopRight(caption).dx;
    for (final value in [
      within(small, '-2 Nos'),
      within(missing, '-'),
      within(large, quantity),
    ]) {
      expect(tester.getTopRight(value).dx, trailing);
    }
    expect(within(missing, 'Balance Qty'), findsNothing);
    expect(within(large, 'Balance Qty'), findsNothing);

    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.binding.setSurfaceSize(const Size(320, 910));
    await tester.pumpAndSettle();
    final scroll = reportScroll(tester);
    final scrollable = find.byWidgetPredicate(
      (widget) => widget is Scrollable && widget.controller == scroll,
    );
    for (final (code, value) in [
      ('SMALL', '-2 Nos'),
      ('LARGE', quantity),
      ('MISSING', '-'),
    ]) {
      final identity = find.text(code);
      if (identity.evaluate().isEmpty) {
        await tester.scrollUntilVisible(identity, 100, scrollable: scrollable);
        await tester.pumpAndSettle();
      }
      final metric = within(rowWith(code), 'Balance Qty $value');
      expect(metric, findsOneWidget);
      expect(
        tester.getTopLeft(metric).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.text(code)).dy),
      );
    }
    expect(caption, findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final textScale in [1.0, 1.3]) {
    testWidgets('fits long item labels on a Pixel 7 at scale $textScale', (
      tester,
    ) async {
      const viewport = Size(1080 / 2.625, 2400 / 2.625);
      const code =
          'UNBROKENITEMCODE0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      const name =
          'Long descriptive item name with enough words to wrap to several '
          'lines on the report screen when the phone text scale is increased';
      tester.view.devicePixelRatio = 2.625;
      tester.view.physicalSize = const Size(1080, 2400);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      api.load = () async => SuppliersByItemNode.parseRows([
        {
          'node_id': 'item:$code',
          'item_name': name,
          'balance_qty': 123456.5,
          'stock_uom': 'Nos',
        },
      ]);
      await openReport(
        tester,
        size: viewport,
        filters: const SuppliersByItemFilters(items: [code]),
      );
      await tester.pumpAndSettle();

      final tile = rowWith(code);
      final title = find.descendant(of: tile, matching: find.text(code));
      final description = find.descendant(of: tile, matching: find.text(name));
      for (final text in [title, description]) {
        final bounds = tester.getRect(text);
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(viewport.width));
      }
      expect(
        tester.getTopLeft(description).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(title).dy),
      );
      final stock = within(tile, 'Balance Qty 123,456.5 Nos');
      expect(stock, findsOneWidget);
      if (textScale == 1.3) {
        expect(
          tester.getTopLeft(stock).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(title).dy),
        );
      }

      final chip = find.widgetWithText(FilterChipWidget, 'Items: $code');
      expect(tester.widget<FilterChipWidget>(chip).maxLabelWidth, isNull);
      final edit = within(chip, 'Items: $code');
      final delete = find.descendant(
        of: chip,
        matching: find.byIcon(Icons.close),
      );
      expect(tester.widget<Text>(edit).overflow, isNull);
      await Scrollable.ensureVisible(tester.element(edit), alignment: 0.5);
      await tester.pumpAndSettle();
      expect(edit.hitTestable(), findsOneWidget);
      await tester.tap(edit);
      await tester.pumpAndSettle();

      final selected = find.widgetWithText(InputChip, code);
      expect(selected, findsOneWidget);
      expect(tester.getSize(selected).width, lessThan(viewport.width));
      final selectedLabel = tester.widget<InputChip>(selected).label as Text;
      expect(selectedLabel.maxLines, 1);
      expect(selectedLabel.overflow, TextOverflow.ellipsis);
      Navigator.of(tester.element(selected)).pop();
      await tester.pumpAndSettle();
      final filters = find.text('Suppliers by Item Filters');
      Navigator.of(tester.element(filters)).pop();
      await tester.pumpAndSettle();
      await tester.ensureVisible(delete);
      await tester.pumpAndSettle();
      expect(delete.hitTestable(), findsOneWidget);
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(api.requests.last.items, isEmpty);
      expect(chip, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('emphasizes the matched supplier and shows the other supplier', (
    tester,
  ) async {
    api.load = () async => SuppliersByItemNode.parseRows([
      {
        ..._acp25Rows[3],
        'parent_id': null,
        'supplier_count': 2,
        'balance_qty': 4,
      },
      {..._acp25Rows[4], 'matched_supplier': 1},
      {
        'node_id': 'supplier:2002506:OTHER',
        'parent_id': 'item:2002506',
        'supplier_name': 'Other Supplier',
        'matched_supplier': 0,
      },
    ]);
    await openReport(
      tester,
      filters: const SuppliersByItemFilters(
        suppliers: ['KANG KAI'],
        warehouses: ['Stores - MM'],
      ),
      themeMode: ThemeMode.dark,
    );
    await tester.pumpAndSettle();
    expect(within(rowWith('2002506'), 'Supplier Count 2'), findsOneWidget);
    expect(within(rowWith('2002506'), 'Balance Qty 4 Nos'), findsOneWidget);

    final matched = tester.widget<Text>(find.text('KANG KAI'));
    final other = tester.widget<Text>(find.text('Other Supplier'));
    expect(matched.style?.fontWeight, FontWeight.w800);
    expect(other.style?.fontWeight, FontWeight.w600);
    expect(matched.style?.color, other.style?.color);
    await currentReport().setFieldVisible(
      SuppliersByItemField.supplierMatchEmphasis,
      false,
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.text('KANG KAI')).style?.fontWeight,
      FontWeight.w600,
    );
  });

  testWidgets('Supplier count off retains the inline no-supplier message', (
    tester,
  ) async {
    api.load = () async => SuppliersByItemNode.parseRows([
      {..._acp25Rows[1], 'parent_id': null, 'indent': 0},
      {..._acp25Rows[2], 'indent': 1},
    ]);
    await openReport(
      tester,
      filters: const SuppliersByItemFilters(items: ['2002492']),
      hideFields: const [SuppliersByItemField.itemSupplierCount],
    );
    await tester.pumpAndSettle();

    final item = rowWith('2002492');
    expect(
      find.descendant(of: item, matching: find.text('No supplier recorded')),
      findsOneWidget,
    );
    expect(reportRow('none:7:2002492'), findsNothing);
  });

  testWidgets('All fields off preserves rows, suppliers, and footer totals', (
    tester,
  ) async {
    api.load = () async => SuppliersByItemNode.parseRows([
      ..._acp25Rows,
      {
        'node_id': 'supplier:2002506:OTHER',
        'parent_id': 'item:2002506',
        'supplier_name': 'Other Supplier',
      },
      {
        'node_id': 'item:STANDALONE',
        'item_name': 'Optional item name',
        'projected_qty': 20,
        'open_order_qty': 5,
        'stock_uom': 'Nos',
      },
      {
        'node_id': 'bom:PARTS',
        'parent_id': 'item:STANDALONE',
        'tree_label': 'BOM-PARTS · default · 1 component · draft',
        'bom_is_default': 1,
        'bom_status': 'Draft',
        'component_count': 1,
      },
      {
        'node_id': 'component:PARTS:PART',
        'parent_id': 'bom:PARTS',
        'item_code': 'PART',
      },
    ]);
    await openReport(
      tester,
      filters: const SuppliersByItemFilters(expandBom: true),
      size: const Size(390, 1120),
      hideFields: SuppliersByItemField.values,
    );
    await tester.pumpAndSettle();

    for (final node in [
      'item:2002492',
      'item:2002506',
      'item:STANDALONE',
      'bom:PARTS',
    ]) {
      await tester.tap(reportRow(node));
      await tester.pumpAndSettle();
    }

    for (final text in [
      'ACP-25',
      '2002492',
      '2002506',
      'STANDALONE',
      'PART',
      'BOM-PARTS',
      'KANG KAI',
      'Other Supplier',
      'End of list · Totals for all loaded items',
      'Balance Qty',
      '12.5 Nos',
      'Projected Qty',
      '20 Nos',
      'Open Order Qty',
      '5 Nos',
    ]) {
      expect(find.text(text).hitTestable(), findsOneWidget);
    }
    expect(reportRow('none:7:2002492'), findsOneWidget);
    expect(find.text('No supplier recorded'), findsNWidgets(3));
    expect(within(reportRow('bom:PARTS'), 'Default BOM'), findsNothing);
    expect(within(reportRow('bom:PARTS'), 'Draft BOM'), findsOneWidget);
    expect(within(reportRow('bom:PARTS'), '1 component'), findsNothing);
    expect(find.text('Optional item name'), findsOneWidget);
    expect(
      within(reportRow('template:ACP-25'), 'Supplier Count 1'),
      findsOneWidget,
    );
    expect(within(reportRow('item:2002506'), 'Supplier Count 1'), findsNothing);
    expect(find.text('Draft Order Qty'), findsNothing);
    expect(find.text('Total Qty Received'), findsOneWidget);
  });

  testWidgets('All fields off preserves only the affected stock unit warning', (
    tester,
  ) async {
    api.load = () async => SuppliersByItemNode.parseRows([
      {'node_id': 'item:KNOWN', 'balance_qty': 8, 'stock_uom': 'Nos'},
      {'node_id': 'item:LEGACY', 'balance_qty': 3},
    ]);
    await openReport(tester, size: const Size(390, 890));
    await tester.pumpAndSettle();
    final missing = reportRow('item:LEGACY');
    final known = reportRow('item:KNOWN');
    expect(
      within(missing, 'Balance Qty 3 (Stock UOM unavailable)'),
      findsOneWidget,
    );
    expect(within(missing, 'Stock UOM unavailable'), findsNothing);

    for (final field in SuppliersByItemField.values.where(
      (field) => field.column != null && !field.fixed,
    )) {
      await currentReport().setFieldVisible(field, false);
    }
    await tester.pumpAndSettle();
    expect(
      within(missing, 'Balance Qty 3 (Stock UOM unavailable)'),
      findsNothing,
    );
    expect(within(missing, 'Stock UOM unavailable'), findsOneWidget);
    expect(within(known, 'Stock UOM unavailable'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp(r'Item LEGACY,.*Stock UOM unavailable')),
      findsOneWidget,
    );
  });

  testWidgets(
    'A computed template supplier count survives hiding leaf counts',
    (tester) async {
      api.load = () async => SuppliersByItemNode.parseRows([
        {..._acp25Rows[0]}..remove('supplier_count'),
        for (final row in [_acp25Rows[1], _acp25Rows[3]]) ...[
          {...row, 'supplier_count': 1},
          {
            'node_id': 'supplier:${row['item_code']}:PING',
            'parent_id': row['node_id'],
            'supplier': 'PING',
          },
        ],
      ]);
      await openReport(tester, size: const Size(390, 890));
      await tester.pumpAndSettle();

      final template = reportRow('template:ACP-25');
      final leaves = ['2002492', '2002506'];
      expect(within(template, 'Supplier Count 1'), findsOneWidget);
      for (final leaf in leaves) {
        expect(
          find.bySemanticsLabel(RegExp('^Item $leaf,.*Supplier Count 1')),
          findsOneWidget,
        );
      }
      await currentReport().setFieldVisible(
        SuppliersByItemField.itemSupplierCount,
        false,
      );
      await tester.pumpAndSettle();
      expect(within(template, 'Supplier Count 1'), findsOneWidget);
      for (final leaf in leaves) {
        expect(reportRow('item:$leaf'), findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp('^Item $leaf,.*Supplier Count 1')),
          findsNothing,
        );
      }
    },
  );

  testWidgets('Rate currency and UOM depend on Supplier rate', (tester) async {
    await openReport(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Fields'));
    await tester.pumpAndSettle();

    final sheetScroll = find.descendant(
      of: find.byType(DraggableScrollableSheet),
      matching: find.byType(Scrollable),
    );
    final rate = find.byKey(const ValueKey(SuppliersByItemField.supplierRate));
    final currency = find.byKey(
      const ValueKey(SuppliersByItemField.supplierRateCurrency),
    );
    final uom = find.byKey(
      const ValueKey(SuppliersByItemField.supplierRateUom),
    );
    await tester.scrollUntilVisible(uom, 140, scrollable: sheetScroll);

    CheckboxListTile checkbox(Finder tile) =>
        tester.widget<CheckboxListTile>(tile);
    final hint = find.text('Needs Last Rate');
    expect(checkbox(rate).value, isFalse);
    for (final tile in [currency, uom]) {
      expect(checkbox(tile).value, isTrue);
      expect(checkbox(tile).onChanged, isNull);
      expect(find.descendant(of: tile, matching: hint), findsOneWidget);
    }

    await tester.ensureVisible(rate);
    await tester.tap(rate);
    await tester.pumpAndSettle();
    for (final tile in [currency, uom]) {
      expect(checkbox(tile).onChanged, isNotNull);
    }
    expect(hint, findsNothing);

    await tester.tap(currency);
    await tester.pumpAndSettle();
    await tester.tap(rate);
    await tester.pumpAndSettle();
    expect(checkbox(currency).onChanged, isNull);
    expect(checkbox(currency).value, isFalse);

    await tester.tap(rate);
    await tester.pumpAndSettle();
    expect(checkbox(currency).onChanged, isNotNull);
    expect(checkbox(currency).value, isFalse);
    expect(checkbox(uom).value, isTrue);
  });

  testWidgets('shows received quantities for templates with one stock unit', (
    tester,
  ) async {
    api.load = () async => SuppliersByItemNode.parseRows([
      {'node_id': 'template:MIXED', 'total_qty_received': 24},
      {
        'node_id': 'template:UNIFORM',
        'total_qty_received': 50,
        'stock_uom': 'Nos',
      },
    ]);
    await openReport(
      tester,
      showFields: [SuppliersByItemField.itemQtyReceived],
    );
    await tester.pumpAndSettle();

    expect(find.text('MIXED'), findsOneWidget);
    expect(find.text('Total Qty Received 24'), findsNothing);
    expect(find.text('Total Qty Received 50 Nos'), findsOneWidget);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('shows projected below reorder level in ${mode.name} mode', (
      tester,
    ) async {
      api.load = () async => SuppliersByItemNode.parseRows([
        {..._acp25Rows[0], 'projected_qty': 7, 'reorder_level': 9},
        {..._acp25Rows[1], 'projected_qty': 4, 'reorder_level': 4},
        _acp25Rows[2],
        {..._acp25Rows[3], 'projected_qty': 3, 'reorder_level': 5},
        _acp25Rows[4],
        {'node_id': 'item:LEGACY', 'reorder_level': 2},
        {'node_id': 'item:ZERO', 'projected_qty': -1, 'reorder_level': 0},
      ]);
      await openReport(
        tester,
        themeMode: mode,
        size: const Size(540, 840),
        showFields: [
          SuppliersByItemField.itemProjected,
          SuppliersByItemField.itemReorderLevel,
        ],
      );
      await tester.pumpAndSettle();
      expect(within(rowWith('ACP-25'), 'Balance Qty 12.5 Nos'), findsOneWidget);
      expect(within(rowWith('2002506'), '12.5 Nos'), findsOneWidget);
      expect(find.text('Projected Qty 7 Nos'), findsOneWidget);
      expect(find.text('Projected Qty 3 Nos'), findsOneWidget);
      expect(find.text('Reorder Level 9 Nos'), findsOneWidget);
      expect(find.text('Reorder Level 5 Nos'), findsOneWidget);
      final warnings = tester.widgetList<Text>(
        find.text('Projected Qty below Reorder Level'),
      );
      expect(warnings, hasLength(2));
      final ink = mode == ThemeMode.dark
          ? AppColors.orange300
          : AppColors.orange700;
      expect(warnings.map((text) => text.style!.color), everyElement(ink));
    });
  }

  testWidgets(
    'Last Purchase Date hides measured dates and preserves unavailable status',
    (tester) async {
      const sources =
          'Purchase Order (Draft), Batch (draft PO), '
          'Batch (cancelled PO), Batch (no PO)';
      api.load = () async => SuppliersByItemNode.parseRows([
        {..._acp25Rows[3], 'parent_id': null},
        {
          ..._acp25Rows[4],
          'supplier_status': 'On Hold (Orders) until 2027-01-01',
          'open_order_qty': 1234.5,
          'draft_order_qty': 2.5,
          'lead_time_days': 4,
          'lead_time_receipts': 3,
          'po_count': 5,
          'receipt_count': 2,
          'last_purchase_date': '2025-10-01',
          'sources': sources,
        },
        {
          'node_id': 'supplier:2002506:ACTIVE',
          'parent_id': 'item:2002506',
          'supplier_name': 'Second Supplier',
          'supplier_status': 'Active',
        },
        {
          'node_id': 'supplier:2002506:INVALID',
          'parent_id': 'item:2002506',
          'supplier_name': 'Invalid Date Supplier',
          'last_purchase_date': '2025-02-30',
        },
      ]);
      await openReport(
        tester,
        size: const Size(540, 880),
        fontFamily: reportFont,
        showFields: [
          SuppliersByItemField.supplierSources,
          SuppliersByItemField.supplierLastPurchase,
          SuppliersByItemField.supplierDraftOrders,
          SuppliersByItemField.supplierLeadTime,
          SuppliersByItemField.supplierLeadTimeReceipts,
          SuppliersByItemField.supplierPoCount,
          SuppliersByItemField.supplierReceiptCount,
        ],
      );
      await tester.pumpAndSettle();
      final supplier = rowWith('KANG KAI');
      final valid = within(supplier, 'Last Purchase Date 1 Oct 25');
      final compactNameWidth = tester.getSize(find.text('KANG KAI')).width;
      expect(valid, findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Last Purchase Date 1 October 2025')),
        findsOneWidget,
      );
      for (final identity in ['Second Supplier', 'Invalid Date Supplier']) {
        final leaf = rowWith(identity);
        final date = within(leaf, 'Last Purchase Date -');
        expect(date, findsOneWidget);
        expect(tester.getTopRight(date).dx, tester.getTopRight(valid).dx);
        final label = find.bySemanticsLabel(
          RegExp('Supplier Name $identity, Last Purchase Date unavailable'),
        );
        expect(
          tester
              .getSemantics(label)
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isFalse,
        );
        expect(
          find.descendant(of: leaf, matching: find.byIcon(Icons.expand_more)),
          findsNothing,
        );
      }
      expect(within(supplier, 'Last Purchase Date'), findsNothing);
      await tester.tap(find.text('KANG KAI'));
      await tester.pumpAndSettle();
      for (final detail in [
        'On Hold (Orders) until 2027-01-01',
        'Open Order Qty',
        '1,234.5\u00a0Nos',
        'Draft Order Qty',
        '2.5\u00a0Nos',
        'Last Purchase Date',
        '1 Oct 2025',
        'Lead Time (Days)',
        '4.0 days',
        'Lead Time Receipts',
        'PO Count',
        'Receipt Count',
        sources,
      ]) {
        expect(within(supplier, detail), findsOneWidget);
      }
      expect(within(supplier, 'Last Rate'), findsNothing);
      await currentReport().setFieldVisible(
        SuppliersByItemField.supplierLastBuyColumn,
        false,
      );
      await tester.pumpAndSettle();
      expect(valid, findsNothing);
      for (final identity in ['Second Supplier', 'Invalid Date Supplier']) {
        expect(
          within(rowWith(identity), 'Last Purchase Date -'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(
            RegExp('Supplier Name $identity, Last Purchase Date unavailable'),
          ),
          findsOneWidget,
        );
      }
      expect(within(supplier, 'Open Order Qty'), findsOneWidget);
      expect(within(supplier, 'Last Purchase Date'), findsOneWidget);
      expect(
        tester.getSize(find.text('KANG KAI')).width,
        greaterThan(compactNameWidth),
      );
    },
  );

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'PO pills use signed quantities and supplier state in ${mode.name}',
      (tester) async {
        const hold = 'On Hold (Orders) until 2027-01-01';
        api.load = () async => SuppliersByItemNode.parseRows([
          {
            'node_id': 'item:BUY',
            'open_order_qty': 4,
            'draft_order_qty': 2,
            'stock_uom': 'Nos',
          },
          for (final (code, open, draft, status) in [
            ('BOTH', 2, 3, hold),
            ('OPEN', 2, 0, 'Active'),
            ('DRAFT', -1, 1, 'Disabled'),
            ('NEGATIVE', -5, -2, null),
            ('UNKNOWN', null, null, null),
          ])
            {
              'node_id': 'supplier:BUY:$code',
              'parent_id': 'item:BUY',
              'supplier': code,
              'supplier_status': status,
              'open_order_qty': open,
              'draft_order_qty': draft,
              'stock_uom': 'Nos',
              'sources': 'Purchase Order (Draft), Cancelled PO',
              'po_count': 40,
            },
          {
            'node_id': 'bom:BUY',
            'parent_id': 'item:BUY',
            'bom_no': 'BOM-BUY',
            'bom_status': 'Draft',
          },
        ]);
        await openReport(
          tester,
          themeMode: mode,
          size: const Size(540, 900),
          filters: const SuppliersByItemFilters(expandBom: true),
        );
        await tester.pumpAndSettle();
        final both = rowWith('BOTH');
        final draft = rowWith('DRAFT');
        final open = rowWith('OPEN');
        final item = rowWith('BUY');
        final bom = rowWith('BOM-BUY');
        for (final (row, openQty, draftQty) in [(both, 2, 3), (item, 4, 2)]) {
          expect(within(row, 'Open Order Qty $openQty Nos'), findsOneWidget);
          expect(within(row, 'Draft Order Qty $draftQty Nos'), findsOneWidget);
        }
        Finder orderQty(Finder row, String label) =>
            find.descendant(of: row, matching: find.textContaining(label));
        expect(within(open, 'Open Order Qty 2 Nos'), findsOneWidget);
        expect(orderQty(open, 'Draft Order Qty'), findsNothing);
        expect(orderQty(draft, 'Open Order Qty'), findsNothing);
        expect(within(draft, 'Draft Order Qty 1 Nos'), findsOneWidget);
        for (final row in [rowWith('NEGATIVE'), rowWith('UNKNOWN'), bom]) {
          expect(orderQty(row, 'Open Order Qty'), findsNothing);
          expect(orderQty(row, 'Draft Order Qty'), findsNothing);
        }
        expect(within(bom, 'Draft BOM'), findsOneWidget);
        expect(
          find.bySemanticsLabel(
            RegExp(
              'Item / Supplier BOTH.*Supplier Status ${RegExp.escape(hold)}.*Open Order Qty 2 Nos.*Draft Order Qty 3 Nos',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(
            RegExp('Item / Supplier DRAFT.*Supplier Status Disabled'),
          ),
          findsOneWidget,
        );

        final dark = mode == ThemeMode.dark;
        for (final (row, text, ramp, ink) in [
          (
            both,
            'Open Order Qty 2 Nos',
            'Submitted',
            dark ? AppColors.blue300 : AppColors.blue700,
          ),
          (
            both,
            'Draft Order Qty 3 Nos',
            'On Hold',
            dark ? AppColors.orange300 : AppColors.orange700,
          ),
          (
            both,
            hold,
            'On Hold',
            dark ? AppColors.orange300 : AppColors.orange700,
          ),
          (
            draft,
            'Disabled',
            'Cancelled',
            dark ? AppColors.red300 : AppColors.red700,
          ),
          (
            bom,
            'Draft BOM',
            'Draft',
            dark ? AppColors.red300 : AppColors.red700,
          ),
        ]) {
          final pill = tester.widget<Text>(within(row, text));
          expect(pill.style?.color, ink);
          final (background, _) = StatusPill.colourForStatus(
            ramp,
            brightness: dark ? Brightness.dark : Brightness.light,
          );
          final luminances = [
            ink.computeLuminance(),
            background.computeLuminance(),
          ]..sort();
          expect(
            (luminances.last + 0.05) / (luminances.first + 0.05),
            greaterThanOrEqualTo(4.5),
          );
        }

        final report = currentReport();
        await report.setFieldVisible(
          SuppliersByItemField.itemOpenPoBadge,
          false,
        );
        await report.setFieldVisible(
          SuppliersByItemField.supplierDraftPoBadge,
          false,
        );
        await tester.pumpAndSettle();
        expect(orderQty(item, 'Open Order Qty'), findsNothing);
        expect(within(item, 'Draft Order Qty 2 Nos'), findsOneWidget);
        expect(within(both, 'Open Order Qty 2 Nos'), findsOneWidget);
        expect(orderQty(both, 'Draft Order Qty'), findsNothing);
        await report.setFieldVisible(
          SuppliersByItemField.itemDraftPoBadge,
          false,
        );
        await report.setFieldVisible(
          SuppliersByItemField.supplierOpenPoBadge,
          false,
        );
        await report.setFieldVisible(
          SuppliersByItemField.supplierStatus,
          false,
        );
        await tester.pumpAndSettle();
        expect(orderQty(both, 'Open Order Qty'), findsNothing);
        expect(orderQty(item, 'Draft Order Qty'), findsNothing);
        expect(within(both, hold), findsOneWidget);
        expect(within(draft, 'Disabled'), findsOneWidget);
        expect(within(bom, 'Draft BOM'), findsOneWidget);
      },
    );
  }

  for (final (count, components, boms, leadTime) in [
    (0, '0 components', '0 BOMs', '0.0 days'),
    (1, '1 component', '1 BOM', '1.0 day'),
    (2, '2 components', '2 BOMs', '2.0 days'),
  ]) {
    testWidgets('shows lead time days and independent counts for $count', (
      tester,
    ) async {
      api.load = () async => SuppliersByItemNode.parseRows([
        {'node_id': 'template:STYLE', 'supplier_count': count},
        {'node_id': 'item:KIT'},
        {
          'node_id': 'supplier:KIT:VENDOR',
          'parent_id': 'item:KIT',
          'po_count': count + 3,
          'receipt_count': count + 6,
          'lead_time_days': count,
          'lead_time_receipts': count + 9,
        },
        {
          'node_id': 'bom:kit',
          'parent_id': 'item:KIT',
          'bom_no': 'BOM-KIT',
          'component_count': count,
        },
        {
          'node_id': 'bom:usage',
          'parent_id': 'item:KIT',
          'bom_no': 'BOM-USAGE',
          'component_count': 1,
        },
        {
          'node_id': 'component:usage:PART',
          'parent_id': 'bom:usage',
          'item_code': 'PART',
          'used_in_bom_count': count,
        },
      ]);
      await openReport(
        tester,
        filters: const SuppliersByItemFilters(expandBom: true),
        size: const Size(540, 920),
        showFields: [
          SuppliersByItemField.supplierLeadTime,
          SuppliersByItemField.supplierLeadTimeReceipts,
          SuppliersByItemField.supplierPoCount,
          SuppliersByItemField.supplierReceiptCount,
          SuppliersByItemField.componentUsedInBoms,
        ],
      );
      await tester.pumpAndSettle();

      expect(within(rowWith('STYLE'), 'Supplier Count $count'), findsOneWidget);
      final supplier = reportRow('supplier:KIT:VENDOR');
      await tester.tap(supplier);
      await tester.pumpAndSettle();
      for (final (label, value) in [
        ('Lead Time (Days)', leadTime),
        ('Lead Time Receipts', '${count + 9}'),
        ('PO Count', '${count + 3}'),
        ('Receipt Count', '${count + 6}'),
      ]) {
        final caption = within(supplier, label);
        final amount = within(supplier, value);
        expect(caption, findsOneWidget);
        expect(amount, findsOneWidget);
        expect(tester.getTopLeft(amount).dy, tester.getTopLeft(caption).dy);
      }
      await currentReport().setFieldVisible(
        SuppliersByItemField.supplierLeadTime,
        false,
      );
      await tester.pumpAndSettle();
      expect(within(supplier, 'Lead Time (Days)'), findsNothing);
      expect(within(supplier, 'Lead Time Receipts'), findsOneWidget);
      expect(within(supplier, 'Receipt Count'), findsOneWidget);
      expect(within(reportRow('bom:kit'), components), findsOneWidget);

      await tester.tap(find.text('BOM-USAGE'));
      await tester.pumpAndSettle();
      expect(find.text('Used in $boms'), findsOneWidget);
    });
  }

  testWidgets('expands BOMs and keeps the item supplier rows first', (
    tester,
  ) async {
    const item = 'item:3000339';
    const bom = 'bom:12:item:3000339|BOM-3000339-001';
    const component = 'component:$bom|1|2002400';
    const missing = 'none:$component';
    const draft = 'bom:12:item:3000339|BOM-3000339-002';
    api.columns = _localizedColumns(expandBom: true);
    api.load = () async => SuppliersByItemNode.parseRows([
      {
        'row_type': 'item',
        'node_id': item,
        'item_code': '3000339',
        'supplier_count': 1,
      },
      {
        'row_type': 'supplier',
        'node_id': 'supplier:3000339:DIRECT',
        'parent_id': item,
        'item_code': '3000339',
        'supplier': 'DIRECT',
        'supplier_name': 'Item Vendor',
        'last_purchase_date': '2025-10-03',
      },
      {
        'row_type': 'bom',
        'node_id': bom,
        'parent_id': item,
        'is_component': 1,
        'bom_no': 'BOM-3000339-001',
        'bom_status': 'Submitted',
        'bom_is_default': 1,
        'component_count': 1,
      },
      {
        'row_type': 'component',
        'node_id': component,
        'parent_id': bom,
        'is_component': 1,
        'item_code': '2002400',
        'item_name': 'Component with a descriptive name',
        'bom_qty_per_unit': 2.5,
        'stock_uom': 'Nos',
        'balance_qty': 4,
        'used_in_bom_count': 3,
        'include_in_manufacturing': 0,
        'supplier_count': 0,
        'bom_cycle': 1,
      },
      {
        'row_type': 'placeholder',
        'node_id': missing,
        'parent_id': component,
        'is_component': 1,
      },
      {
        'row_type': 'bom',
        'node_id': draft,
        'parent_id': item,
        'is_component': 1,
        'bom_no': 'BOM-3000339-002',
        'bom_status': 'Draft',
        'component_count': 0,
      },
    ]);
    await openReport(
      tester,
      themeMode: ThemeMode.dark,
      size: const Size(390, 880),
      filters: const SuppliersByItemFilters(expandBom: true),
      showFields: [
        SuppliersByItemField.componentBalance,
        SuppliersByItemField.componentUsedInBoms,
      ],
    );
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();

    expect(within(rowWith('3000339'), 'Supplier Count 1'), findsOneWidget);
    final supplier = reportRow('supplier:3000339:DIRECT');
    expect(within(supplier, 'Letzter Einkauf 3 Oct 25'), findsOneWidget);
    final spokenPurchase = find.bySemanticsLabel(
      RegExp(r'^Supplier Name Item Vendor,.*Letzter Einkauf 3 October 2025'),
    );
    expect(spokenPurchase, findsOneWidget);

    final title = find.text('BOM-3000339-001');
    expect(within(reportRow(bom), 'Default BOM'), findsOneWidget);
    expect(within(reportRow(bom), '1 component'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Item Vendor')).dy,
      lessThan(tester.getTopLeft(title).dy),
    );
    expect(
      find.descendant(of: reportRow(draft), matching: find.text('Draft BOM')),
      findsOneWidget,
    );
    expect(reportRow(component), findsNothing);

    await tester.tap(title);
    await tester.pumpAndSettle();
    final componentTile = rowWith('2002400');
    for (final detail in [
      'Component with a descriptive name',
      'Stücklistenmenge 2.5 Nos per unit',
      'Available Stock 4 Nos',
      'Used in 3 BOMs',
      'Not used in manufacturing',
      'BOM cycle detected',
    ]) {
      expect(
        find.descendant(of: componentTile, matching: find.text(detail)),
        findsOneWidget,
      );
    }
    final spokenComponentBalance = find.bySemanticsLabel(
      RegExp(r'^Component 2002400,.*Available Stock 4 Nos'),
    );
    final spokenRequirement = find.bySemanticsLabel(
      RegExp(r'^Component 2002400,.*Stücklistenmenge 2\.5 Nos per unit'),
    );
    expect(spokenComponentBalance, findsOneWidget);
    expect(spokenRequirement, findsOneWidget);
    final manufacturingNote = tester.widget<Text>(
      find.text('Not used in manufacturing'),
    );
    expect(manufacturingNote.style?.color, AppScheme.dark.textMuted);
    await tester.tap(componentTile);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: reportRow(missing),
        matching: find.text('No supplier recorded'),
      ),
      findsOneWidget,
    );

    final fields = currentReport();
    await fields.setFieldVisible(SuppliersByItemField.componentBalance, false);
    await fields.setFieldVisible(
      SuppliersByItemField.componentQtyPerUnit,
      false,
    );
    await fields.setFieldVisible(
      SuppliersByItemField.supplierLastBuyColumn,
      false,
    );
    await tester.pumpAndSettle();
    expect(within(componentTile, 'Available Stock 4 Nos'), findsNothing);
    expect(
      within(componentTile, 'Stücklistenmenge 2.5 Nos per unit'),
      findsNothing,
    );
    expect(within(supplier, 'Letzter Einkauf 3 Oct 25'), findsNothing);
    expect(spokenComponentBalance, findsNothing);
    expect(spokenRequirement, findsNothing);
    expect(spokenPurchase, findsNothing);
    semantics.dispose();
    expect(
      within(componentTile, 'Component with a descriptive name'),
      findsOneWidget,
    );
    expect(within(supplier, 'Item Vendor'), findsOneWidget);

    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(reportRow(component), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('caps the visual indent across ten BOM levels on a phone', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    var parentId = 'item:3000338';
    final rows = <Map<String, Object?>>[
      {'row_type': 'item', 'node_id': parentId, 'item_code': '3000338'},
    ];
    for (var level = 1; level <= 10; level++) {
      final bomId = 'bom:$parentId|$level';
      final componentId = 'component:$bomId|1|COMPONENT-$level';
      rows.addAll([
        {
          'row_type': 'bom',
          'node_id': bomId,
          'parent_id': parentId,
          'is_component': 1,
          'bom_no': 'BOM-LONG-COMPONENT-$level',
          'bom_status': 'Draft',
          'component_count': 1,
        },
        {
          'row_type': 'component',
          'node_id': componentId,
          'parent_id': bomId,
          'is_component': 1,
          'item_code': 'COMPONENT-$level',
          'item_name': 'A component description that wraps on a narrow phone',
          'bom_qty_per_unit': 1250.5,
          'stock_uom': 'Nos',
          'balance_qty': 25000,
          'used_in_bom_count': 11,
          'include_in_manufacturing': 0,
          'bom_depth_limit': level == 10 ? 1 : 0,
        },
      ]);
      parentId = componentId;
    }
    const supplierName = 'Long supplier name that needs to wrap';
    rows.add({
      'row_type': 'supplier',
      'node_id': 'supplier:$parentId|EDGE',
      'parent_id': parentId,
      'is_component': 1,
      'supplier': 'EDGE',
      'supplier_name': supplierName,
      'supplier_status': 'On Hold (Orders) until 2027-01-01',
      'matched_supplier': 1,
      'sources': 'Purchase Order (Draft), Batch (draft PO)',
    });
    api.load = () async => SuppliersByItemNode.parseRows(rows);
    await openReport(
      tester,
      filters: const SuppliersByItemFilters(
        expandBom: true,
        suppliers: ['EDGE'],
      ),
      size: const Size(300, 620),
    );
    await tester.pumpAndSettle();

    final scrollable = find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first;
    Future<void> reveal(Finder finder) async {
      if (finder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(finder, 100, scrollable: scrollable);
      }
      await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
      await tester.pumpAndSettle();
      expect(finder.hitTestable(), findsOneWidget);
    }

    Future<void> expand(Finder finder) async {
      await reveal(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    double? cappedIndent;
    for (var level = 1; level <= 10; level++) {
      await expand(find.text('BOM-LONG-COMPONENT-$level'));
      final component = rowWith('COMPONENT-$level');
      await expand(find.text('COMPONENT-$level'));
      if (level == 2) cappedIndent = tester.getTopLeft(component).dx;
      if (level == 10) {
        expect(tester.getTopLeft(component).dx, cappedIndent);
        expect(find.text('Depth 20'), findsOneWidget);
        expect(find.text('BOM depth limit reached'), findsOneWidget);
      }
    }
    final supplier = rowWith(supplierName);
    await reveal(find.text(supplierName));
    expect(
      find.descendant(of: supplier, matching: find.text('Depth 21')),
      findsOneWidget,
    );
    expect(find.text('On Hold (Orders) until 2027-01-01'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text(supplierName)).style?.fontWeight,
      FontWeight.w800,
    );
    expect(tester.takeException(), isNull);
  });

  Future<void> showItemCard(
    WidgetTester tester,
    List<Map<String, Object?>> rows, {
    required bool isTemplate,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ItemSuppliersCard(
            key: ValueKey(rows),
            itemCode: isTemplate ? 'ACP-25' : '2002492',
            isTemplate: isTemplate,
            loadReport: () async => SuppliersByItemNode.parseRows(rows),
            onViewReport: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Item Overview shows the item or template balance and suppliers',
    (tester) async {
      final rows = [
        {..._acp25Rows[0], 'balance_qty': 1234.5},
        {..._acp25Rows[1], 'balance_qty': 0},
        ..._acp25Rows.skip(2),
      ];

      await showItemCard(tester, rows, isTemplate: true);
      expect(find.text('Balance Qty 1,234.5 Nos'), findsOneWidget);
      expect(find.text('KANG KAI'), findsOneWidget);
      expect(find.text('No supplier recorded'), findsNothing);

      await showItemCard(tester, rows.take(3).toList(), isTemplate: false);
      expect(find.text('Balance Qty 0 Nos'), findsOneWidget);
      expect(find.text('Balance Qty 1,234.5 Nos'), findsNothing);
      expect(find.text('No supplier recorded'), findsOneWidget);
      expect(find.text('KANG KAI'), findsNothing);
    },
  );

  testWidgets('Item Overview leaves mixed-UOM template balance blank', (
    tester,
  ) async {
    await showItemCard(tester, [
      {..._acp25Rows[0], 'stock_uom': null, 'balance_qty': null},
      {..._acp25Rows[1], 'balance_qty': 4},
      _acp25Rows[2],
      {..._acp25Rows[3], 'stock_uom': 'Kg', 'balance_qty': 6.5},
      _acp25Rows[4],
    ], isTemplate: true);

    expect(find.textContaining('Balance Qty'), findsNothing);
    expect(find.text('KANG KAI'), findsOneWidget);
  });

  testWidgets('refresh shows busy feedback and guards against re-entry', (
    tester,
  ) async {
    await openReport(tester);
    await tester.pumpAndSettle();

    final button = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Refresh report',
    );
    expect(find.text('No items found for these filters'), findsOneWidget);
    expect(find.text('End of list'), findsOneWidget);
    expect(tester.widget<IconButton>(button).onPressed, isNotNull);

    final result = Completer<List<SuppliersByItemNode>>();
    api.load = () => result.future;
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.widget<IconButton>(button).onPressed, isNull);
    expect(
      find.descendant(
        of: button,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(find.text('No items found for these filters'), findsNothing);

    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    expect(api.requests, hasLength(2));

    result.complete([]);
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(button).onPressed, isNotNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No items found for these filters'), findsOneWidget);
  });

  testWidgets(
    'refresh keeps the results search focused when replacing the query',
    (tester) async {
      api.load = () async => SuppliersByItemNode.parseRows([
        {'node_id': 'item:EDGE', 'item_code': 'EDGE'},
      ]);
      await openReport(tester);
      await tester.pumpAndSettle();
      final input = find.byType(TextField);
      await tester.enterText(input, 'EDGE');
      await tester.pumpAndSettle();

      final pending = Completer<List<SuppliersByItemNode>>();
      api.load = () => pending.future;
      await tester.tap(find.byTooltip('Refresh report'));
      await tester.pump();
      await tester.showKeyboard(input);
      final editor = tester.state<EditableTextState>(find.byType(EditableText));
      tester.testTextInput.enterText('');
      await tester.pump();
      expect(
        tester.state<EditableTextState>(find.byType(EditableText)),
        same(editor),
      );
      expect(editor.widget.focusNode.hasFocus, isTrue);
      tester.testTextInput.enterText('NEW');
      await tester.pump();

      pending.complete(
        SuppliersByItemNode.parseRows([
          {'node_id': 'item:NEW', 'item_code': 'NEW'},
          {'node_id': 'item:EDGE', 'item_code': 'EDGE'},
        ]),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, 'NEW');
      expect(find.text('Items 1'), findsOneWidget);
      expect(reportRow('item:NEW'), findsOneWidget);
      expect(reportRow('item:EDGE'), findsNothing);
    },
  );

  testWidgets(
    'failed refresh suspends report search and restores it on retry',
    (tester) async {
      Future<List<SuppliersByItemNode>> loadedRows() async =>
          SuppliersByItemNode.parseRows([
            {'node_id': 'item:1002890', 'item_code': '1002890'},
            {
              'node_id': 'supplier:1002890:EDGE',
              'parent_id': 'item:1002890',
              'supplier': 'EDGE',
            },
          ]);
      api.load = loadedRows;
      await openReport(
        tester,
        filters: const SuppliersByItemFilters(variantOf: ['ALS']),
      );
      await tester.pumpAndSettle();
      final input = find.byType(TextField);
      await tester.enterText(input, 'EDGE');
      await tester.pumpAndSettle();
      expect(find.text('Items 1'), findsOneWidget);
      expect(find.text('1002890'), findsOneWidget);

      final pending = Completer<List<SuppliersByItemNode>>();
      api.load = () => pending.future;
      await tester.tap(find.byTooltip('Refresh report'));
      await tester.pump();
      expect(find.textContaining(RegExp(r'^Items \d')), findsNothing);
      expect(find.text('1002890'), findsNothing);
      final chip = find.byType(FilterChipWidget);
      expect(chip, findsNothing);
      pending.completeError(StateError('unavailable'));
      await tester.pumpAndSettle();
      expect(find.text('Could not load Suppliers by Item.'), findsOneWidget);
      expect(find.text('1002890'), findsNothing);
      expect(find.textContaining(RegExp(r'^Items \d')), findsNothing);
      expect(tester.widget<TextField>(input).controller!.text, 'EDGE');
      expect(tester.widget<FilterChipWidget>(chip).onTap, isNotNull);
      expect(tester.widget<FilterChipWidget>(chip).onDeleted, isNotNull);

      await openView(tester);
      for (final label in ['Expand all', 'Collapse all']) {
        final tile = find.widgetWithText(ListTile, label);
        expect(tester.widget<ListTile>(tile).enabled, isFalse);
        expect(tester.widget<ListTile>(tile).onTap, isNull);
      }
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      api.load = loadedRows;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Items 1'), findsOneWidget);
      expect(find.text('1002890'), findsOneWidget);
      expect(reportRow('supplier:1002890:EDGE').hitTestable(), findsOneWidget);
      expect(tester.widget<TextField>(input).controller!.text, 'EDGE');
      expect(api.requests, hasLength(3));
    },
  );

  testWidgets(
    'search-forced branches retain expanded semantics without a tap',
    (tester) async {
      final semantics = tester.ensureSemantics();
      api.load = () async => SuppliersByItemNode.parseRows([
        {'node_id': 'item:1002890', 'item_code': '1002890'},
        {
          'node_id': 'supplier:1002890:EDGE',
          'parent_id': 'item:1002890',
          'supplier': 'EDGE',
        },
      ]);
      await openReport(tester);
      await tester.pumpAndSettle();
      final parent = find.bySemanticsLabel(RegExp(r'^Item 1002890'));
      expect(
        tester
            .getSemantics(parent)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );

      await tester.enterText(find.byType(TextField), 'EDGE');
      await tester.pumpAndSettle();
      final data = tester.getSemantics(parent).getSemanticsData();
      expect(data.flagsCollection.isExpanded, Tristate.isTrue);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      expect(
        find.descendant(
          of: reportRow('item:1002890'),
          matching: find.byIcon(Icons.expand_less),
        ),
        findsNothing,
      );
      expect(reportRow('supplier:1002890:EDGE').hitTestable(), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('View enables only commands that affect the projected rows', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    api.load = () async => SuppliersByItemNode.parseRows([
      {'node_id': 'item:1002890', 'item_code': '1002890'},
      {
        'node_id': 'supplier:1002890:EDGE',
        'parent_id': 'item:1002890',
        'supplier': 'EDGE',
        'sources': 'Purchase Order',
      },
      {'node_id': 'item:another', 'item_code': 'another'},
    ]);
    await openReport(
      tester,
      showFields: [SuppliersByItemField.supplierSources],
    );
    await tester.pumpAndSettle();
    Future<void> checkView({
      required bool expand,
      required bool collapse,
    }) async {
      await openView(tester);
      for (final (label, enabled) in [
        ('Expand all', expand),
        ('Collapse all', collapse),
      ]) {
        final tile = find.widgetWithText(ListTile, label);
        final data = tester.getSemantics(tile).getSemanticsData();
        expect(tester.widget<ListTile>(tile).enabled, enabled);
        expect(
          data.flagsCollection.isEnabled,
          enabled ? Tristate.isTrue : Tristate.isFalse,
        );
        expect(data.hasAction(SemanticsAction.tap), enabled);
      }
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    }

    await checkView(expand: true, collapse: false);
    await tester.enterText(find.byType(TextField), 'EDGE');
    await tester.pumpAndSettle();
    await tester.tap(within(reportRow('supplier:1002890:EDGE'), 'EDGE'));
    await tester.pumpAndSettle();
    expect(currentReport().isSupplierExpanded('supplier:1002890:EDGE'), isTrue);
    await checkView(expand: false, collapse: true);
    await tester.enterText(find.byType(TextField), 'missing item');
    await tester.pumpAndSettle();
    expect(find.text('No matches for “missing item”'), findsOneWidget);
    await checkView(expand: false, collapse: false);
    semantics.dispose();
  });

  testWidgets(
    'footer totals all six signed quantities by UOM with Fields off',
    (tester) async {
      const systemBottomPadding = 48.0;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: systemBottomPadding);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      api.load = () async => SuppliersByItemNode.parseRows([
        {
          ..._acp25Rows[0],
          'total_qty_received': 26.5,
          'projected_qty': 15,
          'reorder_qty': 50,
          'open_order_qty': 3,
          'draft_order_qty': 12.25,
        },
        {
          ..._acp25Rows[1],
          'balance_qty': -2,
          'projected_qty': 5,
          'reorder_qty': -2,
          'open_order_qty': -1,
          'draft_order_qty': 0,
          'total_qty_received': 2,
        },
        _acp25Rows[2],
        for (final code in ['ONE', 'TWO'])
          {
            'node_id': 'supplier:2002492:$code',
            'parent_id': 'item:2002492',
            'supplier': code,
            'last_rate': 870,
          },
        {
          ..._acp25Rows[3],
          'supplier_count': 2,
          'balance_qty': 5,
          'total_qty_received': 26.5,
          'projected_qty': 10,
          'reorder_qty': 3,
          'open_order_qty': 2,
          'draft_order_qty': 11,
        },
        {
          ..._acp25Rows[4],
          'last_rate': 110,
          'rate_source': 'Purchase Receipt',
          'total_qty_received': 20,
          'open_order_qty': 2,
          'draft_order_qty': 11,
          'po_count': 3,
          'receipt_count': 4,
        },
        {
          'node_id': 'supplier:7:2002506:OTHER',
          'parent_id': 'item:2002506',
          'supplier': 'OTHER',
          'last_rate': 250,
          'currency': 'AED',
          'total_qty_received': 6.5,
          'stock_uom': 'Nos',
        },
        {
          'node_id': 'item:BULK',
          'supplier_count': 1,
          'total_qty_received': 4,
          'balance_qty': 1,
          'projected_qty': -1.5,
          'reorder_qty': 6,
          'open_order_qty': 0,
          'draft_order_qty': -3,
          'stock_uom': 'Kg',
        },
        {
          'node_id': 'supplier:4:BULK:WHOLESALE',
          'parent_id': 'item:BULK',
          'total_qty_received': 4,
          'open_order_qty': 8,
          'stock_uom': 'Kg',
          'last_rate': 510,
          'currency': 'AED',
        },
        {'node_id': 'bom:BULK', 'parent_id': 'item:BULK'},
        {
          'node_id': 'component:BULK:PART',
          'parent_id': 'bom:BULK',
          'stock_uom': 'Nos',
          'balance_qty': 100,
          'reorder_qty': 500,
          'draft_order_qty': 300,
          'total_qty_received': 400,
        },
        {'node_id': 'item:LEGACY', 'balance_qty': 99},
      ]);
      const quantities = [
        SuppliersByItemField.itemBalance,
        SuppliersByItemField.itemProjected,
        SuppliersByItemField.itemOpenOrders,
        SuppliersByItemField.itemReorderQty,
        SuppliersByItemField.itemDraftOrders,
        SuppliersByItemField.itemQtyReceived,
      ];
      await openReport(
        tester,
        size: const Size(390, 330),
        showFields: quantities,
      );
      await tester.pumpAndSettle();

      final scrollView = find.byType(CustomScrollView);
      final controller = tester
          .widget<CustomScrollView>(scrollView)
          .controller!;
      final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
      expect(scrollbar.controller, same(controller));
      final footer = find.byType(SuppliersByItemFooter);
      final scrollable = find
          .descendant(of: scrollView, matching: find.byType(Scrollable))
          .first;
      Future<void> readFooter() async {
        if (footer.evaluate().isEmpty) {
          await tester.scrollUntilVisible(footer, 150, scrollable: scrollable);
        }
        controller.jumpTo(controller.position.maxScrollExtent);
        await tester.pumpAndSettle();
      }

      void expectTotals() {
        for (final (label, kg, nos) in [
          ('Balance Qty', '1 Kg', '3 Nos'),
          ('Projected Qty', '-1.5 Kg', '15 Nos'),
          ('Open Order Qty', '0 Kg', '1 Nos'),
          ('Reorder Qty', '6 Kg', '1 Nos'),
          ('Draft Order Qty', '-3 Kg', '11 Nos'),
          ('Total Qty Received', '4 Kg', '28.5 Nos'),
        ]) {
          final section = find
              .ancestor(of: within(footer, label), matching: find.byType(Row))
              .first;
          expect(within(section, kg), findsOneWidget, reason: label);
          expect(within(section, nos), findsOneWidget, reason: label);
        }
        expect(
          within(footer, 'End of list · Totals for all loaded items'),
          findsOneWidget,
        );
        expect(
          within(footer, 'Quantities without a Stock UOM are excluded'),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: footer,
            matching: find.textContaining(RegExp('AED|870|100 Nos')),
          ),
          findsNothing,
        );
      }

      await readFooter();
      expectTotals();
      final lastTotal = within(footer, '4 Kg');
      expect(
        tester.getBottomLeft(scrollView).dy -
            tester.getBottomLeft(lastTotal).dy,
        greaterThanOrEqualTo(systemBottomPadding),
      );

      final report = currentReport();
      for (final field in [
        ...quantities,
        SuppliersByItemField.itemStockUom,
        SuppliersByItemField.supplierStockUom,
        SuppliersByItemField.componentStockUom,
        SuppliersByItemField.summaryItemCount,
        SuppliersByItemField.summarySupplierCount,
        SuppliersByItemField.summaryNoDirectCount,
        SuppliersByItemField.summaryStockByUom,
      ]) {
        await report.setFieldVisible(field, false);
      }
      await tester.pumpAndSettle();
      await readFooter();
      expectTotals();

      for (final field in [...quantities, SuppliersByItemField.itemStockUom]) {
        await report.setFieldVisible(field, true);
      }
      await tester.pumpAndSettle();
      controller.jumpTo(0);
      await tester.pumpAndSettle();
      final item = reportRow('item:2002492');
      if (item.evaluate().isEmpty) {
        await tester.scrollUntilVisible(item, 110, scrollable: scrollable);
        await tester.pumpAndSettle();
      }
      expect(
        find.descendant(of: item, matching: find.textContaining('-2 Nos')),
        findsAtLeastNWidgets(1),
      );
      expect(within(item, 'Open Order Qty -1 Nos'), findsOneWidget);
      expect(within(item, 'Draft Order Qty 0 Nos'), findsOneWidget);
      await readFooter();
      expectTotals();
    },
  );

  testWidgets(
    'optimistic Fields save failure offers retry in sheet and report',
    (tester) async {
      final database = _useFieldPreferences('buyer@example.com');
      api.load = () async => SuppliersByItemNode.parseRows([
        {
          'node_id': 'item:KIT',
          'item_name': 'Travel Kit',
          'balance_qty': 3,
          'stock_uom': 'Nos',
        },
      ]);
      await openReport(tester);
      await tester.pumpAndSettle();
      final sheet = find.byType(DraggableScrollableSheet);
      final balance = find.byKey(
        const ValueKey(SuppliersByItemField.itemBalance),
      );
      final figure = within(reportRow('item:KIT'), 'Balance Qty 3 Nos');
      final report = currentReport();
      const error = "Couldn't save Fields. Your choices apply to this session.";

      Future<Completer<void>> beginSave() async {
        await tester.tap(find.byTooltip('Fields'));
        await tester.pumpAndSettle();
        final pending = Completer<void>();
        database.onSave = () => pending.future;
        await tester.ensureVisible(balance);
        await tester.tap(balance);
        await tester.pump();
        expect(within(sheet, 'Saving Fields…'), findsOneWidget);
        expect(tester.widget<CheckboxListTile>(balance).onChanged, isNull);
        return pending;
      }

      final first = await beginSave();
      expect(tester.widget<CheckboxListTile>(balance).value, isFalse);
      expect(
        report.fieldVisibility.shows(SuppliersByItemField.itemBalance),
        isFalse,
      );
      first.completeError(StateError('disk rejected write'));
      await tester.pumpAndSettle();
      expect(within(sheet, error), findsOneWidget);
      expect(within(sheet, 'Retry').hitTestable(), findsOneWidget);
      expect(
        database.records.keys.where(
          (key) => key.startsWith('suppliers_by_item_fields'),
        ),
        isEmpty,
      );

      database.onSave = null;
      await tester.tap(within(sheet, 'Retry'));
      await tester.pumpAndSettle();
      expect(within(sheet, error), findsNothing);
      expect(database.records.values, contains('{"itemBalance":false}'));
      Navigator.of(tester.element(sheet)).pop();
      await tester.pumpAndSettle();
      expect(find.text('Travel Kit'), findsOneWidget);
      expect(figure, findsNothing);

      final second = await beginSave();
      Navigator.of(tester.element(sheet)).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 380));
      second.completeError(StateError('disk rejected write after close'));
      await tester.pumpAndSettle();
      expect(find.text(error).hitTestable(), findsOneWidget);
      expect(find.text('Travel Kit'), findsOneWidget);
      expect(figure, findsOneWidget);
      database.onSave = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text(error), findsNothing);
      expect(database.records.values, contains('{}'));
      expect(api.requests, hasLength(1));
    },
  );

  testWidgets('shows a permission error and retries with the same filter', (
    tester,
  ) async {
    api.load = () async => throw const SuppliersByItemReportException(
      SuppliersByItemReportException.denied,
      permissionDenied: true,
    );
    const filters = SuppliersByItemFilters(items: ['BLUE']);
    await openReport(tester, filters: filters);
    await tester.pumpAndSettle();

    expect(find.text(SuppliersByItemReportException.denied), findsOneWidget);
    expect(find.text('No items found for these filters'), findsNothing);
    expect(api.requests.single.toJson(), {
      'items': ['BLUE'],
      'include_drafts': 1,
      'expand_bom': 0,
    });

    api.load = () async => [];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No items found for these filters'), findsOneWidget);
    expect(api.requests, [filters, filters]);
  });

  testWidgets('opens a template-only multi-select filter', (tester) async {
    await openReport(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();

    expect(find.text('From Date'), findsNothing);
    expect(find.text('To Date'), findsNothing);
    expect(
      find.text(
        'Matches suppliers linked to the item and, when BOM expansion is '
        'enabled, its components. All suppliers are shown.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Filters Balance Qty, Projected Qty, Reorder Level and Reorder Qty.',
      ),
      findsOneWidget,
    );

    final variant = find.text('Variant Of');
    expect(variant, findsOneWidget);
    final add = find.descendant(
      of: find.ancestor(of: variant, matching: find.byType(InputDecorator)),
      matching: find.text('Tap to select'),
    );
    await tester.tap(add);
    await tester.pumpAndSettle();

    await tester.tap(find.text('SHIRT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('JACKET'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run Report'));
    await tester.pumpAndSettle();

    expect(api.requests.last.toJson(), {
      'variant_of': ['SHIRT', 'JACKET'],
      'include_drafts': 1,
      'expand_bom': 0,
    });
    final chip = find.widgetWithText(
      FilterChipWidget,
      'Variant Of: 2 selected',
    );
    expect(chip, findsOneWidget);
    expect(tester.widget<FilterChipWidget>(chip).maxLabelWidth, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('draft switch defaults on and remembers the applied choice', (
    tester,
  ) async {
    await openReport(tester);
    await tester.pumpAndSettle();
    expect(api.requests.single.includeDrafts, isTrue);
    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();

    final draftSwitch = find.widgetWithText(
      SwitchListTile,
      'Include Draft Purchase Orders',
    );
    await tester.ensureVisible(draftSwitch);
    expect(tester.widget<SwitchListTile>(draftSwitch).value, isTrue);
    expect(
      find.text(
        'Suppliers that appear only on draft purchase orders are hidden when off.',
      ),
      findsOneWidget,
    );
    await tester.tap(draftSwitch);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(draftSwitch).value, isFalse);
    await tester.tap(find.text('Run Report'));
    await tester.pumpAndSettle();
    expect(api.requests.last.includeDrafts, isFalse);

    final chip = find.widgetWithText(
      FilterChipWidget,
      'Include Draft Purchase Orders: Off',
    );
    await tester.tap(find.text('Include Draft Purchase Orders: Off'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(draftSwitch).value, isFalse);
    Navigator.of(tester.element(draftSwitch)).pop();
    await tester.pumpAndSettle();

    final remove = find.descendant(
      of: chip,
      matching: find.byIcon(Icons.close),
    );
    await tester.ensureVisible(remove);
    await tester.pumpAndSettle();
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(api.requests.last.includeDrafts, isTrue);
    expect(chip, findsNothing);
  });

  testWidgets('BOM switch starts off, applies, and clears', (tester) async {
    await openReport(tester);
    await tester.pumpAndSettle();
    expect(api.requests.single.toJson()['expand_bom'], 0);
    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();

    final bomSwitch = find.widgetWithText(
      SwitchListTile,
      'Expand BOM components',
    );
    await tester.ensureVisible(bomSwitch);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(bomSwitch).value, isFalse);
    expect(
      find.text(
        'Shows what each item is made from and who supplies those components.',
      ),
      findsOneWidget,
    );
    await tester.tap(bomSwitch);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run Report'));
    await tester.pumpAndSettle();
    expect(api.requests.last.toJson()['expand_bom'], 1);

    final chip = find.widgetWithText(
      FilterChipWidget,
      'Expand BOM components: On',
    );
    await tester.tap(find.text('Expand BOM components: On'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(bomSwitch).value, isTrue);
    Navigator.of(tester.element(bomSwitch)).pop();
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(of: chip, matching: find.byIcon(Icons.close)),
    );
    await tester.pumpAndSettle();
    expect(api.requests.last.toJson()['expand_bom'], 0);
    expect(chip, findsNothing);
  });
}
