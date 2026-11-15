import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/providers/delivery_note_provider.dart';
import 'package:multimax/app/data/providers/material_request_provider.dart';
import 'package:multimax/app/data/providers/packing_slip_provider.dart';
import 'package:multimax/app/data/providers/pos_upload_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/add_filter_chip.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/material_request/material_request_controller.dart';
import 'package:multimax/app/modules/material_request/material_request_screen.dart';
import 'package:multimax/app/modules/material_request/widgets/material_request_filter_bottom_sheet.dart';
import 'package:multimax/app/modules/packing_slip/packing_slip_controller.dart';
import 'package:multimax/app/modules/packing_slip/packing_slip_screen.dart';
import 'package:multimax/app/modules/packing_slip/widgets/packing_slip_filter_bottom_sheet.dart';

// Regression: the Material Request and Packing Slip filter sheets wrote
// `activeFilters` keys (`docstatus`, `creation`) that the list screens' chips
// did not read (`status`, `transaction_date` / `posting_date`), so an applied
// Status or date filter showed no chip. Each test drives the real screen and
// sheet: apply → chip with the right label → tap chip reopens the sheet on
// that filter with the value shown → × clears it and refetches.

class _QuietMaterialRequestController extends MaterialRequestController {
  int fetches = 0;

  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> fetchMaterialRequests(
      {bool isLoadMore = false, bool clear = false}) async {
    fetches++;
    isLoading.value = false;
    hasMore.value = false;
  }

  @override
  Future<void> fetchUsers() async {}
}

class _QuietPackingSlipController extends PackingSlipController {
  int fetches = 0;

  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> fetchPackingSlips(
      {bool isLoadMore = false, bool clear = false}) async {
    fetches++;
    isLoading.value = false;
    hasMore.value = false;
  }
}

class _StubPermissionService extends PermissionService {
  final Rx<bool?> grant = Rx<bool?>(false);

  @override
  bool? hasAccess(String doctype, {String permType = 'read'}) => grant.value;
}

Finder _chip(String label) => find.widgetWithText(FilterChipWidget, label);

Finder _choice(String label) => find.widgetWithText(ChoiceChip, label);

bool _selected(WidgetTester tester, String label) =>
    tester.widget<ChoiceChip>(_choice(label)).selected;

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _apply(WidgetTester tester) =>
    _tap(tester, find.textContaining('Apply').last);

/// Closes the date range picker a date chip's tap opens over the sheet.
Future<void> _closeDatePicker(WidgetTester tester) async {
  final picker = find.byType(DateRangePickerDialog);
  expect(picker, findsOneWidget, reason: 'tapping the date chip opens the picker');
  Navigator.of(tester.element(picker)).pop();
  await tester.pumpAndSettle();
}

Future<void> _closeSheet(WidgetTester tester) async {
  Get.back();
  await tester.pumpAndSettle();
}

Future<void> _removeChip(WidgetTester tester, String label) => _tap(
    tester,
    find.descendant(of: _chip(label), matching: find.byIcon(Icons.close)));

