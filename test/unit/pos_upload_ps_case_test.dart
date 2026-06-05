import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/packing_slip_model.dart';
import 'package:multimax/app/modules/pos_upload/form/pos_upload_form_controller.dart';

PackingSlip _ps(String name, int? from, int? to) => PackingSlip(
      name: name,
      deliveryNote: 'DN-001',
      modified: '',
      creation: '',
      docstatus: 1,
      status: 'Submitted',
      items: [],
      fromCaseNo: from,
      toCaseNo: to,
    );

void main() {
  group('PosUploadFormController.psCaseCell', () {
    test('single case (from == to) → IntCellValue with fromCaseNo', () {
      final result = PosUploadFormController.psCaseCell(_ps('PS-001', 3, 3));
      expect(result, isA<IntCellValue>());
      expect((result as IntCellValue).value, 3);
    });

    test('toCaseNo null → IntCellValue with fromCaseNo', () {
      final result = PosUploadFormController.psCaseCell(_ps('PS-001', 5, null));
      expect(result, isA<IntCellValue>());
      expect((result as IntCellValue).value, 5);
    });

    test('range (from != to) → TextCellValue with "from-to" format', () {
      final result = PosUploadFormController.psCaseCell(_ps('PS-001', 1, 5));
      expect(result, isA<TextCellValue>());
      expect((result as TextCellValue).value.text, '1-5');
    });

    test('no case number → TextCellValue with PS name', () {
      final result =
          PosUploadFormController.psCaseCell(_ps('PS-001', null, null));
      expect(result, isA<TextCellValue>());
      expect((result as TextCellValue).value.text, 'PS-001');
    });
  });
}
