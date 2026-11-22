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

  Future<void> open(
    WidgetTester tester, {
    String? focusKey,
    List<ReportFilterField> filterFields = fields,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => FilledButton(
            onPressed: () => showReportFilterSheet(
              context: ctx,
              title: 'Filters',
              fields: filterFields,
              controllers: ctrls,
              onRun: () {},
              onClear: () {},
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

  testWidgets('a short filter sheet fits its content', (tester) async {
    await open(tester, filterFields: [fields[1]]);

    final sheet = tester.getRect(find.byType(BottomSheet));
    expect(sheet.height, lessThan(250));
    expect(sheet.bottom, 1000);
    expect(find.widgetWithText(TextField, 'Brand').hitTestable(), findsOneWidget);
    expect(find.text('Run Report').hitTestable(), findsOneWidget);
  });

  testWidgets('a tall sheet caps its height and pins its header and footer',
      (tester) async {
    final many = [
      for (var i = 0; i < 18; i++)
        ReportFilterField(key: 'f$i', label: 'Filter $i'),
    ];
    ctrls.addEntries(
      many.map((field) => MapEntry(field.key, TextEditingController())),
    );
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 40);
    addTearDown(tester.view.reset);
    await open(tester, filterFields: many);

    final sheet = find.byType(BottomSheet);
    final title = find.text('Filters');
    final clear = find.text('Clear');
    final run = find.text('Run Report');
    final first = find.widgetWithText(TextField, 'Filter 0');
    final last = find.widgetWithText(TextField, 'Filter 17');
    final viewport = find.byType(SingleChildScrollView);

    expect(tester.getSize(sheet).height, closeTo((1000 - 40) * 0.9, 1));
    final headerTop = tester.getTopLeft(title).dy;
    final footerTop = tester.getTopLeft(run).dy;
    expect(first.hitTestable(), findsOneWidget);
    expect(last.hitTestable(), findsNothing);
    await tester.drag(viewport, const Offset(0, -650));
    await tester.pumpAndSettle();

    expect(first.hitTestable(), findsNothing);
    expect(last.hitTestable(), findsOneWidget);
    expect(tester.getTopLeft(title).dy, headerTop);
    expect(clear.hitTestable(), findsOneWidget);
    expect(tester.getTopLeft(run).dy, footerTop);

    await tester.tap(last);
    tester.view.viewInsets = const FakeViewPadding(bottom: 460);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(title.hitTestable(), findsOneWidget);
    expect(run.hitTestable(), findsOneWidget);
    expect(tester.getBottomRight(run).dy, lessThan(1000 - 460));
  });

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

  testWidgets('a chip group below many fields is brought into view',
      (tester) async {
    final many = [
      for (var i = 0; i < 14; i++) ReportFilterField(key: 'f$i', label: 'F$i'),
    ];
    final c = {
      for (final f in many) f.key: TextEditingController(),
      'status': TextEditingController(text: 'Present'),
    };
    addTearDown(() {
      for (final x in c.values) {
        x.dispose();
      }
    });
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => FilledButton(
            onPressed: () => showReportFilterSheet(
              context: ctx,
              title: 'Filters',
              fields: many,
              controllers: c,
              onRun: () {},
              chipGroups: const [
                ReportFilterChipGroup(
                  key: 'status',
                  label: 'Status',
                  options: [
                    ReportFilterChipOption(value: 'Present', label: 'Present'),
                    ReportFilterChipOption(value: 'Absent', label: 'Absent'),
                  ],
                ),
              ],
              focusKey: 'status',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final absent = find.text('Absent');
    expect(absent, findsOneWidget);
    final y = tester.getCenter(absent).dy;
    expect(y, inInclusiveRange(0, 700)); // above the Run Report bar
  });
}
