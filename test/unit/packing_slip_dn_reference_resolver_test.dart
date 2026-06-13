import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/modules/packing_slip/form/ps_dn_reference_resolver.dart';

PackingSlipItem _slip({
  required String dnDetail,
  required String itemCode,
  String serial = '1',
  String batchNo = '',
  double qty = 1.0,
  String name = 'PS-ROW-1',
}) =>
    PackingSlipItem(
      name: name,
      dnDetail: dnDetail,
      itemCode: itemCode,
      itemName: 'Test Item',
      qty: qty,
      uom: 'Nos',
      batchNo: batchNo,
      netWeight: 0.0,
      weightUom: 0.0,
      customInvoiceSerialNumber: serial,
    );

DeliveryNoteItem _dn({
  required String name,
  required String itemCode,
  String serial = '1',
  String? batchNo,
  double qty = 5.0,
}) =>
    DeliveryNoteItem(
      name: name,
      itemCode: itemCode,
      qty: qty,
      rate: 10.0,
      customInvoiceSerialNumber: serial,
      docstatus: 0,
      batchNo: batchNo,
    );

void main() {
  group('resolveDnReferences', () {
    test('all already valid -> no change, fixed=0, unresolved=0', () {
      final r = resolveDnReferences(
        slipItems: [_slip(dnDetail: 'row-A', itemCode: 'ITEM-A')],
        dnItems: [_dn(name: 'row-A', itemCode: 'ITEM-A')],
      );
      expect(r.fixed, 0);
      expect(r.unresolved, 0);
      expect(r.items.first.dnDetail, 'row-A');
    });

    test('empty dn_detail matched by itemCode + serial -> fixed=1', () {
      final r = resolveDnReferences(
        slipItems: [_slip(dnDetail: '', itemCode: 'ITEM-A')],
        dnItems: [_dn(name: 'new-row', itemCode: 'ITEM-A')],
      );
      expect(r.fixed, 1);
      expect(r.unresolved, 0);
      expect(r.items.first.dnDetail, 'new-row');
    });

    test('stale dn_detail re-matched -> fixed=1', () {
      final r = resolveDnReferences(
        slipItems: [_slip(dnDetail: 'old-row', itemCode: 'ITEM-A')],
        dnItems: [_dn(name: 'new-row', itemCode: 'ITEM-A')],
      );
      expect(r.fixed, 1);
      expect(r.unresolved, 0);
      expect(r.items.first.dnDetail, 'new-row');
    });

    test('no candidate -> unresolved=1, row untouched', () {
      final r = resolveDnReferences(
        slipItems: [_slip(dnDetail: '', itemCode: 'ITEM-A')],
        dnItems: [_dn(name: 'row-B', itemCode: 'ITEM-B')],
      );
      expect(r.fixed, 0);
      expect(r.unresolved, 1);
      expect(r.items.first.dnDetail, '');
    });

    test('batch must match when slip row carries a batch', () {
      final r = resolveDnReferences(
        slipItems: [_slip(dnDetail: '', itemCode: 'ITEM-A', batchNo: 'BX')],
        dnItems: [_dn(name: 'row-by', itemCode: 'ITEM-A', batchNo: 'BY')],
      );
      expect(r.unresolved, 1);
      expect(r.items.first.dnDetail, '');
    });

    test('prefers candidate with remaining qty > 0 when several match', () {
      final r = resolveDnReferences(
        slipItems: [_slip(dnDetail: '', itemCode: 'ITEM-A')],
        dnItems: [
          _dn(name: 'full-row', itemCode: 'ITEM-A'),
          _dn(name: 'open-row', itemCode: 'ITEM-A'),
        ],
        remainingQty: (d) => d.name == 'open-row' ? 3.0 : 0.0,
      );
      expect(r.fixed, 1);
      expect(r.items.first.dnDetail, 'open-row');
    });

    test('falls back to first candidate when none has remaining qty', () {
      final r = resolveDnReferences(
        slipItems: [_slip(dnDetail: '', itemCode: 'ITEM-A')],
        dnItems: [
          _dn(name: 'first-row', itemCode: 'ITEM-A'),
          _dn(name: 'second-row', itemCode: 'ITEM-A'),
        ],
        remainingQty: (_) => 0.0,
      );
      expect(r.fixed, 1);
      expect(r.items.first.dnDetail, 'first-row');
    });

    test('null serial on both sides resolves via sentinel', () {
      final r = resolveDnReferences(
        slipItems: [
          PackingSlipItem(
            name: 'PS-NULL',
            dnDetail: '',
            itemCode: 'ITEM-A',
            itemName: '',
            qty: 1.0,
            uom: 'Nos',
            batchNo: '',
            netWeight: 0.0,
            weightUom: 0.0,
            customInvoiceSerialNumber: null,
          ),
        ],
        dnItems: [
          DeliveryNoteItem(
            name: 'dn-null',
            itemCode: 'ITEM-A',
            qty: 5.0,
            rate: 0.0,
            docstatus: 0,
            customInvoiceSerialNumber: null,
          ),
        ],
      );
      expect(r.fixed, 1);
      expect(r.unresolved, 0);
      expect(r.items.first.dnDetail, 'dn-null');
    });
  });

  group('computeDnRefStatus', () {
    final validNames = {'row-A'};

    test('DN not loaded -> checking', () {
      expect(
        computeDnRefStatus(
          items: [_slip(dnDetail: '', itemCode: 'ITEM-A')],
          validNames: const {},
          dnLoaded: false,
        ),
        DnRefStatus.checking,
      );
    });

    test('all linked -> allLinked', () {
      expect(
        computeDnRefStatus(
          items: [_slip(dnDetail: 'row-A', itemCode: 'ITEM-A')],
          validNames: validNames,
          dnLoaded: true,
        ),
        DnRefStatus.allLinked,
      );
    });

    test('an orphan present -> hasUnlinked', () {
      expect(
        computeDnRefStatus(
          items: [
            _slip(dnDetail: 'row-A', itemCode: 'ITEM-A'),
            _slip(dnDetail: '', itemCode: 'ITEM-B', name: 'PS-ROW-2'),
          ],
          validNames: validNames,
          dnLoaded: true,
        ),
        DnRefStatus.hasUnlinked,
      );
    });

    test('empty slip with DN loaded -> allLinked', () {
      expect(
        computeDnRefStatus(items: const [], validNames: validNames, dnLoaded: true),
        DnRefStatus.allLinked,
      );
    });
  });
}
