import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/stock/reports/stock_balance/stock_balance_sheets.dart';

void main() {
  testWidgets('tapping a reservation opens its Sales Order', (tester) async {
    Map? pushedArgs;
    await tester.pumpWidget(GetMaterialApp(
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
        GetPage(name: AppRoutes.SALES_ORDER_FORM, page: () {
          pushedArgs = Get.arguments as Map?;
          return const Scaffold(body: Text('SO FORM'));
        }),
      ],
    ));
    await tester.tap(find.text('SAL-ORD-2026-00012'));
    await tester.pumpAndSettle();
    expect(find.text('SO FORM'), findsOneWidget);
    expect(pushedArgs, {'name': 'SAL-ORD-2026-00012', 'mode': 'view'});
  });
}
