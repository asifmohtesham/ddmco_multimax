import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/purchase_order/form/po_receipt_helpers.dart';
import 'package:multimax/app/modules/purchase_order/form/widgets/purchase_receipt_resume_sheet.dart';

Widget _host({
  required List<DraftReceiptSummary> drafts,
  void Function(String)? onResume,
  VoidCallback? onCreateNew,
}) =>
    MaterialApp(
      home: Scaffold(
        body: PurchaseReceiptResumeSheet(
          drafts: drafts,
          onResume: onResume ?? (_) {},
          onCreateNew: onCreateNew ?? () {},
        ),
      ),
    );

void main() {
  const drafts = [
    DraftReceiptSummary(name: 'PR-0001', postingDate: '2026-06-26'),
    DraftReceiptSummary(name: 'PR-0002', postingDate: '2026-06-25'),
  ];

  testWidgets('lists each draft and a create-new action', (tester) async {
    await tester.pumpWidget(_host(drafts: drafts));
    expect(find.textContaining('PR-0001'), findsOneWidget);
    expect(find.textContaining('PR-0002'), findsOneWidget);
    expect(find.text('Start a new receipt'), findsOneWidget);
  });

  testWidgets('tapping a draft fires onResume with its name', (tester) async {
    String? resumed;
    await tester.pumpWidget(_host(drafts: drafts, onResume: (n) => resumed = n));
    await tester.tap(find.textContaining('PR-0002'));
    await tester.pumpAndSettle();
    expect(resumed, 'PR-0002');
  });

  testWidgets('tapping create-new fires onCreateNew', (tester) async {
    var created = false;
    await tester.pumpWidget(
        _host(drafts: drafts, onCreateNew: () => created = true));
    await tester.tap(find.text('Start a new receipt'));
    await tester.pumpAndSettle();
    expect(created, isTrue);
  });
}
