import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:image/image.dart' as img;
import 'package:multimax/app/data/providers/stock_sheet_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
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
const _rack = 'KA-WH-DXB1-21A';

/// Remembers the format in memory, like the StorageService-backed store.
class _MemoryFormatStore implements SheetFormatStore {
  SheetFormat? saved;

  @override
  SheetFormat read() => saved ?? SheetFormat.excel;

  @override
  void write(SheetFormat f) => saved = f;
}

/// In-memory stand-in for the GetStorage box used by StorageService.
class _FakeBox {
  final Map<String, dynamic> m = {};
  T? read<T>(String key) => m[key] as T?;
  Future<void> write(String key, dynamic value) async => m[key] = value;
  bool hasData(String key) => m.containsKey(key);
  Future<void> remove(String key) async => m.remove(key);
}

class _FakeDecoder implements PhotoDecoder {
  _FakeDecoder(this.codes, {this.unsupported = false});
  final Map<String, List<String>?> codes;
  final bool unsupported;
  final Set<String> throwFor = {};
  int calls = 0;
  bool disposed = false;

  /// When set, every decode waits for it.
  Completer<void>? gate;

  @override
  Future<List<String>?> decode(String path) async {
    calls++;
    await gate?.future;
    if (unsupported) throw UnsupportedError('no');
    if (throwFor.contains(path)) throw Exception('boom');
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

  /// When set, the stock call waits for it.
  Completer<void>? stockGate;

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
    await stockGate?.future;
    final error = stockError;
    if (error != null) {
      stockError = null;
      throw error;
    }
    return [
      for (final c in codes)
        {'item_code': c, 'bal_qty': stock[c] ?? 0, 'rack': _rack},
    ];
  }
}

