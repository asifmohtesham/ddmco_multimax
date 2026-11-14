import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/doc_picker_field.dart';
import 'package:multimax/main.dart' show buildAppTheme;

void main() {
  Widget app(Brightness b, Widget child) => MaterialApp(
        theme: buildAppTheme(AppScheme.of(b), b),
        darkTheme: buildAppTheme(AppScheme.dark, Brightness.dark),
        themeMode: b == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        home: Scaffold(body: child),
      );

  Container fieldBox(WidgetTester tester) => tester.widget<Container>(
        find.descendant(
          of: find.byType(DocPickerField),
          matching: find.byType(Container),
        ),
      );

  group('DocPickerField', () {
    testWidgets('editable: shows value, trailing affordance, fires onTap',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(app(
        Brightness.light,
        DocPickerField(
          label: 'Request Type',
          icon: Icons.category_outlined,
          value: 'Purchase',
          helperText: 'Request items to be purchased from a supplier.',
          onTap: () => tapped = true,
        ),
      ));

      expect(find.text('Request Type'), findsOneWidget);
      expect(find.text('Purchase'), findsOneWidget);
      expect(find.text('Request items to be purchased from a supplier.'),
          findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);

      await tester.tap(find.byType(DocPickerField));
      expect(tapped, isTrue);
    });

    testWidgets('empty value renders placeholder in muted ink',
        (tester) async {
      await tester.pumpWidget(app(
        Brightness.light,
        DocPickerField(
          label: 'Target Warehouse',
          icon: Icons.warehouse_outlined,
          value: '',
          placeholder: 'Select Warehouse',
          onTap: () {},
        ),
      ));

      final placeholder =
          tester.widget<Text>(find.text('Select Warehouse'));
      expect(placeholder.style?.color, AppScheme.light.textMuted);
    });

    testWidgets('read-only: no trailing affordance, no InkWell',
        (tester) async {
      await tester.pumpWidget(app(
        Brightness.light,
        const DocPickerField(
          label: 'Request Type',
          icon: Icons.category_outlined,
          value: 'Purchase',
        ),
      ));

      expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
      expect(
        find.descendant(
          of: find.byType(DocPickerField),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
    });

    testWidgets('dark mode: no light island, value ink is themed',
        (tester) async {
      await tester.pumpWidget(app(
        Brightness.dark,
        DocPickerField(
          label: 'Request Type',
          icon: Icons.category_outlined,
          value: 'Purchase',
          onTap: () {},
        ),
      ));

      final box = fieldBox(tester).decoration as BoxDecoration;
      // Fill must follow the theme surface — a pastel/white fill in dark mode
      // renders the onSurface value text invisible (~1.1:1).
      expect((box.color as Color).computeLuminance(), lessThan(0.2));
      expect(box.gradient, isNull);

      final value = tester.widget<Text>(find.text('Purchase'));
      final cs = buildAppTheme(AppScheme.dark, Brightness.dark).colorScheme;
      expect(value.style?.color, cs.onSurface);
    });

    testWidgets('dark mode read-only: fill uses subtle token', (tester) async {
      await tester.pumpWidget(app(
        Brightness.dark,
        const DocPickerField(
          label: 'Target Warehouse',
          icon: Icons.warehouse_outlined,
          value: 'Stores - MX',
        ),
      ));

      final box = fieldBox(tester).decoration as BoxDecoration;
      expect(box.color, AppScheme.dark.subtle);
      final value = tester.widget<Text>(find.text('Stores - MX'));
      expect(value.style?.color, AppScheme.dark.textMuted);
    });
  });
}
