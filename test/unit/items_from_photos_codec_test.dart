import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/stock_sheet/logic/items_from_photos_codec.dart';
import 'package:multimax/app/modules/stock_sheet/model/items_from_photos_models.dart';
import 'package:multimax/app/shared/barcode/ean8.dart';

void main() {
  test('valid EAN-8 → item code is first 7 digits', () {
    expect(ItemsFromPhotosCodec.classify('30003330'),
        const ClassifiedCode(itemCode: '3000333', barcode: '30003330', batchNo: null));
  });
  test('bad checksum is ignored', () => expect(ItemsFromPhotosCodec.classify('30003331'), isNull));
  test('batch QR → item from prefix, batch kept', () {
    expect(ItemsFromPhotosCodec.classify(' 30003330-4CPIWR '),
        const ClassifiedCode(itemCode: '3000333', barcode: '30003330', batchNo: '30003330-4CPIWR'));
  });
  test('batch QR with bad prefix checksum is ignored',
      () => expect(ItemsFromPhotosCodec.classify('30003331-4CPIWR'), isNull));
  test('malformed batch suffix is ignored', () {
    for (final s in ['30003330-', '30003330-A-B', '30003330-ab_c']) {
      expect(ItemsFromPhotosCodec.classify(s), isNull, reason: s);
    }
  });
  test('EAN-13, Code 128 text and junk are ignored', () {
    for (final s in ['4006381333931', 'SHIPMENT-12', '', 'ABCDEFGH']) {
      expect(ItemsFromPhotosCodec.classify(s), isNull, reason: s);
    }
  });
  test('same item twice in one photo (EAN + its batch QR) → one entry with batch', () {
    final items = ItemsFromPhotosCodec.itemsInPhoto(['30003330', '30003330-4CPIWR', '20011369']);
    expect(items.map((e) => e.itemCode), ['3000333', '2001136']);
    expect(items.first.batchNo, '30003330-4CPIWR');
  });
  test('batch is kept when the batch QR is seen before the plain EAN', () {
    final items = ItemsFromPhotosCodec.itemsInPhoto(['30003330-4CPIWR', '30003330']);
    expect(items, hasLength(1));
    expect(items.single.batchNo, '30003330-4CPIWR');
  });
  test('Ean8.isValid agrees with ScanService examples', () {
    expect(Ean8.isValid('20011369'), isTrue);
    expect(Ean8.isValid('20011362'), isFalse);
    expect(Ean8.isValid('2001136'), isFalse);
  });
  test('Ean8.withCheckDigit appends the check digit to seven digits', () {
    expect(Ean8.withCheckDigit('2001136'), '20011369');
    expect(Ean8.withCheckDigit('1004765'), '10047651');
    expect(Ean8.isValid(Ean8.withCheckDigit('2001136')), isTrue);
  });
  test('Ean8.withCheckDigit rejects anything but exactly seven digits', () {
    for (final s in ['200113', '20011369', '', 'ABCDEFG', '200113A']) {
      expect(() => Ean8.withCheckDigit(s), throwsArgumentError, reason: s);
    }
  });
  test('resolveTyped trims, then accepts a seven-digit item code', () {
    expect(ItemsFromPhotosCodec.resolveTyped(' 2001136 '),
        const ClassifiedCode(itemCode: '2001136', barcode: '20011369', batchNo: null));
  });
  test('resolveTyped accepts a valid EAN-8 and a batch QR through classify', () {
    expect(ItemsFromPhotosCodec.resolveTyped('20011369'),
        const ClassifiedCode(itemCode: '2001136', barcode: '20011369', batchNo: null));
    expect(ItemsFromPhotosCodec.resolveTyped('30003330-4CPIWR'),
        const ClassifiedCode(itemCode: '3000333', barcode: '30003330', batchNo: '30003330-4CPIWR'));
  });
  test('resolveTyped rejects bad checksums, short, non-numeric and junk input', () {
    for (final s in ['20011362', 'ABC', '200113', '', '   ', '2001136A']) {
      expect(ItemsFromPhotosCodec.resolveTyped(s), isNull, reason: s);
    }
  });
}
