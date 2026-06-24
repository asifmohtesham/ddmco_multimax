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

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('open rows are tappable; closed rows hidden until toggle on',
      (tester) async {
    await tester.pumpWidget(_host(
      PurchaseReceiptPoLinkSheet(
        itemCode: 'A',
        candidates: [
          _cand('open1'),
          _cand('closed1', qty: 10, received: 10),
        ],
        initialAllowOverReceipt: false,
      ),
    ));
    await tester.pumpAndSettle();

    // Open row visible.
    expect(find.textContaining('open1'), findsOneWidget);
    // Closed row hidden while toggle off.
    expect(find.textContaining('closed1'), findsNothing);

    // Toggle on -> closed row appears.
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.textContaining('closed1'), findsOneWidget);
  });
}
