import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;

import '../model/items_from_photos_models.dart';

/// Writes the stock sheet as an `.xlsx` workbook, building the OOXML parts by
/// hand so the thumbnails can be embedded as real pictures.
class XlsxItemsFromPhotosWriter {
  XlsxItemsFromPhotosWriter._();

  static const _sheetName = 'Items';
  static const _firstDataRow = 5;
  static const _headerRow = 4;
  static const _thumbPx = 110;
  static const _emuPerPx = 9525;

  /// 110 px picture at 0.75 pt per px, plus padding.
  static const _rowHeightPt = _thumbPx * 0.75 + 6;

  static const _widths = [5, 17, 12, 22, 20, 48, 14];

  // cellXfs indexes (see [_styles]).
  static const _sTitle = 1;
  static const _sSubtitle = 2;
  static const _sHeader = 3;
  static const _sBody = 4;
  static const _sBarcode = 5;
  static const _sBodyRed = 6;
  static const _sBarcodeRed = 7;

  /// [write] on a background isolate, so decoding every thumbnail does not
  /// freeze the UI. The document is plain data and is copied across.
  static Future<Uint8List> writeInBackground(ItemsFromPhotosDocument doc) =>
      Isolate.run(() => write(doc));

  static Uint8List write(ItemsFromPhotosDocument doc) {
    final headers = [
      '#',
      'Image',
      'Barcode',
      'Variant Of',
      'Country of Origin',
      'Item Name',
      if (doc.showStatus) 'Stock',
    ];
    final colCount = headers.length;

    final pictures = <_Picture>[]; // one per row that has a usable thumbnail
    final sheetRows = StringBuffer();

    sheetRows
      ..write(_row(1, [_text('A1', doc.title, _sTitle)]))
      ..write(_row(2, [_text('A2', doc.subtitle, _sSubtitle)]))
      ..write(_row(_headerRow, [
        for (var c = 0; c < colCount; c++)
          _text('${_col(c)}$_headerRow', headers[c], _sHeader),
      ], height: 30));

    for (var i = 0; i < doc.rows.length; i++) {
      final row = doc.rows[i];
      final r = _firstDataRow + i;
      final red = doc.highlightOutOfStock && row.outOfStock;
      final body = red ? _sBodyRed : _sBody;
      final barcodeStyle = red ? _sBarcodeRed : _sBarcode;

      final key = row.imageKey;
      final pic = _picture(
        key == null ? null : doc.thumbnails[key],
        r - 1,
        pictures.length + 1,
      );
      if (pic != null) pictures.add(pic);

      sheetRows.write(_row(r, [
        _number('A$r', i + 1, body),
        // No ERP image: the cell stays blank.
        _blank('B$r', body),
        _text('C$r', row.barcode, barcodeStyle),
        _text('D$r', row.variantOf ?? '', body),
        _text('E$r', row.countryOfOrigin ?? '', body),
        _text('F$r', row.itemName ?? '', body),
        if (doc.showStatus)
          _text('G$r', row.outOfStock ? 'Out of stock' : 'In stock', body),
      ], height: _rowHeightPt));
    }

    final lastRow = _firstDataRow + doc.rows.length - 1 < _headerRow
        ? _headerRow
        : _firstDataRow + doc.rows.length - 1;
    final lastCol = _col(colCount - 1);
    final filterRef = 'A$_headerRow:$lastCol$lastRow';

    final sheet = '''$_xmlDecl
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>
<dimension ref="A1:$lastCol$lastRow"/>
<sheetViews><sheetView workbookViewId="0"><pane ySplit="$_headerRow" topLeftCell="A$_firstDataRow" activePane="bottomLeft" state="frozen"/><selection pane="bottomLeft" activeCell="A$_firstDataRow" sqref="A$_firstDataRow"/></sheetView></sheetViews>
<sheetFormatPr defaultRowHeight="15"/>
<cols>${[
      for (var c = 0; c < colCount; c++)
        '<col min="${c + 1}" max="${c + 1}" width="${_widths[c]}" customWidth="1"/>',
    ].join()}</cols>
<sheetData>$sheetRows</sheetData>
<autoFilter ref="$filterRef"/>
<pageMargins left="0.4" right="0.4" top="0.5" bottom="0.5" header="0.3" footer="0.3"/>
<pageSetup paperSize="9" orientation="portrait" fitToWidth="1" fitToHeight="0"/>
<drawing r:id="rId1"/>
</worksheet>''';

    final archive = Archive();
    void add(String name, String xml) => archive.addFile(_file(name, utf8.encode(xml)));

    add('[Content_Types].xml', _contentTypes);
    add('_rels/.rels', _rootRels);
    add('xl/workbook.xml', _workbook(filterRef));
    add('xl/_rels/workbook.xml.rels', _workbookRels);
    add('xl/styles.xml', _styles);
    add('xl/worksheets/sheet1.xml', sheet);
    add('xl/worksheets/_rels/sheet1.xml.rels', _sheetRels);
    add('xl/drawings/drawing1.xml', _drawing(pictures));
    add('xl/drawings/_rels/drawing1.xml.rels', _drawingRels(pictures.length));
    for (var i = 0; i < pictures.length; i++) {
      archive.addFile(_file('xl/media/image${i + 1}.jpeg', pictures[i].bytes));
    }

    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  // ---- cells -------------------------------------------------------------

  static const _xmlDecl = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';

  static ArchiveFile _file(String name, List<int> bytes) =>
      ArchiveFile(name, bytes.length, bytes);

  static String _col(int zeroBased) => String.fromCharCode(65 + zeroBased);

  /// Characters XML 1.0 does not allow at all, even escaped. Excel refuses
  /// a workbook that contains one.
  static final _illegalXml = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]');

