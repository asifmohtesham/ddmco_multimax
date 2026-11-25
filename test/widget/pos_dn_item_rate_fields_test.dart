import 'package:dio/dio.dart' as dio;
// Keep the shared Material API until the app migrates to material_ui.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_store.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_bits.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_grouping.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_controller.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/pos_dn_item_rate_screen.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_group_header.dart';
import 'package:multimax/app/modules/selling/reports/pos_dn_item_rate/widgets/pos_dn_item_rate_tile.dart';

import '../support/report_fields_test_kit.dart';

const _site = 'https://reports.example/Desk';
const _otherSite = 'https://reports.example/Other';
const _user = 'reader@example.com';
const _otherUser = 'other@example.com';

class _PosReportApi extends ApiProvider {
  int requests = 0;
  int imageRequests = 0;

  @override
  Future<dio.Response> runPosDnItemRateReport({
    List<String> posUploads = const [],
    String? fromDate,
    String? toDate,
    List<String> customers = const [],
    List<String> customerGroups = const [],
    List<String> itemGroups = const [],
    bool showMapped = false,
    bool onlyCoded = false,
  }) async {
    requests++;
    return dio.Response(
      requestOptions: dio.RequestOptions(path: '/api/method/report'),
      statusCode: 200,
      data: {
        'message': {
          'columns': [
            for (final (key, label) in const [
              ('status', 'Status'),
              ('ref_code', 'Customer Code'),
              ('item_code', 'Item Code'),
              ('item_group', 'Item Group'),
              ('dn_item', 'DN Item Name'),
              ('upload_item', 'POS Item Name'),
              ('customer', 'Customer'),
              ('customer_group', 'Customer Group'),
              ('account_manager', 'Account Manager'),
              ('upload_qty', 'Uploaded Quantity'),
              ('upload_rate', 'Uploaded Rate'),
              ('dn_qty', 'Delivered Units'),
              ('dn_name', 'DN #'),
              ('pos_upload', 'POS #'),
              ('idx', 'Invoice Serial Number'),
            ])
              {'fieldname': key, 'label': label},
          ],
          'result': const [
            {
              'status': 'Already mapped',
              'ref_code': 'CUSTOM-1',
              'item_code': 'ITEM-7',
              'item_group': 'Hardware',
              'dn_item': 'Delivered screw',
              'upload_item': 'Uploaded screw',
              'customer': 'Acme Supply',
              'customer_group': 'Retail',
              'account_manager': 'Sales contact',
              'upload_qty': 11,
              'upload_rate': 2.5,
              'dn_qty': 4,
              'dn_name': 'DN-07',
              'pos_upload': 'POS-11',
              'idx': 7,
            },
            {
              'status': 'No code',
              'upload_item': 'Unmatched screw',
              'upload_qty': 3,
              'upload_rate': 3.75,
              'pos_upload': 'POS-11',
              'idx': 8,
            },
          ],
        },
      },
    );
  }

  @override
  Future<Map<String, String>> getItemImages(List<String> itemCodes) async {
    imageRequests++;
    return const {};
  }
}

Finder _textIn(Finder parent, String text) =>
    find.descendant(of: parent, matching: find.text(text));

Finder _leaf(String itemName) =>
    find.widgetWithText(PosDnItemRateTile, itemName);

Finder _metric(Finder leaf, String label) =>
    find.descendant(of: leaf, matching: find.widgetWithText(StatCell, label));