void main() {
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
    Get.put(AuthenticationController());
    Get.put<PermissionService>(_StubPermissionService());
  });
  tearDown(Get.reset);

  group('Material Request', () {
    late _QuietMaterialRequestController ctrl;

    Future<void> pump(WidgetTester tester) async {
      Get.put(MaterialRequestProvider());
      Get.put(UserProvider());
      ctrl = Get.put<MaterialRequestController>(
          _QuietMaterialRequestController()) as _QuietMaterialRequestController;
      // onInit is skipped, so settle the loading skeleton's shimmer here.
      ctrl.isLoading.value = false;
      await tester
          .pumpWidget(const GetMaterialApp(home: MaterialRequestScreen()));
      await tester.pumpAndSettle();
    }

    testWidgets('Status: apply, chip, reopen on it, remove', (tester) async {
      await pump(tester);

      await _tap(tester, find.byType(AddFilterChip));
      expect(find.byType(MaterialRequestFilterBottomSheet), findsOneWidget);
      await _tap(tester, _choice('Submitted'));
      await _apply(tester);

      expect(ctrl.activeFilters['docstatus'], 1);
      expect(find.byType(MaterialRequestFilterBottomSheet), findsNothing);
      expect(_chip('Status: Submitted'), findsOneWidget);

      await _tap(tester, _chip('Status: Submitted'));
      expect(find.byType(MaterialRequestFilterBottomSheet), findsOneWidget);
      expect(_selected(tester, 'Submitted'), isTrue);
      await _closeSheet(tester);

      final before = ctrl.fetches;
      await _removeChip(tester, 'Status: Submitted');
      expect(ctrl.activeFilters.containsKey('docstatus'), isFalse);
      expect(ctrl.fetches, before + 1);
      expect(_chip('Status: Submitted'), findsNothing);
    });

    testWidgets('date range is on transaction_date end to end',
        (tester) async {
      await pump(tester);
      ctrl.activeFilters.value = {
        'transaction_date': [
          'between',
          ['2024-01-01', '2024-01-10']
        ],
      };
      await tester.pumpAndSettle();

      const label = '2024-01-01  →  2024-01-10';
      expect(_chip(label), findsOneWidget);

      // The chip opens the sheet straight into the range picker, and the
      // sheet shows the applied range.
      await _tap(tester, _chip(label));
      await _closeDatePicker(tester);
      expect(find.byType(MaterialRequestFilterBottomSheet), findsOneWidget);
      expect(find.text('2024-01-01 - 2024-01-10'), findsOneWidget);

      // Re-applying writes the same key back (not `creation`).
      await _apply(tester);
      expect(ctrl.activeFilters.keys, ['transaction_date']);
      expect(ctrl.activeFilters['transaction_date'], [
        'between',
        ['2024-01-01', '2024-01-10']
      ]);
      expect(_chip(label), findsOneWidget);

      final before = ctrl.fetches;
      await _removeChip(tester, label);
      expect(ctrl.activeFilters, isEmpty);
      expect(ctrl.fetches, before + 1);
      expect(_chip(label), findsNothing);
    });
  });

  group('Packing Slip', () {
    late _QuietPackingSlipController ctrl;

    Future<void> pump(WidgetTester tester) async {
      Get.put(PackingSlipProvider());
      Get.put(DeliveryNoteProvider());
      Get.put(PosUploadProvider());
      ctrl = Get.put<PackingSlipController>(_QuietPackingSlipController())
          as _QuietPackingSlipController;
      ctrl.isLoading.value = false;
      await tester.pumpWidget(const GetMaterialApp(home: PackingSlipScreen()));
      await tester.pumpAndSettle();
    }

    testWidgets('Status: apply, chip, reopen on it, remove', (tester) async {
      await pump(tester);

      await _tap(tester, find.byType(AddFilterChip));
      expect(find.byType(PackingSlipFilterBottomSheet), findsOneWidget);
      await _tap(tester, _choice('Cancelled'));
      await _apply(tester);

      expect(ctrl.activeFilters['docstatus'], 2);
      expect(_chip('Status: Cancelled'), findsOneWidget);

      // Reopening reads `docstatus` back (it used to read `status`).
      await _tap(tester, _chip('Status: Cancelled'));
      expect(find.byType(PackingSlipFilterBottomSheet), findsOneWidget);
      expect(_selected(tester, 'Cancelled'), isTrue);
      await _closeSheet(tester);

      final before = ctrl.fetches;
      await _removeChip(tester, 'Status: Cancelled');
      expect(ctrl.activeFilters.containsKey('docstatus'), isFalse);
      expect(ctrl.fetches, before + 1);
      expect(_chip('Status: Cancelled'), findsNothing);
    });

    testWidgets('a deep-linked Draft filter shows selected in the sheet',
        (tester) async {
      await pump(tester);
      ctrl.activeFilters.value = {'docstatus': 0};
      await tester.pumpAndSettle();

      await _tap(tester, _chip('Status: Draft'));
      expect(_selected(tester, 'Draft'), isTrue);
    });

    testWidgets('date range is on creation end to end', (tester) async {
      await pump(tester);
      ctrl.activeFilters.value = {
        'creation': [
          'between',
          ['2024-01-01', '2024-01-10']
        ],
      };
      await tester.pumpAndSettle();

      const label = '2024-01-01  →  2024-01-10';
      expect(_chip(label), findsOneWidget);

      await _tap(tester, _chip(label));
      await _closeDatePicker(tester);
      expect(find.byType(PackingSlipFilterBottomSheet), findsOneWidget);
      expect(find.text('2024-01-01 - 2024-01-10'), findsOneWidget);

      await _apply(tester);
      expect(ctrl.activeFilters.keys, ['creation']);
      expect(_chip(label), findsOneWidget);

      final before = ctrl.fetches;
      await _removeChip(tester, label);
      expect(ctrl.activeFilters, isEmpty);
      expect(ctrl.fetches, before + 1);
      expect(_chip(label), findsNothing);
    });
  });
}
