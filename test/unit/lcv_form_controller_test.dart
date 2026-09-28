import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/enums/save_result.dart';
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

  // ── Busy-state guards (Fix round 1, Finding 1) ──────────────────────────

  testWidgets('a mid-save edit is rejected, not half-applied', (tester) async {
    final c = await start(tester);
    c.upsertCharge(_charge());
    fake.saveGate = Completer<void>();
    final saveFuture = c.saveDocument();

    // saveDocument runs synchronously up to the gate: by now isSaving is
    // true and the in-flight payload has already been recorded.
    expect(c.isSaving.value, isTrue);
    final chargesAtRequestTime = List.of(c.charges);

    // Every mutator must reject while a save is in flight.
    c.upsertCharge(_charge());
    c.removeCharge(0);
    c.removeReceipt(c.receipts.first);
    c.setPostingDate('2020-01-01');
    c.setDistribution('Amount');
    expect(c.charges.length, chargesAtRequestTime.length);
    expect(c.receipts.length, 1);
    expect(c.postingDate.value, isNot('2020-01-01'));

    fake.saveGate!.complete();
    await saveFuture;

    // Only the original in-flight payload was ever sent.
    expect(fake.saved.length, 1);
    final savedCharges = fake.saved.single['taxes'] as List;
    expect(savedCharges.length, chargesAtRequestTime.length);
    await settle(tester);
  });

  testWidgets('save is blocked while a receipt lookup is in flight',
      (tester) async {
    final c = await start(tester);
    c.isAddingReceipt.value = true;
    await c.saveDocument();
    expect(fake.saved, isEmpty);
    c.isAddingReceipt.value = false;
    await settle(tester);
  });

  // ── Failure paths (Fix round 1, Finding 2) ──────────────────────────────

  testWidgets(
      'a version conflict marks the document stale and blocks further edits',
      (tester) async {
    final c = await start(tester);
    c.upsertCharge(_charge());
    fake.saveError = DioException(
      requestOptions: RequestOptions(path: ''),
      response: Response<dynamic>(
        requestOptions: RequestOptions(path: ''),
        statusCode: 409,
      ),
    );

    await c.saveDocument();
    expect(c.isStale.value, isTrue);
    expect(c.saveResult.value, isNot(SaveResult.success));

    final savedCountBefore = fake.saved.length;
    await c.saveDocument();
    expect(fake.saved.length, savedCountBefore);

    final receiptsCountBefore = c.receipts.length;
    await c.addReceipt('MAT-PRE-0002');
    expect(c.receipts.length, receiptsCountBefore);

    // Three stale-conflict dialogs were shown along the way (the initial
    // failure, the blocked save, the blocked addReceipt) — close them all
    // so the test ends with a clean widget tree.
    for (var i = 0; i < 3; i++) {
      Get.back();
      await tester.pump();
    }
    await settle(tester);
  });

  testWidgets('a failed (non-conflict) save keeps the draft dirty, then '
      'a retry resends the same shape', (tester) async {
    final c = await start(tester);
    await c.addReceipt('MAT-PRE-0002');
    expect(c.isDirty.value, isTrue);

    fake.saveError = DioException(
      requestOptions: RequestOptions(path: ''),
      response: Response<dynamic>(
        requestOptions: RequestOptions(path: ''),
        statusCode: 417,
        data: {'exception': 'frappe.exceptions.ValidationError: boom'},
      ),
    );
    await c.saveDocument();
    expect(c.isDirty.value, isTrue);
    expect(c.isStale.value, isFalse);
    expect(fake.saved, isEmpty);

    fake.saveError = null;
    await c.saveDocument();
    expect(fake.saved.single['items'], isEmpty);
    expect(c.isDirty.value, isFalse);
    await settle(tester);
  });

  testWidgets('removing a receipt marks items to be rebuilt', (tester) async {
    final c = await start(tester);
    await c.addReceipt('MAT-PRE-0002');
    final original =
        c.receipts.firstWhere((r) => r.receiptDocument == 'MAT-PRE-0001');
    c.removeReceipt(original);

    await c.saveDocument();
    expect(fake.saved.single['items'], isEmpty);
    await settle(tester);
  });

  testWidgets('canSubmit is false when the server denies submit permission',
      (tester) async {
    fake.submitAllowed = false;
    final c = await start(tester);
    expect(c.canSubmit, isFalse);
    await settle(tester);
  });
}
