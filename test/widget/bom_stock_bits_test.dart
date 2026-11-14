import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/widgets/bom_stock_bits.dart';

void main() {
  testWidgets('StatCell renders its value in ShureTechMono', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: StatCell(label: 'In Stock', value: '816')),
    ));
    final valueText = tester.widget<Text>(find.text('816'));
    expect(valueText.style?.fontFamily, 'ShureTechMono');
    final labelText = tester.widget<Text>(find.text('In Stock'));
    expect(labelText.style?.fontFamily, isNot('ShureTechMono')); // label stays default
  });
}
