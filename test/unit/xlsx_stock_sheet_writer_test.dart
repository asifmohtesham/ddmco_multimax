import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:multimax/app/modules/stock_sheet/model/stock_sheet_models.dart';
import 'package:multimax/app/modules/stock_sheet/output/xlsx_stock_sheet_writer.dart';
import 'package:xml/xml.dart';

Uint8List _jpeg(int w, int h) =>
    Uint8List.fromList(img.encodeJpg(img.Image(width: w, height: h)));

StockSheetRow _row(int i, String barcode,
        {String? name, bool oos = false, String? path}) =>
    StockSheetRow(
      photoIndex: i,
      photoPath: path ?? 'p$i.jpg',
      barcode: barcode,
      itemName: name ?? 'Item $i',
      variantOf: 'Strap',
      countryOfOrigin: 'Italy',
      outOfStock: oos,
    );

Archive _open(Uint8List bytes) => ZipDecoder().decodeBytes(bytes);

String _text(Archive a, String name) =>
    utf8.decode(a.findFile(name)!.content as List<int>);

StockSheetDocument _doc({
  List<StockSheetRow>? rows,
  Map<String, Uint8List>? thumbs,
  bool highlight = true,
  bool status = false,
}) =>
    StockSheetDocument(
      title: 'Items',
      subtitle: '17/11/2026 10:00',
      rows: rows ??
          [
            _row(0, '01234565'),
            _row(1, '20011419', oos: true),
            _row(2, '20011364'),
          ],
      thumbnails: thumbs ??
          {'p0.jpg': _jpeg(200, 100), 'p1.jpg': _jpeg(60, 120)},
      highlightOutOfStock: highlight,
      showStatus: status,
    );

/// Cell texts of the sheet, by cell reference.
Map<String, String> _cells(Archive a) {
  final doc = XmlDocument.parse(_text(a, 'xl/worksheets/sheet1.xml'));
  return {
    for (final c in doc.findAllElements('c'))
      c.getAttribute('r')!: c.findAllElements('t').map((t) => t.innerText).join(),
  };
}

