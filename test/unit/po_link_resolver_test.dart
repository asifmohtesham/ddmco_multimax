import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/purchase_order_model.dart';
import 'package:multimax/app/modules/purchase_receipt/form/po_link_resolver.dart';

PoLinkCandidate _cand(
  String po,
  String code, {
  double qty = 10,
  double received = 0,
  String name = 'row',
}) =>
    PoLinkCandidate(
      po,
      PurchaseOrderItem(
        name: name,
        itemCode: code,
        itemName: code,
        qty: qty,
        receivedQty: received,
        rate: 1,
        amount: qty,
      ),
    );

void main() {
  group('resolvePoLinkFor', () {
    test('single open candidate auto-links', () {
      final r = resolvePoLinkFor([_cand('PO1', 'A', name: 'r1')], 'A');
      expect(r.outcome, PoLinkOutcome.autoLinked);
      expect(r.linked!.item.name, 'r1');
    });

    test('multiple open candidates need picker (open rows only)', () {
      final r = resolvePoLinkFor([
        _cand('PO1', 'A', name: 'r1'),
        _cand('PO2', 'A', name: 'r2'),
      ], 'A');
      expect(r.outcome, PoLinkOutcome.needsPicker);
      expect(r.candidates.length, 2);
    });

    test('a fully-received candidate is never eligible — blocked', () {
      final r = resolvePoLinkFor([
        _cand('PO1', 'A', qty: 10, received: 10, name: 'r1'),
      ], 'A');
      expect(r.outcome, PoLinkOutcome.blocked);
      expect(r.reason, contains('fully received'));
    });

    test('only the open row is offered when a closed row also exists', () {
      final r = resolvePoLinkFor([
        _cand('PO1', 'A', qty: 10, received: 10, name: 'closed'),
        _cand('PO1', 'A', qty: 10, received: 0, name: 'open'),
      ], 'A');
      expect(r.outcome, PoLinkOutcome.autoLinked);
      expect(r.linked!.item.name, 'open');
    });

    test('item absent from all POs is blocked', () {
      final r = resolvePoLinkFor([_cand('PO1', 'B', name: 'r1')], 'A');
      expect(r.outcome, PoLinkOutcome.blocked);
      expect(r.reason, contains('any linked Purchase Order'));
    });
  });

  group('resolvePoLinkRepair', () {
    test('no matching item code → discard', () {
      final r = resolvePoLinkRepair([_cand('PO1', 'B', name: 'r1')], 'A');
      expect(r.outcome, PoRepairOutcome.discard);
    });

    test('single match → relink (even when fully received)', () {
      // Repair restores an existing link; it must re-point even to a line that
      // now reads as fully received, since it never adds new receipt qty.
      final r = resolvePoLinkRepair([
        _cand('PO1', 'A', qty: 10, received: 10, name: 'live'),
      ], 'A');
      expect(r.outcome, PoRepairOutcome.relink);
      expect(r.match!.item.name, 'live');
    });

    test('multiple matches → picker', () {
      final r = resolvePoLinkRepair([
        _cand('PO1', 'A', name: 'r1'),
        _cand('PO1', 'A', name: 'r2'),
      ], 'A');
      expect(r.outcome, PoRepairOutcome.needsPicker);
      expect(r.candidates.length, 2);
    });
  });

  group('poQtyCeiling', () {
    test('caps at PO qty', () {
      expect(poQtyCeiling(5), 5);
    });
    test('infinite when no PO qty', () {
      expect(poQtyCeiling(null), double.infinity);
    });
    test('infinite when PO qty is zero', () {
      expect(poQtyCeiling(0), double.infinity);
    });
  });

  group('parseInvalidPoItemRefs', () {
    test('extracts a single row name', () {
      final s = parseInvalidPoItemRefs(
          'frappe.exceptions.ValidationError: Invalid reference '
          'Purchase Order Item h03g3r24ji');
      expect(s, {'h03g3r24ji'});
    });
    test('extracts multiple distinct names', () {
      final s = parseInvalidPoItemRefs(
          'Invalid reference Purchase Order Item aaa111 ... '
          'Invalid reference Purchase Order Item bbb222');
      expect(s, {'aaa111', 'bbb222'});
    });
    test('returns empty when no match', () {
      expect(parseInvalidPoItemRefs('some other error'), isEmpty);
    });
  });
}
