import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/modules/delivery_note/form/so_pick.dart';

SoPickLine _line(String detail, String code, double qty,
        {double delivered = 0, int idx = 1}) =>
    SoPickLine(
      soDetail: detail,
      idx: idx,
      itemCode: code,
      itemName: 'Item $code',
      orderedQty: qty,
      deliveredQty: delivered,
      rate: 10,
      uom: 'Nos',
      conversionFactor: 1,
      warehouse: 'WH-DXB1 - KA',
    );

DeliveryNoteItem _row(String code, double qty, String? detail,
        {String? name}) =>
    DeliveryNoteItem(
        name: name, itemCode: code, qty: qty, rate: 10, soDetail: detail);

void main() {
  group('SoPickLine.fromSalesOrderItem', () {
    test('reads ERPNext Sales Order Item fields', () {
      final l = SoPickLine.fromSalesOrderItem({
        'name': 'abc',
        'idx': 2,
        'item_code': '3000247',
        'item_name': 'BELTS',
        'qty': 120,
        'delivered_qty': 20,
        'rate': 5.94,
        'uom': 'Nos',
        'conversion_factor': 1,
        'warehouse': 'WH-DXB1 - KA',
      });
      expect(l.soDetail, 'abc');
      expect(l.idx, 2);
      expect(l.pendingQty, 100);
      expect(l.rate, 5.94);
    });
  });

  group('pickedQty', () {
    test('sums only rows bound to that SO line', () {
      final rows = [
        _row('A', 3, 'l1', name: 'r1'),
        _row('A', 2, 'l1', name: 'r2'),
        _row('A', 9, 'l2', name: 'r3'),
        _row('A', 7, null, name: 'r4'),
      ];
      expect(SoPick.pickedQty('l1', rows), 5);
      expect(SoPick.pickedQty('l1', rows, excludeRowName: 'r2'), 3);
    });
  });

  group('resolveLine', () {
    final lines = [
      _line('l1', 'A', 5, idx: 1),
      _line('l2', 'A', 4, idx: 2),
      _line('l3', 'B', 2, delivered: 2, idx: 3),
    ];

    test('item not on the order', () {
      final r = SoPick.resolveLine(lines, 'Z', const []);
      expect(r.outcome, SoPickOutcome.notOnOrder);
      expect(r.line, isNull);
    });

    test('item matching is case-insensitive and trimmed', () {
      final r = SoPick.resolveLine(lines, ' a ', const []);
      expect(r.outcome, SoPickOutcome.ok);
      expect(r.line!.soDetail, 'l1');
    });

    test('first line with room wins; falls through to the next line', () {
      final r = SoPick.resolveLine(lines, 'A', [_row('A', 5, 'l1')]);
      expect(r.outcome, SoPickOutcome.ok);
      expect(r.line!.soDetail, 'l2');
      expect(r.remaining, 4);
    });

    test('fully picked when every matching line is full', () {
      final r = SoPick.resolveLine(
          lines, 'A', [_row('A', 5, 'l1'), _row('A', 4, 'l2')]);
      expect(r.outcome, SoPickOutcome.fullyPicked);
    });

    test('already delivered on the server counts as full', () {
      final r = SoPick.resolveLine(lines, 'B', const []);
      expect(r.outcome, SoPickOutcome.fullyPicked);
    });
  });

  group('remainingFor', () {
    test('excludes the row being edited so its own qty is reusable', () {
      final line = _line('l1', 'A', 5);
      final rows = [_row('A', 3, 'l1', name: 'r1'), _row('A', 1, 'l1', name: 'r2')];
      expect(SoPick.remainingFor(line, rows), 1);
      expect(SoPick.remainingFor(line, rows, excludeRowName: 'r1'), 4);
    });

    test('never negative', () {
      final line = _line('l1', 'A', 2);
      expect(SoPick.remainingFor(line, [_row('A', 9, 'l1')]), 0);
    });
  });

  group('progress', () {
    test('counts complete lines and qty totals, ignoring delivered lines', () {
      final lines = [
        _line('l1', 'A', 5),
        _line('l2', 'B', 2),
        _line('l3', 'C', 3, delivered: 3),
      ];
      final p = SoPick.progress(lines, [_row('A', 5, 'l1'), _row('B', 1, 'l2')]);
      expect(p.totalLines, 2);
      expect(p.completeLines, 1);
      expect(p.pickedQty, 6);
      expect(p.pendingQty, 7);
      expect(p.isComplete, isFalse);
    });
  });

  group('headerFromMappedDn', () {
    test('keeps only whitelisted header keys and drops items/meta', () {
      final h = SoPick.headerFromMappedDn({
        'doctype': 'Delivery Note',
        'name': 'new-delivery-note-1',
        'company': 'Multimax',
        'currency': 'AED',
        'selling_price_list': 'Standard Selling',
        'taxes_and_charges': 'UAE VAT 5%',
        'taxes': [
          {'name': 'x', 'parent': 'p', 'charge_type': 'On Net Total', 'rate': 5, '__islocal': 1}
        ],
        'items': [{'item_code': 'A'}],
        '__islocal': 1,
      });
      expect(h.containsKey('items'), isFalse);
      expect(h.containsKey('name'), isFalse);
      expect(h.containsKey('__islocal'), isFalse);
      expect(h['company'], 'Multimax');
      final tax = (h['taxes'] as List).single as Map;
      expect(tax['rate'], 5);
      expect(tax.containsKey('name'), isFalse);
      expect(tax.containsKey('parent'), isFalse);
      expect(tax.containsKey('__islocal'), isFalse);
    });
  });

  group('POS Upload link', () {
    test('dnFamilyUpload accepts only ML/KA upload names', () {
      expect(SoPick.dnFamilyUpload(' ML-2026-02011 '), 'ML-2026-02011');
      expect(SoPick.dnFamilyUpload('KA-2026-02989'), 'KA-2026-02989');
      expect(SoPick.dnFamilyUpload('MX-2026-00001'), isNull);
      expect(SoPick.dnFamilyUpload('PO-4471'), isNull);
      expect(SoPick.dnFamilyUpload(null), isNull);
    });

    test('a DN with po_no set is linked (its serials are voucher lines)', () {
      expect(SoPick.uploadLink(soPoNo: null, dnPoNo: 'ML-2026-00001', hasRows: true),
          SoUploadLink.linked);
    });

    test('no upload on the order: provisional serials', () {
      expect(SoPick.uploadLink(soPoNo: '', dnPoNo: '', hasRows: true),
          SoUploadLink.none);
      expect(SoPick.uploadLink(soPoNo: 'PO-4471', dnPoNo: null, hasRows: false),
          SoUploadLink.none);
    });

    test('upload linked on the order after picking began: assignment due', () {
      expect(SoPick.uploadLink(soPoNo: 'ML-2026-00001', dnPoNo: '', hasRows: true),
          SoUploadLink.pendingAssignment);
    });

    test('upload linked before any pick: adopt straight away', () {
      expect(SoPick.uploadLink(soPoNo: 'KA-2026-00001', dnPoNo: null, hasRows: false),
          SoUploadLink.linked);
    });

    test('Stock-Entry-family upload on the order is rejected', () {
      expect(SoPick.uploadLink(soPoNo: 'KX-2026-00001', dnPoNo: null, hasRows: true),
          SoUploadLink.wrongFamily);
    });
  });

  group('overAllocatedLines', () {
    test('sums rows per voucher line against its qty', () {
      final over = SoPick.overAllocatedLines(
        [(serial: 1, qty: 3.0), (serial: 1, qty: 2.0), (serial: 2, qty: 1.0)],
        {1: 4.0, 2: 1.0},
      );
      expect(over, {1: 1.0});
    });

    test('a serial that is not a voucher line is over by its full qty', () {
      expect(SoPick.overAllocatedLines([(serial: 9, qty: 2.0)], {1: 4.0}),
          {9: 2.0});
    });

    test('nothing over', () {
      expect(SoPick.overAllocatedLines([(serial: 1, qty: 4.0)], {1: 4.0}),
          isEmpty);
    });
  });

  group('withSoLine', () {
    test('binds link, SO rate/uom and SO idx as invoice serial', () {
      final row = DeliveryNoteItem(itemCode: 'A', qty: 2, rate: 0, uom: 'Box')
          .withSoLine(_line('l9', 'A', 5, idx: 3), 'SAL-ORD-1');
      expect(row.againstSalesOrder, 'SAL-ORD-1');
      expect(row.soDetail, 'l9');
      expect(row.rate, 10);
      expect(row.uom, 'Nos');
      expect(row.customInvoiceSerialNumber, '3');
      expect(row.qty, 2);
    });
    test('a voucher serial wins over the provisional SO idx', () {
      final row = DeliveryNoteItem(itemCode: 'A', qty: 2, rate: 0)
          .withSoLine(_line('l9', 'A', 5, idx: 3), 'SAL-ORD-1', serial: '7');
      expect(row.customInvoiceSerialNumber, '7');
      final prov = DeliveryNoteItem(itemCode: 'A', qty: 2, rate: 0)
          .withSoLine(_line('l9', 'A', 5, idx: 3), 'SAL-ORD-1', serial: '');
      expect(prov.customInvoiceSerialNumber, '3');
    });

    test('no-op without a line', () {
      final row = DeliveryNoteItem(itemCode: 'A', qty: 2, rate: 0);
      expect(identical(row.withSoLine(null, 'SAL-ORD-1'), row), isTrue);
    });
  });

  group('DeliveryNoteItem SO link', () {
    test('round-trips against_sales_order and so_detail', () {
      final i = DeliveryNoteItem.fromJson({
        'item_code': 'A',
        'qty': 1,
        'rate': 2,
        'against_sales_order': 'SAL-ORD-1',
        'so_detail': 'l1',
        'conversion_factor': 1,
      });
      final j = i.toJson();
      expect(j['against_sales_order'], 'SAL-ORD-1');
      expect(j['so_detail'], 'l1');
    });

    test('omits link keys for unlinked rows', () {
      final j = DeliveryNoteItem(itemCode: 'A', qty: 1, rate: 0).toJson();
      expect(j.containsKey('against_sales_order'), isFalse);
      expect(j.containsKey('so_detail'), isFalse);
    });
  });
}
