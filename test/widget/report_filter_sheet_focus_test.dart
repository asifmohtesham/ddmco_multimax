import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';

// showReportFilterSheet(focusKey:) is what an active filter chip calls when
// tapped: the sheet opens on that filter, ready to edit.
void main() {
  const fields = [
    ReportFilterField(
        key: 'to_date', label: 'As On Date', type: ReportFilterType.datePicker),
    ReportFilterField(key: 'brand', label: 'Brand'),
    ReportFilterField(key: 'range', label: 'Ageing Range'),
  ];
  late Map<String, TextEditingController> ctrls;

  setUp(() {
    ctrls = {
      'to_date': TextEditingController(text: '2026-11-14'),
      'brand': TextEditingController(),
      'range': TextEditingController(text: '360, 720'),
    };
  });
  tearDown(() {
    for (final c in ctrls.values) {
      c.dispose();
    }
  });

  Future<void> open(WidgetTester tester, {String? focusKey}) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => FilledButton(
            onPressed: () => showReportFilterSheet(
              context: ctx,
              title: 'Filters',
              fields: fields,
              controllers: ctrls,
              onRun: () {},
              focusKey: focusKey,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  TextField fieldLabelled(WidgetTester tester, String label) =>
      tester.widget<TextField>(find.widgetWithText(TextField, label));

  testWidgets('a text filter takes focus with the caret at the end',
      (tester) async {
    await open(tester, focusKey: 'range');
    final range = fieldLabelled(tester, 'Ageing Range');
    expect(range.focusNode?.hasFocus, isTrue);
    expect(ctrls['range']!.selection,
        const TextSelection.collapsed(offset: 8));
    expect(fieldLabelled(tester, 'Brand').focusNode?.hasFocus ?? false,
        isFalse);
  });

  testWidgets('a date filter opens its date picker', (tester) async {
    await open(tester, focusKey: 'to_date');
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('without a focus key nothing is focused or opened',
      (tester) async {
    await open(tester);
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(fieldLabelled(tester, 'Ageing Range').focusNode?.hasFocus ?? false,
        isFalse);
  });

  testWidgets('a key that is not a field (a toggle) just opens the sheet',
      (tester) async {
    await open(tester, focusKey: 'show_warehouse_wise_stock');
    expect(find.text('Filters'), findsOneWidget);
    expect(find.byType(DatePickerDialog), findsNothing);
  });
}
