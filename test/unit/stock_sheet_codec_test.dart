import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/stock_sheet/logic/stock_sheet_codec.dart';
import 'package:multimax/app/modules/stock_sheet/model/stock_sheet_models.dart';
import 'package:multimax/app/shared/barcode/ean8.dart';

void main() {
  test('valid EAN-8 → item code is first 7 digits', () {
    expect(StockSheetCodec.classify('30003330'),
        const ClassifiedCode(itemCode: '3000333', barcode: '30003330', batchNo: null));
  });
  test('bad checksum is ignored', () => expect(StockSheetCodec.classify('30003331'), isNull));
  test('batch QR → item from prefix, batch kept', () {
    expect(StockSheetCodec.classify(' 30003330-4CPIWR '),
        const ClassifiedCode(itemCode: '3000333', barcode: '30003330', batchNo: '30003330-4CPIWR'));
  });
  test('batch QR with bad prefix checksum is ignored',
      () => expect(StockSheetCodec.classify('30003331-4CPIWR'), isNull));
  test('EAN-13, Code 128 text and junk are ignored', () {
    for (final s in ['4006381333931', 'SHIPMENT-12', '', 'ABCDEFGH']) {
      expect(StockSheetCodec.classify(s), isNull, reason: s);
    }
  });
  test('same item twice in one photo (EAN + its batch QR) → one entry with batch', () {
    final items = StockSheetCodec.itemsInPhoto(['30003330', '30003330-4CPIWR', '20011369']);
    expect(items.map((e) => e.itemCode), ['3000333', '2001136']);
    expect(items.first.batchNo, '30003330-4CPIWR');
  });
  test('batch is kept when the batch QR is seen before the plain EAN', () {
    final items = StockSheetCodec.itemsInPhoto(['30003330-4CPIWR', '30003330']);
    expect(items, hasLength(1));
    expect(items.single.batchNo, '30003330-4CPIWR');
  });
  test('Ean8.isValid agrees with ScanService examples', () {
    expect(Ean8.isValid('20011369'), isTrue);
    expect(Ean8.isValid('20011362'), isFalse);
    expect(Ean8.isValid('2001136'), isFalse);
  });
}