void main() {
  late Directory tmp;
  late List<List<XFile>> shared;
  late List<StockSheetDocument> pdfDocs;

  Future<Uint8List?> Function(String)? thumbOverride;

  /// When set, the PDF writer waits for it.
  Completer<void>? pdfGate;

  /// When set, the next share throws it.
  Object? shareError;

  /// When set, the PDF writer throws it.
  Object? pdfError;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('stock_sheet_ctrl');
    shared = [];
    pdfDocs = [];
    thumbOverride = null;
    pdfGate = null;
    shareError = null;
    pdfError = null;
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  StockSheetController make(
    _FakeDecoder decoder,
    _FakeProvider provider, {
    SheetFormatStore? store,
  }) => StockSheetController(
    formatStore: store ?? _MemoryFormatStore(),
    decoderFactory: () => decoder,
    provider: provider,
    shareFiles: (f) async {
      final error = shareError;
      if (error != null) {
        shareError = null;
        throw error;
      }
      shared.add(f);
    },
    now: () => DateTime(2026, 11, 17, 9, 5),
    tempDir: () async => tmp,
    writePdf: (doc) async {
      await pdfGate?.future;
      final error = pdfError;
      if (error != null) throw error;
      pdfDocs.add(doc);
      return Uint8List.fromList([1, 2, 3]);
    },
    makeThumbnail:
        thumbOverride ??
        (p) async =>
            Uint8List.fromList(img.encodeJpg(img.Image(width: 4, height: 4))),
  );

  /// Reads [paths], then makes the sheet in [format] from the review as is.
  Future<void> run(
    StockSheetController c,
    List<String> paths,
    SheetFormat format,
  ) async {
    await c.start(paths);
    await c.makeSheet(format);
  }

  List<String> reviewPaths(StockSheetController c) =>
      c.review.map((e) => e.path).toList();

  test('more than 100 photos is refused and nothing is decoded', () async {
    final decoder = _FakeDecoder({});
    final c = make(decoder, _FakeProvider());
    await c.start(List.generate(101, (i) => 'p$i.jpg'));
    expect(c.phase.value, StockSheetPhase.error);
    expect(
      c.errorMessage.value,
      'Share up to 100 photos at a time (you shared 101).',
    );
    expect(decoder.calls, 0);
    expect(c.canRetry, isFalse);
  });

  test('start reads and checks, then waits in review in share order', () async {
    final decoder = _FakeDecoder({
      'known.jpg': [_ean(_a)],
      'out.jpg': [_ean(_b)],
      'bad.jpg': null,
    });
    final provider = _FakeProvider(stock: {_a: 4});
    final c = make(decoder, provider);
    await c.start(['known.jpg', 'out.jpg', 'bad.jpg']);

    expect(c.phase.value, StockSheetPhase.reviewing);
    expect(c.busy.value, isFalse);
    expect(reviewPaths(c), ['known.jpg', 'out.jpg', 'bad.jpg']);
    expect(c.review.map((e) => e.included), [true, true, false]);
    expect(c.review[2].decodeFailed, isTrue);
    final known = c.review[0].items.single;
    expect(known.info.itemName, 'Item $_a');
    expect(known.stock!.total, 4);
    expect(known.stock!.racks, [const RackQty(rack: _rack, qty: 4)]);
    expect(c.review[1].items.single.stock!.outOfStock, isTrue);
    expect(c.sheetPhotoCount, 2);
    expect(provider.stockCalls, 1);
    // Nothing is written or shared until Make sheet.
    expect(shared, isEmpty);
    expect(c.result.value, isNull);
    expect(tmp.listSync(), isEmpty);
  });

  test('all in stock builds at once: one xlsx, or two for both', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    });
    final provider = _FakeProvider(stock: {_a: 5});
    final c = make(decoder, provider);
    await run(c, ['a.jpg'], SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.done);
    expect(shared.single.single.name, 'Items-20261117-0905.xlsx');
    expect(
      shared.single.single.mimeType,
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    expect(File(shared.single.single.path).existsSync(), isTrue);
    expect(c.decoded.value, 1);
    expect(c.busy.value, isFalse);

    await run(c, ['a.jpg'], SheetFormat.both);
    expect(shared.last.map((f) => f.name), [
      'Items-20261117-0905.xlsx',
      'Items-20261117-0905.pdf',
    ]);
    expect(
      pdfDocs.single.subtitle,
      '17/11/2026 09:05 · 1 photo · 1 item · 0 out of stock',
    );
    expect(pdfDocs.single.title, 'Items');
    expect(pdfDocs.single.showStatus, isFalse);

    final path = shared.last.first.path;
    c.onClose();
    expect(File(path).existsSync(), isFalse);
  });

  test('makeSheet(pdf) makes only a PDF and is remembered', () async {
    final store = _MemoryFormatStore();
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    });
    final c = make(decoder, _FakeProvider(stock: {_a: 1}), store: store);
    c.onInit();
    expect(c.format.value, SheetFormat.excel);

    await run(c, ['a.jpg'], SheetFormat.pdf);
    expect(c.phase.value, StockSheetPhase.done);
    expect(shared.single.map((f) => f.name), ['Items-20261117-0905.pdf']);
    expect(shared.single.single.mimeType, 'application/pdf');
    expect(c.format.value, SheetFormat.pdf);
    expect(store.saved, SheetFormat.pdf);

    final next = make(_FakeDecoder({}), _FakeProvider(), store: store);
    next.onInit();
    expect(next.format.value, SheetFormat.pdf);
  });

  test('the rows follow the review order', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
      'b.jpg': [_ean(_b)],
    });
    final c = make(decoder, _FakeProvider(stock: {_a: 1, _b: 1}));
    await c.start(['a.jpg', 'b.jpg']);
    c.reorder(0, 2);
    expect(reviewPaths(c), ['b.jpg', 'a.jpg']);

    await c.makeSheet(SheetFormat.pdf);
    expect(pdfDocs.single.rows.map((r) => r.barcode), [_ean(_b), _ean(_a)]);
    expect(pdfDocs.single.rows.map((r) => r.photoPath), ['b.jpg', 'a.jpg']);
  });

  test('reorder, then a switch, keeps the order', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
      'b.jpg': [_ean(_b)],
    });
    final c = make(decoder, _FakeProvider(stock: {_a: 1, _b: 1}));
    await c.start(['a.jpg', 'b.jpg']);
    c.reorder(0, 2);
    c.setIncluded(1, false);
    expect(reviewPaths(c), ['b.jpg', 'a.jpg']);
    expect(c.review.map((e) => e.included), [true, false]);

    c.setItemIncluded(1, 0, true);
    expect(reviewPaths(c), ['b.jpg', 'a.jpg']);
    expect(c.review.map((e) => e.included), [true, true]);
  });

  test('a switched-off out-of-stock photo asks nothing', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
      'b.jpg': [_ean(_b)],
    });
    final c = make(decoder, _FakeProvider(stock: {_a: 1}));
    await c.start(['a.jpg', 'b.jpg']);
    c.setIncluded(1, false);

    await c.makeSheet(SheetFormat.pdf);
    expect(c.phase.value, StockSheetPhase.done);
    expect(pdfDocs.single.rows.map((r) => r.barcode), [_ean(_a)]);
    expect(c.result.value!.rows, hasLength(1));
    // A photo the user switched off is in neither list.
    expect(c.result.value!.unresolved, isEmpty);
  });

  test('the subtitle counts only the photos on the sheet', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
      'b.jpg': [_ean(_b)],
    });
    final c = make(decoder, _FakeProvider(stock: {_a: 1, _b: 1}));
    await c.start(['a.jpg', 'b.jpg']);
    c.setIncluded(0, false);
    expect(c.sheetPhotoCount, 1);

    await c.makeSheet(SheetFormat.pdf);
    expect(
      pdfDocs.single.subtitle,
      '17/11/2026 09:05 · 1 photo · 1 item · 0 out of stock',
    );
  });

  test('review edits and Make sheet are ignored outside the review', () async {
    final store = _MemoryFormatStore();
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
      'b.jpg': [_ean(_b)],
    });
    final c = make(decoder, _FakeProvider(stock: {_a: 1, _b: 1}), store: store);

    // Idle: nothing to edit, nothing to make.
    c.reorder(0, 1);
    c.setIncluded(0, false);
    c.setItemIncluded(0, 0, false);
    await c.makeSheet(SheetFormat.pdf);
    expect(c.phase.value, StockSheetPhase.idle);
    expect(store.saved, isNull);

    await run(c, ['a.jpg', 'b.jpg'], SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.done);
    final before = c.review.toList();
    c.reorder(0, 2);
    c.setIncluded(0, false);
    c.setItemIncluded(1, 0, false);
    expect(c.review, orderedEquals(before));
    await c.makeSheet(SheetFormat.pdf);
    expect(shared, hasLength(1));
    expect(store.saved, SheetFormat.excel);
  });

  test('Make sheet with every photo switched off does nothing', () async {
    final store = _MemoryFormatStore();
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
      'bad.jpg': null,
    });
    final c = make(decoder, _FakeProvider(stock: {_a: 1}), store: store);
    await c.start(['a.jpg', 'bad.jpg']);
    c.setIncluded(0, false);
    expect(c.sheetPhotoCount, 0);

    await c.makeSheet(SheetFormat.pdf);
    expect(c.phase.value, StockSheetPhase.reviewing);
    expect(store.saved, isNull);
    expect(c.format.value, SheetFormat.excel);
    expect(shared, isEmpty);
  });

  test('out of stock asks; dismissing returns to the review intact', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    });
    final c = make(decoder, _FakeProvider());
    await c.start(['a.jpg']);
    final before = c.review.toList();
    await c.makeSheet(SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.awaitingChoice);
    expect(c.result.value!.outOfStockCount, 1);

    await c.chooseOutOfStock(null);
    expect(c.phase.value, StockSheetPhase.reviewing);
    expect(c.result.value, isNull);
    expect(c.review, orderedEquals(before));
    expect(shared, isEmpty);
    expect(tmp.listSync(), isEmpty);
  });

  test('leaveOut drops red rows and hides the status column', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
      'b.jpg': [_ean(_b)],
    });
    final c = make(decoder, _FakeProvider(stock: {_b: 3}));
    await run(c, ['a.jpg', 'b.jpg'], SheetFormat.pdf);
    expect(c.phase.value, StockSheetPhase.awaitingChoice);
    await c.chooseOutOfStock(OutOfStockChoice.leaveOut);
    expect(c.phase.value, StockSheetPhase.done);
    expect(pdfDocs.single.rows.every((r) => !r.outOfStock), isTrue);
    expect(pdfDocs.single.rows, hasLength(1));
    expect(pdfDocs.single.showStatus, isFalse);
    // The out-of-stock row is not in the file, so the count is not shown.
    expect(pdfDocs.single.subtitle, '17/11/2026 09:05 · 2 photos · 1 item');
  });

  test('plural counts in the subtitle', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a), _ean(_b)],
      'b.jpg': [_ean(_b)],
    });
    final c = make(decoder, _FakeProvider(stock: {_a: 1}));
    await run(c, ['a.jpg', 'b.jpg'], SheetFormat.pdf);
    await c.chooseOutOfStock(OutOfStockChoice.includePlain);
    expect(
      pdfDocs.single.subtitle,
      '17/11/2026 09:05 · 2 photos · 3 items · 2 out of stock',
    );
  });

  test('includeRed highlights and shows status', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    });
    final c = make(decoder, _FakeProvider());
    await run(c, ['a.jpg'], SheetFormat.pdf);
    await c.chooseOutOfStock(OutOfStockChoice.includeRed);
    expect(pdfDocs.single.highlightOutOfStock, isTrue);
    expect(pdfDocs.single.showStatus, isTrue);
    expect(
      pdfDocs.single.subtitle,
      '17/11/2026 09:05 · 1 photo · 1 item · 1 out of stock',
    );
    await run(c, ['a.jpg'], SheetFormat.pdf);
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
    await c.start(['a.jpg']);
    expect(c.phase.value, StockSheetPhase.error);
    expect(
      c.errorMessage.value,
      "Couldn't reach the ERP. Check the connection and try again.",
    );
    expect(decoder.calls, 1);
    await c.retry();
    expect(decoder.calls, 1);
    expect(provider.stockCalls, 2);
    expect(c.phase.value, StockSheetPhase.reviewing);
    expect(c.errorMessage.value, isNull);
    expect(reviewPaths(c), ['a.jpg']);

    // Retry belongs to the error screen only.
    await c.retry();
    expect(provider.stockCalls, 2);

    await c.makeSheet(SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.done);
    expect(shared, hasLength(1));
  });

  test('an unreadable photo is listed and the run completes', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
      'bad.jpg': null,
    });
    final c = make(decoder, _FakeProvider(stock: {_a: 1}));
    await run(c, ['bad.jpg', 'a.jpg'], SheetFormat.excel);
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
    await c.start(['a.jpg']);
    expect(c.phase.value, StockSheetPhase.error);
    expect(c.errorMessage.value, "You don't have access to stock levels.");
    expect(c.result.value, isNull);
    expect(c.review, isEmpty);
  });

  test('UnsupportedError from the decoder gives the device message', () async {
    final decoder = _FakeDecoder({}, unsupported: true);
    final c = make(decoder, _FakeProvider());
    await c.start(['a.jpg']);
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
    final first = c.start(['a.jpg']);
    expect(c.busy.value, isTrue);
    await c.start(['a.jpg']);
    await first;
    expect(decoder.calls, 1);
    await c.makeSheet(SheetFormat.excel);
    expect(shared, hasLength(1));

    c.reset();
    expect(c.phase.value, StockSheetPhase.idle);
    expect(c.result.value, isNull);
    expect(c.review, isEmpty);
    expect(c.files, isEmpty);
    expect(c.thumbnails, isEmpty);
    expect(c.decoded.value, 0);
    expect(c.total.value, 0);
  });

  test('a decoder exception marks only that photo unreadable', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    })..throwFor.add('bad.jpg');
    final c = make(decoder, _FakeProvider(stock: {_a: 1}));
    await c.start(['bad.jpg', 'a.jpg']);
    expect(c.phase.value, StockSheetPhase.reviewing);
    expect(c.review.map((e) => e.decodeFailed), [true, false]);
    await c.makeSheet(SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.done);
    expect(
      c.result.value!.unresolved.single.reason,
      UnresolvedReason.unreadable,
    );
    expect(decoder.calls, 2);
  });

  test('a thumbnail exception still completes the run', () async {
    thumbOverride = (_) async => throw Exception('thumb');
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    });
    final c = make(decoder, _FakeProvider(stock: {_a: 1}));
    await run(c, ['a.jpg'], SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.done);
    expect(c.thumbnails, isEmpty);
  });

  test('a build failure returns to the review with the message', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    });
    pdfError = Exception('no pdf');
    final c = make(decoder, _FakeProvider(stock: {_a: 1}));
    await c.start(['a.jpg']);
    final before = c.review.toList();
    await c.makeSheet(SheetFormat.both);

    expect(c.phase.value, StockSheetPhase.reviewing);
    expect(c.errorMessage.value, "Couldn't build the sheet. Try again.");
    expect(c.review, orderedEquals(before));
    expect(c.result.value, isNull);
    expect(c.files, isEmpty);
    expect(tmp.listSync(), isEmpty);
    expect(shared, isEmpty);
    expect(c.busy.value, isFalse);

    // The next Make sheet clears the message.
    pdfError = null;
    await c.makeSheet(SheetFormat.pdf);
    expect(c.phase.value, StockSheetPhase.done);
    expect(c.errorMessage.value, isNull);
    expect(shared.single.single.name, 'Items-20261117-0905.pdf');
  });

  test('a share failure returns to the review with the message', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
    });
    final provider = _FakeProvider(stock: {_a: 1});
    shareError = Exception('no share sheet');
    final c = make(decoder, provider);
    await run(c, ['a.jpg'], SheetFormat.excel);

    expect(c.phase.value, StockSheetPhase.reviewing);
    expect(c.errorMessage.value, StockSheetController.shareFailedMessage);
    expect(reviewPaths(c), ['a.jpg']);
    expect(c.result.value, isNull);
    expect(c.files, isEmpty);
    expect(tmp.listSync(), isEmpty);
    expect(shared, isEmpty);

    await c.makeSheet(SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.done);
    expect(c.errorMessage.value, isNull);
    expect(shared.single.single.name, 'Items-20261117-0905.xlsx');
    expect(provider.stockCalls, 1);
    expect(decoder.calls, 1);
  });

  test(
    'Share files shares again; a failure there stays on the result',
    () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
      });
      final provider = _FakeProvider(stock: {_a: 1});
      final c = make(decoder, provider);
      await run(c, ['a.jpg'], SheetFormat.excel);
      expect(shared, hasLength(1));

      await c.shareAgain();
      expect(shared, hasLength(2));
      expect(shared.last.single.name, 'Items-20261117-0905.xlsx');
      expect(c.errorMessage.value, isNull);
      expect(c.sharing.value, isFalse);
      expect(provider.stockCalls, 1);

      shareError = Exception('again');
      await c.shareAgain();
      expect(c.errorMessage.value, StockSheetController.shareFailedMessage);
      expect(c.phase.value, StockSheetPhase.done);
      expect(File(c.files.single.path).existsSync(), isTrue);
      expect(c.sharing.value, isFalse);
    },
  );

  group('remembered format in StorageService', () {
    tearDown(Get.reset);

    test('missing or unknown reads as Excel; a choice round-trips', () {
      final box = _FakeBox();
      Get.put(StorageService.withStorage(box));
      const store = StorageSheetFormatStore();

      expect(store.read(), SheetFormat.excel);
      store.write(SheetFormat.both);
      expect(box.m['stock_sheet_last_format'], 'both');
      expect(store.read(), SheetFormat.both);
      store.write(SheetFormat.pdf);
      expect(store.read(), SheetFormat.pdf);
      box.m['stock_sheet_last_format'] = 'word';
      expect(store.read(), SheetFormat.excel);
    });
  });

  group('closing the screen mid-run', () {
    List<FileSystemEntity> written() => tmp.listSync();

    test('stops decoding, disposes the decoder and shares nothing', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'b.jpg': [_ean(_b)],
      })..gate = Completer<void>();
      final provider = _FakeProvider(stock: {_a: 1, _b: 1});
      final c = make(decoder, provider);
      final run = c.start(['a.jpg', 'b.jpg']);
      await pumpEventQueue();
      expect(decoder.calls, 1);

      c.onClose();
      decoder.gate!.complete();
      await run;

      expect(decoder.calls, 1);
      expect(decoder.disposed, isTrue);
      expect(provider.stockCalls, 0);
      expect(shared, isEmpty);
      expect(written(), isEmpty);
      expect(c.busy.value, isFalse);
    });

    test('during a thumbnail: the next photo is not decoded', () async {
      final thumbGate = Completer<void>();
      thumbOverride = (_) async {
        await thumbGate.future;
        return null;
      };
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'b.jpg': [_ean(_b)],
      });
      final provider = _FakeProvider(stock: {_a: 1, _b: 1});
      final c = make(decoder, provider);
      final run = c.start(['a.jpg', 'b.jpg']);
      await pumpEventQueue();
      expect(decoder.calls, 1);

      c.onClose();
      thumbGate.complete();
      await run;

      expect(decoder.calls, 1);
      expect(decoder.disposed, isTrue);
      expect(provider.stockCalls, 0);
      expect(shared, isEmpty);
    });

    test('during the stock check: no share and no files', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
      });
      final provider = _FakeProvider(stock: {_a: 1})
        ..stockGate = Completer<void>();
      final c = make(decoder, provider);
      final run = c.start(['a.jpg']);
      await pumpEventQueue();
      expect(provider.stockCalls, 1);

      c.onClose();
      provider.stockGate!.complete();
      await run;

      expect(c.review, isEmpty);
      expect(c.phase.value, isNot(StockSheetPhase.reviewing));
      await c.makeSheet(SheetFormat.both);
      expect(shared, isEmpty);
      expect(pdfDocs, isEmpty);
      expect(written(), isEmpty);
      expect(c.files, isEmpty);
    });

    test('while writing: files already written are removed', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
      });
      pdfGate = Completer<void>();
      final c = make(decoder, _FakeProvider(stock: {_a: 1}));
      await c.start(['a.jpg']);
      final run = c.makeSheet(SheetFormat.both);
      for (var i = 0; i < 50 && written().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(written().map((f) => f.uri.pathSegments.last), [
        'Items-20261117-0905.xlsx',
      ]);

      c.onClose();
      pdfGate!.complete();
      await run;

      expect(shared, isEmpty);
      expect(written(), isEmpty);
      expect(c.files, isEmpty);
    });

    test('an out-of-stock choice after close builds nothing', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
      });
      final c = make(decoder, _FakeProvider());
      await run(c, ['a.jpg'], SheetFormat.excel);
      expect(c.phase.value, StockSheetPhase.awaitingChoice);

      c.onClose();
      await c.chooseOutOfStock(OutOfStockChoice.includeRed);

      expect(shared, isEmpty);
      expect(written(), isEmpty);
    });

    test('Make sheet after close writes nothing', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
      });
      final c = make(decoder, _FakeProvider(stock: {_a: 1}));
      await c.start(['a.jpg']);
      expect(c.phase.value, StockSheetPhase.reviewing);

      c.onClose();
      await c.makeSheet(SheetFormat.both);

      expect(shared, isEmpty);
      expect(pdfDocs, isEmpty);
      expect(written(), isEmpty);
    });
  });

  group('shared photo copies', () {
    late Directory outside;

    setUp(() async {
      outside = await Directory.systemTemp.createTemp('stock_sheet_gallery');
    });

    tearDown(() async {
      if (outside.existsSync()) await outside.delete(recursive: true);
    });

    File photo(Directory dir, String name) =>
        File('${dir.path}/$name')..writeAsBytesSync([1, 2, 3]);

    test('on close, photos in the temp folder go; others stay', () async {
      final cached = photo(tmp, 'shared_1.jpg');
      final nested = photo(
        Directory('${tmp.path}/sub')..createSync(),
        'shared_2.jpg',
      );
      final gallery = photo(outside, 'IMG_0001.jpg');
      // Inside the temp folder by text only: it resolves to the gallery photo.
      final sneaky =
          '${tmp.path}/../${outside.path.split('/').last}/IMG_0001.jpg';
      final c = make(_FakeDecoder({}), _FakeProvider());

      expect(
        c.takeShare([cached.path, nested.path, gallery.path, sneaky]),
        isTrue,
      );
      c.onClose();
      await pumpEventQueue();

      expect(cached.existsSync(), isFalse);
      expect(nested.existsSync(), isFalse);
      expect(gallery.existsSync(), isTrue);
    });

    test('photos of a run and of an earlier share are all removed', () async {
      final first = photo(tmp, 'first.jpg');
      final second = photo(tmp, 'second.jpg');
      final decoder = _FakeDecoder({
        second.path: [_ean(_a)],
      });
      final c = make(decoder, _FakeProvider(stock: {_a: 1}));
      c.takeShare([first.path]);
      c.takeShare([second.path]);
      await c.start([second.path]);
      expect(c.phase.value, StockSheetPhase.reviewing);
      expect(first.existsSync(), isTrue);
      expect(second.existsSync(), isTrue);

      c.onClose();
      await pumpEventQueue();

      expect(first.existsSync(), isFalse);
      expect(second.existsSync(), isFalse);
    });

    test('a photo already gone does not stop the others', () async {
      final kept = photo(tmp, 'b.jpg');
      final c = make(_FakeDecoder({}), _FakeProvider());
      c.takeShare(['${tmp.path}/missing.jpg', kept.path]);
      c.onClose();
      await pumpEventQueue();
      expect(kept.existsSync(), isFalse);
    });
  });
}
