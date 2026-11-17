import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:multimax/app/data/providers/stock_sheet_provider.dart';
import 'package:multimax/app/modules/stock_sheet/logic/photo_decoder.dart';
import 'package:multimax/app/modules/stock_sheet/model/stock_sheet_models.dart';
import 'package:multimax/app/modules/stock_sheet/stock_sheet_controller.dart';
import 'package:share_plus/share_plus.dart';

/// A checksum-valid EAN-8 for a seven-digit item code.
String _ean(String seven) {
  var sum = 0;
  for (var i = 0; i < 7; i++) {
    sum += int.parse(seven[i]) * (i.isEven ? 3 : 1);
  }
  return '$seven${(10 - sum % 10) % 10}';
}

const _a = '1000001';
const _b = '1000002';

class _FakeDecoder implements PhotoDecoder {
  _FakeDecoder(this.codes, {this.unsupported = false});
  final Map<String, List<String>?> codes;
  final bool unsupported;
  int calls = 0;
  bool disposed = false;

  @override
  Future<List<String>?> decode(String path) async {
    calls++;
    if (unsupported) throw UnsupportedError('no');
    return codes[path];
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class _FakeProvider extends StockSheetProvider {
  _FakeProvider({this.stock = const {}});
  final Map<String, double> stock;
  final List<String> known = const [_a, _b];
  Object? stockError;
  int stockCalls = 0;

  @override
  Future<Map<String, ItemInfo>> fetchItems(List<String> codes) async => {
    for (final c in codes.where(known.contains))
      c: ItemInfo(itemCode: c, itemName: 'Item $c'),
  };

  @override
  Future<List<Map<String, dynamic>>> fetchFinishedGoodsStock(
    List<String> codes,
  ) async {
    stockCalls++;
    final error = stockError;
    if (error != null) {
      stockError = null;
      throw error;
    }
    return [
      for (final c in codes) {'item_code': c, 'bal_qty': stock[c] ?? 0},
    ];
  }
}

void main() {
  late Directory tmp;
  late List<List<XFile>> shared;
  late List<StockSheetDocument> pdfDocs;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('stock_sheet_ctrl');
    shared = [];
    pdfDocs = [];
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  StockSheetController make(_FakeDecoder decoder, _FakeProvider provider) =>
      StockSheetController(
        decoderFactory: () => decoder,
        provider: provider,
        shareFiles: (f) async => shared.add(f),
        now: () => DateTime(2026, 11, 17, 9, 5),
        tempDir: () async => tmp,
        writePdf: (doc) async {
          pdfDocs.add(doc);
          return Uint8List.fromList([1, 2, 3]);
        },
        makeThumbnail: (p) async =>
            Uint8List.fromList(img.encodeJpg(img.Image(width: 4, height: 4))),
      );

  test('more than 100 photos is refused and nothing is decoded', () async {
    final decoder = _FakeDecoder({});
    final c = make(decoder, _FakeProvider());
    await c.start(List.generate(101, (i) => 'p$i.jpg'), SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.error);
    expect(
      c.errorMessage.value,
      'Share up to 100 photos at a time (you shared 101).',
    );
    expect(decoder.calls, 0);
  });

  test('all in stock builds at once: one xlsx, or two for both', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    });
    final provider = _FakeProvider(stock: {_a: 5});
    final c = make(decoder, provider);
    await c.start(['a.jpg'], SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.done);
    expect(shared.single.single.name, 'stock-sheet-20261117-0905.xlsx');
    expect(
      shared.single.single.mimeType,
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    expect(File(shared.single.single.path).existsSync(), isTrue);
    expect(c.decoded.value, 1);
    expect(c.busy.value, isFalse);

    await c.start(['a.jpg'], SheetFormat.both);
    expect(shared.last.map((f) => f.name), [
      'stock-sheet-20261117-0905.xlsx',
      'stock-sheet-20261117-0905.pdf',
    ]);
    expect(
      pdfDocs.single.subtitle,
      '17/11/2026 09:05 · 1 photos · 1 items · 0 out of stock',
    );
    expect(pdfDocs.single.title, 'Stock sheet');
    expect(pdfDocs.single.showStatus, isFalse);

    final path = shared.last.first.path;
    c.onClose();
    expect(File(path).existsSync(), isFalse);
  });

