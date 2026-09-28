import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/landed_cost_voucher_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/landed_cost_voucher_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/landed_cost_voucher/form/landed_cost_voucher_form_controller.dart';

import '../helpers/fake_lcv_provider.dart';

class _StubPermissionService extends PermissionService {
  @override
  bool? hasAccess(String doctype, {String permType = 'read'}) => true;
}

LandedCostTaxesAndCharges _charge() => LandedCostTaxesAndCharges(
      description: 'Customs',
      amount: 80,
      expenseAccount: 'Customs - KA',
      exchangeRate: 1,
      baseAmount: 80,
    );

void main() {
  late FakeLcvProvider fake;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => r'C:\temp\test_cookies',
    );
  });

  setUp(() {
    Get.testMode = true;
    Get.put(ApiProvider());
    Get.put<PermissionService>(_StubPermissionService());
    fake = FakeLcvProvider(voucher: sampleLcv(docstatus: 0))
      ..receipts['MAT-PRE-0002'] = {
        'name': 'MAT-PRE-0002',
        'supplier': 'Globex',
        'posting_date': '2026-09-21',
        'grand_total': 500.0,
        'company': 'KA',
        'docstatus': 1,
      }
      ..receipts['MAT-PRE-DRAFT'] = {
        'name': 'MAT-PRE-DRAFT',
        'company': 'KA',
        'docstatus': 0,
      };
    Get.put<LandedCostVoucherProvider>(fake);
  });
  tearDown(Get.reset);

  /// Controllers show snackbars, which need an overlay; host them in an app.
  Future<LandedCostVoucherFormController> start(
    WidgetTester tester, {
    String name = 'MAT-LCV-2026-00001',
    String mode = 'edit',
  }) async {
    await tester.pumpWidget(
        const GetMaterialApp(home: Scaffold(body: SizedBox())));
    final c = Get.put(LandedCostVoucherFormController(
        name: name, mode: mode, defaultCompany: 'KA'));
    await tester.pumpAndSettle();
    return c;
  }

  /// Let snackbar timers run out so the test ends with none pending.
  Future<void> settle(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 5));

  testWidgets('loads a draft as editable and clean', (tester) async {
    final c = await start(tester);
    expect(c.isEditable, isTrue);
    expect(c.isDirty.value, isFalse);
    expect(c.receipts.single.receiptDocument, 'MAT-PRE-0001');
    expect(c.canSubmit, isTrue);
    await settle(tester);
  });

  testWidgets('adding a receipt fills its details and makes items rebuild',
      (tester) async {
    final c = await start(tester);
    await c.addReceipt('MAT-PRE-0002');
    expect(c.receipts.last.supplier, 'Globex');
    expect(c.receipts.last.grandTotal, 500.0);
    expect(c.isDirty.value, isTrue);
    expect(c.canSubmit, isFalse);

    await c.saveDocument();
    expect(fake.saved.single['items'], isEmpty);
    expect(fake.saved.single['modified'], '2026-09-26 10:00:00.000');
    expect(c.isDirty.value, isFalse);
    await settle(tester);
  });

  testWidgets('a draft receipt is rejected and nothing is added',
      (tester) async {
    final c = await start(tester);
    await c.addReceipt('MAT-PRE-DRAFT');
    expect(c.receipts.length, 1);
    expect(c.isDirty.value, isFalse);
    await settle(tester);
  });

  testWidgets('a charge-only edit keeps the existing item rows',
      (tester) async {
    final c = await start(tester);
    c.upsertCharge(_charge());
    await c.saveDocument();
    final items = fake.saved.single['items'] as List;
    expect(items.single['name'], 'row-item-1');
    expect((fake.saved.single['taxes'] as List).length, 2);
    await settle(tester);
  });

  testWidgets('a double-tapped save sends one request', (tester) async {
    final c = await start(tester);
    c.upsertCharge(_charge());
    fake.saveGate = Completer<void>();
    final first = c.saveDocument();
    final second = c.saveDocument();
    fake.saveGate!.complete();
    await Future.wait([first, second]);
    expect(fake.saved.length, 1);
    await settle(tester);
  });

  testWidgets('a new voucher is created, then becomes an edit',
      (tester) async {
    final c = await start(tester, name: '', mode: 'new');
    expect(c.company, 'KA');
    expect(c.isEditable, isTrue);
    await c.addReceipt('MAT-PRE-0002');
    c.upsertCharge(_charge());
    await c.saveDocument();
    expect(fake.saved.single.containsKey('modified'), isFalse);
    expect(c.name, 'MAT-LCV-2026-00002');
    expect(c.isNew, isFalse);
    await settle(tester);
  });

  testWidgets('save is blocked until the voucher is complete',
      (tester) async {
    final c = await start(tester, name: '', mode: 'new');
    c.upsertCharge(_charge());
    await c.saveDocument();
    expect(fake.saved, isEmpty);
    await settle(tester);
  });

  testWidgets('submit runs once and leaves the voucher read-only',
      (tester) async {
    final c = await start(tester);
    await Future.wait([c.performSubmit(), c.performSubmit()]);
    expect(fake.submitCalls, 1);
    expect(c.voucher.value!.docstatus, 1);
    expect(c.isEditable, isFalse);
    await settle(tester);
  });

  testWidgets('a manually distributed draft is read-only', (tester) async {
    fake.voucher = sampleLcv(docstatus: 0, distribute: 'Distribute Manually');
    final c = await start(tester);
    expect(c.isEditable, isFalse);
    await c.addReceipt('MAT-PRE-0002');
    expect(c.receipts.length, 1);
    await settle(tester);
  });
}
