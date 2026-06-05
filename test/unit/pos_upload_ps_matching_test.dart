import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/modules/pos_upload/form/pos_upload_form_controller.dart';

PackingSlipItem _item(String serial, double qty) => PackingSlipItem(
  name: 'row-$serial',
  dnDetail: '',
  itemCode: 'ITEM-001',
  itemName: 'Test Item',
  qty: qty,
  uom: 'Nos',
  batchNo: '',
  netWeight: 0.0,
  weightUom: 0.0,
  customInvoiceSerialNumber: serial,
);

PackingSlip _ps(String name, String? poNo, int? from, int? to,
    List<PackingSlipItem> items) =>
    PackingSlip(
      name: name,
      deliveryNote: 'DN-001',
      modified: '',
      creation: '',
      docstatus: 1,
      status: 'Submitted',
      customPoNo: poNo,
      fromCaseNo: from,
      toCaseNo: to,
      items: items,
    );

void main() {
  group('PosUploadFormController.matchPsItems', () {
    test('returns matching entry when PS po_no and serial match', () {
      final slips = [_ps('PS-001', 'ML-001', 1, 3, [_item('3', 10)])];
      final result = PosUploadFormController.matchPsItems(
        slips: slips,
        posUploadName: 'ML-001',
        itemIdx: 3,
      );
      expect(result, hasLength(1));
      expect(result.first.psName, 'PS-001');
      expect(result.first.item.qty, 10);
      expect(result.first.fromCaseNo, 1);
      expect(result.first.toCaseNo, 3);
    });

    test('returns multiple entries when serial appears across different PSes', () {
      final slips = [
        _ps('PS-001', 'ML-001', 1, 3, [_item('3', 10)]),
        _ps('PS-002', 'ML-001', 4, 6, [_item('3', 5)]),
      ];
      final result = PosUploadFormController.matchPsItems(
        slips: slips,
        posUploadName: 'ML-001',
        itemIdx: 3,
      );
      expect(result, hasLength(2));
      expect(result.map((e) => e.psName), containsAll(['PS-001', 'PS-002']));
    });

    test('excludes PSes with different po_no', () {
      final slips = [
        _ps('PS-001', 'ML-002', 1, 3, [_item('3', 10)]),
        _ps('PS-002', 'ML-001', 1, 3, [_item('3', 7)]),
      ];
      final result = PosUploadFormController.matchPsItems(
        slips: slips,
        posUploadName: 'ML-001',
        itemIdx: 3,
      );
      expect(result, hasLength(1));
      expect(result.first.psName, 'PS-002');
    });

    test('excludes PSes with null po_no', () {
      final slips = [_ps('PS-001', null, 1, 3, [_item('3', 10)])];
      final result = PosUploadFormController.matchPsItems(
        slips: slips,
        posUploadName: 'ML-001',
        itemIdx: 3,
      );
      expect(result, isEmpty);
    });

    test('excludes items whose serial does not match itemIdx', () {
      final slips = [
        _ps('PS-001', 'ML-001', 1, 3, [_item('5', 10), _item('3', 8)]),
      ];
      final result = PosUploadFormController.matchPsItems(
        slips: slips,
        posUploadName: 'ML-001',
        itemIdx: 3,
      );
      expect(result, hasLength(1));
      expect(result.first.item.qty, 8);
    });

    test('returns empty list when no slips match', () {
      final slips = [_ps('PS-001', 'ML-002', 1, 3, [_item('3', 10)])];
      final result = PosUploadFormController.matchPsItems(
        slips: slips,
        posUploadName: 'ML-001',
        itemIdx: 3,
      );
      expect(result, isEmpty);
    });

    test('returns empty list for empty slips input', () {
      final result = PosUploadFormController.matchPsItems(
        slips: [],
        posUploadName: 'ML-001',
        itemIdx: 1,
      );
      expect(result, isEmpty);
    });

    test('returns two entries when same serial appears twice in one PS', () {
      final slips = [
        _ps('PS-001', 'ML-001', 1, 3, [_item('3', 10), _item('3', 5)]),
      ];
      final result = PosUploadFormController.matchPsItems(
        slips: slips,
        posUploadName: 'ML-001',
        itemIdx: 3,
      );
      expect(result, hasLength(2));
      expect(result.map((e) => e.item.qty), containsAll([10.0, 5.0]));
    });
  });
}
