import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget card) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: card))));

  testWidgets('trailing replaces the status pill; body renders', (tester) async {
    await pump(
      tester,
      GenericDocumentCard(
        title: 'WALLETS COW',
        subtitle: '1000001',
        status: 'Active',
        isExpanded: false,
        navigatesOnTap: true,
        onTap: () {},
        trailing: const Text('AED 25.00'),
        body: const Text('10% off for everyone'),
      ),
    );
    expect(find.text('AED 25.00'), findsOneWidget);
    expect(find.text('10% off for everyone'), findsOneWidget);
    expect(find.byType(StatusPill), findsNothing);
  });

  testWidgets('empty subtitle is not rendered', (tester) async {
    await pump(
      tester,
      GenericDocumentCard(
        title: 'Rule',
        subtitle: '',
        isExpanded: false,
        onTap: () {},
      ),
    );
    expect(find.byType(Text), findsOneWidget);
  });
}