void main() {
  late _PosReportApi api;
  late ReportFieldsTestConfig config;
  late ReportFieldsTestOwner owner;
  late ReportFieldsTestStorage storage;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => r'C:\temp\test_cookies',
        );
  });

  setUp(() {
    Get.testMode = true;
    owner = ReportFieldsTestOwner();
    config = ReportFieldsTestConfig();
    storage = ReportFieldsTestStorage();
    api = _PosReportApi();
    Get.put<ApiProvider>(api);
    Get.put<StorageService>(storage);
    Get.put<ReportOwnerSource>(owner);
    Get.put(PermissionService());
    Get.put(AuthenticationController());
  });

  tearDown(Get.reset);

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> mount(
    WidgetTester tester, {
    required bool grouped,
    String site = _site,
    String user = _user,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await Get.delete<PosDnItemRateController>();
    await Get.delete<ReportFieldsStore>();
    owner.change(site, user);
    Get.put<ReportFieldsStore>(
      ScopedReportFieldsStore(database: config, storage: storage),
    );
    final controller = Get.put(PosDnItemRateController());
    await tester.pumpWidget(
      GetMaterialApp(
        home: const PosDnItemRateScreen(),
        getPages: [
          for (final (route, title) in const [
            (AppRoutes.ITEM_FORM, 'Item destination'),
            (AppRoutes.DELIVERY_NOTE_FORM, 'Delivery destination'),
            (AppRoutes.POS_UPLOAD_FORM, 'POS destination'),
          ])
            GetPage(
              name: route,
              page: () => Scaffold(body: Text(title)),
            ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Run report').hitTestable());
    await tester.pumpAndSettle();
    if (grouped) {
      controller.setPrimaryGroup(PosDnGroupField.itemGroup);
      controller.setSecondaryGroup(PosDnGroupField.customerGroup);
      await tester.pumpAndSettle();
      for (final heading in ['Hardware', 'Retail']) {
        final header = find.widgetWithText(PosDnGroupHeader, heading);
        expect(_textIn(header, heading).hitTestable(), findsOneWidget);
      }
    }
    expect(_leaf('Uploaded screw').hitTestable(), findsOneWidget);
  }

  for (final grouped in [false, true]) {
    testWidgets(
      'POS ${grouped ? 'grouped' : 'flat'} Fields controls and links',
      (tester) async {
        phone(tester);
        await mount(tester, grouped: grouped);
        final driver = WidgetReportFieldsDriver(tester, owner);
        final mapped = _leaf('Uploaded screw');
        final unmatched = _leaf('Unmatched screw');
        const details = [
          ('item_group', 'Hardware', null),
          ('customer_group', 'Retail', null),
          ('upload_qty', 'Uploaded Quantity', '11'),
          ('upload_rate', 'Uploaded Rate', '2.50'),
          ('dn_qty', 'Delivered Units', '4'),
        ];

        void expectDetails(int hidden) {
          for (final (index, (_, caption, value)) in details.indexed) {
            final present = index >= hidden ? findsOneWidget : findsNothing;
            if (value == null) {
              expect(_textIn(mapped, caption), present);
            } else {
              expect(_metric(mapped, caption), present);
              expect(_textIn(_metric(mapped, caption), value), present);
            }
          }
        }

        expectDetails(0);
        for (final (index, (key, _, _)) in details.indexed) {
          await driver.openFields();
          await driver.setVisible(key, false);
          await driver.dismiss();
          expectDetails(index + 1);
        }
        for (final (leaf, texts) in [
          (
            mapped,
            [
              'CUSTOM-1',
              'ITEM-7',
              'Delivered screw',
              'Uploaded screw',
              'Acme Supply',
              'Already mapped',
              'DN-07',
              'POS-11 · Invoice Serial Number 7',
            ],
          ),
          (
            unmatched,
            [
              '—',
              'No code',
              'Unmatched screw',
              'POS-11 · Invoice Serial Number 8',
            ],
          ),
        ]) {
          for (final text in texts) {
            expect(_textIn(leaf, text), findsOneWidget);
          }
        }
        await driver.scrollToEnd();
        final end = find.text('End of list · 2 rows');
        expect(end.hitTestable(), findsOneWidget);
        final footer = find
            .ancestor(of: end, matching: find.byType(Column))
            .first;
        for (final (caption, value) in const [
          ('Uploaded Quantity', '14'),
          ('Delivered Units', '4'),
        ]) {
          final metric = find
              .ancestor(
                of: _textIn(footer, caption),
                matching: find.byType(Column),
              )
              .first;
          expect(_textIn(metric, value), findsOneWidget);
        }
        driver.position.jumpTo(0);
        await tester.pumpAndSettle();
        if (grouped) {
          final header = find.widgetWithText(PosDnGroupHeader, 'Hardware');
          expect(header, findsOneWidget);
          expect(
            find.widgetWithText(PosDnGroupHeader, 'Retail'),
            findsOneWidget,
          );
          expect(_textIn(header, 'Uploaded Quantity 11'), findsOneWidget);
          expect(_textIn(header, 'Delivered Units 4'), findsOneWidget);
        }
        for (final (label, destination, arguments) in const [
          ('ITEM-7', 'Item destination', {'itemCode': 'ITEM-7'}),
          ('DN-07', 'Delivery destination', {'name': 'DN-07', 'mode': 'edit'}),
          (
            'POS-11 · Invoice Serial Number 7',
            'POS destination',
            {'name': 'POS-11', 'mode': 'edit'},
          ),
        ]) {
          final link = _textIn(mapped, label);
          await tester.ensureVisible(link);
          await tester.tap(link.hitTestable());
          await tester.pumpAndSettle();
          expect(find.text(destination), findsOneWidget);
          expect(Get.arguments, arguments);
          Get.back<void>();
          await tester.pumpAndSettle();
        }
        await driver.openFields();
        await driver.reset();
        await driver.dismiss();
        expectDetails(0);
        expect(api.requests, 1);
        expect(api.imageRequests, 1);
      },
    );
  }

  testWidgets('POS grouped Fields persist and cold-reset for one owner', (
    tester,
  ) async {
    phone(tester);
    final driver = WidgetReportFieldsDriver(tester, owner);
    String configKey(String report, String site, String user) =>
        '${report}_fields::${Uri.encodeComponent(site)}::${Uri.encodeComponent(user)}';
    final target = configKey('pos_dn_item_rate', _site, _user);
    final controls = {
      configKey('pos_dn_item_rate', _site, _otherUser): '{"dn_qty":false}',
      configKey('pos_dn_item_rate', _otherSite, _user): '{"upload_rate":false}',
      configKey('job_card_summary', _site, _user): '{"operation":false}',
    };
    config.values.addAll(controls);
    final mapped = _leaf('Uploaded screw');
    final retail = _textIn(mapped, 'Retail');

    await mount(tester, grouped: true);
    expect(retail, findsOneWidget);
    await driver.openFields();
    await driver.setVisible('customer_group', false);
    await driver.dismiss();
    expect(retail, findsNothing);
    expect(config.values, {...controls, target: '{"customer_group":false}'});
    await mount(tester, grouped: true);
    expect(retail, findsNothing);
    await mount(tester, grouped: true, user: _otherUser);
    expect(retail, findsOneWidget);
    expect(_metric(mapped, 'Delivered Units'), findsNothing);
    await mount(tester, grouped: true, site: _otherSite);
    expect(retail, findsOneWidget);
    expect(_metric(mapped, 'Uploaded Rate'), findsNothing);
    await mount(tester, grouped: true);
    expect(retail, findsNothing);
    await driver.openFields();
    await driver.reset();
    await driver.dismiss();
    expect(retail, findsOneWidget);
    expect(config.values, {...controls, target: '{}'});
    await mount(tester, grouped: true);
    expect(retail, findsOneWidget);
    expect(config.values, {...controls, target: '{}'});
  });
}
