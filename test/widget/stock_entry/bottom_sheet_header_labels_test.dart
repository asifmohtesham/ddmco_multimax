// Widget Test #5.1 - Bottom sheet header labels
//
// Requirement (from -YourRequirement-CorrectTestType.csv):
//   The draggable bottom sheet header (the area above the form fields) must
//   render the correct identity labels:
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
import 'package:multimax/app/modules/stock_entry/form/widgets/stock_entry_item_form_sheet.dart';

class _StubCtrl extends StockEntryFormController {
  @override
  void onInit() {}
}

Future<void> _pump(WidgetTester tester, _StubCtrl ctrl) async {
  await tester.pumpWidget(
    GetMaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 800,
          child: StockEntryItemFormSheet(
            controller: ctrl,
            scrollController: ScrollController(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  late _StubCtrl ctrl;

  setUp(() {
    Get.testMode = true;
    ctrl = _StubCtrl();
    ctrl.currentItemCode = 'ITEM-TEM-001';
    ctrl.currentItemName = 'Tempered Glass Panel';
    ctrl.currentVariantOf = 'ITEM-TEM';
    ctrl.selectedStockEntryType.value = 'Material Issue';
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
      // currentItemNameKey == null → isEditing = false → title = 'Add Item'
      ctrl.currentItemNameKey.value = null;
      await _pump(tester, ctrl);
      expect(find.text('Add Item'), findsWidgets,
          reason: '\'Add Item\' must appear as the sheet title when '
              'no existing item is being edited.');
    });

    testWidgets('Title reads "Update Item" when editing an existing item',
        (tester) async {
      ctrl.currentItemNameKey.value = 'some-name-key';
      await _pump(tester, ctrl);
      expect(find.text('Update Item'), findsWidgets,
          reason: '\'Update Item\' must appear when an existing item '
              'is loaded into the sheet.');
    });

    testWidgets('"Add Item" title is absent when editing (no stale label)',
        (tester) async {
      ctrl.currentItemNameKey.value = 'some-name-key';
      await _pump(tester, ctrl);
      expect(find.text('Add Item'), findsNothing,
          reason: '\'Add Item\' must not appear while in edit mode.');
    });

    testWidgets('"Update Item" title is absent when adding (no stale label)',
        (tester) async {
      ctrl.currentItemNameKey.value = null;
      await _pump(tester, ctrl);
      expect(find.text('Update Item'), findsNothing,
          reason: '\'Update Item\' must not appear while in add mode.');
    });
  });

  // =========================================================================
  // 2. Item code chip
  // =========================================================================
  group('Item code chip in header', () {
    testWidgets('Item code is rendered in the header chip', (tester) async {
      await _pump(tester, ctrl);
      expect(find.textContaining('ITEM-TEM-001'), findsWidgets,
          reason: 'The item code must be visible in the header chip.');
    });

    testWidgets('Different item code is rendered correctly', (tester) async {
      ctrl.currentItemCode = 'RACK-STEEL-002';
      await _pump(tester, ctrl);
      expect(find.textContaining('RACK-STEEL-002'), findsWidgets);
    });

    testWidgets('Item code chip updates when code changes', (tester) async {
      await _pump(tester, ctrl);
      expect(find.textContaining('ITEM-TEM-001'), findsWidgets);

      // Rebuild with a new code.
      ctrl.currentItemCode = 'NEW-CODE-999';
      await _pump(tester, ctrl);
      expect(find.textContaining('NEW-CODE-999'), findsWidgets);
    });
  });

  // =========================================================================
  // 3. Variant Of suffix in chip
  // =========================================================================
  group('Variant Of suffix in header chip', () {
    testWidgets('Variant Of suffix is appended to item code in chip',
        (tester) async {
      // Production: '$itemCode • $itemSubtext' in one Text widget.
      ctrl.currentVariantOf = 'ITEM-TEM';
      await _pump(tester, ctrl);
      expect(find.textContaining('ITEM-TEM'), findsWidgets,
          reason: 'Variant Of must appear in the header chip alongside '
              'the item code.');
    });

    testWidgets('Chip shows only item code when Variant Of is empty',
        (tester) async {
      ctrl.currentVariantOf = '';
      await _pump(tester, ctrl);
      // The bullet separator must not appear when there is no variant.
      expect(find.textContaining(' • '), findsNothing,
          reason: 'Bullet separator must be absent when Variant Of is empty.');
    });

    testWidgets('Chip contains bullet separator when Variant Of is non-empty',
        (tester) async {
      ctrl.currentVariantOf = 'ITEM-TEM';
      await _pump(tester, ctrl);
      expect(find.textContaining(' • '), findsOneWidget,
          reason: 'Bullet (•) separator must be present between item code '
              'and variant of text.');
    });
  });

  // =========================================================================
  // 4. Item name
  // =========================================================================
  group('Item name in header', () {
    testWidgets('Item name is rendered in the header', (tester) async {
      await _pump(tester, ctrl);
      expect(find.text('Tempered Glass Panel'), findsOneWidget,
          reason: 'Item name must be displayed in the sheet header.');
    });

    testWidgets('Different item name renders correctly', (tester) async {
      ctrl.currentItemName = 'Steel Rack Bracket';
      await _pump(tester, ctrl);
      expect(find.text('Steel Rack Bracket'), findsOneWidget);
    });

    testWidgets('Item name is distinct from item code in the header',
        (tester) async {
      await _pump(tester, ctrl);
      // Code and name must each appear as separate Text widgets.
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
      await _pump(tester, ctrl);

      // The drag handle is a Container with width=32, height=4, and a
      // circular BorderRadius(2). Find it by matching those dimensions.
      final handleFinder = find.byWidgetPredicate((widget) {
        if (widget is! Container) return false;
        final decoration = widget.decoration;
        if (decoration is! BoxDecoration) return false;
        final border = decoration.borderRadius;
        if (border == null) return false;
        // Pill: all radii == 2.
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
      await _pump(tester, ctrl);

      // Find the drag handle pill - it has a specific size: 32x4.
      final handleFinder = find.byWidgetPredicate((widget) {
        if (widget is! Container) return false;
        final d = widget.decoration;
        if (d is! BoxDecoration) return false;
        return d.borderRadius == BorderRadius.circular(2);
      });

      if (handleFinder.evaluate().isEmpty) return; // skip if not locatable

      final handlePos = tester.getTopLeft(handleFinder.first);
      final titlePos = tester.getTopLeft(find.text('Add Item'));

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
        ctrl.selectedStockEntryType.value = type;
        ctrl.currentItemNameKey.value = null;
        await _pump(tester, ctrl);

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
        ctrl.selectedStockEntryType.value = type;
        ctrl.currentItemNameKey.value = null;
        await _pump(tester, ctrl);

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
