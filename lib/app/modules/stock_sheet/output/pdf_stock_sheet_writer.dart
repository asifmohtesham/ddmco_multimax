import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../model/stock_sheet_models.dart';

/// Writes the stock sheet as an A4 portrait PDF that mirrors the Excel
/// layout: the same columns, header colour and red out-of-stock rows.
class PdfStockSheetWriter {
  PdfStockSheetWriter._();

  static const _headerFill = PdfColor.fromInt(0xFF305496);
  static const _grid = PdfColor.fromInt(0xFFBFBFBF);
  static const _redFill = PdfColor.fromInt(0xFFFFC7CE);
  static const _redText = PdfColor.fromInt(0xFF9C0006);
  static const _footerGrey = PdfColor.fromInt(0xFF808080);

  static const _bodySize = 8.5;
  static const _thumbMm = 26.0;

  static const _widthsMm = [8.0, 30.0, 22.0, 34.0, 26.0, 66.0];
  static const _widthsStatusMm = [8.0, 30.0, 20.0, 30.0, 24.0, 52.0, 22.0];

  /// [regular] and [bold] default to the bundled Inter fonts, so characters
  /// outside Latin-1 do not break the built-in Helvetica.
  static Future<Uint8List> write(
    StockSheetDocument doc, {
    pw.Font? regular,
    pw.Font? bold,
  }) async {
    final regularFont = regular ?? await _loadFont('Inter-Regular.ttf');
    final boldFont = bold ?? await _loadFont('Inter-Medium.ttf');

    final headers = [
      '#',
      'Image',
      'Barcode',
      'Variant Of',
      'Country of Origin',
      'Item Name',
      if (doc.showStatus) 'Stock',
    ];
    final widths = doc.showStatus ? _widthsStatusMm : _widthsMm;

    // One MemoryImage per photo, so a photo shared by several rows is
    // embedded in the PDF once.
    final images = <String, pw.MemoryImage>{};
    pw.MemoryImage? imageFor(String path) {
      final cached = images[path];
      if (cached != null) return cached;
      final bytes = doc.thumbnails[path];
      if (bytes == null) return null;
      try {
        return images[path] = pw.MemoryImage(bytes);
      } catch (_) {
        return null; // unreadable thumbnail: fall back to "(no image)"
      }
    }

    pw.Widget cell(
      pw.Widget child, {
      pw.Alignment alignment = pw.Alignment.centerLeft,
    }) =>
        pw.Container(
          alignment: alignment,
          padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
          child: child,
        );

    pw.Widget text(String value, {PdfColor? colour, pw.Font? font}) => pw.Text(
          value,
          style: pw.TextStyle(
            font: font,
            fontSize: _bodySize,
            color: colour ?? PdfColors.black,
          ),
        );

    final headerRow = pw.TableRow(
      repeat: true,
      decoration: const pw.BoxDecoration(color: _headerFill),
      children: [
        for (final h in headers)
          cell(text(h, colour: PdfColors.white, font: boldFont)),
      ],
    );

    final bodyRows = <pw.TableRow>[];
    for (var i = 0; i < doc.rows.length; i++) {
      final row = doc.rows[i];
      final red = doc.highlightOutOfStock && row.outOfStock;
      final ink = red ? _redText : null;
      final image = imageFor(row.photoPath);

      bodyRows.add(pw.TableRow(
        verticalAlignment: pw.TableCellVerticalAlignment.middle,
        decoration: red ? const pw.BoxDecoration(color: _redFill) : null,
        children: [
          cell(text('${i + 1}', colour: ink)),
          cell(
            image == null
                ? text('(no image)', colour: ink)
                : pw.Image(
                    image,
                    width: _thumbMm * PdfPageFormat.mm,
                    height: _thumbMm * PdfPageFormat.mm,
                    fit: pw.BoxFit.contain,
                    alignment: pw.Alignment.centerLeft,
                  ),
          ),
          cell(text(row.barcode, colour: ink)),
          cell(text(row.variantOf ?? '', colour: ink)),
          cell(text(row.countryOfOrigin ?? '', colour: ink)),
          cell(text(row.itemName ?? '', colour: ink)),
          if (doc.showStatus)
            cell(text(row.outOfStock ? 'Out of stock' : 'In stock',
                colour: ink)),
        ],
      ));
    }

    final pdf = pw.Document(title: doc.title);
    pdf.addPage(pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(
          12 * PdfPageFormat.mm,
          12 * PdfPageFormat.mm,
          12 * PdfPageFormat.mm,
          14 * PdfPageFormat.mm,
        ),
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
      ),
      header: (context) => context.pageNumber == 1
          ? pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(doc.title,
                      style: pw.TextStyle(font: boldFont, fontSize: 14)),
                  pw.SizedBox(height: 2),
                  pw.Text(doc.subtitle,
                      style: const pw.TextStyle(
                          fontSize: 9, color: _footerGrey)),
                ],
              ),
            )
          : pw.SizedBox(),
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(doc.title,
              style: const pw.TextStyle(fontSize: 7.5, color: _footerGrey)),
          pw.Text('Page ${context.pageNumber}',
              style: const pw.TextStyle(fontSize: 7.5, color: _footerGrey)),
        ],
      ),
      build: (context) => [
        pw.Table(
          border: pw.TableBorder.all(color: _grid, width: 0.4),
          columnWidths: {
            for (var c = 0; c < widths.length; c++)
              c: pw.FixedColumnWidth(widths[c] * PdfPageFormat.mm),
          },
          children: [headerRow, ...bodyRows],
        ),
      ],
    ));

    return pdf.save();
  }

  static Future<pw.Font> _loadFont(String file) async =>
      pw.Font.ttf(await rootBundle.load('lib/assets/fonts/$file'));
}
