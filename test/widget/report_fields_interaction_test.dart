import 'dart:async';

// Keep the shared Material API until the app migrates to material_ui.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_anchor.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_controller.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_sheet.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_store.dart';

import '../support/report_fields_test_kit.dart';

const _optionalKey = 'qty';
const _reportId = 'fields_interaction';

class _Fixture {
  _Fixture() {
    owner.change('https://erp.example', 'Alice');
    fields = ScopedReportFieldsController(
      definition: ReportFieldsDefinition(
        id: _reportId,
        sections: const [(id: 'row', title: 'Row')],
        alwaysShown: 'Item is always shown.',
        fields: [
          const ReportField(
            key: _optionalKey,
            column: (fieldname: _optionalKey, label: 'Quantity'),
            section: 'row',
            defaultVisible: true,
          ),
          for (var i = 0; i < 10; i++)
            ReportField(
              key: 'field_$i',
              column: (fieldname: 'field_$i', label: 'Field $i'),
              section: 'row',
              defaultVisible: true,
            ),
        ],
      ),
      owner: owner,
      store: ScopedReportFieldsStore(
        database: config,
        storage: ReportFieldsTestStorage(),
      ),
    );
  }

  final owner = ReportFieldsTestOwner();
  final config = ReportFieldsTestConfig();
  final scroll = ScrollController();
  late final ScopedReportFieldsController fields;

  String get configKey =>
      ScopedReportFieldsStore.configKey(_reportId, owner.current!.scope);

  Future<void> mount(WidgetTester tester, {double textScale = 1}) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      fields.dispose();
      scroll.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          appBar: AppBar(actions: [ReportFieldsAction(controller: fields)]),
          body: Obx(() {
            final showQuantity = fields.state.value.shows(_optionalKey);
            return ReportFieldsResults(
              controller: fields,
              scrollController: scroll,
              result: 0,
              occurrenceIds: List.generate(15, (index) => index),
              builder: (context, anchors) => CustomScrollView(
                controller: scroll,
                slivers: [
                  SliverList.builder(
                    itemCount: 15,
                    itemBuilder: (context, index) => anchors.row(
                      index,
                      index,
                      SizedBox(
                        height: index == 0 ? (showQuantity ? 160 : 80) : 110,
                        child: Text('Item $index'),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

void main() {
  final tile = find.byKey(const ValueKey(_optionalKey));
  final sheet = find.byType(DraggableScrollableSheet);
  final saving = find.text('Saving field settings…');

  testWidgets('save progress stays visible after closing Fields', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    await tester.tap(find.byTooltip('Fields'));
    await tester.pumpAndSettle();
    final write = Completer<void>();
    fixture.config.beforeWrite = (_, _) => write.future;
    await tester.tap(tile);
    await tester.pump();
    expect(saving, findsOneWidget);

    Navigator.of(tester.element(sheet)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(sheet, findsNothing);
    expect(saving.hitTestable(), findsOneWidget);

    write.complete();
    await tester.pumpAndSettle();
    expect(saving, findsNothing);
    expect(fixture.config.values[fixture.configKey], '{"qty":false}');
  });

  testWidgets('pending checkbox keeps its keyboard focus across a save', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    await tester.tap(find.byTooltip('Fields'));
    await tester.pumpAndSettle();

    bool tileHasFocus() {
      final focused = FocusManager.instance.primaryFocus?.context;
      final detector = find.ancestor(
        of: tile,
        matching: find.byType(FocusableActionDetector),
      );
      return find
          .descendant(
            of: detector,
            matching: find.byElementPredicate(
              (element) => identical(focused, element),
            ),
          )
          .evaluate()
          .isNotEmpty;
    }

    for (var i = 0; i < 6 && !tileHasFocus(); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
    }
    expect(tileHasFocus(), isTrue);
    final write = Completer<void>();
    fixture.config.beforeWrite = (_, _) => write.future;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(tile).onChanged, isNull);
    expect(tester.widget<CheckboxListTile>(tile).value, isFalse);
    expect(tileHasFocus(), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(tile).value, isFalse);
    write.complete();
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(tile).value, isTrue);
    expect(fixture.config.values[fixture.configKey], '{}');
  });

  testWidgets('compact landscape sheet can shrink with enlarged error text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _Fixture();
    fixture.config.beforeRead = (_) async => throw StateError('read failed');
    await fixture.mount(tester, textScale: 2);
    await tester.tap(find.byTooltip('Fields'));
    await tester.pumpAndSettle();
    final retry = find.descendant(of: sheet, matching: find.text('Retry'));
    expect(retry.hitTestable(), findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(sheet));
    await gesture.moveBy(const Offset(0, 25));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 95));
    await tester.pump();
    expect(tester.getSize(sheet).height, lessThan(110));
    expect(tester.takeException(), isNull);
    await gesture.moveBy(const Offset(0, -110));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    fixture.config.beforeRead = null;
    await tester.tap(retry.hitTestable());
    await tester.pumpAndSettle();
    expect(retry, findsNothing);
    expect(tester.widget<CheckboxListTile>(tile).onChanged, isNotNull);
  });

  testWidgets('late field settings allow the same results drag to continue', (
    tester,
  ) async {
    final fixture = _Fixture();
    final saved = Completer<void>();
    fixture.config.values[fixture.configKey] = '{"qty":false}';
    fixture.config.beforeRead = (_) => saved.future;
    unawaited(fixture.fields.bind());
    await fixture.mount(tester);
    fixture.scroll.jumpTo(180);
    await tester.pump();

    final gesture = await tester.startGesture(const Offset(200, 350));
    await gesture.moveBy(const Offset(0, -35));
    await tester.pump();
    expect(fixture.scroll.offset, greaterThan(180));

    saved.complete();
    await tester.pump();
    await tester.pump();
    expect(fixture.fields.shows(_optionalKey), isFalse);
    final before = fixture.scroll.offset;
    await gesture.moveBy(const Offset(0, -35));
    await tester.pump();
    expect(fixture.scroll.offset, closeTo(before + 35, 1));
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
