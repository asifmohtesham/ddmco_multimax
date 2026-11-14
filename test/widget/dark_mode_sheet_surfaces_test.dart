import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/core/widgets/keyboard_safe_bottom_sheet.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/modules/global_widgets/validated_field_widget.dart';
import 'package:multimax/app/modules/global_widgets/warehouse_picker_sheet.dart';
import 'package:multimax/app/modules/home/widgets/scan_bottom_sheets.dart';
import 'package:multimax/app/shared/item_sheet/widgets/validated_batch_field.dart';
import 'package:multimax/main.dart' show buildAppTheme;

/// Bottom sheets and input fills must use the THEMED surface, not hardcoded
/// Colors.white — in dark mode the default text colour is near-white, so a
/// hardcoded white surface renders the content invisible (~1.1:1).
void main() {
  final darkTheme = buildAppTheme(AppScheme.dark, Brightness.dark);
  final darkSurface = darkTheme.colorScheme.surface;

  Widget darkApp(Widget child) => GetMaterialApp(
        theme: darkTheme,
        darkTheme: darkTheme,
        themeMode: ThemeMode.dark,
        home: Scaffold(body: child),
      );

  /// The background colour of the first ancestor Container of [inner] that
  /// paints a BoxDecoration colour.
  Color? sheetColorAbove(WidgetTester tester, Finder inner) {
    final containers = find.ancestor(
        of: inner, matching: find.byType(Container));
    for (final e in containers.evaluate()) {
      final deco = (e.widget as Container).decoration;
      if (deco is BoxDecoration && deco.color != null) return deco.color;
    }
    return null;
  }

  group('dark mode sheet surfaces', () {
    testWidgets('KeyboardSafeBottomSheet defaults to themed surface',
        (tester) async {
      await tester.pumpWidget(darkApp(
        const KeyboardSafeBottomSheet(child: Text('content')),
      ));
      expect(sheetColorAbove(tester, find.text('content')), darkSurface);
    });

    testWidgets('GlobalDialog.confirm sheet uses themed surface + inks',
        (tester) async {
      await tester.pumpWidget(darkApp(const SizedBox.shrink()));
      GlobalDialog.confirm(title: 'Submit', message: 'Really submit?');
      await tester.pumpAndSettle();

      expect(sheetColorAbove(tester, find.text('Submit')), darkSurface);
      // The Cancel label must not pin a light-mode ink on the themed sheet.
      final cancel = tester.widget<Text>(find.text('Cancel'));
      expect(cancel.style?.color, isNot(Colors.black87));
    });

    testWidgets('WarehousePickerSheet uses themed surface', (tester) async {
      await tester.pumpWidget(darkApp(WarehousePickerSheet(
        warehouses: const ['WH-A', 'WH-B'],
        isLoading: false,
        onSelected: (_) {},
      )));
      expect(sheetColorAbove(tester, find.text('WH-A')), darkSurface);
    });

    testWidgets('RackBalanceSheet uses themed surface', (tester) async {
      await tester.pumpWidget(darkApp(const RackBalanceSheet(
        itemCode: 'ITEM-1',
        stockData: [],
      )));
      expect(
        sheetColorAbove(tester, find.text('Stock Balance by Rack')),
        darkSurface,
      );
    });
  });

  group('dark mode input fills', () {
    testWidgets('ValidatedFieldWidget idle fill is themed, not white',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(darkApp(ValidatedFieldWidget(
        controller: controller,
        color: Colors.blue,
        hintText: 'Rack',
        isReadOnly: false,
        isValid: false,
        isValidating: false,
        onValidate: () {},
        onReset: () {},
      )));
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration?.fillColor, isNot(Colors.white));
      expect(field.decoration?.fillColor, darkSurface);
    });

    testWidgets('ValidatedBatchField idle fill is themed, not white',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(darkApp(ValidatedBatchField(
        textController: controller,
        isValid: false,
        isValidating: false,
        isHardError: false,
        isWarning: false,
        label: 'Batch',
        accentColor: Colors.blue,
        validFill: Colors.blue.withValues(alpha: 0.05),
        validBorder: Colors.blue,
        onReset: () {},
        onValidate: () {},
        onSubmitted: (_) {},
      )));
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration?.fillColor, isNot(Colors.white));
      expect(field.decoration?.fillColor, darkSurface);
    });
  });
}
