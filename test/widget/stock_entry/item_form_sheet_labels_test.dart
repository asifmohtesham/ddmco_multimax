// Widget Test #4.1 - All fields have labels
//
// Requirement (from -YourRequirement-CorrectTestType.csv):
//   Every input field visible in the Stock Entry item form sheet must have
//   an explicit text label rendered above it so the user always knows what
//   they are filling in.
//
// Labels under test:
//   - 'Quantity'         (QuantityInputWidget label, always present)
//   - 'Batch No'         (buildInputGroup label, always present)
//   - 'Source Rack'      (buildInputGroup label, shown for Issue / Transfer)
//   - 'Target Rack'      (buildInputGroup label, shown for Receipt / Transfer)
//   - 'Invoice Serial No'(buildInputGroup label, shown when posUploadSerialOptions non-empty)
//
// Header identity fields are also verified:
//   - item code text is rendered
//   - item name text is rendered
//
// Run: flutter test test/widget/stock_entry/item_form_sheet_labels_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/stock_entry_item_form_sheet.dart';

// ---------------------------------------------------------------------------
// Stub controller - overrides onInit() so no provider/service wiring runs.
// We populate only the fields the sheet reads via Obx.
// ---------------------------------------------------------------------------
class _StubCtrl extends StockEntryFormController {
  @override
  void onInit() {}
}

// ---------------------------------------------------------------------------
// Helper: pump the sheet inside a bounded GetMaterialApp.
//
// scrollController is provided so the sheet follows the
// DraggableScrollableSheet/bounded path (Expanded + ListView), which is the
// production path for the Stock Entry screen.
// ---------------------------------------------------------------------------
Future<void> _pumpSheet(
  WidgetTester tester,
  _StubCtrl ctrl, {
  ScrollController? scrollController,
}) async {
  scrollController ??= ScrollController();
  await tester.pumpWidget(
    GetMaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 800,
          child: StockEntryItemFormSheet(
            controller: ctrl,
            scrollController: scrollController,
          ),
        ),
      ),
    ),
  );
  // One extra pump so Obx widgets settle after their first reactive read.
  await tester.pump();
}

// Convenience: find a Text widget whose data exactly matches [label].
Finder _label(String label) => find.text(label);

