import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';

// Pure-logic helper extracted for testing: given a slip and a DN,
// returns the patched items list and whether any items changed.
// Mirrors the algorithm in PackingSlipFormController._refreshDnDetails.
({List<PackingSlipItem> items, bool changed}) refreshDnDetails(
  PackingSlip slip,
  DeliveryNote dn,
) {
  final validNames = {
    for (final d in dn.items)
      if (d.name != null && d.name!.isNotEmpty) d.name!,
  };

  bool changed = false;
  final patched = slip.items.map((item) {
    if (item.dnDetail.isNotEmpty && validNames.contains(item.dnDetail)) {
      return item;
    }
    final itemSerial = item.customInvoiceSerialNumber ?? '0';
    final match = dn.items
        .where((d) => d.name != null && d.name!.isNotEmpty)
        .where((d) => d.itemCode == item.itemCode)
        .where((d) => (d.customInvoiceSerialNumber ?? '0') == itemSerial)
        .where((d) => item.batchNo.isEmpty || d.batchNo == item.batchNo)
        .cast<DeliveryNoteItem?>()
        .followedBy([null])
        .first;

    if (match == null) return item;
    changed = true;
    return item.copyWith(dnDetail: match.name!);
  }).toList();

  return (items: patched, changed: changed);
}

void main() {
  group('refreshDnDetails', () {
    PackingSlipItem _slipItem({
      required String dnDetail,
      required String itemCode,
      String serial = '1',
    }) =>
        PackingSlipItem(
          name: 'PS-ROW-1',
          dnDetail: dnDetail,
          itemCode: itemCode,
          itemName: 'Test Item',
          qty: 1.0,
          uom: 'Nos',
          batchNo: '',
          netWeight: 0.0,
          weightUom: 0.0,
          customInvoiceSerialNumber: serial,
        );

    DeliveryNoteItem _dnItem({
      required String name,
      required String itemCode,
      String serial = '1',
    }) =>
        DeliveryNoteItem(
          name: name,
          itemCode: itemCode,
          qty: 5.0,
          rate: 10.0,
          customInvoiceSerialNumber: serial,
          docstatus: 1,
        );

    test('returns changed=false when all dn_detail values are already valid', () {
      final dn = DeliveryNote(
        name: 'DN-001', customer: '', grandTotal: 0, postingDate: '',
        modified: '', creation: '', status: 'Submitted', currency: 'AED',
        totalQty: 5, docstatus: 1,
        items: [_dnItem(name: 'existing-row', itemCode: 'ITEM-A')],
      );
      final slip = PackingSlip(
        name: 'PS-001', deliveryNote: 'DN-001', modified: '', creation: '',
        docstatus: 0, status: 'Draft',
        items: [_slipItem(dnDetail: 'existing-row', itemCode: 'ITEM-A')],
      );

      final result = refreshDnDetails(slip, dn);

      expect(result.changed, isFalse);
      expect(result.items.first.dnDetail, equals('existing-row'));
    });

    test('returns changed=true and patches empty dn_detail when a match is found', () {
      final dn = DeliveryNote(
        name: 'DN-001', customer: '', grandTotal: 0, postingDate: '',
        modified: '', creation: '', status: 'Submitted', currency: 'AED',
        totalQty: 5, docstatus: 1,
        items: [_dnItem(name: 'new-row-name', itemCode: 'ITEM-A')],
      );
      final slip = PackingSlip(
        name: 'PS-001', deliveryNote: 'DN-001', modified: '', creation: '',
        docstatus: 0, status: 'Draft',
        items: [_slipItem(dnDetail: '', itemCode: 'ITEM-A')],
      );

      final result = refreshDnDetails(slip, dn);

      expect(result.changed, isTrue);
      expect(result.items.first.dnDetail, equals('new-row-name'));
    });

    test('returns changed=true and patches stale dn_detail', () {
      final dn = DeliveryNote(
        name: 'DN-001', customer: '', grandTotal: 0, postingDate: '',
        modified: '', creation: '', status: 'Submitted', currency: 'AED',
        totalQty: 5, docstatus: 1,
        items: [_dnItem(name: 'new-row-name', itemCode: 'ITEM-A')],
      );
      final slip = PackingSlip(
        name: 'PS-001', deliveryNote: 'DN-001', modified: '', creation: '',
        docstatus: 0, status: 'Draft',
        items: [_slipItem(dnDetail: 'stale-old-row', itemCode: 'ITEM-A')],
      );

      final result = refreshDnDetails(slip, dn);

      expect(result.changed, isTrue);
      expect(result.items.first.dnDetail, equals('new-row-name'));
    });

    test('returns changed=false when no match is found for an empty dn_detail', () {
      final dn = DeliveryNote(
        name: 'DN-001', customer: '', grandTotal: 0, postingDate: '',
        modified: '', creation: '', status: 'Submitted', currency: 'AED',
        totalQty: 5, docstatus: 1,
        items: [_dnItem(name: 'row-B', itemCode: 'ITEM-B')],
      );
      final slip = PackingSlip(
        name: 'PS-001', deliveryNote: 'DN-001', modified: '', creation: '',
        docstatus: 0, status: 'Draft',
        items: [_slipItem(dnDetail: '', itemCode: 'ITEM-A')],
      );

      final result = refreshDnDetails(slip, dn);

      expect(result.changed, isFalse);
      expect(result.items.first.dnDetail, isEmpty);
    });
  });
}
