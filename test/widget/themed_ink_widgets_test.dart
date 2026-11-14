import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/material_request_model.dart';
import 'package:multimax/app/modules/global_widgets/quantity_input_widget.dart';
import 'package:multimax/app/modules/material_request/form/widgets/material_request_item_card.dart';
import 'package:multimax/main.dart' show buildAppTheme;

/// Widgets must not pin light-mode inks (black87, grey/amber shades, pastel
/// x50 fills) onto surfaces that follow the theme — in dark mode those inks
/// land on dark surfaces (or force light islands) and become unreadable.
void main() {
  Widget app(Brightness b, Widget child) => GetMaterialApp(
        theme: buildAppTheme(AppScheme.of(b), b),
        darkTheme: buildAppTheme(AppScheme.dark, Brightness.dark),
        themeMode: b == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        home: Scaffold(body: child),
      );

  tearDown(Get.reset);

  group('QuantityInputWidget', () {
    testWidgets('label and value default to themed inks in dark mode',
        (tester) async {
      final controller = TextEditingController(text: '5');
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(
        Brightness.dark,
        QuantityInputWidget(
          controller: controller,
          onIncrement: () {},
          onDecrement: () {},
          label: 'Quantity',
        ),
      ));

      final label = tester.widget<Text>(find.text('Quantity'));
      expect(label.style?.color, isNot(Colors.black87));

      final field = tester.widget<TextFormField>(find.byType(TextFormField));
      // The value ink must be themed too — assert via the built TextField.
      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.style?.color, isNot(Colors.black87));
      expect(field, isNotNull);
    });

    testWidgets('input box does not force a white island in dark mode',
        (tester) async {
      final controller = TextEditingController(text: '5');
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(
        Brightness.dark,
        QuantityInputWidget(
          controller: controller,
          onIncrement: () {},
          onDecrement: () {},
        ),
      ));

      final boxes = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.color)
          .whereType<Color>();
      expect(boxes, isNot(contains(Colors.white)));
    });
  });

  group('MaterialRequestItemCard', () {
    MaterialRequestItem mrItem({required double ordered}) =>
        MaterialRequestItem(
          itemCode: 'ITEM-1',
          variantOf: null,
          qty: 10,
          orderedQty: ordered,
        );

    testWidgets('completed card does not force a pastel-green light island',
        (tester) async {
      await tester.pumpWidget(app(
        Brightness.dark,
        MaterialRequestItemCard(item: mrItem(ordered: 10)),
      ));
      final card = tester.widget<Card>(find.byType(Card));
      expect(card.color, isNot(Colors.green.shade50));
    });

    testWidgets('partial progress % label is not amber700 on the light card',
        (tester) async {
      await tester.pumpWidget(app(
        Brightness.light,
        MaterialRequestItemCard(item: mrItem(ordered: 4)),
      ));
      final pct = tester.widget<Text>(find.text('40%'));
      // amber.shade700 is ~2.1:1 on a light card — must use a readable ramp.
      expect(pct.style?.color, isNot(Colors.amber.shade700));
    });
  });
}