void main() {
  test('contains every OOXML part', () {
    final a = _open(XlsxStockSheetWriter.write(_doc()));
    final names = a.files.map((f) => f.name).toSet();
    for (final n in [
      '[Content_Types].xml',
      '_rels/.rels',
      'xl/workbook.xml',
      'xl/_rels/workbook.xml.rels',
      'xl/styles.xml',
      'xl/worksheets/sheet1.xml',
      'xl/worksheets/_rels/sheet1.xml.rels',
      'xl/drawings/drawing1.xml',
      'xl/drawings/_rels/drawing1.xml.rels',
      'xl/media/image1.jpeg',
      'xl/media/image2.jpeg',
    ]) {
      expect(names, contains(n));
    }
    expect(names, isNot(contains('xl/media/image3.jpeg')));
  });

  test('header texts are in order and there is no Item Code', () {
    final c = _cells(_open(XlsxStockSheetWriter.write(_doc())));
    expect(
      ['A4', 'B4', 'C4', 'D4', 'E4', 'F4'].map((r) => c[r]).toList(),
      ['#', 'Image', 'Barcode', 'Variant Of', 'Country of Origin', 'Item Name'],
    );
    expect(c.containsKey('G4'), isFalse);
    expect(c.values, isNot(contains('Item Code')));
    expect(c['A1'], 'Items');
    expect(c['A2'], '17/11/2026 10:00');
  });

  test('showStatus adds the Stock column', () {
    final c = _cells(_open(XlsxStockSheetWriter.write(_doc(status: true))));
    expect(c['G4'], 'Stock');
    expect(c['G5'], 'In stock');
    expect(c['G6'], 'Out of stock');
  });

  test('one picture per row with a thumbnail, (no image) otherwise', () {
    final a = _open(XlsxStockSheetWriter.write(_doc()));
    final drawing = _text(a, 'xl/drawings/drawing1.xml');
    expect('<xdr:pic>'.allMatches(drawing).length, 2);
    final c = _cells(a);
    expect(c['B5'], isEmpty);
    expect(c['B7'], '(no image)');
  });

  test('pictures are scaled to a 110 px long side', () {
    final a = _open(XlsxStockSheetWriter.write(_doc()));
    final drawing = XmlDocument.parse(_text(a, 'xl/drawings/drawing1.xml'));
    final exts = drawing
        .findAllElements('xdr:ext')
        .map((e) => [int.parse(e.getAttribute('cx')!),
            int.parse(e.getAttribute('cy')!)])
        .toList();
    expect(exts[0], [110 * 9525, 55 * 9525]);
    expect(exts[1], [55 * 9525, 110 * 9525]);
  });

  Set<int> redStyles(Archive a) {
    final styles = XmlDocument.parse(_text(a, 'xl/styles.xml'));
    final fills = styles.findAllElements('fill').toList();
    final redFill = fills.indexWhere(
        (f) => f.findAllElements('fgColor').any((c) => c.getAttribute('rgb') == 'FFFFC7CE'));
    expect(redFill, greaterThan(1));
    final xfs = styles.findAllElements('cellXfs').first.findElements('xf').toList();
    return {
      for (var i = 0; i < xfs.length; i++)
        if (xfs[i].getAttribute('fillId') == '$redFill') i,
    };
  }

  Map<int, Set<int>> rowStyles(Archive a) {
    final doc = XmlDocument.parse(_text(a, 'xl/worksheets/sheet1.xml'));
    return {
      for (final r in doc.findAllElements('row'))
        int.parse(r.getAttribute('r')!): {
          for (final c in r.findElements('c')) int.parse(c.getAttribute('s') ?? '0'),
        },
    };
  }

  test('out-of-stock row uses the red style, in-stock rows do not', () {
    final a = _open(XlsxStockSheetWriter.write(_doc(status: true)));
    final red = redStyles(a);
    final rows = rowStyles(a);
    expect(rows[6]!.every(red.contains), isTrue);
    expect(rows[5]!.any(red.contains), isFalse);
    expect(rows[7]!.any(red.contains), isFalse);
  });

  test('highlightOutOfStock false leaves every row unhighlighted', () {
    final a = _open(XlsxStockSheetWriter.write(_doc(highlight: false, status: true)));
    final red = redStyles(a);
    for (final r in [5, 6, 7]) {
      expect(rowStyles(a)[r]!.any(red.contains), isFalse);
    }
    expect(_cells(a)['G6'], 'Out of stock');
  });

  test('special characters round-trip through XML', () {
    const name = 'STRAPS & BELTS <35mm> "x" \'y\'';
    final a = _open(XlsxStockSheetWriter.write(
        _doc(rows: [_row(0, '01234565', name: name)])));
    expect(_cells(a)['F5'], name);
  });

  test('barcode keeps its leading zero as text', () {
    final a = _open(XlsxStockSheetWriter.write(_doc()));
    expect(_cells(a)['C5'], '01234565');
    final doc = XmlDocument.parse(_text(a, 'xl/worksheets/sheet1.xml'));
    final c = doc.findAllElements('c').firstWhere((e) => e.getAttribute('r') == 'C5');
    expect(c.getAttribute('t'), 'inlineStr');
    final styles = XmlDocument.parse(_text(a, 'xl/styles.xml'));
    final xf = styles.findAllElements('cellXfs').first
        .findElements('xf').toList()[int.parse(c.getAttribute('s')!)];
    expect(xf.getAttribute('numFmtId'), '49');
  });

  test('sheet set-up: freeze, filter, print titles, fit to width', () {
    final a = _open(XlsxStockSheetWriter.write(_doc(status: true)));
    final sheet = _text(a, 'xl/worksheets/sheet1.xml');
    expect(sheet, contains('ySplit="4"'));
    expect(sheet, contains('state="frozen"'));
    expect(sheet, contains('<autoFilter ref="A4:G7"'));
    expect(sheet, contains('fitToPage="1"'));
    expect(sheet, contains('fitToHeight="0"'));
    expect(sheet, contains('paperSize="9"'));
    final wb = _text(a, 'xl/workbook.xml');
    expect(wb, contains("'Items'!\$4:\$4"));
    expect(wb, contains('_xlnm.Print_Titles'));
  });

  test('writeInBackground gives the same workbook as write', () async {
    final doc = _doc(status: true);
    final here = _open(XlsxStockSheetWriter.write(doc));
    final there = _open(await XlsxStockSheetWriter.writeInBackground(doc));
    expect(
      there.files.map((f) => f.name).toList(),
      here.files.map((f) => f.name).toList(),
    );
    for (final f in here.files) {
      expect(there.findFile(f.name)!.content, f.content, reason: f.name);
    }
  });
}