  test('out of stock asks; dismissing cancels without sharing', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    });
    final c = make(decoder, _FakeProvider());
    await c.start(['a.jpg'], SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.awaitingChoice);
    expect(c.result.value!.outOfStockCount, 1);
    await c.chooseOutOfStock(null);
    expect(c.phase.value, StockSheetPhase.idle);
    expect(shared, isEmpty);
  });

  test('leaveOut drops red rows and hides the status column', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
      'b.jpg': [_ean(_b)],
    });
    final c = make(decoder, _FakeProvider(stock: {_b: 3}));
    await c.start(['a.jpg', 'b.jpg'], SheetFormat.pdf);
    expect(c.phase.value, StockSheetPhase.awaitingChoice);
    await c.chooseOutOfStock(OutOfStockChoice.leaveOut);
    expect(c.phase.value, StockSheetPhase.done);
    expect(pdfDocs.single.rows.every((r) => !r.outOfStock), isTrue);
    expect(pdfDocs.single.rows, hasLength(1));
    expect(pdfDocs.single.showStatus, isFalse);
    expect(
      pdfDocs.single.subtitle.endsWith('1 items · 1 out of stock'),
      isTrue,
    );
  });

  test('includeRed highlights and shows status', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    });
    final c = make(decoder, _FakeProvider());
    await c.start(['a.jpg'], SheetFormat.pdf);
    await c.chooseOutOfStock(OutOfStockChoice.includeRed);
    expect(pdfDocs.single.highlightOutOfStock, isTrue);
    expect(pdfDocs.single.showStatus, isTrue);
    await c.start(['a.jpg'], SheetFormat.pdf);
    await c.chooseOutOfStock(OutOfStockChoice.includePlain);
    expect(pdfDocs.last.highlightOutOfStock, isFalse);
    expect(pdfDocs.last.showStatus, isTrue);
  });

  test('retry after a stock failure does not decode again', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    });
    final provider = _FakeProvider(stock: {_a: 2})..stockError = Exception('x');
    final c = make(decoder, provider);
    await c.start(['a.jpg'], SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.error);
    expect(
      c.errorMessage.value,
      "Couldn't reach the ERP. Check the connection and try again.",
    );
    expect(decoder.calls, 1);
    await c.retry();
    expect(decoder.calls, 1);
    expect(c.phase.value, StockSheetPhase.done);
    expect(c.errorMessage.value, isNull);
    expect(shared, hasLength(1));
  });

  test('an unreadable photo is listed and the run completes', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
      'bad.jpg': null,
    });
    final c = make(decoder, _FakeProvider(stock: {_a: 1}));
    await c.start(['bad.jpg', 'a.jpg'], SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.done);
    expect(
      c.result.value!.unresolved.single.reason,
      UnresolvedReason.unreadable,
    );
    expect(c.thumbnails.keys, containsAll(['bad.jpg', 'a.jpg']));
  });

  test('a 403 shows the access-denied text', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    });
    final provider = _FakeProvider()..stockError = const StockAccessDenied();
    final c = make(decoder, provider);
    await c.start(['a.jpg'], SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.error);
    expect(c.errorMessage.value, "You don't have access to stock levels.");
    expect(c.result.value, isNull);
  });

  test('UnsupportedError from the decoder gives the device message', () async {
    final decoder = _FakeDecoder({}, unsupported: true);
    final c = make(decoder, _FakeProvider());
    await c.start(['a.jpg'], SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.error);
    expect(
      c.errorMessage.value,
      "Reading barcodes from photos isn't supported on this device.",
    );
    expect(decoder.disposed, isTrue);
  });

  test('start while busy is a no-op; reset clears when idle', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    });
    final c = make(decoder, _FakeProvider(stock: {_a: 1}));
    final first = c.start(['a.jpg'], SheetFormat.excel);
    expect(c.busy.value, isTrue);
    await c.start(['a.jpg'], SheetFormat.excel);
    await first;
    expect(decoder.calls, 1);
    expect(shared, hasLength(1));

    c.reset();
    expect(c.phase.value, StockSheetPhase.idle);
    expect(c.result.value, isNull);
    expect(c.files, isEmpty);
    expect(c.thumbnails, isEmpty);
    expect(c.decoded.value, 0);
    expect(c.total.value, 0);
  });
}
