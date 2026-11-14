import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/doc_picker_field.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/entry_type_card.dart';
import 'package:multimax/main.dart' show buildAppTheme;

void main() {
  Widget app(Brightness b, Widget child) => MaterialApp(
        theme: buildAppTheme(AppScheme.of(b), b),
        darkTheme: buildAppTheme(AppScheme.dark, Brightness.dark),
        themeMode: b == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  EntryTypeCard card({
    String type = 'Material Transfer',
    String? from,
    String? to,
    bool isEditable = true,
    VoidCallback? onTypeTap,
    VoidCallback? onFromTap,
    VoidCallback? onToTap,
  }) =>
      EntryTypeCard(
        type: type,
        helperText: 'helper',
        fromWarehouse: from,
        toWarehouse: to,
        isEditable: isEditable,
        onTypeTap: onTypeTap,
        onFromTap: onFromTap,
        onToTap: onToTap,
      );

  DocPickerField fieldByLabel(WidgetTester tester, String label) =>
      tester.widget<DocPickerField>(find.ancestor(
        of: find.text(label),
        matching: find.byType(DocPickerField),
      ));

  group('EntryTypeCard type gating', () {
    testWidgets('Material Issue: FROM tappable, TO reads N/A and is inert',
        (tester) async {
      var fromTapped = false, toTapped = false;
      await tester.pumpWidget(app(
        Brightness.light,
        card(
          type: 'Material Issue',
          onFromTap: () => fromTapped = true,
          onToTap: () => toTapped = true,
        ),
      ));

      expect(find.text('Select Source'), findsOneWidget);
      expect(find.text('N/A'), findsOneWidget);

      await tester.tap(find.text('Select Source'));
      await tester.tap(find.text('N/A'), warnIfMissed: false);
      expect(fromTapped, isTrue);
      expect(toTapped, isFalse);
    });

    testWidgets('Material Receipt: TO tappable, FROM reads N/A',
        (tester) async {
      await tester.pumpWidget(
          app(Brightness.light, card(type: 'Material Receipt')));
      expect(find.text('Select Target'), findsOneWidget);
      expect(find.text('N/A'), findsOneWidget);
      expect(fieldByLabel(tester, 'From Warehouse').onTap, isNull);
    });

    for (final t in ['Material Transfer', 'Material Transfer for Manufacture']) {
      testWidgets('$t: both warehouses active', (tester) async {
        await tester.pumpWidget(app(
          Brightness.light,
          card(type: t, onFromTap: () {}, onToTap: () {}),
        ));
        expect(find.text('Select Source'), findsOneWidget);
        expect(find.text('Select Target'), findsOneWidget);
        expect(fieldByLabel(tester, 'From Warehouse').onTap, isNotNull);
        expect(fieldByLabel(tester, 'To Warehouse').onTap, isNotNull);
      });
    }

    testWidgets('empty type: Select Type placeholder, both warehouses inert',
        (tester) async {
      var typeTapped = false;
      await tester.pumpWidget(app(
        Brightness.light,
        card(type: '', onTypeTap: () => typeTapped = true, onFromTap: () {}),
      ));

      expect(find.text('Select Type'), findsOneWidget);
      expect(find.text('N/A'), findsNWidgets(2));
      expect(fieldByLabel(tester, 'From Warehouse').onTap, isNull);
      expect(fieldByLabel(tester, 'To Warehouse').onTap, isNull);

      await tester.tap(find.text('Select Type'));
      expect(typeTapped, isTrue);
    });

    testWidgets('read-only doc: nothing tappable even for transfer',
        (tester) async {
      await tester.pumpWidget(app(
        Brightness.light,
        card(
          isEditable: false,
          from: 'Stores - MX',
          to: 'WIP - MX',
          onTypeTap: () {},
          onFromTap: () {},
          onToTap: () {},
        ),
      ));
      expect(fieldByLabel(tester, 'Entry Type').onTap, isNull);
      expect(fieldByLabel(tester, 'From Warehouse').onTap, isNull);
      expect(fieldByLabel(tester, 'To Warehouse').onTap, isNull);
      expect(find.text('Stores - MX'), findsOneWidget);
      expect(find.text('WIP - MX'), findsOneWidget);
    });
  });

  group('EntryTypeCard dark mode', () {
    testWidgets('no pastel gradient / light island; value ink themed',
        (tester) async {
      await tester.pumpWidget(app(
        Brightness.dark,
        card(from: 'Stores - MX', onFromTap: () {}, onToTap: () {}),
      ));

      // Every decorated box inside the card must be gradient-free and dark.
      final boxes = tester
          .widgetList<Container>(find.descendant(
            of: find.byType(EntryTypeCard),
            matching: find.byType(Container),
          ))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>();
      for (final d in boxes) {
        expect(d.gradient, isNull);
        if (d.color != null) {
          expect(d.color!.computeLuminance(), lessThan(0.2));
        }
      }

      final cs = buildAppTheme(AppScheme.dark, Brightness.dark).colorScheme;
      final value = tester.widget<Text>(find.text('Stores - MX'));
      expect(value.style?.color, cs.onSurface);
    });
  });
}
