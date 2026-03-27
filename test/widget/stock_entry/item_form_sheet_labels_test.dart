// Widget Test #4.1 - All fields have labels
//
// Requirement:
//   Every input field visible in the Stock Entry item form sheet must have
//   an explicit text label rendered above it.
//
// Labels under test:
//   - 'Quantity'          (always present)
//   - 'Batch No'          (always present)
//   - 'Source Rack'       (shown for Issue / Transfer types)
//   - 'Target Rack'       (shown for Receipt / Transfer types)
//   - 'Invoice Serial No' (shown when posUploadSerialOptions non-empty)
//
// Run: flutter test test/widget/stock_entry/item_form_sheet_labels_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_item_form_controller.dart';
import 'package:multimax/app/shared/item_sheet/universal_item_form_sheet.dart';

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------
class _ParentCtrl extends StockEntryFormController {
  @override
  void onInit() {}
}

class _ItemCtrl extends StockEntryItemFormController {
  @override
  void onInit() {}
}

// ---------------------------------------------------------------------------
// Rack field widgets that mirror the production SE custom fields.
// They read requiresSourceWarehouse / requiresTargetWarehouse from the parent
// to decide visibility, exactly as the real SE sheet does.
// ---------------------------------------------------------------------------
List<Widget> _seRackFields(_ParentCtrl parent, _ItemCtrl ctrl) {
  return [
    if (parent.requiresSourceWarehouse)
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Source Rack'),
          TextField(controller: ctrl.sourceRackController),
        ],
      ),
    if (parent.requiresTargetWarehouse)
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Target Rack'),
          TextField(controller: ctrl.targetRackController),
        ],
      ),
    if (parent.posUploadSerialOptions.isNotEmpty)
      const Text('Invoice Serial No'),
  ];
}

