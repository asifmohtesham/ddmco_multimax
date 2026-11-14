import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/modules/purchase_order/form/po_receipt_helpers.dart';

PurchaseOrderItem _poItem({required double qty, required double received}) =>
    PurchaseOrderItem(
      name: 'row',
      itemCode: 'A',
      itemName: 'Item A',
      qty: qty,
      receivedQty: received,
      rate: 1,
      amount: qty,
    );

void main() {
  group('hasOpenReceiptQty', () {
    test('true when a line is partially received', () {
      expect(hasOpenReceiptQty([_poItem(qty: 10, received: 3)]), isTrue);
    });

    test('true when a line is not received at all', () {
      expect(hasOpenReceiptQty([_poItem(qty: 10, received: 0)]), isTrue);
    });

    test('false when every line is fully received', () {
      expect(hasOpenReceiptQty([_poItem(qty: 10, received: 10)]), isFalse);
    });

    test('false when over-received', () {
      expect(hasOpenReceiptQty([_poItem(qty: 10, received: 12)]), isFalse);
    });

    test('false for an empty list', () {
      expect(hasOpenReceiptQty(const []), isFalse);
    });
  });

  group('parseDraftReceiptParents', () {
    test('extracts distinct parents, order preserved', () {
      final data = {
        'data': [
          {'parent': 'PR-1'},
          {'parent': 'PR-2'},
          {'parent': 'PR-1'},
        ]
      };
      expect(parseDraftReceiptParents(data), ['PR-1', 'PR-2']);
    });

    test('skips blank/missing/non-string parents', () {
      final data = {
        'data': [
          {'parent': ''},
          {'parent': null},
          {'nope': 'x'},
          {'parent': 'PR-9'},
        ]
      };
      expect(parseDraftReceiptParents(data), ['PR-9']);
    });

    test('tolerates null / non-map / missing data key', () {
      expect(parseDraftReceiptParents(null), isEmpty);
      expect(parseDraftReceiptParents('oops'), isEmpty);
      expect(parseDraftReceiptParents({'data': 'notalist'}), isEmpty);
      expect(parseDraftReceiptParents({}), isEmpty);
    });
  });
}
