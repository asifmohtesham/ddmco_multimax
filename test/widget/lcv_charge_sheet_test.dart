import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/landed_cost_voucher_model.dart';
import 'package:multimax/app/modules/global_widgets/link_field_widget.dart';
import 'package:multimax/app/modules/landed_cost_voucher/form/widgets/lcv_charge_sheet.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget sheet) =>
      tester.pumpWidget(GetMaterialApp(home: Scaffold(body: sheet)));

  testWidgets('save is enabled only once the charge is complete, and it '
      'returns the charge', (tester) async {
    LandedCostTaxesAndCharges? result;
    await pump(
      tester,
      LcvChargeSheet(
        company: 'KA',
        defaultAccount: () async => 'Expenses Included In Valuation - KA',
        onSaved: (c) => result = c,
      ),
    );
    await tester.pumpAndSettle();

    FilledButton save() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save Charge'));
    expect(save().onPressed, isNull);

    await tester.enterText(find.widgetWithText(TextField, 'Description *'), 'Freight');
    await tester.enterText(find.widgetWithText(TextField, 'Amount *'), '120.5');
    await tester.pump();
    expect(save().onPressed, isNotNull);

    await tester.tap(find.text('Save Charge'));
    await tester.pumpAndSettle();
    expect(result!.description, 'Freight');
    expect(result!.amount, 120.5);
    expect(result!.expenseAccount, 'Expenses Included In Valuation - KA');
  });

  testWidgets('with the keyboard open every field and Save Charge stay '
      'visible above it', (tester) async {
    // Pixel 7 (1080x2400 @ 2.625) with the IME covering ~1100px, as seen on
    // device: the sheet used to add the inset on top of the route's own
    // keyboard padding and squeezed everything but Description off-screen.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
    showLcvChargeSheet(company: 'KA', onSaved: (_) {});
    await tester.pumpAndSettle();

    tester.view.viewInsets = const FakeViewPadding(bottom: 1100);
    await tester.pumpAndSettle();

    final keyboardTop = (2400 - 1100) / 2.625;
    for (final finder in [
      find.widgetWithText(TextField, 'Description *'),
      find.widgetWithText(TextField, 'Amount *'),
      find.byType(LinkFieldWidget),
      find.widgetWithText(FilledButton, 'Save Charge'),
    ]) {
      // Laid out but clipped by a squeezed scroll viewport is still
      // unusable, so require the control to actually receive taps.
      expect(finder.hitTestable(), findsOneWidget,
          reason: '$finder cannot be tapped with the keyboard open');
      expect(tester.getRect(finder).bottom, lessThanOrEqualTo(keyboardTop),
          reason: '$finder is hidden behind the keyboard');
    }
  });

  testWidgets('editing shows a whole amount without a trailing .0',
      (tester) async {
    await pump(
      tester,
      LcvChargeSheet(
        company: 'KA',
        initial: LandedCostTaxesAndCharges(
          name: 'row-tax-1',
          description: 'Freight',
          amount: 300,
          expenseAccount: 'Freight - KA',
          exchangeRate: 1,
          baseAmount: 300,
        ),
        onSaved: (_) {},
      ),
    );
    final amount = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Amount *'));
    expect(amount.controller!.text, '300');
  });

  group('buildLcvCharge', () {
    test('an unchanged expense account keeps the old rate and currency', () {
      final base = LandedCostTaxesAndCharges(
        name: 'row-tax-1',
        description: 'Freight',
        amount: 150,
        expenseAccount: 'Freight - KA',
        accountCurrency: 'USD',
        exchangeRate: 83.5,
        baseAmount: 150 * 83.5,
      );
      final result = buildLcvCharge(
        base: base,
        description: 'Freight',
        amount: 200,
        expenseAccount: 'Freight - KA',
      );
      expect(result.exchangeRate, 83.5);
      expect(result.accountCurrency, 'USD');
    });

    test('a changed expense account resets the rate to 1 and drops the '
        'old currency — the old rate belonged to the old account', () {
      final base = LandedCostTaxesAndCharges(
        name: 'row-tax-1',
        description: 'Freight',
        amount: 150,
        expenseAccount: 'Freight - KA',
        accountCurrency: 'USD',
        exchangeRate: 83.5,
        baseAmount: 150 * 83.5,
      );
      final result = buildLcvCharge(
        base: base,
        description: 'Freight',
        amount: 200,
        expenseAccount: 'Customs - KA',
      );
      expect(result.exchangeRate, 1);
      expect(result.accountCurrency, isNull);
      expect(result.baseAmount, 200);
    });

    test('a new charge (no base) always gets rate 1 and no currency', () {
      final result = buildLcvCharge(
        base: null,
        description: 'Insurance',
        amount: 30,
        expenseAccount: 'Insurance - KA',
      );
      expect(result.exchangeRate, 1);
      expect(result.accountCurrency, isNull);
    });
  });

  testWidgets('a double-tapped Save Charge calls onSaved once', (tester) async {
    var calls = 0;
    await pump(
      tester,
      LcvChargeSheet(
        company: 'KA',
        defaultAccount: () async => 'Expenses Included In Valuation - KA',
        onSaved: (c) => calls++,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Description *'), 'Freight');
    await tester.enterText(find.widgetWithText(TextField, 'Amount *'), '120.5');
    await tester.pump();

    // Two rapid taps before the sheet has a chance to pop.
    await tester.tap(find.text('Save Charge'));
    await tester.tap(find.text('Save Charge'));
    await tester.pumpAndSettle();

    expect(calls, 1);
  });

  testWidgets('editing keeps the server row name', (tester) async {
    LandedCostTaxesAndCharges? result;
    await pump(
      tester,
      LcvChargeSheet(
        company: 'KA',
        initial: LandedCostTaxesAndCharges(
          name: 'row-tax-1',
          description: 'Freight',
          amount: 150,
          expenseAccount: 'Freight - KA',
          exchangeRate: 1,
          baseAmount: 150,
        ),
        onSaved: (c) => result = c,
      ),
    );
    await tester.enterText(find.widgetWithText(TextField, 'Amount *'), '175');
    await tester.pump();
    await tester.tap(find.text('Save Charge'));
    await tester.pumpAndSettle();
    expect(result!.name, 'row-tax-1');
    expect(result!.amount, 175);
    expect(result!.expenseAccount, 'Freight - KA');
  });
}
