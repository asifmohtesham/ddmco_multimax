import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/modules/item/form/widgets/reorder_rule_sheet.dart';
import 'package:multimax/main.dart' show buildAppTheme;

Future<List<String>> _fakeWarehouses({required bool isGroup}) async =>
    isGroup ? ['Stores - KA'] : ['WH-A', 'WH-B'];

void main() {
  final darkTheme = buildAppTheme(AppScheme.dark, Brightness.dark);
  final darkSurface = darkTheme.colorScheme.surface;

  /// Background colour of the first ancestor Container of [inner] that paints
  /// a BoxDecoration colour. Mirrors dark_mode_sheet_surfaces_test.dart.
  Color? sheetColorAbove(WidgetTester tester, Finder inner) {
    final containers =
        find.ancestor(of: inner, matching: find.byType(Container));
    for (final e in containers.evaluate()) {
      final deco = (e.widget as Container).decoration;
      if (deco is BoxDecoration && deco.color != null) return deco.color;
    }
    return null;
  }

  Widget darkApp(Widget child) => MaterialApp(
        theme: darkTheme,
        darkTheme: darkTheme,
        themeMode: ThemeMode.dark,
        home: Scaffold(body: child),
      );

  // GetMaterialApp, not plain MaterialApp: Get.bottomSheet() (used by
  // _pickWarehouse) resolves its Navigator via Get's own GlobalKey, which
  // only attaches when the tree is rooted in a GetMaterialApp.
  Widget darkGetApp(Widget child) => GetMaterialApp(
        theme: darkTheme,
        darkTheme: darkTheme,
        themeMode: ThemeMode.dark,
        home: Scaffold(body: child),
      );

  Widget sheet({ItemReorder? initial, ValueChanged<ItemReorder>? onSaved}) =>
      ReorderRuleSheet(
        initial: initial ??
            const ItemReorder(warehouse: '', materialRequestType: 'Purchase'),
        loadWarehouses: _fakeWarehouses,
        onSaved: onSaved ?? (_) {},
      );

  testWidgets('uses the themed surface, not a hardcoded white', (tester) async {
    await tester.pumpWidget(darkApp(sheet()));
    expect(sheetColorAbove(tester, find.text('Re-order rule')), darkSurface);
  });

  testWidgets('renders all five v15 fields with Desk labels', (tester) async {
    await tester.pumpWidget(darkApp(sheet()));

    expect(find.text('Check in (group)'), findsOneWidget);
    expect(find.text('Request for'), findsOneWidget);
    expect(find.text('Re-order Level'), findsOneWidget);
    expect(find.text('Re-order Qty'), findsOneWidget);
    expect(find.text('Material Request Type'), findsOneWidget);
  });

  testWidgets('a blank group reads as "Same as Request for"', (tester) async {
    // Mirrors item.py:508-509 rather than showing an empty field.
    await tester.pumpWidget(darkApp(sheet()));
    expect(find.text('Same as Request for'), findsOneWidget);
  });

  testWidgets('renders zero levels as blank, not "0"', (tester) async {
    await tester.pumpWidget(darkApp(sheet()));
    final fields = tester.widgetList<TextField>(find.byType(TextField));
    for (final f in fields) {
      expect(f.controller?.text, '');
    }
  });

  testWidgets('seeds the fields from an existing rule', (tester) async {
    await tester.pumpWidget(darkApp(sheet(
      initial: const ItemReorder(
        warehouseGroup: 'Stores - KA',
        warehouse: 'WH-A',
        warehouseReorderLevel: 2400,
        warehouseReorderQty: 50,
        materialRequestType: 'Transfer',
      ),
    )));

    expect(find.text('Stores - KA'), findsOneWidget);
    expect(find.text('WH-A'), findsOneWidget);
    expect(find.text('Transfer'), findsOneWidget);

    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[0].controller?.text, '2400');
    expect(fields[1].controller?.text, '50');
  });

  testWidgets('Done emits the edited row', (tester) async {
    ItemReorder? saved;

    // Pushed modally rather than pumped as the only route: _save() ends with
    // Navigator.pop(), and popping the last route in a test navigator is not
    // safe. This also matches how the sheet is actually shown.
    await tester.pumpWidget(MaterialApp(
      theme: darkTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.dark,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => sheet(
                  initial: const ItemReorder(
                    name: 'r1',
                    warehouse: 'WH-A',
                    materialRequestType: 'Purchase',
                  ),
                  onSaved: (r) => saved = r,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '300');
    await tester.enterText(find.byType(TextField).last, '150');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.name, 'r1', reason: 'the child-row name must survive an edit');
    expect(saved!.warehouseReorderLevel, 300);
    expect(saved!.warehouseReorderQty, 150);
  });

  testWidgets('Done button clears the system navigation-bar inset',
      (tester) async {
    // Regression: the sheet is shown edge-to-edge (Get.bottomSheet, no safe
    // area), so its footer must add MediaQuery.padding.bottom or the Done
    // button sits under the Android nav bar.
    const inset = 48.0;
    await tester.pumpWidget(MaterialApp(
      theme: darkTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.dark,
      // Inject a bottom system inset above the Navigator so the pushed modal
      // sheet inherits it (mirrors an Android gesture/3-button nav bar).
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(padding: const EdgeInsets.only(bottom: inset)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => sheet(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final screenBottom = tester.getSize(find.byType(MaterialApp)).height;
    final doneBottom =
        tester.getRect(find.widgetWithText(FilledButton, 'Done')).bottom;
    expect(doneBottom, lessThanOrEqualTo(screenBottom - inset),
        reason: 'Done must sit above the ${inset}px system nav bar');
  });

  testWidgets('Material Request Type picker renders its options without the '
      'ListTile ink-splash assertion', (tester) async {
    // _pickType shows its own Get.bottomSheet; Get.testMode + Get.reset keep
    // that global navigation state isolated per test.
    Get.testMode = true;
    addTearDown(Get.reset);

    await tester.pumpWidget(darkGetApp(sheet(
      initial: const ItemReorder(warehouse: '', materialRequestType: 'Purchase'),
    )));

    await tester.tap(find.text('Material Request Type'));
    await tester.pumpAndSettle();

    // The option rows render (build throws no ListTile-in-a-coloured-Container
    // assertion). Assert on non-selected types so the match can only be a
    // picker row, not the field value.
    expect(find.text('Manufacture'), findsOneWidget);
    expect(find.text('Material Issue'), findsOneWidget);
  });

  testWidgets('a second tap while warehouses load does not re-fire the loader',
      (tester) async {
    // Get.testMode + addTearDown(Get.reset): the resolved load below reaches
    // Get.bottomSheet(), which registers with Get's global navigation state.
    Get.testMode = true;
    addTearDown(Get.reset);

    var calls = 0;
    final gate = Completer<List<String>>();
    Future<List<String>> gatedLoader({required bool isGroup}) {
      calls++;
      return gate.future;
    }

    await tester.pumpWidget(darkGetApp(ReorderRuleSheet(
      initial: const ItemReorder(warehouse: '', materialRequestType: 'Purchase'),
      loadWarehouses: gatedLoader,
      onSaved: (_) {},
    )));

    // First tap starts the load (still pending on the gate).
    await tester.tap(find.text('Check in (group)'));
    await tester.pump();
    // Second tap while in flight must be ignored.
    await tester.tap(find.text('Check in (group)'));
    await tester.pump();

    expect(calls, 1);

    // Let the pending future resolve so the widget tree settles cleanly.
    // Resolved empty (rather than with a warehouse) so the picker sheet
    // renders its "No warehouses found" placeholder instead of a ListTile —
    // WarehousePickerSheet's ListTile-in-a-decorated-Container is a
    // pre-existing, unrelated framework-assertion trap that is out of scope
    // for this fix.
    gate.complete(const <String>[]);
    await tester.pumpAndSettle();
  });
}
