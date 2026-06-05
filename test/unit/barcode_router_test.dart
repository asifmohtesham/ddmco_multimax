import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/shared/image_scan/barcode_router.dart';

void main() {
  group('BarcodeRouter.classify', () {
    test('8 numeric digits → ean8', () {
      expect(BarcodeRouter.classify('20003609'), BarcodeType.ean8);
    });
    test('7 digits → unknown (not 8)', () {
      expect(BarcodeRouter.classify('2000360'), BarcodeType.unknown);
    });
    test('8 non-numeric → unknown', () {
      expect(BarcodeRouter.classify('ABCDEFGH'), BarcodeType.unknown);
    });
    test('12 chars with hyphen → fullBatchNo', () {
      expect(BarcodeRouter.classify('20003609-ESU'), BarcodeType.fullBatchNo);
    });
    test('15 chars with hyphen → fullBatchNo', () {
      expect(BarcodeRouter.classify('20003609-ESU001'), BarcodeType.fullBatchNo);
    });
    test('12 chars no hyphen → unknown', () {
      expect(BarcodeRouter.classify('200036090ESU'), BarcodeType.unknown);
    });
    test('3 chars → batchIdOnly', () {
      expect(BarcodeRouter.classify('ESU'), BarcodeType.batchIdOnly);
    });
    test('6 chars → batchIdOnly', () {
      expect(BarcodeRouter.classify('ESU001'), BarcodeType.batchIdOnly);
    });
    test('trims leading/trailing whitespace before classifying', () {
      expect(BarcodeRouter.classify('  20003609  '), BarcodeType.ean8);
    });
  });

  group('BarcodeRouter.ean8ToItemCode', () {
    test('extracts first 7 digits', () {
      expect(BarcodeRouter.ean8ToItemCode('20003609'), '2000360');
    });
    test('throws ArgumentError on input shorter than 8', () {
      expect(() => BarcodeRouter.ean8ToItemCode('1234567'), throwsArgumentError);
    });
    test('throws ArgumentError on non-numeric 8-char input', () {
      expect(() => BarcodeRouter.ean8ToItemCode('ABCDEFGH'), throwsArgumentError);
    });
  });
}