  static String _esc(String s) => s
      .replaceAll(_illegalXml, '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _text(String ref, String value, int style) =>
      '<c r="$ref" s="$style" t="inlineStr"><is><t xml:space="preserve">${_esc(value)}</t></is></c>';

  static String _number(String ref, int value, int style) =>
      '<c r="$ref" s="$style"><v>$value</v></c>';

  static String _blank(String ref, int style) => '<c r="$ref" s="$style"/>';

  static String _row(int r, List<String> cells, {double? height}) =>
      '<row r="$r"${height == null ? '' : ' ht="$height" customHeight="1"'}>${cells.join()}</row>';

  // ---- pictures ----------------------------------------------------------

  /// Null when there is no thumbnail or it cannot be read as an image.
  static _Picture? _picture(Uint8List? bytes, int zeroRow, int number) {
    if (bytes == null) return null;
    final decoded = img.decodeImage(bytes);
    if (decoded == null || decoded.width == 0 || decoded.height == 0) return null;
    final scale = _thumbPx / (decoded.width > decoded.height ? decoded.width : decoded.height);
    return _Picture(
      bytes: bytes,
      number: number,
      zeroRow: zeroRow,
      cx: (decoded.width * scale).round() * _emuPerPx,
      cy: (decoded.height * scale).round() * _emuPerPx,
    );
  }

  static String _drawing(List<_Picture> pictures) {
    final b = StringBuffer(
        '$_xmlDecl\n<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">');
    for (final p in pictures) {
      b.write('<xdr:oneCellAnchor>'
          '<xdr:from><xdr:col>1</xdr:col><xdr:colOff>${3 * _emuPerPx}</xdr:colOff><xdr:row>${p.zeroRow}</xdr:row><xdr:rowOff>${3 * _emuPerPx}</xdr:rowOff></xdr:from>'
          '<xdr:ext cx="${p.cx}" cy="${p.cy}"/>'
          '<xdr:pic>'
          '<xdr:nvPicPr><xdr:cNvPr id="${p.number + 1}" name="Picture ${p.number}"/><xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr></xdr:nvPicPr>'
          '<xdr:blipFill><a:blip r:embed="rId${p.number}"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill>'
          '<xdr:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="${p.cx}" cy="${p.cy}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr>'
          '</xdr:pic><xdr:clientData/></xdr:oneCellAnchor>');
    }
    b.write('</xdr:wsDr>');
    return b.toString();
  }

  static String _drawingRels(int count) => '''$_xmlDecl
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${[
        for (var i = 1; i <= count; i++)
          '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image$i.jpeg"/>',
      ].join()}</Relationships>''';

  // ---- fixed parts -------------------------------------------------------

  static const _contentTypes = '''$_xmlDecl
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="jpeg" ContentType="image/jpeg"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/><Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/></Types>''';

  static const _rootRels = '''$_xmlDecl
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>''';

  static String _workbook(String filterRef) {
    final abs = filterRef.replaceAllMapped(
        RegExp(r'([A-Z]+)(\d+)'), (m) => '\$${m[1]}\$${m[2]}');
    return '''$_xmlDecl
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="$_sheetName" sheetId="1" r:id="rId1"/></sheets><definedNames><definedName name="_xlnm._FilterDatabase" localSheetId="0" hidden="1">'$_sheetName'!$abs</definedName><definedName name="_xlnm.Print_Titles" localSheetId="0">'$_sheetName'!\$$_headerRow:\$$_headerRow</definedName></definedNames></workbook>''';
  }

  static const _workbookRels = '''$_xmlDecl
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>''';

  static const _sheetRels = '''$_xmlDecl
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/></Relationships>''';

  // Fonts: 0 default, 1 title, 2 subtitle, 3 header, 4 out of stock.
  // Fills: 0 none, 1 gray125 (both required), 2 header, 3 out of stock.
  // Borders: 0 none, 1 thin BFBFBF.
  static const _styles = '''$_xmlDecl
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="5"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="14"/><name val="Calibri"/></font><font><i/><sz val="11"/><color rgb="FF666666"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font><font><sz val="11"/><color rgb="FF9C0006"/><name val="Calibri"/></font></fonts>
<fills count="4"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF305496"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFFFC7CE"/><bgColor indexed="64"/></patternFill></fill></fills>
<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left style="thin"><color rgb="FFBFBFBF"/></left><right style="thin"><color rgb="FFBFBFBF"/></right><top style="thin"><color rgb="FFBFBFBF"/></top><bottom style="thin"><color rgb="FFBFBFBF"/></bottom><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="8">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="0" fontId="3" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>
<xf numFmtId="49" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>
<xf numFmtId="0" fontId="4" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>
<xf numFmtId="49" fontId="4" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>
</cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>''';
}

class _Picture {
  const _Picture({
    required this.bytes,
    required this.number,
    required this.zeroRow,
    required this.cx,
    required this.cy,
  });

  final Uint8List bytes;

  /// 1-based picture/media number.
  final int number;
  final int zeroRow;
  final int cx;
  final int cy;
}
