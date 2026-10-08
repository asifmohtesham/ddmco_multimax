import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/delivery_note/form/so_pick.dart';
import 'package:multimax/app/modules/delivery_note/form/widgets/so_pick_header.dart';
import 'package:multimax/app/modules/home/widgets/sales_order_pick_sheet.dart';

const _order = SoPickContext(
  name: 'SAL-ORD-2026-00013',
  customer: 'C1',
  customerName: 'Nesto Hypermarket',
  lines: [],
);

Widget _host(Widget child, Brightness b) => MaterialApp(
      theme: ThemeData(brightness: b),
      home: Scaffold(body: child),
    );

void main() {
  group('dueStateOf', () {
    final now = DateTime(2026, 10, 8, 15);
    test('overdue / today / upcoming / none', () {
      expect(dueStateOf(DateTime(2026, 10, 7), now), DueState.overdue);
      expect(dueStateOf(DateTime(2026, 10, 8), now), DueState.today);
      expect(dueStateOf(DateTime(2026, 10, 9), now), DueState.upcoming);
      expect(dueStateOf(null, now), DueState.none);
    });
  });

  group('OpenSalesOrder', () {
    final so = OpenSalesOrder.fromJson({
      'name': 'SAL-ORD-2026-00013',
      'customer': 'NESTO-01',
      'customer_name': 'Nesto Hypermarket',
      'delivery_date': '2026-10-09',
      'per_delivered': 25.5,
      'total_qty': 240,
    });
    test('parses list fields', () {
      expect(so.deliveryDate, DateTime(2026, 10, 9));
      expect(so.perDelivered, 25.5);
    });
    test('search matches name, customer id and customer name', () {
      expect(so.matches('00013'), isTrue);
      expect(so.matches('nesto-01'), isTrue);
      expect(so.matches('hyper'), isTrue);
      expect(so.matches(''), isTrue);
      expect(so.matches('grand'), isFalse);
    });
  });

  for (final b in Brightness.values) {
    testWidgets('SoPickHeader in progress ($b)', (t) async {
      await t.pumpWidget(_host(
        const SoPickHeader(
          order: _order,
          progress: SoPickProgress(
              totalLines: 2, completeLines: 1, pickedQty: 6, pendingQty: 7),
          isEditable: true,
        ),
        b,
      ));
      expect(find.text('1/2 lines'), findsOneWidget);
      expect(find.text('Nesto Hypermarket'), findsOneWidget);
      expect(find.textContaining('Scan an item from this order'), findsOneWidget);
      expect(find.textContaining('6 of 7 picked'), findsOneWidget);
    });

    testWidgets('SoPickHeader complete ($b)', (t) async {
      await t.pumpWidget(_host(
        const SoPickHeader(
          order: _order,
          progress: SoPickProgress(
              totalLines: 2, completeLines: 2, pickedQty: 7, pendingQty: 7),
          isEditable: true,
        ),
        b,
      ));
      expect(find.text('Everything on this order is picked'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });
  }
}
