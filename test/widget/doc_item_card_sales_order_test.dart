import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/sales_order_model.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/shared/item_card/doc_item_card.dart';
import 'package:multimax/app/shared/item_card/item_card_data.dart';

Widget _host(ItemCardData data) => MaterialApp(
      home: Scaffold(body: DocItemCard(data: data)),
    );

void main() {
  testWidgets('Sales Order card shows Rate beside Qty and hides Warehouse',
      (tester) async {
    const item = SalesOrderItem(
      name: 'row1',
      itemCode: '3000247',
      itemName: 'BELTS LADIES PU',
      qty: 120,
      uom: 'Nos',
      rate: 1234.5,
      warehouse: 'WH-DXB1 - KA',
    );
    await tester.pumpWidget(_host(
      ItemCardData.fromSalesOrderItem(item, index: 0, isEditable: true),
    ));

    expect(find.text('Rate'), findsOneWidget);
    expect(find.text('1,234.50'), findsOneWidget);
    expect(find.text('Warehouse'), findsNothing);
    expect(find.text('WH-DXB1 - KA'), findsNothing);
  });

  testWidgets('Purchase Order card still shows no Rate', (tester) async {
    final item = PurchaseOrderItem(
      itemCode: 'X',
      itemName: 'X',
      qty: 5,
      receivedQty: 0,
      rate: 10,
      amount: 50,
      uom: 'Nos',
    );
    await tester.pumpWidget(_host(
      ItemCardData.fromPurchaseOrderItem(item, index: 0, isEditable: true),
    ));

    expect(find.text('Rate'), findsNothing);
  });
}
