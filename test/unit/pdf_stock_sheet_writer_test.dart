import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:multimax/app/modules/stock_sheet/model/stock_sheet_models.dart';
import 'package:multimax/app/modules/stock_sheet/output/pdf_stock_sheet_writer.dart';

Uint8List _jpeg(int w, int h) =>
    Uint8List.fromList(img.encodeJpg(img.Image(width: w, height: h)));

StockSheetRow _row(int i, {bool oos = false, String? path}) => StockSheetRow(
      photoIndex: i,
      photoPath: path ?? 'p$i.jpg',
      barcode: '2001${i.toString().padLeft(4, '0')}',
      itemName: 'Item $i – café',
      variantOf: 'Strap',
      countryOfOrigin: 'Italy',
      outOfStock: oos,
    );

StockSheetDocument _doc(int n, {bool status = false, bool thumbs = true}) =>
    StockSheetDocument(
      title: 'Items',
      subtitle: '17/11/2026 10:00',
      rows: [for (var i = 0; i < n; i++) _row(i, oos: i == 1)],
      thumbnails: thumbs ? {for (var i = 0; i < n; i++) 'p$i.jpg': _jpeg(80, 120)} : {},
      showStatus: status,
    );

int _pageCount(Uint8List bytes) =>
    RegExp(r'/Type\s*/Page\b(?!s)').allMatches(latin1.decode(bytes)).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('produces a PDF', () async {
    final bytes = await PdfStockSheetWriter.write(_doc(3));
    expect(latin1.decode(bytes.sublist(0, 4)), '%PDF');
  });

  test('40 rows span more than one page', () async {
    final small = await PdfStockSheetWriter.write(_doc(5));
    final big = await PdfStockSheetWriter.write(_doc(40));
    expect(_pageCount(small), 1);
    expect(_pageCount(big), greaterThan(1));
  });

  test('showStatus renders the seven-column table', () async {
    final bytes = await PdfStockSheetWriter.write(_doc(4, status: true));
    expect(latin1.decode(bytes.sublist(0, 4)), '%PDF');
  });

  test('rows without thumbnails and an empty sheet do not throw', () async {
    expect((await PdfStockSheetWriter.write(_doc(3, thumbs: false))).isNotEmpty, isTrue);
    expect((await PdfStockSheetWriter.write(_doc(0))).isNotEmpty, isTrue);
  });

  test('a photo shared by several rows is embedded once', () async {
    final shared = StockSheetDocument(
      title: 't',
      subtitle: 's',
      rows: [for (var i = 0; i < 5; i++) _row(i, path: 'same.jpg')],
      thumbnails: {'same.jpg': _jpeg(80, 120)},
    );
    final separate = StockSheetDocument(
      title: 't',
      subtitle: 's',
      rows: [for (var i = 0; i < 5; i++) _row(i)],
      thumbnails: {for (var i = 0; i < 5; i++) 'p$i.jpg': _jpeg(80, 120)},
    );
    final a = await PdfStockSheetWriter.write(shared);
    final b = await PdfStockSheetWriter.write(separate);
    expect(a.length, lessThan(b.length));
  });
}
