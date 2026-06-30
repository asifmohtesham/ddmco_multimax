import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/modules/packing_slip/form/ps_serial_balance.dart';

DeliveryNoteItem _dn({
  required String name,
  required String itemCode,
  required String itemGroup,
  String serial = '1',
  double qty = 10.0,
}) =>
    DeliveryNoteItem(
      name: name,
      itemCode: itemCode,
      qty: qty,
      rate: 1.0,
      itemGroup: itemGroup,
      customInvoiceSerialNumber: serial,
      docstatus: 1,
    );

void main() {
  group('isPairedItemGroup', () {
    test('true for Straps and Buckles, false otherwise', () {
      expect(isPairedItemGroup('Straps'), isTrue);
      expect(isPairedItemGroup('Buckles'), isTrue);
      expect(isPairedItemGroup('Boxes'), isFalse);
      expect(isPairedItemGroup(''), isFalse);
      expect(isPairedItemGroup(null), isFalse);
    });
  });

  group('strapBuckleQtyFor', () {
    test('sums each group only for the requested serial', () {
      final items = [
        _dn(name: 'a', itemCode: 'S1', itemGroup: 'Straps', serial: '5', qty: 6),
        _dn(name: 'b', itemCode: 'S2', itemGroup: 'Straps', serial: '5', qty: 4),
        _dn(name: 'c', itemCode: 'B1', itemGroup: 'Buckles', serial: '5', qty: 8),
        _dn(name: 'd', itemCode: 'S3', itemGroup: 'Straps', serial: '6', qty: 99),
      ];
      final r = strapBuckleQtyFor(items, '5');
      expect(r.strap, 10.0);
      expect(r.buckle, 8.0);
    });
  });

  group('isSerialStrapBuckleUnbalanced', () {
    test('balanced when equal qty', () {
      final items = [
        _dn(name: 'a', itemCode: 'S', itemGroup: 'Straps', serial: '1', qty: 10),
        _dn(name: 'b', itemCode: 'B', itemGroup: 'Buckles', serial: '1', qty: 10),
      ];
      expect(isSerialStrapBuckleUnbalanced(items, '1'), isFalse);
    });

    test('balanced when one side absent (the "or 0" rule)', () {
      final items = [
        _dn(name: 'a', itemCode: 'S', itemGroup: 'Straps', serial: '1', qty: 10),
      ];
      expect(isSerialStrapBuckleUnbalanced(items, '1'), isFalse);
    });

    test('unbalanced when both present and differ', () {
      final items = [
        _dn(name: 'a', itemCode: 'S', itemGroup: 'Straps', serial: '1', qty: 10),
        _dn(name: 'b', itemCode: 'B', itemGroup: 'Buckles', serial: '1', qty: 8),
      ];
      expect(isSerialStrapBuckleUnbalanced(items, '1'), isTrue);
    });

    test('balanced when serial has no paired rows at all', () {
      final items = [
        _dn(name: 'a', itemCode: 'X', itemGroup: 'Boxes', serial: '1', qty: 3),
      ];
      expect(isSerialStrapBuckleUnbalanced(items, '1'), isFalse);
    });

    test('equal within epsilon is balanced', () {
      final items = [
        _dn(name: 'a', itemCode: 'S', itemGroup: 'Straps', serial: '1', qty: 0.1 + 0.2),
        _dn(name: 'b', itemCode: 'B', itemGroup: 'Buckles', serial: '1', qty: 0.3),
      ];
      expect(isSerialStrapBuckleUnbalanced(items, '1'), isFalse);
    });
  });

  group('isPackBlockedByBalance', () {
    final unbalanced = [
      _dn(name: 'a', itemCode: 'S', itemGroup: 'Straps', serial: '4', qty: 10),
      _dn(name: 'b', itemCode: 'B', itemGroup: 'Buckles', serial: '4', qty: 8),
    ];

    test('blocked: paired item on an unbalanced serial', () {
      expect(isPackBlockedByBalance(unbalanced, 'Straps', '4'), isTrue);
      expect(isPackBlockedByBalance(unbalanced, 'Buckles', '4'), isTrue);
    });

    test('not blocked: non-paired item even on an unbalanced serial', () {
      expect(isPackBlockedByBalance(unbalanced, 'Boxes', '4'), isFalse);
      expect(isPackBlockedByBalance(unbalanced, '', '4'), isFalse);
      expect(isPackBlockedByBalance(unbalanced, null, '4'), isFalse);
    });

    test('not blocked: paired item on a balanced serial', () {
      final balanced = [
        _dn(name: 'a', itemCode: 'S', itemGroup: 'Straps', serial: '4', qty: 10),
        _dn(name: 'b', itemCode: 'B', itemGroup: 'Buckles', serial: '4', qty: 10),
      ];
      expect(isPackBlockedByBalance(balanced, 'Straps', '4'), isFalse);
    });

    test('not blocked: paired item on a one-side-zero serial', () {
      final strapOnly = [
        _dn(name: 'a', itemCode: 'S', itemGroup: 'Straps', serial: '4', qty: 10),
      ];
      expect(isPackBlockedByBalance(strapOnly, 'Straps', '4'), isFalse);
    });

    test('not blocked: null/empty/sentinel serial is never blocked', () {
      expect(isPackBlockedByBalance(unbalanced, 'Straps', null), isFalse);
      expect(isPackBlockedByBalance(unbalanced, 'Straps', ''), isFalse);
      expect(isPackBlockedByBalance(unbalanced, 'Straps', '0'), isFalse);
    });
  });
}
