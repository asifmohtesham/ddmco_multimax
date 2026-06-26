import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/modules/purchase_receipt/form/po_link_resolver.dart';
import 'package:multimax/app/modules/purchase_receipt/form/widgets/purchase_receipt_po_link_sheet.dart';

PoLinkCandidate _cand(String name,
        {double qty = 10, double received = 0}) =>
    PoLinkCandidate(
      'PO1',
      PurchaseOrderItem(
        name: name,
        itemCode: 'A',
        itemName: 'Item A',
        qty: qty,
        receivedQty: received,
        rate: 1,
        amount: qty,
      ),
    );

// Hosts the sheet behind a button so we can capture the popped result,
// mirroring how showPoLinkPicker awaits Get.bottomSheet's return value.
Widget _host(List<PoLinkCandidate> candidates,
        void Function(PoLinkCandidate?) onPicked) =>
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                final r = await showModalBottomSheet<PoLinkCandidate>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => PurchaseReceiptPoLinkSheet(
                    itemCode: 'A',
                    candidates: candidates,
                  ),
                );
                onPicked(r);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('lists the open candidates and has no over-receipt toggle',
      (tester) async {
    await tester.pumpWidget(_host([_cand('open1'), _cand('open2')], (_) {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('open1'), findsOneWidget);
    expect(find.textContaining('open2'), findsOneWidget);
    // No over-receipt affordance exists any more.
    expect(find.byType(Switch), findsNothing);
    expect(find.text('Allow Over-Receipt'), findsNothing);
  });

  testWidgets('tapping a row pops that candidate', (tester) async {
    PoLinkCandidate? picked;
    final rows = [_cand('open1'), _cand('open2')];
    await tester.pumpWidget(_host(rows, (c) => picked = c));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('open2'));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.item.name, 'open2');
  });
}
