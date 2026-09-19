import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/sales_order_model.dart';

void main() {
  test('fromJson parses header, progress and rows', () {
    final so = SalesOrder.fromJson({
      'name': 'SAL-ORD-2026-00012',
      'customer': 'C1',
      'customer_name': 'Cust One',
      'transaction_date': '2026-09-19',
      'delivery_date': '2026-09-25',
      'order_type': 'Sales',
      'company': 'Multimax',
      'currency': 'AED',
      'selling_price_list': 'Standard Selling',
      'set_warehouse': null,
      'po_no': 'PO-9',
      'skip_delivery_note': 0,
      'status': 'To Deliver and Bill',
      'docstatus': 1,
      'per_delivered': 40,
      'per_billed': 0.0,
      'total_qty': 5,
      'grand_total': 105,
      'rounded_total': 105,
      'total_taxes_and_charges': 5,
      'owner': 'a@b.com',
      'modified': '2026-09-19 10:00:00',
      'items': [
        {
          'name': 'row1', 'item_code': 'I1', 'item_name': 'Item 1',
          'qty': 5, 'uom': 'Nos', 'stock_uom': 'Nos', 'conversion_factor': 1,
          'rate': 20, 'price_list_rate': 20, 'amount': 100,
          'delivery_date': '2026-09-25', 'warehouse': 'Stores - M',
          'delivered_qty': 2, 'delivered_by_supplier': 0,
          'tax_amount': 5, 'total_amount': 105,
        }
      ],
    });
    expect(so.docstatus, 1);
    expect(so.perDelivered, 40.0);
    expect(so.setWarehouse, isNull);
    expect(so.skipDeliveryNote, isFalse);
    expect(so.items.single.deliveredQty, 2.0);
    expect(so.items.single.deliveredBySupplier, isFalse);
    expect(so.items.single.totalAmount, 105.0);
    expect(so.items.single.isLocal, isFalse);
  });

  test('missing fields fall back to safe defaults', () {
    final so = SalesOrder.fromJson({'name': 'X'});
    expect(so.status, 'Draft');
    expect(so.orderType, 'Sales');
    expect(so.items, isEmpty);
    expect(so.currency, 'AED');
  });

  test('local rows are recognised', () {
    const row = SalesOrderItem(name: 'local_1', itemCode: 'I', itemName: 'I', qty: 1);
    expect(row.isLocal, isTrue);
  });
}