void main() {
  late _StubCtrl ctrl;

  setUp(() {
    Get.testMode = true;
    ctrl = _StubCtrl();
    // Seed the identity fields the sheet header reads.
    ctrl.currentItemCode = 'ITEM-001';
    ctrl.currentItemName = 'Test Item Name';
    ctrl.currentVariantOf = '';
  });

  tearDown(() async {
    await tester_teardown();
    Get.reset();
  });

  // =========================================================================
  // 1. Always-present labels (independent of SE type)
  // =========================================================================
  group('Always-present labels', () {
    setUp(() {
      // Material Issue has source rack; use it as the default non-trivial type.
      ctrl.selectedStockEntryType.value = 'Material Issue';
    });

    testWidgets('Quantity label is rendered', (tester) async {
      await _pumpSheet(tester, ctrl);
      expect(_label('Quantity'), findsOneWidget,
          reason: 'Qty field must always carry a "Quantity" label.');
    });

    testWidgets('Batch No label is rendered', (tester) async {
      await _pumpSheet(tester, ctrl);
      expect(_label('Batch No'), findsOneWidget,
          reason: 'Batch field must always carry a "Batch No" label.');
    });

    testWidgets('Item code is rendered in the header', (tester) async {
      await _pumpSheet(tester, ctrl);
      expect(find.textContaining('ITEM-001'), findsWidgets,
          reason: 'Item code must be visible in the sheet header.');
    });

    testWidgets('Item name is rendered in the header', (tester) async {
      await _pumpSheet(tester, ctrl);
      expect(_label('Test Item Name'), findsOneWidget,
          reason: 'Item name must be visible in the sheet header.');
    });
  });

  // =========================================================================
  // 2. Source Rack label - shown for types that require a source warehouse
  // =========================================================================
  group('Source Rack label visibility', () {
    testWidgets('Source Rack label shown for Material Issue', (tester) async {
      ctrl.selectedStockEntryType.value = 'Material Issue';
      await _pumpSheet(tester, ctrl);
      expect(_label('Source Rack'), findsOneWidget,
          reason: 'Material Issue must show a Source Rack label.');
    });

    testWidgets('Source Rack label shown for Material Transfer', (tester) async {
      ctrl.selectedStockEntryType.value = 'Material Transfer';
      await _pumpSheet(tester, ctrl);
      expect(_label('Source Rack'), findsOneWidget,
          reason: 'Material Transfer must show a Source Rack label.');
    });

    testWidgets(
        'Source Rack label shown for Material Transfer for Manufacture',
        (tester) async {
      ctrl.selectedStockEntryType.value = 'Material Transfer for Manufacture';
      await _pumpSheet(tester, ctrl);
      expect(_label('Source Rack'), findsOneWidget);
    });

    testWidgets('Source Rack label NOT shown for Material Receipt',
        (tester) async {
      ctrl.selectedStockEntryType.value = 'Material Receipt';
      await _pumpSheet(tester, ctrl);
      expect(_label('Source Rack'), findsNothing,
          reason: 'Material Receipt has no source; Source Rack must be hidden.');
    });
  });

  // =========================================================================
  // 3. Target Rack label - shown for types that require a target warehouse
  // =========================================================================
  group('Target Rack label visibility', () {
    testWidgets('Target Rack label shown for Material Receipt', (tester) async {
      ctrl.selectedStockEntryType.value = 'Material Receipt';
      await _pumpSheet(tester, ctrl);
      expect(_label('Target Rack'), findsOneWidget,
          reason: 'Material Receipt must show a Target Rack label.');
    });

    testWidgets('Target Rack label shown for Material Transfer', (tester) async {
      ctrl.selectedStockEntryType.value = 'Material Transfer';
      await _pumpSheet(tester, ctrl);
      expect(_label('Target Rack'), findsOneWidget,
          reason: 'Material Transfer must show a Target Rack label.');
    });

    testWidgets(
        'Target Rack label shown for Material Transfer for Manufacture',
        (tester) async {
      ctrl.selectedStockEntryType.value = 'Material Transfer for Manufacture';
      await _pumpSheet(tester, ctrl);
      expect(_label('Target Rack'), findsOneWidget);
    });

    testWidgets('Target Rack label NOT shown for Material Issue',
        (tester) async {
      ctrl.selectedStockEntryType.value = 'Material Issue';
      await _pumpSheet(tester, ctrl);
      expect(_label('Target Rack'), findsNothing,
          reason: 'Material Issue has no target; Target Rack must be hidden.');
    });
  });

  // =========================================================================
  // 4. Both Source Rack AND Target Rack labels present for transfer types
  // =========================================================================
  group('Both rack labels present for transfer types', () {
    testWidgets('Material Transfer shows both Source Rack and Target Rack',
        (tester) async {
      ctrl.selectedStockEntryType.value = 'Material Transfer';
      await _pumpSheet(tester, ctrl);
      expect(_label('Source Rack'), findsOneWidget);
      expect(_label('Target Rack'), findsOneWidget);
    });

    testWidgets(
        'Material Transfer for Manufacture shows both rack labels',
        (tester) async {
      ctrl.selectedStockEntryType.value = 'Material Transfer for Manufacture';
      await _pumpSheet(tester, ctrl);
      expect(_label('Source Rack'), findsOneWidget);
      expect(_label('Target Rack'), findsOneWidget);
    });
  });

  // =========================================================================
  // 5. Invoice Serial No label - conditional on posUploadSerialOptions
  // =========================================================================
  group('Invoice Serial No label visibility', () {
    testWidgets(
        'Invoice Serial No label shown when posUploadSerialOptions is non-empty',
        (tester) async {
      ctrl.selectedStockEntryType.value = 'Material Issue';
      ctrl.posUploadSerialOptions.assignAll(['1', '2', '3']);
      await _pumpSheet(tester, ctrl);
      expect(_label('Invoice Serial No'), findsOneWidget,
          reason: 'Invoice Serial No label must appear when serial '
              'options are available.');
    });

    testWidgets(
        'Invoice Serial No label NOT shown when posUploadSerialOptions is empty',
        (tester) async {
      ctrl.selectedStockEntryType.value = 'Material Issue';
      ctrl.posUploadSerialOptions.clear();
      await _pumpSheet(tester, ctrl);
      expect(_label('Invoice Serial No'), findsNothing,
          reason: 'Invoice Serial No label must be hidden when there '
              'are no serial options.');
    });
  });

  // =========================================================================
  // 6. Full-label audit per SE type
  //    One consolidated sweep per entry type to guarantee no label is missing.
  // =========================================================================
  group('Full label audit per Stock Entry type', () {
    testWidgets('Material Issue: Quantity + Batch No + Source Rack present',
        (tester) async {
      ctrl.selectedStockEntryType.value = 'Material Issue';
      await _pumpSheet(tester, ctrl);
      for (final label in ['Quantity', 'Batch No', 'Source Rack']) {
        expect(_label(label), findsOneWidget,
            reason: 'Material Issue must show "$label" label.');
      }
      expect(_label('Target Rack'), findsNothing);
    });

    testWidgets('Material Receipt: Quantity + Batch No + Target Rack present',
        (tester) async {
      ctrl.selectedStockEntryType.value = 'Material Receipt';
      await _pumpSheet(tester, ctrl);
      for (final label in ['Quantity', 'Batch No', 'Target Rack']) {
        expect(_label(label), findsOneWidget,
            reason: 'Material Receipt must show "$label" label.');
      }
      expect(_label('Source Rack'), findsNothing);
    });

    testWidgets(
        'Material Transfer: Quantity + Batch No + Source Rack + Target Rack present',
        (tester) async {
      ctrl.selectedStockEntryType.value = 'Material Transfer';
      await _pumpSheet(tester, ctrl);
      for (final label in [
        'Quantity',
        'Batch No',
        'Source Rack',
        'Target Rack',
      ]) {
        expect(_label(label), findsOneWidget,
            reason: 'Material Transfer must show "$label" label.');
      }
    });

    testWidgets(
        'Material Transfer for Manufacture: all four field labels present',
        (tester) async {
      ctrl.selectedStockEntryType.value = 'Material Transfer for Manufacture';
      await _pumpSheet(tester, ctrl);
      for (final label in [
        'Quantity',
        'Batch No',
        'Source Rack',
        'Target Rack',
      ]) {
        expect(_label(label), findsOneWidget,
            reason:
                'Material Transfer for Manufacture must show "$label" label.');
      }
    });
  });
}

// ---------------------------------------------------------------------------
// Shared async teardown helper (disposes scroll controllers etc.).
// ---------------------------------------------------------------------------
Future<void> tester_teardown() async {
  // Allow any pending timers / microtasks from GetX to complete cleanly.
  await Future.delayed(Duration.zero);
}