// ---------------------------------------------------------------------------
// Pump helper
// ---------------------------------------------------------------------------
Future<void> _pumpSheet(
  WidgetTester tester,
  _ParentCtrl parent,
  _ItemCtrl ctrl, {
  ScrollController? scrollController,
}) async {
  scrollController ??= ScrollController();
  await tester.pumpWidget(
    GetMaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 800,
          child: UniversalItemFormSheet(
            controller: ctrl,
            scrollController: scrollController,
            customFields: _seRackFields(parent, ctrl),
            onSubmit: () async {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder _label(String label) => find.text(label);

void main() {
  late _ParentCtrl parent;
  late _ItemCtrl ctrl;

  setUp(() {
    Get.testMode = true;
    parent = _ParentCtrl();
    ctrl   = _ItemCtrl();
    ctrl.testInjectParent(parent);
    ctrl.itemCode.value = 'ITEM-001';
    ctrl.itemName.value = 'Test Item Name';
  });

  tearDown(() async {
    await Future.delayed(Duration.zero);
    Get.reset();
  });

  // =========================================================================
  // 1. Always-present labels
  // =========================================================================
  group('Always-present labels', () {
    setUp(() {
      parent.selectedStockEntryType.value = 'Material Issue';
    });

    testWidgets('Quantity label is rendered', (tester) async {
      await _pumpSheet(tester, parent, ctrl);
      expect(_label('Quantity'), findsOneWidget,
          reason: 'Qty field must always carry a "Quantity" label.');
    });

    testWidgets('Batch No label is rendered', (tester) async {
      await _pumpSheet(tester, parent, ctrl);
      expect(_label('Batch No'), findsOneWidget,
          reason: 'Batch field must always carry a "Batch No" label.');
    });

    testWidgets('Item code is rendered in the header', (tester) async {
      await _pumpSheet(tester, parent, ctrl);
      expect(find.textContaining('ITEM-001'), findsWidgets,
          reason: 'Item code must be visible in the sheet header.');
    });

    testWidgets('Item name is rendered in the header', (tester) async {
      await _pumpSheet(tester, parent, ctrl);
      expect(_label('Test Item Name'), findsOneWidget,
          reason: 'Item name must be visible in the sheet header.');
    });
  });

  // =========================================================================
  // 2. Source Rack label
  // =========================================================================
  group('Source Rack label visibility', () {
    testWidgets('Source Rack label shown for Material Issue', (tester) async {
      parent.selectedStockEntryType.value = 'Material Issue';
      await _pumpSheet(tester, parent, ctrl);
      expect(_label('Source Rack'), findsOneWidget);
    });

    testWidgets('Source Rack label shown for Material Transfer', (tester) async {
      parent.selectedStockEntryType.value = 'Material Transfer';
      await _pumpSheet(tester, parent, ctrl);
      expect(_label('Source Rack'), findsOneWidget);
    });

    testWidgets(
        'Source Rack label shown for Material Transfer for Manufacture',
        (tester) async {
      parent.selectedStockEntryType.value = 'Material Transfer for Manufacture';
      await _pumpSheet(tester, parent, ctrl);
      expect(_label('Source Rack'), findsOneWidget);
    });

    testWidgets('Source Rack label NOT shown for Material Receipt',
        (tester) async {
      parent.selectedStockEntryType.value = 'Material Receipt';
      await _pumpSheet(tester, parent, ctrl);
      expect(_label('Source Rack'), findsNothing,
          reason: 'Material Receipt has no source; Source Rack must be hidden.');
    });
  });

  // =========================================================================
  // 3. Target Rack label
  // =========================================================================
  group('Target Rack label visibility', () {
    testWidgets('Target Rack label shown for Material Receipt', (tester) async {
      parent.selectedStockEntryType.value = 'Material Receipt';
      await _pumpSheet(tester, parent, ctrl);
      expect(_label('Target Rack'), findsOneWidget);
    });

    testWidgets('Target Rack label shown for Material Transfer', (tester) async {
      parent.selectedStockEntryType.value = 'Material Transfer';
      await _pumpSheet(tester, parent, ctrl);
      expect(_label('Target Rack'), findsOneWidget);
    });

    testWidgets(
        'Target Rack label shown for Material Transfer for Manufacture',
        (tester) async {
      parent.selectedStockEntryType.value = 'Material Transfer for Manufacture';
      await _pumpSheet(tester, parent, ctrl);
      expect(_label('Target Rack'), findsOneWidget);
    });

    testWidgets('Target Rack label NOT shown for Material Issue',
        (tester) async {
      parent.selectedStockEntryType.value = 'Material Issue';
      await _pumpSheet(tester, parent, ctrl);
      expect(_label('Target Rack'), findsNothing,
          reason: 'Material Issue has no target; Target Rack must be hidden.');
    });
  });

  // =========================================================================
  // 4. Both rack labels for transfer types
  // =========================================================================
  group('Both rack labels present for transfer types', () {
    testWidgets('Material Transfer shows both Source Rack and Target Rack',
        (tester) async {
      parent.selectedStockEntryType.value = 'Material Transfer';
      await _pumpSheet(tester, parent, ctrl);
      expect(_label('Source Rack'), findsOneWidget);
      expect(_label('Target Rack'), findsOneWidget);
    });

    testWidgets(
        'Material Transfer for Manufacture shows both rack labels',
        (tester) async {
      parent.selectedStockEntryType.value = 'Material Transfer for Manufacture';
      await _pumpSheet(tester, parent, ctrl);
      expect(_label('Source Rack'), findsOneWidget);
      expect(_label('Target Rack'), findsOneWidget);
    });
  });

  // =========================================================================
  // 5. Invoice Serial No label
  // =========================================================================
  group('Invoice Serial No label visibility', () {
    testWidgets(
        'Invoice Serial No label shown when posUploadSerialOptions is non-empty',
        (tester) async {
      parent.selectedStockEntryType.value = 'Material Issue';
      parent.posUploadSerialOptions.assignAll(['1', '2', '3']);
      await _pumpSheet(tester, parent, ctrl);
      expect(_label('Invoice Serial No'), findsOneWidget);
    });

    testWidgets(
        'Invoice Serial No label NOT shown when posUploadSerialOptions is empty',
        (tester) async {
      parent.selectedStockEntryType.value = 'Material Issue';
      parent.posUploadSerialOptions.clear();
      await _pumpSheet(tester, parent, ctrl);
      expect(_label('Invoice Serial No'), findsNothing);
    });
  });

  // =========================================================================
  // 6. Full-label audit per SE type
  // =========================================================================
  group('Full label audit per Stock Entry type', () {
    testWidgets('Material Issue: Quantity + Batch No + Source Rack present',
        (tester) async {
      parent.selectedStockEntryType.value = 'Material Issue';
      await _pumpSheet(tester, parent, ctrl);
      for (final label in ['Quantity', 'Batch No', 'Source Rack']) {
        expect(_label(label), findsOneWidget,
            reason: 'Material Issue must show "$label" label.');
      }
      expect(_label('Target Rack'), findsNothing);
    });

    testWidgets('Material Receipt: Quantity + Batch No + Target Rack present',
        (tester) async {
      parent.selectedStockEntryType.value = 'Material Receipt';
      await _pumpSheet(tester, parent, ctrl);
      for (final label in ['Quantity', 'Batch No', 'Target Rack']) {
        expect(_label(label), findsOneWidget,
            reason: 'Material Receipt must show "$label" label.');
      }
      expect(_label('Source Rack'), findsNothing);
    });

    testWidgets(
        'Material Transfer: Quantity + Batch No + Source Rack + Target Rack present',
        (tester) async {
      parent.selectedStockEntryType.value = 'Material Transfer';
      await _pumpSheet(tester, parent, ctrl);
      for (final label in ['Quantity', 'Batch No', 'Source Rack', 'Target Rack']) {
        expect(_label(label), findsOneWidget,
            reason: 'Material Transfer must show "$label" label.');
      }
    });

    testWidgets(
        'Material Transfer for Manufacture: all four field labels present',
        (tester) async {
      parent.selectedStockEntryType.value = 'Material Transfer for Manufacture';
      await _pumpSheet(tester, parent, ctrl);
      for (final label in ['Quantity', 'Batch No', 'Source Rack', 'Target Rack']) {
        expect(_label(label), findsOneWidget,
            reason:
                'Material Transfer for Manufacture must show "$label" label.');
      }
    });
  });
}
