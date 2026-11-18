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
  final decoded = <String>[];
  bool disposed = false;

  /// When set, every decode waits for it.
  Completer<void>? gate;

  @override
  Future<List<String>?> decode(String path) async {
    calls++;
    decoded.add(path);
    await gate?.future;
    if (unsupported) throw UnsupportedError('no');
    if (throwFor.contains(path)) throw Exception('boom');
    return codes[path];
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class _FakeProvider extends StockSheetProvider {
  _FakeProvider({this.stock = const {}, this.known = const [_a, _b]});
  final Map<String, double> stock;
  final List<String> known;
  Object? stockError;
  int stockCalls = 0;

  /// Every code list passed to [fetchItems] and [fetchFinishedGoodsStock].
  final itemRequests = <List<String>>[];
  final stockRequests = <List<String>>[];

  /// When set, the next Item call throws it.
  Object? itemsError;

  /// When set, the Item call waits for it.
  Completer<void>? itemsGate;

  /// When set, only the next Item call waits for it.
  Completer<void>? itemsGateOnce;

  /// When set, the stock call waits for it.
  Completer<void>? stockGate;

  @override
  Future<Map<String, ItemInfo>> fetchItems(List<String> codes) async {
    itemRequests.add(List.of(codes));
    await itemsGate?.future;
    final once = itemsGateOnce;
    itemsGateOnce = null;
    await once?.future;
    final error = itemsError;
    if (error != null) {
      itemsError = null;
      throw error;
    }
    return {
      for (final c in codes.where(known.contains))
        c: ItemInfo(itemCode: c, itemName: 'Item $c'),
    };
  }

  @override
  Future<List<Map<String, dynamic>>> fetchFinishedGoodsStock(
    List<String> codes,
  ) async {
    stockCalls++;
    stockRequests.add(List.of(codes));
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

  /// Fixed fingerprints by path; any other path is its own content.
  late Map<String, String> fingerprints;

  Future<Uint8List?> Function(String)? thumbOverride;

  /// When set, the PDF writer waits for it.
  Completer<void>? pdfGate;

  /// When set, the next share throws it.
  Object? shareError;

  /// When set, the PDF writer throws it.
  Object? pdfError;

  late List<(String, Uint8List)> saveCalls;
  late List<bool> saveAnswers;
  Object? saveError;
  Completer<void>? saveGate;

  setUp(() async {
    saveCalls = [];
    saveAnswers = [];
    saveError = null;
    saveGate = null;
    tmp = await Directory.systemTemp.createTemp('stock_sheet_ctrl');
    shared = [];
    pdfDocs = [];
    fingerprints = {};
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
    Future<List<String>> Function()? extraRoots,
    Future<void> Function()? clearPickerFiles,
  }) => StockSheetController(
    clearPickerFiles: clearPickerFiles ?? () async {},
    formatStore: store ?? _MemoryFormatStore(),
    decoderFactory: () => decoder,
    provider: provider,
    saveFile: (name, bytes) async {
      saveCalls.add((name, bytes));
      await saveGate?.future;
      final error = saveError;
      if (error != null) throw error;
      final answers = saveAnswers;
      return answers.isEmpty ? true : answers.removeAt(0);
    },
    shareFiles: (f) async {
      final error = shareError;
      if (error != null) {
        shareError = null;
        throw error;
      }
      shared.add(f);
    },
    now: () => DateTime(2026, 11, 17, 9, 5),
    fingerprint: (paths) async => {
      for (final path in paths) path: fingerprints[path] ?? 'fp:$path',
    },
    tempDir: () async => tmp,
    extraCleanupRoots: extraRoots ?? () async => const [],
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

  /// Waits for the clean-up after onClose, which deletes files for real.
  Future<void> untilGone(List<File> files) async {
    for (var i = 0; i < 200 && files.any((f) => f.existsSync()); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

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
    // Nothing is written or shared until Generate file.
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

  test('the subtitle counts only the photos in the file', () async {
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

  test(
    'review edits and Generate file are ignored outside the review',
    () async {
      final store = _MemoryFormatStore();
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'b.jpg': [_ean(_b)],
      });
      final c = make(
        decoder,
        _FakeProvider(stock: {_a: 1, _b: 1}),
        store: store,
      );

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
    },
  );

  test('Generate file with every photo switched off does nothing', () async {
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

  test('leaving out every item goes back to the review and says why', () async {
    final decoder = _FakeDecoder({
      'a.jpg': [_ean(_a)],
      'b.jpg': [_ean(_b)],
    });
    final c = make(decoder, _FakeProvider(stock: {_b: 2}));
    await c.start(['a.jpg', 'b.jpg']);
    c.setIncluded(1, false);
    await c.makeSheet(SheetFormat.excel);
    expect(c.phase.value, StockSheetPhase.awaitingChoice);

    await c.chooseOutOfStock(OutOfStockChoice.leaveOut);

    expect(c.phase.value, StockSheetPhase.reviewing);
    expect(c.errorMessage.value, 'Every photo in the file is out of stock.');
    expect(c.result.value, isNull);
    expect(c.files, isEmpty);
    expect(shared, isEmpty);
    expect(reviewPaths(c), ['a.jpg', 'b.jpg']);
    expect(c.busy.value, isFalse);
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

    // The next Generate file clears the message.
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

  group('Download', () {
    Future<StockSheetController> both() async {
      final c = make(
        _FakeDecoder({
          'a.jpg': [_ean(_a)],
        }),
        _FakeProvider(stock: {_a: 1}),
      );
      await run(c, ['a.jpg'], SheetFormat.both);
      return c;
    }

    test('download saves each file in order with its name', () async {
      final c = await both();
      final message = await c.download();
      expect(saveCalls.map((e) => e.$1).toList(), [
        'Items-20261117-0905.xlsx',
        'Items-20261117-0905.pdf',
      ]);
      expect(saveCalls.every((e) => e.$2.isNotEmpty), isTrue);
      expect(message, 'Saved 2 files.');
    });

    test('one file returns "Saved <name>."', () async {
      final c = make(
        _FakeDecoder({
          'a.jpg': [_ean(_a)],
        }),
        _FakeProvider(stock: {_a: 1}),
      );
      await run(c, ['a.jpg'], SheetFormat.excel);
      expect(await c.download(), 'Saved Items-20261117-0905.xlsx.');
    });

    test(
      'cancelling the second dialog keeps the first and returns null',
      () async {
        final c = await both();
        saveAnswers = [true, false];
        expect(await c.download(), isNull);
        expect(saveCalls, hasLength(2));
      },
    );

    test('a saver error returns saveFailedMessage and stops', () async {
      final c = await both();
      saveError = Exception('disk');
      expect(await c.download(), StockSheetController.saveFailedMessage);
      expect(saveCalls, hasLength(1));
      expect(c.downloading.value, isFalse);
    });

    test('download while running or while sharing does nothing', () async {
      final c = await both();
      saveGate = Completer<void>();
      final first = c.download();
      await Future<void>.delayed(Duration.zero);
      expect(await c.download(), isNull);
      saveGate!.complete();
      expect(await first, 'Saved 2 files.');
      expect(saveCalls, hasLength(2));

      saveCalls.clear();
      c.sharing.value = true;
      expect(await c.download(), isNull);
      expect(saveCalls, isEmpty);
    });

    test('sharing does nothing while downloading', () async {
      final c = await both();
      final before = shared.length;
      saveGate = Completer<void>();
      final first = c.download();
      await Future<void>.delayed(Duration.zero);
      await c.shareAgain();
      expect(shared, hasLength(before));
      saveGate!.complete();
      await first;
    });

    test('downloading is true during the run and false after', () async {
      final c = await both();
      saveGate = Completer<void>();
      final run1 = c.download();
      await Future<void>.delayed(Duration.zero);
      expect(c.downloading.value, isTrue);
      saveGate!.complete();
      await run1;
      expect(c.downloading.value, isFalse);
    });
  });

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

    test('Generate file after close writes nothing', () async {
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
        c.offerShare([cached.path, nested.path, gallery.path, sneaky]),
        ShareOffer.started,
      );
      c.onClose();
      await untilGone([cached, nested]);

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
      c.offerShare([first.path]);
      await pumpEventQueue();
      c.offerShare([second.path]);
      await c.start([second.path]);
      expect(c.phase.value, StockSheetPhase.reviewing);
      expect(first.existsSync(), isTrue);
      expect(second.existsSync(), isTrue);

      c.onClose();
      await untilGone([first, second]);

      expect(first.existsSync(), isFalse);
      expect(second.existsSync(), isFalse);
    });

    test('a photo already gone does not stop the others', () async {
      final kept = photo(tmp, 'b.jpg');
      final c = make(_FakeDecoder({}), _FakeProvider());
      c.offerShare(['${tmp.path}/missing.jpg', kept.path]);
      await pumpEventQueue();
      c.onClose();
      await pumpEventQueue();
      expect(kept.existsSync(), isFalse);
    });
  });

  group('fixCode', () {
    const typed = '2001136';
    const noteItem = '1004765';
    const note = '99999995';

    /// a.jpg (A), b.jpg (B), bad.jpg (unreadable), c.jpg (A).
    Future<StockSheetController> fourPhotos(_FakeProvider provider) async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'b.jpg': [_ean(_b)],
        'bad.jpg': null,
        'c.jpg': [_ean(_a)],
      });
      final c = make(decoder, provider);
      await c.start(['a.jpg', 'b.jpg', 'bad.jpg', 'c.jpg']);
      expect(c.phase.value, StockSheetPhase.reviewing);
      return c;
    }

    test('a typed item code resolves the unresolved row in place', () async {
      final provider = _FakeProvider(
        stock: {typed: 3},
        known: const [_a, _b, typed],
      );
      final c = await fourPhotos(provider);
      expect(c.review[2].resolved, isFalse);

      final error = await c.fixCode(2, ' $typed ');

      expect(error, isNull);
      expect(reviewPaths(c), ['a.jpg', 'b.jpg', 'bad.jpg', 'c.jpg']);
      final entry = c.review[2];
      expect(entry.typed, isTrue);
      expect(entry.notInErp, isEmpty);
      expect(entry.items.single.code.barcode, '20011369');
      expect(entry.items.single.code.itemCode, typed);
      expect(entry.items.single.included, isTrue);
      expect(entry.items.single.stock!.total, 3);
      expect(entry.items.single.stock!.racks.single.rack, _rack);
      expect(c.sheetPhotoCount, 4);
      expect(provider.itemRequests.last, [typed]);
      expect(provider.stockRequests.last, [typed]);
      expect(c.fixing.value, isFalse);
    });

    test('fixing an Also read note appends the item to the row', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a), note],
      });
      final provider = _FakeProvider(
        stock: {_a: 1, noteItem: 2},
        known: const [_a, noteItem],
      );
      final c = make(decoder, provider);
      await c.start(['a.jpg']);
      expect(c.review.single.items, hasLength(1));
      expect(c.review.single.notInErp, [note]);

      final error = await c.fixCode(0, noteItem, noteBarcode: note);

      expect(error, isNull);
      final entry = c.review.single;
      expect(entry.items.map((i) => i.code.itemCode), [_a, noteItem]);
      expect(entry.items.every((i) => i.included), isTrue);
      expect(entry.notInErp, isEmpty);
      expect(entry.typed, isTrue);
    });

    test('fixing a note to an item switched off switches it on', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a), _ean(_b), note],
      });
      final provider = _FakeProvider(stock: {_a: 1, _b: 2});
      final c = make(decoder, provider);
      await c.start(['a.jpg']);
      c.setItemIncluded(0, 1, false);
      expect(c.review.single.items[1].included, isFalse);

      expect(await c.fixCode(0, _b, noteBarcode: note), isNull);

      final entry = c.review.single;
      expect(entry.items.map((i) => i.code.itemCode), [_a, _b]);
      expect(entry.items.every((i) => i.included), isTrue);
      expect(entry.notInErp, isEmpty);
    });

    test('text that is not a code is refused without asking the ERP', () async {
      final provider = _FakeProvider();
      final c = await fourPhotos(provider);
      final calls = provider.itemRequests.length;

      expect(await c.fixCode(2, 'ABC'), 'Not a barcode or item code');
      expect(await c.fixCode(2, '12345678'), 'Not a barcode or item code');
      expect(provider.itemRequests, hasLength(calls));
      expect(c.review[2].resolved, isFalse);
    });

    test('a code the ERP does not know says Not in ERP', () async {
      final provider = _FakeProvider();
      final c = await fourPhotos(provider);

      expect(await c.fixCode(2, typed), 'Not in ERP');
      expect(c.review[2].resolved, isFalse);
      expect(c.review[2].typed, isFalse);
      expect(c.fixing.value, isFalse);
    });

    test('a code already on another row still resolves this one', () async {
      final provider = _FakeProvider(stock: {_a: 1, _b: 1});
      final c = await fourPhotos(provider);

      expect(await c.fixCode(2, _ean(_a)), isNull);

      expect(c.review[0].items.single.code.itemCode, _a);
      expect(c.review[2].items.single.code.itemCode, _a);
      expect(c.review[2].typed, isTrue);
      expect(c.sheetPhotoCount, 4);
    });

    test('403 and network errors give the base messages', () async {
      final provider = _FakeProvider(stock: {_a: 1, _b: 1});
      final c = await fourPhotos(provider);

      provider.itemsError = const StockAccessDenied();
      expect(await c.fixCode(2, _a), "You don't have access to stock levels.");
      provider.stockError = Exception('offline');
      expect(
        await c.fixCode(2, _a),
        "Couldn't reach the ERP. Check the connection and try again.",
      );
      expect(c.review[2].resolved, isFalse);
      expect(c.fixing.value, isFalse);
    });

    test('closing during the lookup leaves the review alone', () async {
      final provider = _FakeProvider(stock: {_a: 1, _b: 1});
      final c = await fourPhotos(provider);
      provider.itemsGate = Completer<void>();

      final fix = c.fixCode(2, _a);
      expect(c.fixing.value, isTrue);
      c.onClose();
      provider.itemsGate!.complete();
      await fix;

      expect(c.review[2].resolved, isFalse);
      expect(c.fixing.value, isFalse);
    });
  });

  group('addPhotos', () {
    test('more than the limit allows adds nothing and says why', () async {
      final decoder = _FakeDecoder({});
      final c = make(decoder, _FakeProvider());
      await c.start(List.generate(98, (i) => 'p$i.jpg'));
      expect(c.review, hasLength(98));
      final calls = decoder.calls;

      expect(
        await c.addPhotos(['x.jpg', 'y.jpg', 'z.jpg']),
        'Only 2 more photos fit (limit 100).',
      );
      expect(c.review, hasLength(98));
      expect(decoder.calls, calls);
      expect(c.adding.value, isFalse);
    });

    test('one place left, then none, say so in the singular', () async {
      final c = make(_FakeDecoder({}), _FakeProvider());
      await c.start(List.generate(99, (i) => 'p$i.jpg'));

      expect(
        await c.addPhotos(['x.jpg', 'y.jpg']),
        'Only 1 more photo fits (limit 100).',
      );
      expect(await c.addPhotos(['x.jpg']), isNull);
      expect(c.review, hasLength(100));
      expect(await c.addPhotos(['y.jpg']), 'No more photos fit (limit 100).');
      expect(
        StockSheetController.roomMessage(3),
        'Only 3 more photos fit (limit 100).',
      );
    });

    test('photos already in the list are skipped', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'b.jpg': [_ean(_b)],
        'd.jpg': [_ean(_b)],
      });
      final c = make(decoder, _FakeProvider(stock: {_a: 1, _b: 1}));
      await c.start(['a.jpg', 'b.jpg']);

      expect(await c.addPhotos(['b.jpg', 'd.jpg', 'd.jpg']), isNull);
      expect(reviewPaths(c), ['a.jpg', 'b.jpg', 'd.jpg']);
      final calls = decoder.calls;

      expect(
        await c.addPhotos(['a.jpg', 'd.jpg']),
        'Those photos are already in the list.',
      );
      expect(reviewPaths(c), ['a.jpg', 'b.jpg', 'd.jpg']);
      expect(decoder.calls, calls);
    });

    test('a photo shared twice is read and listed once', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'b.jpg': [_ean(_b)],
      });
      final c = make(decoder, _FakeProvider(stock: {_a: 1, _b: 1}));

      await c.start(['a.jpg', 'b.jpg', 'a.jpg']);

      expect(reviewPaths(c), ['a.jpg', 'b.jpg']);
      expect(decoder.calls, 2);
    });

    test('new photos go after a reorder, checked by their own codes', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'b.jpg': [_ean(_b)],
        'bad.jpg': null,
        'd.jpg': [_ean(_b)],
        'e.jpg': ['not a code'],
      });
      final provider = _FakeProvider(stock: {_a: 1, _b: 2});
      final c = make(decoder, provider);
      await c.start(['a.jpg', 'b.jpg', 'bad.jpg']);
      c.reorder(0, 3);
      expect(reviewPaths(c), ['b.jpg', 'bad.jpg', 'a.jpg']);

      final added = c.addPhotos(['d.jpg', 'e.jpg']);
      expect(c.adding.value, isTrue);
      expect(c.total.value, 2);
      expect(await added, isNull);

      expect(reviewPaths(c), ['b.jpg', 'bad.jpg', 'a.jpg', 'd.jpg', 'e.jpg']);
      expect(c.review[3].items.single.code.itemCode, _b);
      expect(c.review[3].items.single.stock!.total, 2);
      expect(c.review[4].resolved, isFalse);
      expect(c.review[4].rawValues, ['not a code']);
      expect(provider.itemRequests.last, [_b]);
      expect(provider.stockRequests.last, [_b]);
      expect(c.thumbnails.keys, containsAll(['d.jpg', 'e.jpg']));
      expect(c.decoded.value, 2);
      expect(c.adding.value, isFalse);
      expect(c.phase.value, StockSheetPhase.reviewing);
    });

    test(
      'a failed check adds them unchecked; Retry check resolves one',
      () async {
        final decoder = _FakeDecoder({
          'a.jpg': [_ean(_a)],
          'd.jpg': [_ean(_b)],
          'e.jpg': [_ean(_a)],
        });
        final provider = _FakeProvider(stock: {_a: 1, _b: 2});
        final c = make(decoder, provider);
        await c.start(['a.jpg']);
        provider.stockError = Exception('offline');

        expect(await c.addPhotos(['d.jpg', 'e.jpg']), isNull);

        expect(reviewPaths(c), ['a.jpg', 'd.jpg', 'e.jpg']);
        for (final entry in c.review.skip(1)) {
          expect(entry.unchecked, isTrue);
          expect(entry.items, isEmpty);
          expect(entry.included, isFalse);
        }
        // Never a false out-of-stock row.
        expect(c.sheetPhotoCount, 1);
        final decodes = decoder.calls;

        await c.retryCheck(1);

        expect(decoder.calls, decodes);
        expect(c.review[1].unchecked, isFalse);
        expect(c.review[1].items.single.code.itemCode, _b);
        expect(c.review[1].items.single.stock!.total, 2);
        expect(c.review[2].unchecked, isTrue);
        expect(provider.stockRequests.last, [_b]);
        expect(c.sheetPhotoCount, 2);
        expect(c.rechecking.value, isFalse);
      },
    );

    test('a failed Retry check leaves the photo unchecked', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'd.jpg': [_ean(_b)],
      });
      final provider = _FakeProvider(stock: {_a: 1, _b: 2});
      final c = make(decoder, provider);
      await c.start(['a.jpg']);
      provider.stockError = Exception('offline');
      await c.addPhotos(['d.jpg']);
      provider.itemsError = Exception('still offline');

      expect(
        await c.retryCheck(1),
        "Couldn't reach the ERP. Check the connection and try again.",
      );
      expect(c.review[1].unchecked, isTrue);
      expect(c.review[1].items, isEmpty);

      provider.itemsError = const StockAccessDenied();
      expect(await c.retryCheck(1), "You don't have access to stock levels.");
      expect(c.review[1].unchecked, isTrue);
      expect(c.rechecking.value, isFalse);
    });

    test('a code typed during Retry check is not overwritten', () async {
      const typed = '2001136';
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'd.jpg': [_ean(_b)],
      });
      final provider = _FakeProvider(
        stock: {_a: 1, _b: 2, typed: 3},
        known: const [_a, _b, typed],
      );
      final c = make(decoder, provider);
      await c.start(['a.jpg']);
      provider.stockError = Exception('offline');
      await c.addPhotos(['d.jpg']);
      expect(c.review[1].unchecked, isTrue);
      final gate = provider.itemsGateOnce = Completer<void>();

      final retry = c.retryCheck(1);
      await pumpEventQueue();
      // The gate was taken by the retry's Item call.
      expect(provider.itemsGateOnce, isNull);
      expect(await c.fixCode(1, typed), isNull);
      expect(c.review[1].items.single.code.itemCode, typed);
      gate.complete();

      expect(await retry, isNull);
      expect(c.review[1].typed, isTrue);
      expect(c.review[1].unchecked, isFalse);
      expect(c.review[1].items.single.code.itemCode, typed);
    });

    test('closing mid-add appends nothing', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'd.jpg': [_ean(_b)],
      });
      final provider = _FakeProvider(stock: {_a: 1, _b: 2});
      final c = make(decoder, provider);
      await c.start(['a.jpg']);
      provider.stockGate = Completer<void>();

      final added = c.addPhotos(['d.jpg']);
      await pumpEventQueue();
      c.onClose();
      provider.stockGate!.complete();
      await added;

      expect(reviewPaths(c), ['a.jpg']);
      expect(c.adding.value, isFalse);
    });

    test('Generate file waits for an add in flight', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'd.jpg': [_ean(_b)],
      });
      final provider = _FakeProvider(stock: {_a: 1, _b: 2});
      final c = make(decoder, provider);
      await c.start(['a.jpg']);
      provider.stockGate = Completer<void>();

      final added = c.addPhotos(['d.jpg']);
      await pumpEventQueue();
      await c.makeSheet(SheetFormat.excel);
      expect(shared, isEmpty);
      provider.stockGate!.complete();
      await added;

      expect(c.phase.value, StockSheetPhase.reviewing);
      await c.makeSheet(SheetFormat.excel);
      expect(c.phase.value, StockSheetPhase.done);
      expect(c.result.value!.rows.map((r) => r.photoPath), ['a.jpg', 'd.jpg']);
    });
  });

  group('removeAt and restore', () {
    Future<StockSheetController> three() async {
      final c = make(
        _FakeDecoder({
          'a.jpg': [_ean(_a)],
          'b.jpg': [_ean(_b)],
          'd.jpg': [_ean(_a)],
        }),
        _FakeProvider(stock: {_a: 1, _b: 1}),
      );
      fingerprints.addAll({'a.jpg': 'A', 'b.jpg': 'B', 'd.jpg': 'D'});
      await c.start(['a.jpg', 'b.jpg', 'd.jpg']);
      return c;
    }

    test('removeAt drops the entry and returns it', () async {
      final c = await three();

      final removed = c.removeAt(1);

      expect(removed?.path, 'b.jpg');
      expect(reviewPaths(c), ['a.jpg', 'd.jpg']);
      expect(c.removeAt(5), isNull);
      expect(c.removeAt(-1), isNull);
    });

    test('removeAt does nothing while photos are being added', () async {
      final c = await three();
      c.adding.value = true;

      expect(c.canRemove, isFalse);
      expect(c.removeAt(0), isNull);
      expect(reviewPaths(c), ['a.jpg', 'b.jpg', 'd.jpg']);

      c.adding.value = false;
      for (final flag in [c.rechecking, c.fixing, c.busy]) {
        flag.value = true;
        expect(c.canRemove, isFalse);
        expect(c.removeAt(0), isNull);
        flag.value = false;
      }
      expect(c.canRemove, isTrue);
    });

    test('restore puts the entry back at its index', () async {
      final c = await three();
      final removed = c.removeAt(1)!;

      c.restore(removed, 1);

      expect(reviewPaths(c), ['a.jpg', 'b.jpg', 'd.jpg']);
    });

    test('restore clamps the index after the list shrank', () async {
      final c = await three();
      final removed = c.removeAt(2)!;
      c.removeAt(1);

      c.restore(removed, 2);

      expect(reviewPaths(c), ['a.jpg', 'd.jpg']);
    });

    test('restore ignores an entry that is already listed', () async {
      final c = await three();
      final removed = c.removeAt(0)!;
      c.restore(removed, 0);
      c.restore(removed, 0);

      expect(reviewPaths(c), ['a.jpg', 'b.jpg', 'd.jpg']);
    });

    test(
      'restore skips a photo that was added again under a new path',
      () async {
        final c = await three();
        fingerprints['a2.jpg'] = 'A';
        final removed = c.removeAt(0)!;
        expect(await c.addPhotos(['a2.jpg']), isNull);

        c.restore(removed, 0);

        expect(reviewPaths(c), ['b.jpg', 'd.jpg', 'a2.jpg']);
      },
    );

    test('a removed photo can be added again', () async {
      final c = await three();
      fingerprints['a2.jpg'] = 'A';
      c.removeAt(0);

      expect(await c.addPhotos(['a2.jpg']), isNull);
      expect(reviewPaths(c), contains('a2.jpg'));
    });
  });

  group('picker copies', () {
    test('onClose clears the file picker temporary files', () async {
      var cleared = 0;
      final c = make(
        _FakeDecoder({}),
        _FakeProvider(stock: {}),
        clearPickerFiles: () async => cleared++,
      );
      c.onClose();
      await pumpEventQueue();
      expect(cleared, 1);
    });

    test('onClose ignores an error from the clean-up', () async {
      final c = make(
        _FakeDecoder({}),
        _FakeProvider(stock: {}),
        clearPickerFiles: () async => throw StateError('no picker'),
      );
      c.onClose();
      await pumpEventQueue();
    });
  });

  group('duplicates by content', () {
    test('start reads two copies of the same photo once', () async {
      fingerprints.addAll({'a.jpg': 'X', 'b.jpg': 'X'});
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'b.jpg': [_ean(_a)],
      });
      final c = make(decoder, _FakeProvider(stock: {_a: 1}));

      await c.start(['a.jpg', 'b.jpg']);

      expect(decoder.decoded, ['a.jpg']);
      expect(c.review.map((e) => e.path), ['a.jpg']);
    });

    test('addPhotos skips a photo already listed by content', () async {
      fingerprints.addAll({'a.jpg': 'X', 'c.jpg': 'X'});
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'c.jpg': [_ean(_a)],
      });
      final c = make(decoder, _FakeProvider(stock: {_a: 1}));
      await c.start(['a.jpg']);
      final calls = decoder.calls;

      expect(
        await c.addPhotos(['c.jpg']),
        StockSheetController.alreadyListedMessage,
      );
      expect(decoder.calls, calls);
      expect(c.review.length, 1);
    });
  });

  group('offerShare', () {
    Future<StockSheetController> reviewing() async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'b.jpg': [_ean(_b)],
        'n1.jpg': [_ean(_b)],
        'n2.jpg': [_ean(_a)],
      });
      final c = make(decoder, _FakeProvider(stock: {_a: 1, _b: 1}));
      await c.start(['a.jpg', 'b.jpg']);
      expect(c.phase.value, StockSheetPhase.reviewing);
      return c;
    }

    test('from idle it starts the share', () {
      final c = make(_FakeDecoder({}), _FakeProvider());
      expect(c.offerShare(['a.jpg']), ShareOffer.started);
      expect(c.sharedPaths, ['a.jpg']);
      expect(c.shareSerial.value, 1);
      expect(c.pendingShare, isEmpty);
    });

    test('while busy it is refused and nothing changes', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
      })..gate = Completer<void>();
      final c = make(decoder, _FakeProvider(stock: {_a: 1}));
      final run = c.start(['a.jpg']);

      expect(c.offerShare(['b.jpg']), ShareOffer.refusedBusy);
      expect(c.pendingShare, isEmpty);
      expect(c.shareSerial.value, 0);
      decoder.gate!.complete();
      await run;
    });

    test('while reviewing it is held, with the review untouched', () async {
      final c = await reviewing();
      c.setIncluded(1, false);

      expect(c.offerShare(['n1.jpg', 'n2.jpg']), ShareOffer.pending);
      await pumpEventQueue();

      expect(c.pendingShare, ['n1.jpg', 'n2.jpg']);
      expect(c.pendingShareFits, isTrue);
      expect(reviewPaths(c), ['a.jpg', 'b.jpg']);
      expect(c.review[1].included, isFalse);
      expect(c.phase.value, StockSheetPhase.reviewing);
      expect(c.shareSerial.value, 0);
    });

    test('while the out-of-stock question is open it is held', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
      });
      final c = make(decoder, _FakeProvider());
      await run(c, ['a.jpg'], SheetFormat.excel);
      expect(c.phase.value, StockSheetPhase.awaitingChoice);

      expect(c.offerShare(['n1.jpg']), ShareOffer.pending);
      await pumpEventQueue();
      expect(c.pendingShare, ['n1.jpg']);
      expect(c.phase.value, StockSheetPhase.awaitingChoice);
    });

    test('pendingShareFits follows the 100-photo limit', () async {
      final c = make(_FakeDecoder({}), _FakeProvider());
      await c.start(List.generate(99, (i) => 'p$i.jpg'));
      c.offerShare(['x.jpg']);
      await pumpEventQueue();
      expect(c.pendingShareFits, isTrue);
      c.offerShare(['x.jpg', 'y.jpg']);
      await pumpEventQueue();
      expect(c.pendingShareFits, isFalse);
    });

    test('a held share counts only new photos', () async {
      fingerprints.addAll({'a.jpg': 'X', 'c.jpg': 'X'});
      final c = await reviewing();

      c.offerShare(['c.jpg', 'd.jpg']);
      await pumpEventQueue();

      expect(c.pendingShare, ['d.jpg']);
    });

    test('a held share of only duplicates is not asked', () async {
      fingerprints.addAll({'a.jpg': 'X', 'c.jpg': 'X'});
      final c = await reviewing();

      c.offerShare(['c.jpg']);
      await pumpEventQueue();

      expect(c.pendingShare, isEmpty);
      expect(c.alreadyListed.value, 1);
    });

    test('Add appends the held photos', () async {
      final c = await reviewing();
      c.offerShare(['n1.jpg', 'n2.jpg']);
      await pumpEventQueue();

      expect(await c.resolvePendingShare(PendingShareChoice.add), isNull);

      expect(reviewPaths(c), ['a.jpg', 'b.jpg', 'n1.jpg', 'n2.jpg']);
      expect(c.pendingShare, isEmpty);
      expect(c.phase.value, StockSheetPhase.reviewing);
    });

    test('Add from the out-of-stock question returns to the review', () async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'n1.jpg': [_ean(_a)],
      });
      final c = make(decoder, _FakeProvider());
      await run(c, ['a.jpg'], SheetFormat.excel);
      c.offerShare(['n1.jpg']);
      await pumpEventQueue();

      await c.resolvePendingShare(PendingShareChoice.add);

      expect(c.phase.value, StockSheetPhase.reviewing);
      expect(c.result.value, isNull);
      expect(reviewPaths(c), ['a.jpg', 'n1.jpg']);
    });

    test('Add that will not fit adds nothing and is held again', () async {
      final c = make(_FakeDecoder({}), _FakeProvider());
      await c.start(List.generate(99, (i) => 'p$i.jpg'));
      c.offerShare(['n1.jpg', 'n2.jpg']);
      await pumpEventQueue();

      expect(await c.resolvePendingShare(PendingShareChoice.add), isNull);
      expect(c.review, hasLength(99));
      // The screen asks again, offering only Start again.
      expect(c.pendingShare, ['n1.jpg', 'n2.jpg']);
      expect(c.pendingShareFits, isFalse);
    });

    test('a share of photos already in the list says so, not asks', () async {
      final c = await reviewing();
      c.offerShare(['b.jpg']);
      await pumpEventQueue();

      expect(c.pendingShare, isEmpty);
      expect(c.alreadyListed.value, 1);
      expect(reviewPaths(c), ['a.jpg', 'b.jpg']);
    });

    test('Start again replaces the review with the held photos', () async {
      final c = await reviewing();
      c.offerShare(['n1.jpg', 'n2.jpg']);
      await pumpEventQueue();

      await c.resolvePendingShare(PendingShareChoice.startAgain);

      expect(reviewPaths(c), ['n1.jpg', 'n2.jpg']);
      expect(c.pendingShare, isEmpty);
      expect(c.sharedPaths, ['n1.jpg', 'n2.jpg']);
      expect(c.phase.value, StockSheetPhase.reviewing);
    });

    test('Cancel drops the held photos and keeps the review', () async {
      final c = await reviewing();
      c.offerShare(['n1.jpg', 'n2.jpg']);
      await pumpEventQueue();

      await c.resolvePendingShare(PendingShareChoice.cancel);

      expect(reviewPaths(c), ['a.jpg', 'b.jpg']);
      expect(c.pendingShare, isEmpty);
      expect(c.phase.value, StockSheetPhase.reviewing);
    });
  });

  test('added and held photos in the temp folder go on close', () async {
    final first = File('${tmp.path}/first.jpg')..writeAsBytesSync([1]);
    final added = File('${tmp.path}/added.jpg')..writeAsBytesSync([1]);
    final held = File('${tmp.path}/held.jpg')..writeAsBytesSync([1]);
    final decoder = _FakeDecoder({
      first.path: [_ean(_a)],
      added.path: [_ean(_b)],
    });
    final c = make(decoder, _FakeProvider(stock: {_a: 1, _b: 1}));
    await c.start([first.path]);
    await c.addPhotos([added.path]);
    expect(c.offerShare([held.path]), ShareOffer.pending);
    await c.resolvePendingShare(PendingShareChoice.cancel);
    expect(added.existsSync(), isTrue);

    c.onClose();
    await untilGone([first, added, held]);

    expect(first.existsSync(), isFalse);
    expect(added.existsSync(), isFalse);
    expect(held.existsSync(), isFalse);
  });

  test('refused and held photos in the temp folder go on close', () async {
    File photo(String name) => File('${tmp.path}/$name')..writeAsBytesSync([1]);
    final refused = photo('refused.jpg');
    final full1 = photo('full1.jpg');
    final full2 = photo('full2.jpg');
    final held = photo('held.jpg');
    final decoder = _FakeDecoder({})..gate = Completer<void>();
    final c = make(decoder, _FakeProvider());
    final run = c.start(List.generate(99, (i) => 'p$i.jpg'));
    expect(c.offerShare([refused.path]), ShareOffer.refusedBusy);
    decoder.gate!.complete();
    await run;
    expect(
      await c.addPhotos([full1.path, full2.path]),
      'Only 1 more photo fits (limit 100).',
    );
    expect(c.offerShare([held.path]), ShareOffer.pending);

    c.onClose();
    await untilGone([refused, full1, full2, held]);

    expect(refused.existsSync(), isFalse);
    expect(full1.existsSync(), isFalse);
    expect(full2.existsSync(), isFalse);
    expect(held.existsSync(), isFalse);
  });

  group('clean-up in extra intake folders', () {
    late Directory group;
    late Directory elsewhere;
    setUp(() {
      group = Directory('${tmp.path}_group')..createSync();
      elsewhere = Directory('${tmp.path}_elsewhere')..createSync();
    });
    tearDown(() {
      for (final d in [group, elsewhere]) {
        if (d.existsSync()) d.deleteSync(recursive: true);
      }
    });

    test(
      'onClose deletes given photos in an extra intake folder but not elsewhere',
      () async {
        final x = File('${group.path}/x.jpg')..writeAsBytesSync([1]);
        final y = File('${elsewhere.path}/y.jpg')..writeAsBytesSync([1]);
        final c = make(
          _FakeDecoder({}),
          _FakeProvider(),
          extraRoots: () async => [group.path],
        );
        await c.start([x.path, y.path]);

        c.onClose();
        await untilGone([x]);

        expect(x.existsSync(), isFalse);
        expect(y.existsSync(), isTrue);
      },
    );

    test('copies in sub-folders of the native temporary folder are deleted, '
        'the folders kept', () async {
      // sharedFolders returns NSTemporaryDirectory() itself: "Choose files…"
      // copies land in its <bundle id>-Inbox/, drops in its dropped/.
      final inbox = Directory('${group.path}/com.ddmco.multimax-Inbox')
        ..createSync();
      final dropped = Directory('${group.path}/dropped')..createSync();
      final picked = File('${inbox.path}/picked.jpg')..writeAsBytesSync([1]);
      final drop = File('${dropped.path}/drop.png')..writeAsBytesSync([1]);
      final kept = File('${inbox.path}/not-given.jpg')..writeAsBytesSync([1]);
      final c = make(
        _FakeDecoder({}),
        _FakeProvider(),
        extraRoots: () async => [group.path],
      );
      await c.start([picked.path, drop.path]);

      c.onClose();
      await untilGone([picked, drop]);

      expect(picked.existsSync(), isFalse);
      expect(drop.existsSync(), isFalse);
      expect(kept.existsSync(), isTrue, reason: 'only given paths go');
      expect(inbox.existsSync(), isTrue);
      expect(dropped.existsSync(), isTrue);
    });

    test('empty, relative and root folders are not clean-up roots', () async {
      final y = File('${elsewhere.path}/y.jpg')..writeAsBytesSync([1]);
      final t = File('${tmp.path}/t.jpg')..writeAsBytesSync([1]);
      final c = make(
        _FakeDecoder({}),
        _FakeProvider(),
        extraRoots: () async => ['', '/', 'relative'],
      );
      await c.start([y.path, t.path]);

      c.onClose();
      await untilGone([t]);

      expect(t.existsSync(), isFalse);
      expect(y.existsSync(), isTrue);
    });

    test(
      'a failing extra-folder lookup still cleans the temp folder',
      () async {
        final t = File('${tmp.path}/t.jpg')..writeAsBytesSync([1]);
        final c = make(
          _FakeDecoder({}),
          _FakeProvider(),
          extraRoots: () async => throw Exception('no channel'),
        );
        await c.start([t.path]);

        c.onClose();
        await untilGone([t]);

        expect(t.existsSync(), isFalse);
      },
    );
  });

  group('a share during an add', () {
    /// a.jpg and b.jpg in the review, d.jpg being added (its stock check
    /// waits for [_FakeProvider.stockGate]).
    Future<(StockSheetController, Future<String?>)> addingOne(
      _FakeProvider provider,
    ) async {
      final decoder = _FakeDecoder({
        'a.jpg': [_ean(_a)],
        'b.jpg': [_ean(_b)],
        'd.jpg': [_ean(_b)],
        'n1.jpg': [_ean(_a)],
        'n2.jpg': [_ean(_b)],
      });
      final c = make(decoder, provider);
      await c.start(['a.jpg', 'b.jpg']);
      provider.stockGate = Completer<void>();
      final add = c.addPhotos(['d.jpg']);
      await pumpEventQueue();
      expect(c.adding.value, isTrue);
      return (c, add);
    }

    test('it is held, not refused', () async {
      final provider = _FakeProvider(stock: {_a: 1, _b: 1});
      final (c, add) = await addingOne(provider);

      expect(c.offerShare(['n1.jpg']), ShareOffer.pending);
      await pumpEventQueue();
      expect(c.pendingShare, ['n1.jpg']);
      expect(c.pendingShareFits, isTrue);

      provider.stockGate!.complete();
      await add;
    });

    test('Add waits for the add, then appends both in order', () async {
      final provider = _FakeProvider(stock: {_a: 1, _b: 1});
      final (c, add) = await addingOne(provider);
      c.offerShare(['n1.jpg', 'n2.jpg']);
      await pumpEventQueue();

      final resolved = c.resolvePendingShare(PendingShareChoice.add);
      await pumpEventQueue();
      expect(reviewPaths(c), ['a.jpg', 'b.jpg']);
      provider.stockGate!.complete();

      expect(await add, isNull);
      expect(await resolved, isNull);
      expect(reviewPaths(c), ['a.jpg', 'b.jpg', 'd.jpg', 'n1.jpg', 'n2.jpg']);
      expect(c.pendingShare, isEmpty);
      expect(c.adding.value, isFalse);
    });

    test('Start again appends nothing from the add in flight', () async {
      final provider = _FakeProvider(stock: {_a: 1, _b: 1});
      final (c, add) = await addingOne(provider);
      c.offerShare(['n1.jpg', 'n2.jpg']);
      await pumpEventQueue();

      final resolved = c.resolvePendingShare(PendingShareChoice.startAgain);
      await pumpEventQueue();
      provider.stockGate!.complete();
      await add;
      expect(await resolved, isNull);

      expect(reviewPaths(c), ['n1.jpg', 'n2.jpg']);
      expect(c.sharedPaths, ['n1.jpg', 'n2.jpg']);
      expect(c.phase.value, StockSheetPhase.reviewing);
    });

    test('the photos being added count against the limit', () async {
      final decoder = _FakeDecoder({});
      final c = make(decoder, _FakeProvider());
      await c.start(List.generate(97, (i) => 'p$i.jpg'));
      decoder.gate = Completer<void>();
      final add = c.addPhotos(['x1.jpg', 'x2.jpg']);
      expect(c.photoRoom, 1);

      c.offerShare(['n1.jpg', 'n2.jpg']);
      await pumpEventQueue();
      expect(c.pendingShareFits, isFalse);
      // A photo already being added is not counted twice.
      c.pendingShare.assignAll(['x1.jpg', 'n1.jpg']);
      expect(c.pendingShareFits, isTrue);

      decoder.gate!.complete();
      await add;
      expect(c.photoRoom, 1);
    });

    test(
      'an Add that no longer fits once the adds land is held again',
      () async {
        final decoder = _FakeDecoder({});
        final c = make(decoder, _FakeProvider());
        await c.start(List.generate(96, (i) => 'p$i.jpg'));
        decoder.gate = Completer<void>();
        final add = c.addPhotos(['x1.jpg', 'x2.jpg']);

        // Each fits beside the review and the add, but not both.
        c.offerShare(['n1.jpg', 'n2.jpg']);
        await pumpEventQueue();
        expect(c.pendingShareFits, isTrue);
        final first = c.resolvePendingShare(PendingShareChoice.add);
        c.offerShare(['m1.jpg', 'm2.jpg']);
        await pumpEventQueue();
        expect(c.pendingShareFits, isTrue);
        final second = c.resolvePendingShare(PendingShareChoice.add);
        decoder.gate!.complete();

        await add;
        expect(await first, isNull);
        expect(await second, isNull);
        expect(c.review, hasLength(100));
        expect(reviewPaths(c).skip(96), [
          'x1.jpg',
          'x2.jpg',
          'n1.jpg',
          'n2.jpg',
        ]);
        expect(c.pendingShare, ['m1.jpg', 'm2.jpg']);
        expect(c.pendingShareFits, isFalse);
      },
    );

    test('a second share joins the one waiting, each photo once', () async {
      final provider = _FakeProvider(stock: {_a: 1, _b: 1});
      final (c, add) = await addingOne(provider);

      c.offerShare(['n1.jpg']);

      await pumpEventQueue();
      expect(c.offerShare(['n2.jpg', 'n1.jpg']), ShareOffer.pending);
      await pumpEventQueue();
      expect(c.pendingShare, ['n1.jpg', 'n2.jpg']);

      provider.stockGate!.complete();
      await add;
    });
  });
}
