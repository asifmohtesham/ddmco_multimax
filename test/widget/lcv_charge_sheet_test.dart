import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/landed_cost_voucher_model.dart';
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
