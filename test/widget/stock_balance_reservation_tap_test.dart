import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_controller.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_fields.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_screen.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_sheets.dart';

void main() {
  testWidgets(
    'reservation and ledger taps survive hiding all balance details',
    (tester) async {
      final controller = ScopedReportFieldsController(
        definition: stockBalanceFields(),
        owner: null,
        store: null,
      );
      addTearDown(controller.dispose);
      await controller.bind();
      for (final key in [
        'stock_uom',
        'bal_qty',
        'opening_qty',
        'in_qty',
        'out_qty',
        'val_rate',
        'bal_val',
      ]) {
        await controller.setVisible(key, false);
      }
      var openedLedger = false;
      var openedReservations = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: buildStockBalanceTileForTest(
              row: const {
                'item_code': 'I-01',
                'item_name': 'Item one',
                'warehouse': 'Ware',
                'bal_qty': 10,
                'reserved_stock': 15,
                'stock_uom': 'Each',
              },
              attrCols: const [],
              fields: controller.state.value,
              onLedgerTap: () => openedLedger = true,
              onReservedTap: () => openedReservations = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Opening Qty'), findsNothing);
      expect(find.text('Balance Qty'), findsNothing);
      expect(find.textContaining('Reserved Stock'), findsNothing);
      expect(find.textContaining('Reserved'), findsOneWidget);
      await tester.tap(find.textContaining('Reserved'));
      expect(openedReservations, isTrue);
      await tester.tap(find.text('Item one'));
      expect(openedLedger, isTrue);
    },
  );

  testWidgets('tapping a reservation opens its Sales Order', (tester) async {
    Map? pushedArgs;
    await tester.pumpWidget(
      GetMaterialApp(
        getPages: [
          GetPage(
            name: '/',
            page: () => Scaffold(
              body: ReservationsSheetBody(
                itemCode: 'I1',
                itemName: 'Item 1',
                reserved: 5,
                reservations: const [
                  {
                    'voucher_type': 'Sales Order',
                    'voucher_no': 'SAL-ORD-2026-00012',
                    'status': 'Reserved',
                    'reserved': 5,
                  },
                ],
              ),
            ),
          ),
          GetPage(
            name: AppRoutes.SALES_ORDER_FORM,
            page: () {
              pushedArgs = Get.arguments as Map?;
              return const Scaffold(body: Text('SO FORM'));
            },
          ),
        ],
      ),
    );
    await tester.tap(find.text('SAL-ORD-2026-00012'));
    await tester.pumpAndSettle();
    expect(find.text('SO FORM'), findsOneWidget);
    expect(pushedArgs, {'name': 'SAL-ORD-2026-00012', 'mode': 'view'});
  });
}
