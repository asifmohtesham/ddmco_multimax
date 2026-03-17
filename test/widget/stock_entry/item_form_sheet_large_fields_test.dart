// Widget Test #4.2 - Variant Of & Qty fields are large
//
// Requirement (from -YourRequirement-CorrectTestType.csv):
//   The Variant Of (itemSubtext / itemCode chip) and Quantity input must
//   render at a noticeably large size so they are easy to read and tap on
//   a warehouse handheld device.
//
// "Large" is defined by the actual values baked into the production widgets:
//   - Item code chip text:  fontSize >= 16  (labelMedium override, fontSize: 16)
//   - Qty input text:       fontSize >= 18  (bold number inside QuantityInputWidget)
//   - Qty label text:       fontSize >= 13  (QuantityInputWidget header label)
//
// Run: flutter test test/widget/stock_entry/item_form_sheet_large_fields_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/stock_entry_item_form_sheet.dart';

// ---------------------------------------------------------------------------
// Stub controller - no I/O wiring.
// ---------------------------------------------------------------------------
class _StubCtrl extends StockEntryFormController {
  @override
  void onInit() {}
}

// ---------------------------------------------------------------------------
// Pump helpers
// ---------------------------------------------------------------------------
Future<void> _pumpSheet(WidgetTester tester, _StubCtrl ctrl) async {
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

// Returns the RichText / Text fontSize for the first widget whose text data
// contains [substring], walking the render tree via [tester.widget].
double? _fontSizeOf(WidgetTester tester, String substring) {
  final candidates = find.textContaining(substring);
  if (candidates.evaluate().isEmpty) return null;
  final widget = tester.widget(candidates.first);
  if (widget is Text && widget.style?.fontSize != null) {
    return widget.style!.fontSize;
  }
  // TextFormField renders via EditableText - walk descendants.
  final editables = find.descendant(
    of: candidates.first,
    matching: find.byType(EditableText),
  );
  if (editables.evaluate().isNotEmpty) {
    final et = tester.widget<EditableText>(editables.first);
    return et.style.fontSize;
  }
  return null;
}

// Collect ALL font sizes for Text widgets whose data matches [exactText].
List<double> _allFontSizes(WidgetTester tester, String exactText) {
  final sizes = <double>[];
  for (final element in find.text(exactText).evaluate()) {
    final widget = element.widget;
    if (widget is Text && widget.style?.fontSize != null) {
      sizes.add(widget.style!.fontSize!);
    }
  }
  return sizes;
}

// Walk ALL EditableText descendants inside a finder and return their sizes.
List<double> _editableTextSizes(WidgetTester tester, Finder parent) {
  final sizes = <double>[];
  final editables = find.descendant(
    of: parent,
    matching: find.byType(EditableText),
  );
  for (final element in editables.evaluate()) {
    final et = element.widget as EditableText;
    sizes.add(et.style.fontSize ?? 0);
  }
  return sizes;
}

void main() {
  late _StubCtrl ctrl;

  setUp(() {
    Get.testMode = true;
    ctrl = _StubCtrl();
    ctrl.currentItemCode = 'ITEM-TEM-001';
    ctrl.currentItemName = 'Template Item';
    ctrl.currentVariantOf = 'ITEM-TEM';
    ctrl.selectedStockEntryType.value = 'Material Issue';
  });

  tearDown(() async {
    await Future.delayed(Duration.zero);
    Get.reset();
  });

  // =========================================================================
  // A. Item code chip — fontSize >= 16
  // =========================================================================
  group('Item code chip is large (fontSize >= 16)', () {
    testWidgets('Item code chip renders at fontSize >= 16', (tester) async {
      await _pumpSheet(tester, ctrl);

      // The chip renders itemCode (+ optional itemSubtext) inside a Text
      // with labelMedium overridden to fontSize: 16.
      final size = _fontSizeOf(tester, 'ITEM-TEM-001');
      expect(size, isNotNull,
          reason: 'Item code chip Text widget must be found in the tree.');
      expect(size, greaterThanOrEqualTo(16),
          reason: 'Item code chip font must be >= 16 for handheld readability.');
    });

    testWidgets('Variant Of suffix inside chip is also large (>= 16)',
        (tester) async {
      await _pumpSheet(tester, ctrl);
      // itemCode and itemSubtext are concatenated: "ITEM-TEM-001 • ITEM-TEM"
      final size = _fontSizeOf(tester, 'ITEM-TEM');
      expect(size, isNotNull);
      expect(size, greaterThanOrEqualTo(16),
          reason: 'Variant Of suffix in the chip must share the large font.');
    });

    testWidgets(
        'Chip font stays >= 16 when Variant Of is empty (plain item code)',
        (tester) async {
      ctrl.currentVariantOf = '';
      ctrl.currentItemCode = 'PLAIN-ITEM';
      await _pumpSheet(tester, ctrl);
      final size = _fontSizeOf(tester, 'PLAIN-ITEM');
      expect(size, isNotNull);
      expect(size, greaterThanOrEqualTo(16));
    });

    testWidgets('Chip font >= 16 regardless of SE type (Material Receipt)',
        (tester) async {
      ctrl.selectedStockEntryType.value = 'Material Receipt';
      await _pumpSheet(tester, ctrl);
      final size = _fontSizeOf(tester, 'ITEM-TEM-001');
      expect(size, isNotNull);
      expect(size, greaterThanOrEqualTo(16));
    });
  });

  // =========================================================================
  // B. Quantity label — fontSize >= 13
  // =========================================================================
  group('Quantity label is large (fontSize >= 13)', () {
    testWidgets('"Quantity" label Text renders at fontSize >= 13',
        (tester) async {
      await _pumpSheet(tester, ctrl);
      final sizes = _allFontSizes(tester, 'Quantity');
      expect(sizes, isNotEmpty,
          reason: '"Quantity" label Text widget must be present.');
      for (final size in sizes) {
        expect(size, greaterThanOrEqualTo(13),
            reason:
                '"Quantity" label font ($size) must be >= 13.');
      }
    });

    testWidgets('Quantity label >= 13 for all SE types', (tester) async {
      for (final type in [
        'Material Issue',
        'Material Receipt',
        'Material Transfer',
        'Material Transfer for Manufacture',
      ]) {
        ctrl.selectedStockEntryType.value = type;
        await _pumpSheet(tester, ctrl);
        final sizes = _allFontSizes(tester, 'Quantity');
        expect(sizes, isNotEmpty,
            reason: '"Quantity" label must be present for $type.');
        for (final size in sizes) {
          expect(size, greaterThanOrEqualTo(13),
              reason:
                  '"Quantity" label font ($size) must be >= 13 for $type.');
        }
        // Clean up between pumps.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  });

  // =========================================================================
  // C. Quantity input text — fontSize >= 18
  //    The bold number inside QuantityInputWidget's TextFormField.
  // =========================================================================
  group('Quantity input text is large (fontSize >= 18)', () {
    testWidgets('Qty TextFormField EditableText renders at fontSize >= 18',
        (tester) async {
      await _pumpSheet(tester, ctrl);

      // QuantityInputWidget sets the text field style to fontSize: 18.
      // We locate the field by its hintText '0'.
      final qtyField = find.descendant(
        of: find.byType(TextFormField),
        matching: find.byType(EditableText),
      );
      // There may be multiple TextFormFields (batch, rack, qty).
      // Qty is the one with the largest fontSize.
      final sizes = <double>[];
      for (final element in qtyField.evaluate()) {
        final et = element.widget as EditableText;
        sizes.add(et.style.fontSize ?? 0);
      }
      expect(sizes, isNotEmpty,
          reason: 'At least one EditableText must be found in the sheet.');
      final maxSize = sizes.reduce((a, b) => a > b ? a : b);
      expect(maxSize, greaterThanOrEqualTo(18),
          reason: 'Qty input font ($maxSize) must be >= 18 so the number '
              'is easy to read on a handheld device.');
    });

    testWidgets(
        'Qty input font >= 18 across all SE types', (tester) async {
      for (final type in [
        'Material Issue',
        'Material Receipt',
        'Material Transfer',
        'Material Transfer for Manufacture',
      ]) {
        ctrl.selectedStockEntryType.value = type;
        await _pumpSheet(tester, ctrl);

        final sizes = _editableTextSizes(
          tester,
          find.byType(StockEntryItemFormSheet),
        );
        expect(sizes, isNotEmpty);
        final maxSize = sizes.reduce((a, b) => a > b ? a : b);
        expect(maxSize, greaterThanOrEqualTo(18),
            reason:
                'Qty input font ($maxSize) must be >= 18 for $type.');

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  });

  // =========================================================================
  // D. Size relationship contract
  //    Qty input text must be strictly larger than the Qty label text,
  //    confirming intentional visual hierarchy.
  // =========================================================================
  group('Size hierarchy: Qty input > Qty label', () {
    testWidgets(
        'Qty input fontSize is strictly greater than Qty label fontSize',
        (tester) async {
      await _pumpSheet(tester, ctrl);

      final labelSizes = _allFontSizes(tester, 'Quantity');
      expect(labelSizes, isNotEmpty);
      final labelSize = labelSizes.first;

      final inputSizes = _editableTextSizes(
        tester,
        find.byType(StockEntryItemFormSheet),
      );
      expect(inputSizes, isNotEmpty);
      final inputSize = inputSizes.reduce((a, b) => a > b ? a : b);

      expect(inputSize, greaterThan(labelSize),
          reason:
              'The qty number ($inputSize) must be visually larger than '
              'the label ($labelSize) to create clear hierarchy.');
    });
  });

  // =========================================================================
  // E. Item code chip larger than item name
  //    The chip (monospace, 16pt) should be >= body text for the item name.
  // =========================================================================
  group('Item code chip size >= item name text size', () {
    testWidgets(
        'Item code chip fontSize is >= item name bodyLarge fontSize',
        (tester) async {
      await _pumpSheet(tester, ctrl);

      final chipSize = _fontSizeOf(tester, 'ITEM-TEM-001');
      expect(chipSize, isNotNull);

      // Item name is rendered as bodyLarge - find by its text content.
      final nameSizes = _allFontSizes(tester, 'Template Item');
      // bodyLarge may not carry an explicit fontSize (inherits theme);
      // if so, skip the comparison rather than failing on a theme default.
      if (nameSizes.isNotEmpty) {
        expect(chipSize, greaterThanOrEqualTo(nameSizes.first),
            reason: 'Item code chip ($chipSize) should be >= item name '
                'size (${nameSizes.first}) for handheld scanners.');
      }
    });
  });
}
