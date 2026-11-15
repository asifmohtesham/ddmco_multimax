import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/filter_focus.dart';

// FilterFocusScope/FilterFocusTarget are what a list screen's active filter
// chip uses to open its filter sheet on that filter, ready to edit.
void main() {
  late TextEditingController po;
  late TextEditingController customer;
  late FocusNode poFocus;
  late int pickerOpens;

  setUp(() {
    po = TextEditingController(text: 'PO-77');
    customer = TextEditingController(text: 'Acme');
    poFocus = FocusNode();
    pickerOpens = 0;
  });
  tearDown(() {
    po.dispose();
    customer.dispose();
    poFocus.dispose();
  });

  Widget sheet() => Column(children: [
        FilterFocusTarget(
          filterKey: 'status',
          child: Wrap(children: [
            ChoiceChip(label: const Text('Draft'), selected: false),
          ]),
        ),
        // Pushes the next fields well below the fold.
        const SizedBox(height: 1500),
        FilterFocusTarget(
          filterKey: 'customer',
          onActivate: () => pickerOpens++,
          child: TextField(controller: customer, readOnly: true),
        ),
        FilterFocusTarget(
          filterKey: 'po_no',
          alsoMatches: const ['po_alias'],
          child: TextField(controller: po, focusNode: poFocus),
        ),
      ]);

  Future<void> open(WidgetTester tester, {String? focusKey}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FilterFocusScope.wrap(
          focusKey: focusKey,
          SingleChildScrollView(child: sheet()),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a text filter takes focus, caret at the end, scrolled into view',
      (tester) async {
    await open(tester, focusKey: 'po_no');

    expect(poFocus.hasFocus, isTrue);
    expect(po.selection, const TextSelection.collapsed(offset: 5));
    expect(pickerOpens, 0);
    final y = tester.getTopLeft(find.byType(TextField).last).dy;
    expect(y, inInclusiveRange(0, 600));
  });

  testWidgets('a picker filter runs its onActivate once', (tester) async {
    await open(tester, focusKey: 'customer');
    expect(pickerOpens, 1);
    expect(poFocus.hasFocus, isFalse);

    // A rebuild (an Obx firing, say) must not re-open the picker.
    await open(tester, focusKey: 'customer');
    expect(pickerOpens, 1);
  });

  testWidgets('alsoMatches routes another chip key to the same section',
      (tester) async {
    await open(tester, focusKey: 'po_alias');
    expect(poFocus.hasFocus, isTrue);
  });

  testWidgets('no key, or an unknown one, activates nothing', (tester) async {
    await open(tester);
    expect(poFocus.hasFocus, isFalse);
    expect(pickerOpens, 0);

    await open(tester, focusKey: 'nope');
    expect(poFocus.hasFocus, isFalse);
    expect(pickerOpens, 0);
  });
}
