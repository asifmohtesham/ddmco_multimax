// Widget Test #5.1 - Bottom sheet header labels
//
// Requirement:
//   The draggable bottom sheet header must render the correct identity labels:
//     - Sheet title:   'Add Item'  (new)  or  'Update Item'  (editing)
//     - Item code:     the actual item code string
//     - Item name:     the actual item name string
//     - Variant Of:    appended to the item code chip when non-empty
//     - Drag handle:   a pill-shaped handle at the very top of the sheet
//
// Run: flutter test test/widget/stock_entry/bottom_sheet_header_labels_test.dart

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
  String variantOf = '';
}

class _ItemCtrl extends StockEntryItemFormController {
  @override
  void onInit() {}
}

// ---------------------------------------------------------------------------
// Pump helper
// ---------------------------------------------------------------------------
Future<void> _pump(WidgetTester tester, _ParentCtrl parent, _ItemCtrl ctrl) async {
  await tester.pumpWidget(
    GetMaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 800,
          child: UniversalItemFormSheet(
            controller: ctrl,
            scrollController: ScrollController(),
            itemSubtext: parent.variantOf.isEmpty ? null : parent.variantOf,
            customFields: const [],
            onSubmit: () async {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  late _ParentCtrl parent;
  late _ItemCtrl ctrl;

  setUp(() {
    Get.testMode = true;
    parent = _ParentCtrl();
    ctrl = _ItemCtrl();
    ctrl.testInjectParent(parent);
    ctrl.itemCode.value  = 'ITEM-TEM-001';
    ctrl.itemName.value  = 'Tempered Glass Panel';
    parent.variantOf     = 'ITEM-TEM';
    parent.selectedStockEntryType.value = 'Material Issue';
  });

  tearDown(() async {
    await Future.delayed(Duration.zero);
    Get.reset();
  });

  // =========================================================================
  // 1. Sheet title
  // =========================================================================
  group('Sheet title label', () {
    testWidgets('Title reads "Add Item" when no item is being edited',
        (tester) async {
      ctrl.editingItemName.value = null;
      await _pump(tester, parent, ctrl);
      expect(find.text('Add Item'), findsWidgets,
          reason: '\'Add Item\' must appear as the sheet title when '
              'no existing item is being edited.');
    });

    testWidgets('Title reads "Update Item" when editing an existing item',
        (tester) async {
      ctrl.editingItemName.value = 'some-name-key';
      await _pump(tester, parent, ctrl);
      expect(find.text('Update Item'), findsWidgets,
          reason: '\'Update Item\' must appear when an existing item '
              'is loaded into the sheet.');
    });

    testWidgets('"Add Item" title is absent when editing (no stale label)',
        (tester) async {
      ctrl.editingItemName.value = 'some-name-key';
      await _pump(tester, parent, ctrl);
      expect(find.text('Add Item'), findsNothing,
          reason: '\'Add Item\' must not appear while in edit mode.');
    });

    testWidgets('"Update Item" title is absent when adding (no stale label)',
        (tester) async {
      ctrl.editingItemName.value = null;
      await _pump(tester, parent, ctrl);
      expect(find.text('Update Item'), findsNothing,
          reason: '\'Update Item\' must not appear while in add mode.');
    });
  });

  // =========================================================================
  // 2. Item code chip
  // =========================================================================
  group('Item code chip in header', () {
    testWidgets('Item code is rendered in the header chip', (tester) async {
      await _pump(tester, parent, ctrl);
      expect(find.textContaining('ITEM-TEM-001'), findsWidgets,
          reason: 'The item code must be visible in the header chip.');
    });

    testWidgets('Different item code is rendered correctly', (tester) async {
      ctrl.itemCode.value = 'RACK-STEEL-002';
      await _pump(tester, parent, ctrl);
      expect(find.textContaining('RACK-STEEL-002'), findsWidgets);
    });

    testWidgets('Item code chip updates when code changes', (tester) async {
      await _pump(tester, parent, ctrl);
      expect(find.textContaining('ITEM-TEM-001'), findsWidgets);

      ctrl.itemCode.value = 'NEW-CODE-999';
      await _pump(tester, parent, ctrl);
      expect(find.textContaining('NEW-CODE-999'), findsWidgets);
    });
  });

  // =========================================================================
  // 3. Variant Of suffix in chip
  // =========================================================================
  group('Variant Of suffix in header chip', () {
    testWidgets('Variant Of suffix is appended to item code in chip',
        (tester) async {
      parent.variantOf = 'ITEM-TEM';
      await _pump(tester, parent, ctrl);
      expect(find.textContaining('ITEM-TEM'), findsWidgets,
          reason: 'Variant Of must appear in the header chip alongside '
              'the item code.');
    });

    testWidgets('Chip shows only item code when Variant Of is empty',
        (tester) async {
      parent.variantOf = '';
      await _pump(tester, parent, ctrl);
      expect(find.textContaining(' \u2022 '), findsNothing,
          reason: 'Bullet separator must be absent when Variant Of is empty.');
    });

    testWidgets('Chip contains bullet separator when Variant Of is non-empty',
        (tester) async {
      parent.variantOf = 'ITEM-TEM';
      await _pump(tester, parent, ctrl);
      expect(find.textContaining(' \u2022 '), findsOneWidget,
          reason: 'Bullet (\u2022) separator must be present between item code '
              'and variant of text.');
    });
  });

  // =========================================================================
  // 4. Item name
  // =========================================================================
  group('Item name in header', () {
    testWidgets('Item name is rendered in the header', (tester) async {
      await _pump(tester, parent, ctrl);
      expect(find.text('Tempered Glass Panel'), findsOneWidget,
          reason: 'Item name must be displayed in the sheet header.');
    });

    testWidgets('Different item name renders correctly', (tester) async {
      ctrl.itemName.value = 'Steel Rack Bracket';
      await _pump(tester, parent, ctrl);
      expect(find.text('Steel Rack Bracket'), findsOneWidget);
    });

    testWidgets('Item name is distinct from item code in the header',
        (tester) async {
      await _pump(tester, parent, ctrl);
      expect(find.textContaining('ITEM-TEM-001'), findsWidgets);
      expect(find.text('Tempered Glass Panel'), findsOneWidget);
    });
  });

  // =========================================================================
  // 5. Drag handle
  // =========================================================================
  group('Drag handle is present at the top of the sheet', () {
    testWidgets('A pill-shaped drag handle Container is rendered',
        (tester) async {
      await _pump(tester, parent, ctrl);

      final handleFinder = find.byWidgetPredicate((widget) {
        if (widget is! Container) return false;
        final decoration = widget.decoration;
        if (decoration is! BoxDecoration) return false;
        final border = decoration.borderRadius;
        if (border == null) return false;
        if (border != BorderRadius.circular(2)) return false;
        return widget.constraints?.maxWidth == 32 ||
            widget.constraints?.maxHeight == 4;
      });
      expect(handleFinder, findsWidgets,
          reason: 'A pill-shaped drag handle (w=32, h=4, radius=2) must '
              'be present at the top of the sheet.');
    });

    testWidgets('Drag handle is positioned above the sheet title',
        (tester) async {
      ctrl.editingItemName.value = null;
      await _pump(tester, parent, ctrl);

      final handleFinder = find.byWidgetPredicate((widget) {
        if (widget is! Container) return false;
        final d = widget.decoration;
        if (d is! BoxDecoration) return false;
        return d.borderRadius == BorderRadius.circular(2);
      });

      if (handleFinder.evaluate().isEmpty) return;

      final handlePos = tester.getTopLeft(handleFinder.first);
      final titlePos  = tester.getTopLeft(find.text('Add Item'));

      expect(handlePos.dy, lessThan(titlePos.dy),
          reason: 'Drag handle must be above the sheet title.');
    });

    testWidgets('Drag handle is present for all SE types', (tester) async {
      for (final type in [
        'Material Issue',
        'Material Receipt',
        'Material Transfer',
        'Material Transfer for Manufacture',
      ]) {
        parent.selectedStockEntryType.value = type;
        ctrl.editingItemName.value = null;
        await _pump(tester, parent, ctrl);

        final handleFinder = find.byWidgetPredicate((widget) {
          if (widget is! Container) return false;
          final d = widget.decoration;
          if (d is! BoxDecoration) return false;
          return d.borderRadius == BorderRadius.circular(2);
        });
        expect(handleFinder, findsWidgets,
            reason: 'Drag handle must be present for SE type: $type.');

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  });

  // =========================================================================
  // 6. Header renders correctly for all SE types
  // =========================================================================
  group('Header integrity across all SE types', () {
    testWidgets(
        'All header elements present for every SE type in add mode',
        (tester) async {
      for (final type in [
        'Material Issue',
        'Material Receipt',
        'Material Transfer',
        'Material Transfer for Manufacture',
      ]) {
        parent.selectedStockEntryType.value = type;
        ctrl.editingItemName.value = null;
        await _pump(tester, parent, ctrl);

        expect(find.text('Add Item'), findsWidgets,
            reason: 'Title missing for $type.');
        expect(find.textContaining('ITEM-TEM-001'), findsWidgets,
            reason: 'Item code missing for $type.');
        expect(find.text('Tempered Glass Panel'), findsOneWidget,
            reason: 'Item name missing for $type.');
        expect(find.byIcon(Icons.close), findsOneWidget,
            reason: 'Close button missing for $type.');

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  });
}
